output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.assets.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.assets.id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.assets.domain_name
}

output "assets_url" {
  description = "URL for serving static assets"
  value       = "https://${aws_cloudfront_distribution.assets.domain_name}"
}
