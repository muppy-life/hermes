variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-south-2" # Madrid region
}

variable "environment" {
  description = "Environment name (production, staging)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-south-2a", "eu-south-2b", "eu-south-2c"]
}

# Database variables (external managed database)
variable "database_url" {
  description = "External database URL (ecto format)"
  type        = string
  sensitive   = true
}

# EC2 variables
variable "instance_type" {
  description = "EC2 instance type (consider t4g.small for 20% cost savings with ARM)"
  type        = string
  default     = "t4g.small"  # ARM-based Graviton2 - 20% cheaper than t3.small
}

variable "instance_count" {
  description = "Number of EC2 instances"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "SSH key pair name for EC2 instances"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for HTTPS"
  type        = string
}

variable "secret_key_base" {
  description = "Phoenix secret key base"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude"
  type        = string
  sensitive   = true
}

variable "phx_host" {
  description = "Phoenix host domain (e.g., hermes.muppy.dev)"
  type        = string
  default     = "hermes.muppy.com"
}
