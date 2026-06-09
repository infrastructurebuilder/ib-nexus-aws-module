
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
    description = "Docker Registry V2 API"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name   = "${var.name_prefix}-alb-sg"
    system = "nexus"
  }
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
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "Nexus Docker traffic from ALB"
    from_port       = 8082
    to_port         = 8082
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

  tags = {
    Name   = "${var.name_prefix}-ec2-sg"
    system = "nexus"
  }
}
