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

variable "phx_host" {
  description = "Phoenix host domain"
  type        = string
  default     = "localhost"
}
