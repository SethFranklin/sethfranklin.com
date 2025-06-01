
output "s3_bucket_url" {
  value = "s3://${aws_s3_bucket.website.bucket}?region=${var.aws_region}"
}

