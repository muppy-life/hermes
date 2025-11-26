terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "hermes-terraform-state-026790686268"
    key            = "production/terraform.tfstate"
    region         = "eu-south-2"
    encrypt        = true
    dynamodb_table = "hermes-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Hermes"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  environment         = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# Note: Database is managed externally in another cloud provider
# Application will connect using DATABASE_URL environment variable

# Application Load Balancer Module
module "alb" {
  source = "./modules/alb"

  environment      = var.environment
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnets
  certificate_arn = var.certificate_arn
}

# EC2 Instances Module (Blue-Green Deployment)
module "ec2" {
  source = "./modules/ec2"

  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  private_subnets       = module.vpc.private_subnets
  target_group_blue_arn  = module.alb.target_group_blue_arn
  target_group_green_arn = module.alb.target_group_green_arn
  alb_security_group_id = module.alb.alb_security_group_id

  instance_type     = var.instance_type
  instance_count    = var.instance_count
  key_name          = var.key_name

  database_url      = var.database_url
  secret_key_base   = var.secret_key_base
  anthropic_api_key = var.anthropic_api_key
  phx_host          = var.phx_host
}

# S3 + CloudFront for static assets
module "s3_assets" {
  source = "./modules/s3_assets"

  environment = var.environment
  domain      = var.phx_host
}

# ECR Repository for Docker images
resource "aws_ecr_repository" "hermes" {
  name                 = "hermes"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ECR Lifecycle Policy - keep last 10 images
resource "aws_ecr_lifecycle_policy" "hermes" {
  repository = aws_ecr_repository.hermes.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
