# Variable-validation tests: each run supplies one invalid value and expects
# the matching validation to reject it. Providers are mocked only so the runs
# need no AWS credentials; the plans abort at variable validation regardless.

# Even expected-failure runs evaluate the full plan (Terraform gathers all
# diagnostics), so the mocked VPC still needs enough subnets to plan cleanly.
mock_provider "aws" {
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-aaaa1111", "subnet-bbbb2222"]
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

run "rejects_long_name_prefix" {
  command = plan

  variables {
    name_prefix = "this-prefix-is-far-too-long-for-target-groups"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_name_prefix_with_invalid_chars" {
  command = plan

  variables {
    name_prefix = "nexus_prod"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_out_of_range_port" {
  command = plan

  variables {
    nexus_port = 70000
  }

  expect_failures = [var.nexus_port]
}

run "rejects_invalid_additional_ports" {
  command = plan

  variables {
    additional_ports = [{ host = 0, container = 9090 }]
  }

  expect_failures = [var.additional_ports]
}

run "rejects_inverted_docker_port_block" {
  command = plan

  variables {
    docker_port_block = {
      from = 6010
      to   = 6000
    }
  }

  expect_failures = [var.docker_port_block]
}

run "rejects_oversized_docker_port_block" {
  command = plan

  variables {
    docker_port_block = {
      from = 5000
      to   = 5100
    }
  }

  expect_failures = [var.docker_port_block]
}

run "rejects_bad_heap_format" {
  command = plan

  variables {
    java_max_heap = "1200mb"
  }

  expect_failures = [var.java_max_heap]
}

run "rejects_unknown_volume_type" {
  command = plan

  variables {
    data_volume_type = "standard"
  }

  expect_failures = [var.data_volume_type]
}

run "rejects_small_root_volume" {
  command = plan

  variables {
    root_volume_size = 4
  }

  expect_failures = [var.root_volume_size]
}

run "rejects_invalid_restart_policy" {
  command = plan

  variables {
    restart_policy = "sometimes"
  }

  expect_failures = [var.restart_policy]
}

run "rejects_waf_rate_limit_below_minimum" {
  command = plan

  variables {
    waf_rate_limit = 50
  }

  expect_failures = [var.waf_rate_limit]
}

run "rejects_unsupported_waf_log_retention" {
  command = plan

  variables {
    waf_log_retention_days = 45
  }

  expect_failures = [var.waf_log_retention_days]
}

run "rejects_invalid_backup_interval" {
  command = plan

  variables {
    backup_interval_hours = 5
  }

  expect_failures = [var.backup_interval_hours]
}

run "rejects_invalid_backup_time" {
  command = plan

  variables {
    backup_time = "25:00"
  }

  expect_failures = [var.backup_time]
}
