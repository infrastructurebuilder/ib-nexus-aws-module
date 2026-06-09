# ==============================================================================
# 10. ALB ACCESS LOGS (S3 BUCKET + BUCKET POLICY)
# ==============================================================================

locals {
  alb_logs_enabled     = var.enable_alb_access_logs
  alb_logs_bucket_name = var.alb_logs_bucket_name != null ? var.alb_logs_bucket_name : lower("${var.name_prefix}-alb-logs-${random_id.alb_logs_suffix[0].hex}")
  # S3 key prefix under which the ALB writes its logs.
  alb_log_prefix = var.name_prefix
}

data "aws_caller_identity" "current" {}

# The regional Elastic Load Balancing service account that delivers ALB access
# logs. (Used for standard regions; opt-in regions created after Aug 2022 use a
# service principal instead — see the README note if you deploy there.)
data "aws_elb_service_account" "main" {}

# Stable random suffix for the auto-named log bucket.
resource "random_id" "alb_logs_suffix" {
  count       = local.alb_logs_enabled ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket" "alb_logs" {
  count  = local.alb_logs_enabled ? 1 : 0
  bucket = local.alb_logs_bucket_name

  tags = {
    Name   = "${var.name_prefix}-alb-logs"
    system = "nexus"
  }
}

# Block all public access to the log bucket.
resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count  = local.alb_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ALB access logs only support SSE-S3 (AES256), not customer-managed KMS keys.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = local.alb_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Expire old access logs.
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = local.alb_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.alb_logs_retention_days
    }
  }
}

# Allow the regional ELB account to write access logs into the bucket.
resource "aws_s3_bucket_policy" "alb_logs" {
  count  = local.alb_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBLogDelivery"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.main.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs[0].arn}/${local.alb_log_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}
