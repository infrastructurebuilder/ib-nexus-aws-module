# Behavior tests against mocked providers: conditional resource creation and
# port wiring. No AWS credentials required.

mock_provider "aws" {
  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-aaaa1111", "subnet-bbbb2222"]
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

run "defaults" {
  command = plan

  assert {
    condition     = length(aws_eip.nat_eip) == 1 && length(aws_nat_gateway.nexus_nat) == 1 && length(aws_route_table.private_rt) == 1
    error_message = "manage_private_routing defaults to true, so the NAT gateway, EIP, and route table should be created"
  }

  assert {
    condition     = length(data.aws_s3_bucket.alb_logs) == 1 && length(aws_s3_bucket_policy.alb_logs) == 1
    error_message = "ALB access logging defaults to enabled, so the bucket lookup and delivery policy should exist"
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.nexus_data) == 0
    error_message = "backups default to disabled, so no DLM policy should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.system_status_check) == 0
    error_message = "monitoring defaults to disabled, so no alarms should be created"
  }

  assert {
    condition     = length(aws_lb_target_group.docker) == 10 && contains(keys(aws_lb_listener.docker), "5000")
    error_message = "the default docker_port_block (5000-5009) must provision ten listener/target-group pairs including :5000"
  }
}

run "port_wiring_follows_variables" {
  command = plan

  variables {
    nexus_port = 9001
    docker_port_block = {
      from = 6000
      to   = 6004
    }
  }

  assert {
    condition     = aws_lb_target_group.nexus_core_tg.port == 9001
    error_message = "core target group port must follow nexus_port"
  }

  assert {
    condition     = length(aws_lb_target_group.docker) == 5 && length(aws_lb_listener.docker) == 5 && length(aws_lb_target_group_attachment.docker) == 5
    error_message = "every port in docker_port_block must get a target group, listener, and attachment"
  }

  assert {
    condition     = aws_lb_target_group.docker["6002"].port == 6002 && aws_lb_listener.docker["6002"].port == 6002
    error_message = "docker listeners/target groups must use an identity port mapping"
  }

  assert {
    condition     = aws_lb_target_group.docker["6002"].health_check[0].port == "9001"
    error_message = "docker target groups must health-check the Nexus core port so unclaimed ports stay healthy"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.nexus_ec2_sg.ingress : r.from_port == 9001 && r.to_port == 9001
      ]) && anytrue([
      for r in aws_security_group.nexus_ec2_sg.ingress : r.from_port == 6000 && r.to_port == 6004
    ])
    error_message = "instance security group ingress must cover nexus_port and the docker port block"
  }

  assert {
    condition     = output.docker_registry_urls["6000"] == output.nexus_docker_url
    error_message = "nexus_docker_url must point at the first port of the block"
  }
}

run "no_managed_routing" {
  command = plan

  variables {
    manage_private_routing = false
  }

  assert {
    condition     = length(aws_eip.nat_eip) == 0 && length(aws_nat_gateway.nexus_nat) == 0 && length(aws_route_table.private_rt) == 0 && length(aws_route_table_association.private_rt_assoc) == 0
    error_message = "manage_private_routing = false must not create any NAT/routing resources"
  }
}

run "alb_logs_disabled" {
  command = plan

  variables {
    enable_alb_access_logs = false
    alb_logs_bucket_name   = null
  }

  assert {
    condition     = length(data.aws_s3_bucket.alb_logs) == 0
    error_message = "disabling ALB access logs must not look up (or require) the logs bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_policy.alb_logs) == 0 && length(aws_s3_bucket_lifecycle_configuration.alb_logs) == 0 && length(aws_s3_bucket_server_side_encryption_configuration.alb_logs) == 0
    error_message = "disabling ALB access logs must not configure the logs bucket"
  }

  assert {
    condition     = output.alb_logs_bucket_name == null && output.alb_logs_bucket_arn == null
    error_message = "ALB-logs outputs must be null when logging is disabled"
  }
}

run "backups_enabled" {
  command = plan

  variables {
    enable_data_volume_backups = true
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.nexus_data) == 1 && length(aws_iam_role.dlm) == 1
    error_message = "enabling backups must create the DLM policy and its role"
  }

  assert {
    condition     = aws_ebs_volume.nexus_data.tags["DlmBackup"] == aws_dlm_lifecycle_policy.nexus_data[0].policy_details[0].target_tags["DlmBackup"]
    error_message = "the DLM policy's target tag must match the tag on the data volume"
  }
}

run "monitoring_enabled" {
  command = plan

  variables {
    enable_monitoring   = true
    alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:alerts"
  }

  assert {
    condition = alltrue([
      length(aws_cloudwatch_metric_alarm.system_status_check) == 1,
      length(aws_cloudwatch_metric_alarm.instance_status_check) == 1,
      length(aws_cloudwatch_metric_alarm.core_tg_unhealthy) == 1,
      length(aws_cloudwatch_metric_alarm.alb_5xx) == 1,
      length(aws_cloudwatch_metric_alarm.data_volume_disk_usage) == 1,
      length(aws_iam_role_policy_attachment.cw_agent) == 1,
    ])
    error_message = "enabling monitoring must create all five alarms and the CloudWatch agent policy attachment"
  }

  assert {
    condition     = contains(aws_cloudwatch_metric_alarm.system_status_check[0].alarm_actions, "arn:aws:sns:us-east-1:123456789012:alerts")
    error_message = "alarms must notify the provided SNS topic"
  }
}
