variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ARN of the ALB target group"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "instance_count" {
  description = "Number of EC2 instances"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "database_url" {
  description = "Database URL"
  type        = string
  sensitive   = true
}

variable "secret_key_base" {
  description = "Phoenix secret key base"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key"
  type        = string
  sensitive   = true
}

variable "sendgrid_api_key" {
  description = "SendGrid API key for email notifications"
  type        = string
  sensitive   = true
}

variable "phx_host" {
  description = "Phoenix host domain"
  type        = string
  default     = "localhost"
}

variable "hermes_github_token" {
  description = "GitHub PAT"
  type        = string
  sensitive   = true
  default     = ""
}

variable "hermes_github_owner" {
  description = "GitHub owner login"
  type        = string
  default     = ""
}

variable "hermes_github_default_repo" {
  description = "Default GitHub repo"
  type        = string
  default     = ""
}

variable "hermes_github_project_id" {
  description = "GitHub Projects v2 board node ID"
  type        = string
  default     = ""
}

variable "hermes_github_status_field_id" {
  description = "GitHub Projects v2 Status field node ID"
  type        = string
  default     = ""
}

variable "hermes_github_webhook_secret" {
  description = "GitHub webhook HMAC secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "appsignal_push_api_key" {
  description = "AppSignal push API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_region" {
  description = "AWS region, used for the ECR login at instance boot"
  type        = string
}

variable "ecr_registry" {
  description = "ECR registry host (<account_id>.dkr.ecr.<region>.amazonaws.com)"
  type        = string
}

variable "static_url" {
  description = "CloudFront URL for static assets"
  type        = string
}

variable "aws_s3_bucket" {
  description = "S3 bucket for uploads"
  type        = string
}

variable "aws_s3_host" {
  description = "S3 endpoint host"
  type        = string
}

variable "aws_s3_region" {
  description = "S3 bucket region"
  type        = string
}

variable "aws_s3_access_key_id" {
  description = "Access key ID for S3 uploads"
  type        = string
  sensitive   = true
}

variable "aws_s3_secret_access_key" {
  description = "Secret access key for S3 uploads"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "Access key ID for ex_aws"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "Secret access key for ex_aws"
  type        = string
  sensitive   = true
}

variable "app_image_tag" {
  description = <<-DESC
    ECR tag the instance boots at. Must be an image whose migrations have
    already run: CD pushes :latest before terraform applies, and migrations
    run after, so booting :latest here would serve code ahead of the schema.
    Defaults to the last deployed commit; CD overrides it per deploy.
  DESC
  type        = string
}

