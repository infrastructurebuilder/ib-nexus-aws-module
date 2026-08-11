
# ==============================================================================
# 3. SECURITY GROUPS
# ==============================================================================

resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Allow inbound traffic for Nexus UI/Maven and Docker"
  vpc_id      = data.aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description = "HTTP (redirected to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS for Nexus Core"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Docker registry connector port block"
    from_port   = var.docker_port_block.from
    to_port     = var.docker_port_block.to
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "nexus_ec2_sg" {
  name_prefix = "${var.name_prefix}-ec2-"
  description = "Allow traffic from ALB to Nexus"
  vpc_id      = data.aws_vpc.main.id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description     = "Nexus Core traffic from ALB"
    from_port       = var.nexus_port
    to_port         = var.nexus_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "Nexus Docker connector port block from ALB"
    from_port       = var.docker_port_block.from
    to_port         = var.docker_port_block.to
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Outbound internet access via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-ec2-sg"
  })
}
