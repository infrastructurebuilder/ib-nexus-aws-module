
# Regonal WAF for ALB

resource "aws_wafv2_web_acl" "nexus" {
  name        = "${var.name_prefix}-waf"
  description = "WAF protecting the public Nexus ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # --- AWS Managed: Core rule set (OWASP common threats) ---
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      dynamic "none" {
        for_each = var.waf_block_mode ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_block_mode ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Nexus uploads (artifacts, Docker layers) can exceed the default body
        # inspection limit; allow large bodies through rather than blocking.
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            allow {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "nexus-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # --- AWS Managed: Known bad inputs ---
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      dynamic "none" {
        for_each = var.waf_block_mode ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_block_mode ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "nexus-waf-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # --- AWS Managed: SQL injection ---
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      dynamic "none" {
        for_each = var.waf_block_mode ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_block_mode ? [] : [1]
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "nexus-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  # --- IP-based rate limiting ---
  rule {
    name     = "RateLimitPerIP"
    priority = 10

    action {
      dynamic "block" {
        for_each = var.waf_block_mode ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = var.waf_block_mode ? [] : [1]
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "nexus-waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "nexus-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name   = "${var.name_prefix}-waf"
    system = "nexus"
  }
}

resource "aws_wafv2_web_acl_association" "nexus_alb" {
  resource_arn = aws_lb.nexus_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.nexus.arn
}

# --- Request logging ---
# WAF logging requires a CloudWatch log group whose name is prefixed with
# "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "nexus_waf" {
  name              = "aws-waf-logs-${var.name_prefix}"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name   = "aws-waf-logs-${var.name_prefix}"
    system = "nexus"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "nexus" {
  resource_arn            = aws_wafv2_web_acl.nexus.arn
  log_destination_configs = [aws_cloudwatch_log_group.nexus_waf.arn]

  # Redact the Authorization header so credentials (e.g. docker login / Maven
  # basic-auth) are not written to the logs.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}
