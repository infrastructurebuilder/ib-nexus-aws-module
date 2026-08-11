
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

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-nexus-cert"
  })
}

# The for_each key is the certificate's single domain — statically known, and
# identical to the key the old dvo-derived for_each produced, so existing
# state addresses are unchanged. Keeping the key static (rather than iterating
# domain_validation_options directly) lets the expansion be resolved even when
# the validation options themselves are unknown at plan time, e.g. under
# mocked providers in `terraform test`.
resource "aws_route53_record" "nexus_cert_validation" {
  for_each = toset([local.full_domain_name])

  allow_overwrite = true
  name            = [for dvo in aws_acm_certificate.nexus_cert.domain_validation_options : dvo.resource_record_name if dvo.domain_name == each.value][0]
  records         = [for dvo in aws_acm_certificate.nexus_cert.domain_validation_options : dvo.resource_record_value if dvo.domain_name == each.value]
  ttl             = 60
  type            = [for dvo in aws_acm_certificate.nexus_cert.domain_validation_options : dvo.resource_record_type if dvo.domain_name == each.value][0]
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
