# ==============================================================================
# OUTPUTS: APPLICATION, LOAD BALANCING, & INSTANCE
# ==============================================================================

# --- Access URLs ---
output "nexus_ui_url" {
  description = "The public HTTPS URL to access the Nexus Web UI and repository endpoints"
  value       = "https://${aws_route53_record.nexus_alb_alias.name}"
}

output "nexus_docker_url" {
  description = "Convenience HTTPS URL at the first port of the Docker block (the conventional home for the primary registry). See docker_registry_urls for the full block."
  value       = "https://${aws_route53_record.nexus_alb_alias.name}:${var.docker_port_block.from}"
}

output "docker_registry_urls" {
  description = "Map of every reserved Docker connector port to its public HTTPS URL. A repository claims a port by setting its connector's HTTP port to one of these keys."
  value = {
    for p in local.docker_ports :
    p => "https://${aws_route53_record.nexus_alb_alias.name}:${p}"
  }
}

output "docker_port_block" {
  description = "The reserved Docker connector port range (from/to, inclusive), for downstream modules to validate their port choices against"
  value       = var.docker_port_block
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

# --- Backups ---
output "data_volume_backup_policy_id" {
  description = "ID of the DLM lifecycle policy snapshotting the Nexus data volume. Null when enable_data_volume_backups is false."
  value       = one(aws_dlm_lifecycle_policy.nexus_data[*].id)
}

# --- ALB Access Logs ---
output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket receiving ALB access logs. Null when enable_alb_access_logs is false."
  value       = one(data.aws_s3_bucket.alb_logs[*].bucket)
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket receiving ALB access logs. Null when enable_alb_access_logs is false."
  value       = one(data.aws_s3_bucket.alb_logs[*].arn)
}