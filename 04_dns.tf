
# ==============================================================================
# 4. ACM CERTIFICATE & ROUTE 53 DNS
# ==============================================================================

locals {
  # Construct the full domain name for the Nexus ALB
  full_domain_name = "${var.domain_name}.${var.route53_zone_name}"
}
resource "aws_acm_certificate" "nexus_cert" {
  domain_name       = local.full_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name   = "nexus-certificate"
    system = "nexus"
  }
}

resource "aws_route53_record" "nexus_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.nexus_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "nexus_cert_waiter" {
  certificate_arn         = aws_acm_certificate.nexus_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.nexus_cert_validation : record.fqdn]
}

resource "aws_route53_record" "nexus_alb_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.full_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.nexus_alb.dns_name
    zone_id                = aws_lb.nexus_alb.zone_id
    evaluate_target_health = true
  }
}
