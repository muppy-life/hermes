terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get latest Amazon Linux 2 ECS-optimized AMI
# This AMI includes: Docker, ECS agent, CloudWatch agent, SSM agent pre-installed
# This significantly reduces boot time compared to installing these on first boot
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    # Automatically select ARM64 for t4g/c6g/m6g instances, x86_64 for others
    values = [
      length(regexall("^(t4g|c6g|c6gn|c7g|m6g|m6gd|m7g|r6g|r6gd|r7g)", var.instance_type)) > 0
      ? "amzn2-ami-ecs-hvm-*-arm64-ebs"
      : "amzn2-ami-ecs-hvm-*-x86_64-ebs"
    ]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Application Security Group
resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "Security group for application instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  ingress {
    description = "SSH from anywhere (consider restricting)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-app-sg"
    Environment = var.environment
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2" {
  name = "${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-ec2-role"
    Environment = var.environment
  }
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_role_policy" "ec2_cloudwatch" {
  name = "${var.environment}-ec2-cloudwatch-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach SSM managed policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Policy for ECR access (to pull Docker images)
resource "aws_iam_role_policy" "ec2_ecr" {
  name = "${var.environment}-ec2-ecr-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name        = "${var.environment}-ec2-profile"
    Environment = var.environment
  }
}

# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "${var.environment}-app-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    database_url      = var.database_url
    secret_key_base   = var.secret_key_base
    anthropic_api_key = var.anthropic_api_key
    environment       = var.environment
    phx_host          = var.phx_host
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.environment}-app-instance"
      Environment = var.environment
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tags = {
    Name        = "${var.environment}-app-launch-template"
    Environment = var.environment
  }
}

# Blue EC2 Instances
resource "aws_instance" "blue" {
  count = var.instance_count

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  subnet_id = var.private_subnets[count.index % length(var.private_subnets)]

  tags = {
    Name        = "${var.environment}-app-blue-${count.index + 1}"
    Environment = var.environment
    Color       = "blue"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Green EC2 Instances
resource "aws_instance" "green" {
  count = var.instance_count

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  subnet_id = var.private_subnets[count.index % length(var.private_subnets)]

  tags = {
    Name        = "${var.environment}-app-green-${count.index + 1}"
    Environment = var.environment
    Color       = "green"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Blue Target Group Attachments
resource "aws_lb_target_group_attachment" "blue" {
  count = var.instance_count

  target_group_arn = var.target_group_blue_arn
  target_id        = aws_instance.blue[count.index].id
  port             = 4000
}

# Green Target Group Attachments
resource "aws_lb_target_group_attachment" "green" {
  count = var.instance_count

  target_group_arn = var.target_group_green_arn
  target_id        = aws_instance.green[count.index].id
  port             = 4000
}
