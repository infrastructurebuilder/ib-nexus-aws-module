
# ==============================================================================
# 5. APPLICATION LOAD BALANCER & TARGET GROUPS
# ==============================================================================

resource "aws_lb" "nexus_alb" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = false

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = var.name_prefix
      enabled = true
    }
  }

  # The bucket policy must exist before the ALB validates write access on create.
  depends_on = [aws_s3_bucket_policy.alb_logs]

  tags = {
    Name   = "nexus-public-alb"
    system = "nexus"
  }
}

resource "aws_lb_target_group" "nexus_core_tg" {
  name     = "${var.name_prefix}-core-tg"
  port     = 8081
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

  tags = {
    Name   = "nexus-core-tg"
    system = "nexus"
  }
}

resource "aws_lb_target_group" "nexus_docker_tg" {
  name     = "${var.name_prefix}-docker-tg"
  port     = 8082
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.main.id

  health_check {
    path                = "/v2/"
    protocol            = "HTTP"
    matcher             = "200-401"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name   = "nexus-docker-tg"
    system = "nexus"
  }
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

  tags = {
    Name   = "nexus-http-redirect-listener"
    system = "nexus"
  }
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

  tags = {
    Name   = "nexus-core-listener"
    system = "nexus"
  }
}

resource "aws_lb_listener" "nexus_docker_listener" {
  load_balancer_arn = aws_lb.nexus_alb.arn
  port              = "5000"
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = aws_acm_certificate_validation.nexus_cert_waiter.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nexus_docker_tg.arn
  }

  tags = {
    Name   = "nexus-docker-listener"
    system = "nexus"
  }
}
