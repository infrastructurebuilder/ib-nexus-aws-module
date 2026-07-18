# ==============================================================================
# 10. ALB ACCESS LOGS (S3 BUCKET + BUCKET POLICY)
# ==============================================================================

locals {
  alb_logs_enabled = var.enable_alb_access_logs
  alb_log_prefix   = var.name_prefix
}

data "aws_caller_identity" "current" {}

# The regional Elastic Load Balancing service account that delivers ALB access
# logs. (Used for standard regions; opt-in regions created after Aug 2022 use a
# service principal instead — see the README note if you deploy there.)
data "aws_elb_service_account" "main" {}

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
  bucket = data.aws_s3_bucket.alb_logs[0].id

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
        Resource  = "${data.aws_s3_bucket.alb_logs[0].arn}/${local.alb_log_prefix}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}
