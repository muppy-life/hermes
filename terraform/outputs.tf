output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.alb.alb_zone_id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener for blue-green switching"
  value       = module.alb.https_listener_arn
}

output "target_group_blue_arn" {
  description = "ARN of the blue target group"
  value       = module.alb.target_group_blue_arn
}

output "target_group_green_arn" {
  description = "ARN of the green target group"
  value       = module.alb.target_group_green_arn
}

output "target_group_blue_name" {
  description = "Name of the blue target group"
  value       = module.alb.target_group_blue_name
}

output "target_group_green_name" {
  description = "Name of the green target group"
  value       = module.alb.target_group_green_name
}

output "blue_instance_ids" {
  description = "IDs of the blue EC2 instances"
  value       = module.ec2.blue_instance_ids
}

output "green_instance_ids" {
  description = "IDs of the green EC2 instances"
  value       = module.ec2.green_instance_ids
}

output "blue_private_ips" {
  description = "Private IP addresses of blue EC2 instances"
  value       = module.ec2.blue_private_ips
}

output "green_private_ips" {
  description = "Private IP addresses of green EC2 instances"
  value       = module.ec2.green_private_ips
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
