output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.alb.alb_zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = module.alb.target_group_arn
}

output "target_group_name" {
  description = "Name of the target group"
  value       = module.alb.target_group_name
}

output "instance_ids" {
  description = "IDs of the EC2 instances"
  value       = module.ec2.instance_ids
}

output "private_ips" {
  description = "Private IP addresses of EC2 instances"
  value       = module.ec2.private_ips
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.hermes.repository_url
}

output "ecr_registry_id" {
  description = "Registry ID of the ECR repository"
  value       = aws_ecr_repository.hermes.registry_id
}

output "assets_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  value       = module.s3_assets.bucket_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = module.s3_assets.cloudfront_distribution_id
}

output "assets_url" {
  description = "URL for serving static assets (CloudFront)"
  value       = module.s3_assets.assets_url
}
