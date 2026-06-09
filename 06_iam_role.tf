
# ==============================================================================
# 6. IAM ROLE & INSTANCE PROFILE
# ==============================================================================

resource "aws_iam_role" "nexus_role" {
  name = "${var.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name   = "${var.name_prefix}-ec2-role"
    system = "nexus"
  }
}

resource "aws_iam_role_policy_attachment" "nexus_ssm_policy" {
  role       = aws_iam_role.nexus_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "nexus_s3_access" {
  role       = aws_iam_role.nexus_role.name
  policy_arn = aws_iam_policy.nexus_s3_access.arn
}

# Allow the instance to read ONLY the admin-password secret at boot.
resource "aws_iam_role_policy" "nexus_secret_access" {
  name = "${var.name_prefix}-admin-password-access"
  role = aws_iam_role.nexus_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [data.aws_secretsmanager_secret.admin_password.arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nexus_profile" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.nexus_role.name

  tags = {
    Name   = "${var.name_prefix}-instance-profile"
    system = "nexus"
  }
}
