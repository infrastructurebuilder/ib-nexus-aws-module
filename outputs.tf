# ==============================================================================
# OUTPUTS: APPLICATION, LOAD BALANCING, & INSTANCE
# ==============================================================================

# --- Access URLs ---
output "nexus_ui_url" {
  description = "The public HTTPS URL to access the Nexus Web UI and repository endpoints"
  value       = "https://${aws_route53_record.nexus_alb_alias.name}"
}

output "nexus_docker_url" {
  description = "The public HTTPS URL and port to use for 'docker login' and pulling/pushing images"
  value       = "https://${aws_route53_record.nexus_alb_alias.name}:5000"
}

output "alb_dns_name" {
  description = "The raw DNS name of the Application Load Balancer"
  value       = aws_lb.nexus_alb.dns_name
}

# --- Networking & Outbound ---
output "nat_gateway_public_ip" {
  description = "The public Elastic IP of the NAT Gateway (useful if your corporate firewall requires whitelisting outgoing Nexus traffic). Null when manage_private_routing is false."
  value       = one(aws_eip.nat_eip[*].public_ip)
}

output "acm_certificate_arn" {
  description = "The ARN of the validated ACM Certificate"
  value       = aws_acm_certificate.nexus_cert.arn
}

# --- Instance Details ---
output "nexus_instance_id" {
  description = "The EC2 Instance ID of the Nexus server (used for SSM Session Manager access)"
  value       = aws_instance.nexus_server.id
}

output "nexus_instance_private_ip" {
  description = "The private IP address of the Nexus EC2 instance"
  value       = aws_instance.nexus_server.private_ip
}

# --- Security Groups ---
output "alb_security_group_id" {
  description = "The ID of the ALB's public-facing security group"
  value       = aws_security_group.alb_sg.id
}

output "nexus_ec2_security_group_id" {
  description = "The ID of the internal security group attached to the Nexus EC2 instance"
  value       = aws_security_group.nexus_ec2_sg.id
}

output "domain_name" {
  description = "The domain name used for the Nexus ALB (e.g. nexus.example.com)"
  value       = aws_route53_record.nexus_alb_alias.name
}

output "blobstore_s3_bucket_name" {
  description = "The name of the S3 bucket used for Nexus blob storage"
  value       = aws_s3_bucket.nexus_blobstore.bucket
}

output "blobstore_s3_bucket_arn" {
  description = "The ARN of the S3 bucket used for Nexus blob storage"
  value       = aws_s3_bucket.nexus_blobstore.arn
}

output "nexus_ec2_role_arn" {
  description = "The ARN of the IAM role attached to the Nexus EC2 instance (grants S3 blobstore access)"
  value       = aws_iam_role.nexus_role.arn
}

# --- WAF ---
output "waf_web_acl_arn" {
  description = "The ARN of the WAFv2 WebACL associated with the Nexus ALB"
  value       = aws_wafv2_web_acl.nexus.arn
}

output "waf_log_group_name" {
  description = "The CloudWatch log group receiving WAF request logs"
  value       = aws_cloudwatch_log_group.nexus_waf.name
}

# --- ALB Access Logs ---
output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket receiving ALB access logs. Null when enable_alb_access_logs is false."
  value       = one(aws_s3_bucket.alb_logs[*].bucket)
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket receiving ALB access logs. Null when enable_alb_access_logs is false."
  value       = one(aws_s3_bucket.alb_logs[*].arn)
}