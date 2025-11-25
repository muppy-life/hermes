# Hermes Infrastructure - Terraform

This directory contains Terraform configuration for deploying Hermes to AWS (Madrid region).

## Architecture Overview

- **VPC**: Custom VPC with public, private, and database subnets across 3 availability zones
- **EC2**: Application instances running in private subnets behind an ALB
- **ALB**: Application Load Balancer with HTTPS termination
- **Database**: External managed PostgreSQL (not in AWS)
- **Assets**: Served directly from application (no S3)

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **AWS CLI** configured
4. **External PostgreSQL database** URL in ecto format
5. **ACM Certificate** for HTTPS (must be in eu-south-2)
6. **EC2 Key Pair** for SSH access

## Initial Setup

### 1. Create S3 Backend for Terraform State

First, create the S3 bucket and DynamoDB table for Terraform state management:

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket hermes-terraform-state \
  --region eu-south-2 \
  --create-bucket-configuration LocationConstraint=eu-south-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket hermes-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket hermes-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket hermes-terraform-state \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name hermes-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-south-2
```

### 2. Create ACM Certificate

```bash
# Request certificate
aws acm request-certificate \
  --domain-name hermes.yourdomain.com \
  --validation-method DNS \
  --region eu-south-2

# Follow DNS validation steps in ACM console
# Note the certificate ARN for later use
```

### 3. Create EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name hermes-production \
  --region eu-south-2 \
  --query 'KeyMaterial' \
  --output text > hermes-production.pem

chmod 400 hermes-production.pem
```

## Configuration

### Required Variables

Create a `terraform.tfvars` file:

```hcl
# AWS Configuration
aws_region         = "eu-south-2"
environment        = "production"

# Network Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["eu-south-2a", "eu-south-2b", "eu-south-2c"]

# EC2 Configuration
instance_type      = "t3.small"
instance_count     = 2
key_name           = "hermes-production"

# SSL Certificate
certificate_arn    = "arn:aws:acm:eu-south-2:ACCOUNT_ID:certificate/CERT_ID"

# Secrets (use environment variables instead)
# These should be passed via -var or TF_VAR_ environment variables
# database_url      = "ecto://user:pass@host:5432/hermes_production"
# secret_key_base   = "your-secret-key-base"
# anthropic_api_key = "your-anthropic-api-key"
```

### Using Environment Variables for Secrets

Instead of storing secrets in `terraform.tfvars`, use environment variables:

```bash
export TF_VAR_database_url="ecto://user:pass@host:5432/hermes_production"
export TF_VAR_secret_key_base="your-secret-key-base"
export TF_VAR_anthropic_api_key="your-anthropic-api-key"
```

## Deployment

### Initialize Terraform

```bash
cd terraform
terraform init
```

### Plan Infrastructure Changes

```bash
terraform plan \
  -var="database_url=$DATABASE_URL" \
  -var="secret_key_base=$SECRET_KEY_BASE" \
  -var="anthropic_api_key=$ANTHROPIC_API_KEY"
```

### Apply Infrastructure

```bash
terraform apply \
  -var="database_url=$DATABASE_URL" \
  -var="secret_key_base=$SECRET_KEY_BASE" \
  -var="anthropic_api_key=$ANTHROPIC_API_KEY"
```

### View Outputs

```bash
terraform output
```

Key outputs:
- `alb_dns_name`: Load balancer DNS for Route53 configuration
- `ec2_instance_ids`: Instance IDs for monitoring
- `ec2_private_ips`: Private IPs for direct access via bastion

## Post-Deployment

### 1. Configure DNS

Point your domain to the ALB:

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)
ALB_ZONE=$(terraform output -raw alb_zone_id)

# Create Route53 alias record (example)
aws route53 change-resource-record-sets \
  --hosted-zone-id YOUR_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "hermes.yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "'$ALB_ZONE'",
          "DNSName": "'$ALB_DNS'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

### 2. SSH Access to Instances

Use AWS Systems Manager Session Manager (recommended) or SSH:

```bash
# Via Session Manager (no SSH key needed)
aws ssm start-session \
  --target INSTANCE_ID \
  --region eu-south-2

# Via SSH (through bastion or VPN)
ssh -i hermes-production.pem ec2-user@PRIVATE_IP
```

### 3. Monitor Deployment

```bash
# Check application logs
aws logs tail /aws/ec2/production/hermes --follow

# Check EC2 instance status
aws ec2 describe-instance-status \
  --instance-ids $(terraform output -json ec2_instance_ids | jq -r '.[]')
```

## Modules

### VPC Module (`modules/vpc/`)
- Creates VPC with public, private, and database subnets
- NAT gateways for private subnet internet access
- Internet gateway for public subnet access

### ALB Module (`modules/alb/`)
- Application Load Balancer in public subnets
- HTTPS listener with ACM certificate
- HTTP to HTTPS redirect
- Target group for EC2 instances

### EC2 Module (`modules/ec2/`)
- Launch template with user data script
- Auto-configured Docker and application setup
- CloudWatch agent for logging
- IAM roles for CloudWatch Logs access

## Maintenance

### Update Infrastructure

```bash
# Pull latest changes
git pull

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### Scale EC2 Instances

Update `instance_count` in `terraform.tfvars` and apply:

```bash
terraform apply -var="instance_count=3"
```

### Destroy Infrastructure

**Warning**: This will destroy all resources!

```bash
terraform destroy
```

## Troubleshooting

### EC2 Instances Not Healthy

1. Check instance logs:
   ```bash
   ssh -i hermes-production.pem ec2-user@INSTANCE_IP
   sudo journalctl -u hermes -f
   ```

2. Check Docker status:
   ```bash
   cd /opt/hermes
   docker-compose ps
   docker-compose logs -f
   ```

3. Verify environment variables:
   ```bash
   cat /opt/hermes/.env
   ```

### ALB Health Checks Failing

1. Ensure `/health` endpoint is responding:
   ```bash
   curl http://INSTANCE_PRIVATE_IP:4000/health
   ```

2. Check security group rules allow ALB to reach instances on port 4000

### Database Connection Issues

1. Verify database URL is correct and accessible from AWS
2. Check database firewall allows connections from EC2 instances
3. Test connection from EC2 instance:
   ```bash
   docker exec -it hermes_app_1 /app/bin/hermes remote
   Hermes.Repo.query("SELECT 1")
   ```

## Security Considerations

1. **SSH Access**: Consider using AWS Systems Manager Session Manager instead of SSH keys
2. **Secrets Management**: Use AWS Secrets Manager or Parameter Store for production
3. **Database**: Ensure external database has proper firewall rules and SSL enabled
4. **ALB**: Keep security groups restrictive
5. **IAM**: Follow principle of least privilege for EC2 instance roles

## Cost Optimization

- Use Savings Plans or Reserved Instances for EC2
- Consider smaller instance types if load is low
- Use CloudWatch for monitoring and cost allocation tags
- Already optimized: Single NAT Gateway and ARM instances (t4g.small)

## Monitoring and Alerting

Set up CloudWatch alarms for:
- EC2 instance CPU/memory utilization
- ALB target health
- Application errors in CloudWatch Logs

Example alarm for unhealthy targets:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name hermes-unhealthy-targets \
  --alarm-description "Alert when ALB has unhealthy targets" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold
```
