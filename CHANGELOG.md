# Changelog

<!-- markdownlint-disable-file MD024 -->

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases are
tagged with [Semantic Versioning](https://semver.org/) (`vMAJOR.MINOR.PATCH`)
so consumers can pin `source = "...?ref=vX.Y.Z"`.

## [Unreleased]

### Changed

- The ALB now drops invalid HTTP header fields (trivy AWS-0052); remaining
  HIGH/CRITICAL trivy findings are deliberate design choices, ignored inline
  with justifications.

## [1.0.0] - 2026-08-11

First stable release: complete infrastructure for a single-instance Sonatype
Nexus on EC2/Docker behind a TLS ALB with WAF, S3 blobstore, reserved Docker
connector port block, opt-in backups and monitoring, tests, and CI. The
entries below describe the changes leading up to this release relative to
the unversioned module.

### BREAKING

- The single Docker path (`docker_port` variable, hardcoded `:5000` ALB
  listener forwarding to container port 8082) is replaced by
  `docker_port_block` (default `{from = 5000, to = 5009}`): one HTTPS
  listener + target group per port with an identity mapping (ALB `:N` →
  container `:N`). Docker repositories claim a port by setting their
  connector's HTTP port to a number in the block. Existing Docker
  repositories must move their connector from 8082 to a port inside the
  block (e.g. 5000). Applying over an existing deployment replaces the
  `:5000` listener and the docker target group; if the apply hits a
  transient duplicate-listener error, re-apply (or destroy the old listener
  first with `terraform destroy -target`).
- `nexus_docker_url` now points at the first port of the block; the new
  `docker_registry_urls` output maps every block port to its URL, and
  `docker_port_block` is exported for downstream port validation.
- The per-Docker-target-group unhealthy alarm is gone: Docker-block target
  groups health-check the Nexus core port (so unclaimed ports stay healthy),
  making the core target-group alarm the single source of truth.

### Added

- Full README (architecture, prerequisites, usage, post-deploy steps,
  inputs/outputs).
- Opt-in DLM snapshot backups of the data volume
  (`enable_data_volume_backups`).
- Opt-in CloudWatch alarms — EC2 status checks with auto-recover, target-group
  health, ALB 5xx, data-volume disk usage — plus CloudWatch agent install
  (`enable_monitoring`, `alarm_sns_topic_arn`).
- Blobstore lifecycle rules: noncurrent versions expire after
  `blobstore_noncurrent_version_expiration_days` (default 90); incomplete
  multipart uploads abort after 7 days.
- Input validations across the board, and clear precondition errors when the
  VPC lacks `Tier = Public/Private` tagged subnets.
- `alb_deletion_protection` variable (default false).
- Docker log rotation (100 MB × 3) for the Nexus container.
- Consistent tagging: `var.tags` now propagates to every taggable resource.
- Examples, terraform tests, CI, pre-commit config, LICENSE.

### Changed

- Default `image` is now pinned (`sonatype/nexus3:3.95.0`) instead of
  `latest`.
- `nexus_port` / `docker_port` are honored end-to-end (security group, target
  groups, attachments) instead of being silently fixed at 8081/8082.
- `enable_alb_access_logs = false` no longer requires the logs bucket to
  exist; `alb_logs_bucket_name` defaults to `null`.
- The initial-admin-password env file is shredded after container creation.
- **Upgrade note**: the user-data changes cause a one-time stop/start of an
  existing instance on the next apply (the script does not re-run; new
  container settings take effect on instance replacement).

### Deprecated

- `external_random_id` is unused and will be removed in the next major
  version.

### Removed

- Unused `random` provider requirement.
