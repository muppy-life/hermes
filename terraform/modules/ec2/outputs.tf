output "blue_instance_ids" {
  description = "IDs of the blue EC2 instances"
  value       = aws_instance.blue[*].id
}

output "green_instance_ids" {
  description = "IDs of the green EC2 instances"
  value       = aws_instance.green[*].id
}

output "blue_private_ips" {
  description = "Private IP addresses of the blue instances"
  value       = aws_instance.blue[*].private_ip
}

output "green_private_ips" {
  description = "Private IP addresses of the green instances"
  value       = aws_instance.green[*].private_ip
}

output "security_group_id" {
  description = "Security group ID of the application instances"
  value       = aws_security_group.app.id
}

output "iam_role_arn" {
  description = "IAM role ARN for EC2 instances"
  value       = aws_iam_role.ec2.arn
}
