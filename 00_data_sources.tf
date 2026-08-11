# ==============================================================================
# 1. DATA SOURCES
# ==============================================================================

# Pre-existing bucket for ALB access logs; only looked up when logging is
# enabled, so the bucket (and its name) are not required otherwise.
data "aws_s3_bucket" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = var.alb_logs_bucket_name

  lifecycle {
    precondition {
      condition     = var.alb_logs_bucket_name != null
      error_message = "alb_logs_bucket_name must be set when enable_alb_access_logs is true."
    }
  }
}

data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier = "Public"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = {
    Tier = "Private"
  }
}

data "aws_route53_zone" "main" {
  name         = var.route53_zone_name
  private_zone = false
}

# Metadata (ARN) for the Secrets Manager secret holding the initial admin
# password. We deliberately do NOT read the secret version here: the value is
# fetched at boot by the instance via GetSecretValue, so the plaintext never
# lands in Terraform state or the instance user-data.
data "aws_secretsmanager_secret" "admin_password" {
  name = var.admin_password_secret_id
}

data "aws_ami" "al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
