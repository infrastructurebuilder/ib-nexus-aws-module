# Precondition tests: assumptions about the surrounding VPC and port choices
# must fail with clear errors instead of opaque ones.

mock_provider "aws" {
  # Only ONE Tier-tagged subnet: enough for the instance, not for the ALB.
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-aaaa1111"]
    }
  }

  mock_data "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:nexus-abc123"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0123456789ABCDEFGHIJ"
    }
  }

  mock_data "aws_s3_bucket" {
    defaults = {
      id     = "test-nexus-alb-logs"
      bucket = "test-nexus-alb-logs"
      arn    = "arn:aws:s3:::test-nexus-alb-logs"
    }
  }
}

mock_provider "cloudinit" {}

variables {
  vpc_id                   = "vpc-0123456789abcdef0"
  route53_zone_name        = "example.com"
  blobstore_bucket_name    = "test-nexus-blobstore"
  alb_logs_bucket_name     = "test-nexus-alb-logs"
  admin_password_secret_id = "nexus/test-admin-password"
  ami_id                   = "ami-0123456789abcdef0"
}

run "alb_requires_two_public_subnets" {
  command = plan

  expect_failures = [aws_lb.nexus_alb]
}

run "rejects_nexus_port_inside_docker_block" {
  command = plan

  variables {
    nexus_port = 5003
  }

  expect_failures = [
    aws_lb.nexus_alb,
    aws_instance.nexus_server,
  ]
}
