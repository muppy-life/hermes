output "instance_ids" {
  description = "IDs of the EC2 instances"
  value       = aws_instance.app[*].id
}

output "private_ips" {
  description = "Private IP addresses of the instances"
  value       = aws_instance.app[*].private_ip
}

output "security_group_id" {
  description = "Security group ID of the application instances"
  value       = aws_security_group.app.id
}

output "iam_role_arn" {
  description = "IAM role ARN for EC2 instances"
  value       = aws_iam_role.ec2.arn
}
