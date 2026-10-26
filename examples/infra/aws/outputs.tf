output "bucket_name" {
  description = "Name of the demo bucket."
  value       = aws_s3_bucket.demo.bucket
}

output "bucket_arn" {
  description = "ARN of the demo bucket."
  value       = aws_s3_bucket.demo.arn
}
