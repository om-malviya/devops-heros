# Random suffix so the bucket name is globally unique (S3 names are global).
resource "random_id" "suffix" {
  byte_length = 4
}

# The S3 bucket itself.
resource "aws_s3_bucket" "demo" {
  bucket        = "${var.bucket_prefix}-${var.environment}-${random_id.suffix.hex}"
  force_destroy = true # allow `terraform destroy` even if objects exist (demo only)

  tags = {
    Name        = "${var.bucket_prefix}-${var.environment}"
    Environment = var.environment
  }
}

# Keep every version of every object.
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with S3-managed keys (SSE-S3 / AES256).
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all forms of public access.
resource "aws_s3_bucket_public_access_block" "demo" {
  bucket = aws_s3_bucket.demo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
