# ==============================================================================
# 11. DATA VOLUME BACKUPS (DLM SNAPSHOT LIFECYCLE)
# ==============================================================================
# The data volume holds the Nexus embedded database and configuration; the S3
# blobstore alone is NOT a restorable Nexus. DLM targets the volume via the
# DlmBackup tag (applied unconditionally in 01_ec2_instance.tf, so turning
# backups on later does not touch the volume).
#
# Restore procedure: create a volume from the newest snapshot in the instance's
# AZ, detach the old data volume, attach the new one, reboot the instance (the
# fstab entry mounts by filesystem UUID, which the snapshot preserves).

resource "aws_iam_role" "dlm" {
  count = var.enable_data_volume_backups ? 1 : 0
  name  = "${var.name_prefix}-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-dlm-role"
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count      = var.enable_data_volume_backups ? 1 : 0
  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "nexus_data" {
  count              = var.enable_data_volume_backups ? 1 : 0
  description        = "Scheduled snapshots of the ${var.instance_name} Nexus data volume"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      DlmBackup = "${var.name_prefix}-nexus-data"
    }

    schedule {
      name      = "${var.name_prefix}-data-volume-snapshots"
      copy_tags = true

      create_rule {
        interval      = var.backup_interval_hours
        interval_unit = "HOURS"
        times         = [var.backup_time]
      }

      retain_rule {
        count = var.backup_retain_count
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name_prefix}-data-volume-backup-policy"
  })
}
