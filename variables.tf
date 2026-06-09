variable "route53_zone_name" {
  description = "The name of the Route 53 hosted zone to create the ALIAS record in"
  type        = string
}

variable "blobstore_bucket_name" {
  description = "The name of the S3 bucket to use for Nexus blob storage (must be globally unique, or leave empty to auto-generate)"
  type        = string
  nullable    = true
  default     = null
}

variable "blobstore_bucket_prefix" {
  description = "Prefix for auto-generating a unique S3 bucket name for Nexus blob storage (used if blobstore_bucket_name is empty)"
  type        = string
  default     = "nexus-blobstore"
}
variable "domain_name" {
  description = "The domain name for the Nexus server (e.g., nexus) appended to the zone name"
  type        = string
  default     = "nexus"
}
variable "vpc_id" {
  description = "The ID of the VPC to deploy Nexus into"
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to the names of named resources (security groups, ALB, target groups, IAM role/profile/policies, WAF) so multiple copies of this module can coexist in one account/region"
  type        = string
  default     = "nexus"
}

variable "manage_private_routing" {
  description = "When true, the module creates a NAT gateway, private route table, and associates the Nexus instance's subnet with it. Set to false if the VPC already provides outbound internet egress for the private subnet."
  type        = bool
  default     = true
}

variable "enable_alb_access_logs" {
  description = "When true, create an S3 bucket and enable ALB access logging to it"
  type        = bool
  default     = true
}

variable "alb_logs_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs (must be globally unique, or leave null to auto-generate from name_prefix)"
  type        = string
  nullable    = true
  default     = null
}

variable "alb_logs_retention_days" {
  description = "Number of days to retain ALB access logs in S3 before expiring them"
  type        = number
  default     = 90
}


variable "associate_public_ip" {
  description = "Whether to associate a public IP address with the instance"
  type        = bool
  default     = false
}
variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 50
}

variable "data_volume_size" {
  description = "Size of the EBS data volume for Nexus data in GB"
  type        = number
  default     = 50
}

variable "data_volume_type" {
  description = "EBS volume type for the data volume (gp3, gp2, io1, etc.)"
  type        = string
  default     = "gp3"
}

variable "tags" {
  description = "Tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "nexus-docker-instance"
}

# -----------------------------------------------------------------------------
# Nexus Container Configuration
# -----------------------------------------------------------------------------

variable "container_name" {
  description = "Name of the Nexus Docker container"
  type        = string
  default     = "nexus3"
}

variable "image" {
  description = "Nexus Docker image URI"
  type        = string
  default     = "sonatype/nexus3:latest"
}

variable "nexus_port" {
  description = "Port to expose for Nexus web interface on the host"
  type        = number
  default     = 8081
}

variable "docker_port" {
  description = "Host port to expose for the Nexus Docker registry connector"
  type        = number
  default     = 8082
}

variable "admin_password_secret_id" {
  description = "Secrets Manager secret name holding the initial Nexus admin password (fetched by the instance at boot)"
  type        = string
  default     = "/prod/sonatype_nexus/admin_password"
}

variable "additional_env_vars" {
  description = "Additional environment variables to pass to the Nexus container"
  type        = map(string)
  default     = {}
}

variable "additional_ports" {
  description = "Additional ports to expose from the container (format: {host=8082, container=8082})"
  type = list(object({
    host      = number
    container = number
  }))
  default = []
}

variable "java_max_heap" {
  description = "Java max heap size for Nexus (e.g., '1200m', '2g')"
  type        = string
  default     = "1200m"
}

variable "java_min_heap" {
  description = "Java min heap size for Nexus (e.g., '1200m', '2g')"
  type        = string
  default     = "1200m"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID to use for the EC2 instance. If null, the latest Amazon Linux 2023 AMI is used."
  type        = string
  default     = null
  nullable    = true
}


variable "restart_policy" {
  description = "Restart policy for the container"
  type        = string
  default     = "unless-stopped"
}

# -----------------------------------------------------------------------------
# WAF Configuration
# -----------------------------------------------------------------------------

variable "waf_block_mode" {
  description = "WAF rules block matching requests; if false, rules run in COUNT mode"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Max reqs from a single IP within a 5-minute window"
  type        = number
  default     = 2000
}

variable "waf_log_retention_days" {
  description = "CloudWatch WAF request logs retention period in days"
  type        = number
  default     = 90
}

