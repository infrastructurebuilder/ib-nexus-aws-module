# Minimal example: every required input, defaults for everything else.
# Values are placeholders — point them at real infrastructure before applying.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "nexus" {
  source = "../.."

  # An existing VPC with subnets tagged Tier = "Public" (>= 2 AZs) and
  # Tier = "Private" (>= 1).
  vpc_id = "vpc-0123456789abcdef0"

  # An existing public Route 53 hosted zone; the module creates
  # nexus.<zone> plus the ACM validation records in it.
  route53_zone_name = "example.com"

  # Created by the module (must be globally unique).
  blobstore_bucket_name = "example-nexus-blobstore"

  # Must already exist; the module attaches encryption, lifecycle, and the
  # ELB log-delivery policy to it.
  alb_logs_bucket_name = "example-nexus-alb-logs"

  # Must already exist; its string value is the initial admin password.
  admin_password_secret_id = "nexus/initial-admin-password"

  tags = {
    environment = "example"
  }
}

output "nexus_ui_url" {
  value = module.nexus.nexus_ui_url
}

output "nexus_docker_url" {
  value = module.nexus.nexus_docker_url
}
