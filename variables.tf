
# Deliberately unused: kept only so existing callers that still pass it don't
# break. Remove in the next major version.
# tflint-ignore: terraform_unused_declarations
variable "external_random_id" {
  description = "DEPRECATED: no longer used by this module (callers embed their own uniqueness in the bucket-name inputs). Accepted for backward compatibility; will be removed in a future major version."
  type        = string
  default     = null
  nullable    = true
}
variable "route53_zone_name" {
  description = "The name of the Route 53 hosted zone to create the ALIAS record in"
  type        = string
}

variable "blobstore_bucket_name" {
  description = "Name of the S3 bucket this module creates for Nexus blob storage (must be globally unique)"
  type        = string
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

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name_prefix)) && length(var.name_prefix) <= 22
    error_message = "name_prefix must start with a letter, contain only letters, digits, and hyphens, and be at most 22 characters (target-group names derived from it are limited to 32)."
  }
}

variable "manage_private_routing" {
  description = "When true, the module creates a NAT gateway, private route table, and associates the Nexus instance's subnet with it. Set to false if the VPC already provides outbound internet egress for the private subnet."
  type        = bool
  default     = true
}

variable "enable_alb_access_logs" {
  description = "When true, enable ALB access logging to the existing S3 bucket named by alb_logs_bucket_name. The bucket is not created by this module, but the module does configure it for log delivery (SSE-S3 encryption, expiration lifecycle, and the ELB delivery bucket policy)."
  type        = bool
  default     = true
}

variable "alb_logs_bucket_name" {
  description = "Name of an existing S3 bucket to receive ALB access logs. Required when enable_alb_access_logs is true; ignored otherwise."
  type        = string
  default     = null
  nullable    = true
}

variable "alb_logs_retention_days" {
  description = "Number of days to retain ALB access logs in S3 before expiring them"
  type        = number
  default     = 90

  validation {
    condition     = var.alb_logs_retention_days >= 1
    error_message = "alb_logs_retention_days must be at least 1."
  }
}

variable "alb_deletion_protection" {
  description = "Enable deletion protection on the ALB. Defaults to false to preserve existing behavior; set to true for production deployments."
  type        = bool
  default     = false
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

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GB (Amazon Linux 2023 AMI minimum)."
  }
}

variable "data_volume_size" {
  description = "Size of the EBS data volume for Nexus data in GB"
  type        = number
  default     = 50

  validation {
    condition     = var.data_volume_size >= 1
    error_message = "data_volume_size must be at least 1 GB."
  }
}

variable "data_volume_type" {
  description = "EBS volume type for the data volume (gp3, gp2, io1, io2, st1, sc1)"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2", "st1", "sc1"], var.data_volume_type)
    error_message = "data_volume_type must be one of: gp3, gp2, io1, io2, st1, sc1."
  }
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
  description = "Nexus Docker image URI. Pinned by default (bump deliberately and replace the instance to upgrade); avoid 'latest' so instance replacement doesn't silently change the Nexus version."
  type        = string
  default     = "sonatype/nexus3:3.95.0"
}

variable "nexus_port" {
  description = "Host port for the Nexus web UI; the security group, target group, and attachment follow this value (the container side is fixed at 8081)"
  type        = number
  default     = 8081

  validation {
    condition     = var.nexus_port >= 1 && var.nexus_port <= 65535
    error_message = "nexus_port must be a valid TCP port (1-65535)."
  }
}

variable "docker_port_block" {
  description = "Inclusive port range reserved for Nexus Docker registry connectors. Every port in the block gets an ALB HTTPS listener, a target group, and a host->container mapping (identity: ALB port = host port = container port), so repositories built elsewhere can claim any port in the block by setting their connector's HTTP port to it — no infrastructure change needed."
  type = object({
    from = number
    to   = number
  })
  default = {
    from = 5000
    to   = 5009
  }

  validation {
    condition     = var.docker_port_block.from >= 1024 && var.docker_port_block.to <= 65535
    error_message = "docker_port_block must lie within 1024-65535."
  }

  validation {
    condition     = var.docker_port_block.from <= var.docker_port_block.to
    error_message = "docker_port_block.from must be <= docker_port_block.to."
  }

  validation {
    condition     = (var.docker_port_block.to - var.docker_port_block.from + 1) <= 40
    error_message = "docker_port_block may span at most 40 ports (each one is an ALB listener; the default ALB quota is 50 listeners including :80 and :443)."
  }
}

variable "admin_password_secret_id" {
  description = "Secrets Manager secret name holding the initial Nexus admin password (fetched by the instance at boot)"
  type        = string
}

variable "additional_env_vars" {
  description = "Additional environment variables to pass to the Nexus container"
  type        = map(string)
  default     = {}
}

variable "additional_ports" {
  description = "Additional ports to publish from the container onto the host (format: {host=9090, container=9090}). Host-local only: not opened in the security group and not routed by the ALB — reachable via SSM port-forwarding for debugging."
  type = list(object({
    host      = number
    container = number
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.additional_ports :
      p.host >= 1 && p.host <= 65535 && p.container >= 1 && p.container <= 65535
    ])
    error_message = "Every additional_ports host and container value must be a valid TCP port (1-65535)."
  }
}

variable "java_max_heap" {
  description = "Java max heap size for Nexus (e.g., '1200m', '2g')"
  type        = string
  default     = "1200m"

  validation {
    condition     = can(regex("^[0-9]+[mMgG]$", var.java_max_heap))
    error_message = "java_max_heap must be a number followed by m or g, e.g. '1200m' or '2g'."
  }
}

variable "java_min_heap" {
  description = "Java min heap size for Nexus (e.g., '1200m', '2g')"
  type        = string
  default     = "1200m"

  validation {
    condition     = can(regex("^[0-9]+[mMgG]$", var.java_min_heap))
    error_message = "java_min_heap must be a number followed by m or g, e.g. '1200m' or '2g'."
  }
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
  description = "Docker restart policy for the container"
  type        = string
  default     = "unless-stopped"

  validation {
    condition     = contains(["no", "always", "on-failure", "unless-stopped"], var.restart_policy)
    error_message = "restart_policy must be one of: no, always, on-failure, unless-stopped."
  }
}

# -----------------------------------------------------------------------------
# Backups (EBS data volume snapshots via DLM)
# -----------------------------------------------------------------------------

variable "enable_data_volume_backups" {
  description = "When true, create a Data Lifecycle Manager policy that takes scheduled snapshots of the Nexus data volume (which holds the Nexus database — the S3 blobstore alone is not a restorable Nexus)"
  type        = bool
  default     = false
}

variable "backup_interval_hours" {
  description = "Hours between data-volume snapshots (DLM only accepts 1, 2, 3, 4, 6, 8, 12, or 24)"
  type        = number
  default     = 24

  validation {
    condition     = contains([1, 2, 3, 4, 6, 8, 12, 24], var.backup_interval_hours)
    error_message = "backup_interval_hours must be one of: 1, 2, 3, 4, 6, 8, 12, 24."
  }
}

variable "backup_time" {
  description = "Time of day (UTC, 24-hour HH:MM) at which the snapshot window starts"
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_time))
    error_message = "backup_time must be HH:MM in 24-hour UTC time, e.g. \"03:00\"."
  }
}

variable "backup_retain_count" {
  description = "Number of data-volume snapshots to retain before DLM deletes the oldest"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retain_count >= 1 && var.backup_retain_count <= 1000
    error_message = "backup_retain_count must be between 1 and 1000."
  }
}

# -----------------------------------------------------------------------------
# Monitoring & Alarms
# -----------------------------------------------------------------------------

variable "enable_monitoring" {
  description = "When true, create CloudWatch alarms (EC2 status checks with auto-recover, target-group health, ALB 5xx, data-volume disk usage) and install the CloudWatch agent for disk metrics. NOTE: the agent is installed by user-data at first boot, so enabling this on an already-running instance requires replacing the instance (terraform apply -replace=...aws_instance.nexus_server) before the disk alarm receives data."
  type        = bool
  default     = false
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN to notify on alarm and OK transitions. When null, alarms still exist (and the system status-check alarm still auto-recovers the instance) but send no notifications."
  type        = string
  default     = null
  nullable    = true
}

variable "data_volume_disk_alarm_threshold" {
  description = "Percentage of used space on the Nexus data volume that triggers the disk-usage alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.data_volume_disk_alarm_threshold > 0 && var.data_volume_disk_alarm_threshold <= 100
    error_message = "data_volume_disk_alarm_threshold must be a percentage between 1 and 100."
  }
}

variable "alb_5xx_alarm_threshold" {
  description = "Number of ALB-generated 5xx responses within 5 minutes that triggers the 5xx alarm"
  type        = number
  default     = 10
}

# -----------------------------------------------------------------------------
# Blobstore lifecycle
# -----------------------------------------------------------------------------

variable "blobstore_noncurrent_version_expiration_days" {
  description = "Days after which noncurrent (deleted/overwritten) object versions in the blobstore bucket are permanently expired. The bucket is versioned, so without this rule noncurrent versions accumulate forever."
  type        = number
  default     = 90

  validation {
    condition     = var.blobstore_noncurrent_version_expiration_days >= 1
    error_message = "blobstore_noncurrent_version_expiration_days must be at least 1."
  }
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

  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000
    error_message = "waf_rate_limit must be between 100 (the WAF minimum) and 2,000,000,000."
  }
}

variable "waf_log_retention_days" {
  description = "CloudWatch WAF request logs retention period in days (must be a value CloudWatch Logs accepts)"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.waf_log_retention_days)
    error_message = "waf_log_retention_days must be one of the retention values CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

