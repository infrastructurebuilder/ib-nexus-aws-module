
# ==============================================================================
# 5. APPLICATION LOAD BALANCER & TARGET GROUPS
# ==============================================================================

resource "aws_lb" "nexus_alb" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = var.alb_deletion_protection

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = data.aws_s3_bucket.alb_logs[0].id
      prefix  = var.name_prefix
      enabled = true
    }
  }

  # The bucket policy must exist before the ALB validates write access on create.
  depends_on = [aws_s3_bucket_policy.alb_logs]

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.public.ids) >= 2
      error_message = "Fewer than two public subnets found: the ALB requires subnets tagged Tier = \"Public\" in at least two availability zones."
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-public-alb"
  })
}

resource "aws_lb_target_group" "nexus_core_tg" {
  name     = "${var.name_prefix}-core-tg"
  port     = var.nexus_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-core-tg"
  })
}

# One target group per port in the reserved Docker block. Health checks probe
# the Nexus core port instead of the connector port: an unclaimed port has
# nothing listening on it, and probing it directly would leave every unused
# target group permanently unhealthy. With the core probe, a block port is
# "healthy" whenever Nexus itself is up; a request to a port whose connector
# hasn't been configured yet simply gets a 502 from the ALB.
resource "aws_lb_target_group" "docker" {
  for_each = local.docker_ports

  name     = "${var.name_prefix}-dkr-${each.value}"
  port     = tonumber(each.value)
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id

  health_check {
    port                = var.nexus_port
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-dkr-${each.value}"
  })
}

resource "aws_lb_listener" "nexus_http_redirect" {
  load_balancer_arn = aws_lb.nexus_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-redir-lstn"
  })
}

resource "aws_lb_listener" "nexus_core_listener" {
  load_balancer_arn = aws_lb.nexus_alb.arn
  port              = "443"
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = aws_acm_certificate_validation.nexus_cert_waiter.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nexus_core_tg.arn
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-core-listener"
  })
}

resource "aws_lb_listener" "docker" {
  for_each = local.docker_ports

  load_balancer_arn = aws_lb.nexus_alb.arn
  port              = tonumber(each.value)
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = aws_acm_certificate_validation.nexus_cert_waiter.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.docker[each.key].arn
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-dkr-lstn-${each.value}"
  })
}
