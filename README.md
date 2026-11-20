# ib-nexus-aws-module

Terraform module that deploys **Sonatype Nexus Repository 3** on a single EC2
instance running Docker, fronted by a public Application Load Balancer with TLS,
a WAF, and an S3 blobstore.

Nexus **users and repositories are out of scope** — they are managed by a
companion module that configures Nexus itself after this module has stood up the
infrastructure.

## Architecture

```text
                              Internet
                                 │
                          ┌──────▼──────┐
                          │   WAFv2     │  AWS managed rule sets + per-IP rate
                          │ (REGIONAL)  │  limit; COUNT mode by default
                          └──────┬──────┘
              ┌──────────────────▼──────────────────┐
              │       ALB  (public subnets)         │
              │  :80  → HTTP 301 redirect to :443   │
              │  :443 → HTTPS  → target :8081 (UI)  │
              │  :5000-:5009 → HTTPS → same ports   │
              │   (reserved Docker connector block) │
              └──────────────────┬──────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  EC2  (private subnet)  │
                    │  Amazon Linux 2023      │
                    │  docker: sonatype/nexus3│
                    │  /data/nexus ← EBS gp3  │
                    │  (encrypted, separate   │
                    │   data volume)          │
                    └──┬─────────┬────────┬───┘
                       │         │        │
              NAT gateway   S3 blobstore  Secrets Manager
              (egress for   (via instance (initial admin
              dnf/docker    IAM role)     password, read
              pull)                       once at boot)
```

Key design points:

- **TLS everywhere in front**: an ACM certificate for
  `<domain_name>.<route53_zone_name>` is created and DNS-validated
  automatically; a Route 53 ALIAS record points at the ALB. Traffic from the ALB
  to the instance is plain HTTP inside the VPC.
- **A reserved Docker port block**: every port in `docker_port_block` (default
  5000-5009) gets an HTTPS listener on the ALB and an identity mapping straight
  through to the container (ALB `:5001` → container `:5001`). Repositories
  built elsewhere claim a port simply by setting their Docker connector's HTTP
  port to a number in the block — no infrastructure change, no redeploy. Ports
  without a connector yet answer with an ALB 502; their target groups
  health-check the Nexus core port, so unclaimed ports never show as unhealthy
  or trip alarms.
- **Secrets handling**: the initial admin password is *never* in Terraform state
  or user-data. The instance reads it from Secrets Manager at boot (scoped IAM
  policy allows `GetSecretValue` on that one secret) and passes it to the
  container via a root-only env file.
- **Data persistence**: `/nexus-data` lives on a dedicated encrypted EBS volume,
  mounted by UUID, separate from the root volume, so the instance can be
  replaced without losing the Nexus database.
- **No SSH**: the instance role includes `AmazonSSMManagedInstanceCore`; use SSM
  Session Manager (`aws ssm start-session --target <instance-id>`).
- **Optional NAT management**: with `manage_private_routing = true` (default)
  the module creates an EIP + NAT gateway + private route table and associates
  the instance's subnet. Set it to `false` if the VPC already provides egress.

## Prerequisites

The module deploys into existing infrastructure. Before applying you need:

1. **A VPC with tagged subnets.** Public subnets tagged `Tier = "Public"` and
   private subnets tagged `Tier = "Private"`. The ALB spans all public subnets;
   the instance lands in the first private subnet (sorted by ID).
2. **A public Route 53 hosted zone** matching `route53_zone_name` (used for the
   ALIAS record and ACM DNS validation).
3. **A Secrets Manager secret** whose *string value is the initial admin
   password*, named by `admin_password_secret_id`. Create it before applying;
   the module only reads its metadata.
4. **An S3 bucket for ALB access logs** (name in `alb_logs_bucket_name`), unless
   you set `enable_alb_access_logs = false`. The bucket is created elsewhere
   (e.g. by a bootstrap stack); this module configures it for delivery — SSE-S3
   encryption, an expiration lifecycle rule, and the ELB log-delivery bucket
   policy.
5. **Capacity for one Elastic IP and one NAT gateway** in the region (when
   `manage_private_routing = true`).

## Usage

```hcl
module "nexus" {
  source = "git::https://github.com/infrastructurebuilder/ib-nexus-aws-module.git?ref=<tag>"

  # Required
  vpc_id                   = "vpc-0123456789abcdef0"
  route53_zone_name        = "example.com"
  blobstore_bucket_name    = "example-nexus-blobstore"   # created by this module
  alb_logs_bucket_name     = "example-nexus-alb-logs"    # must already exist
  admin_password_secret_id = "nexus/initial-admin-password"

  # Common options (defaults shown)
  domain_name            = "nexus"          # => nexus.example.com
  name_prefix            = "nexus"
  instance_type          = "t3.medium"
  data_volume_size       = 50
  manage_private_routing = true
  waf_block_mode         = false            # WAF observes (COUNT) until true

  # Ports reserved for Docker registry connectors; repositories built
  # elsewhere each claim one (defaults shown)
  docker_port_block = {
    from = 5000
    to   = 5009
  }

  tags = {
    environment = "prod"
    cost-center = "platform"
  }
}
```

After apply, `nexus_ui_url` gives the browser URL and `nexus_docker_url` the
registry endpoint.

## Post-deploy steps

The module builds the infrastructure; Nexus itself still needs first-time
configuration (the companion repos/users module automates most of this):

1. **First login**: browse to `nexus_ui_url`, sign in as `admin` with the value
   of the Secrets Manager secret, and complete the setup wizard.
2. **Create the S3 blobstore inside Nexus**: the module creates the bucket and
   grants the instance role access, but Nexus must be told to use it
   (*Settings → Repository → Blob Stores → Create → S3*, bucket =
   `blobstore_s3_bucket_name` output, authentication = instance role — leave
   keys blank). Default repositories are skipped at boot
   (`nexus.skipDefaultRepositories=true`), so new repositories should be created
   pointing at the S3 blobstore from the start.
3. **Enable Docker connectors**: for each Docker repository, set its HTTP
   connector to an unused port from `docker_port_block` (the
   `docker_registry_urls` output lists them; `docker_port_block` is also
   exported for downstream validation). The registry is then live at
   `https://<domain>:<port>` with no infrastructure change. A block port with
   no connector behind it returns ALB 502s until one is configured.

## Operational notes

- **Shell access**: `aws ssm start-session --target $(terraform output -raw nexus_instance_id)`.
- **Egress allowlisting**: outbound traffic (proxying to Maven Central, Docker
  Hub, …) leaves via the NAT gateway; give `nat_gateway_public_ip` to any
  corporate firewall that needs to allowlist it.
- **WAF rollout**: rules start in COUNT mode (`waf_block_mode = false`). Watch
  the `aws-waf-logs-<name_prefix>` CloudWatch log group and the WAF metrics for
  false positives (large artifact uploads are the usual suspects — the body-size
  rule is already overridden to allow), then flip `waf_block_mode = true`.
  The `Authorization` header is redacted from WAF logs.
- **Container upgrades**: the container is started once by cloud-init. To
  upgrade Nexus, bump the pinned `image` tag and replace the instance (the data
  volume and S3 blobstore survive), or upgrade manually over SSM
  (`docker pull … && docker rm -f nexus3 && docker run …`). Container logs are
  rotated (json-file, 100 MB × 3), and the initial-password env file is
  shredded once the container is created.
- **Backups**: the EBS data volume holds the Nexus database — the S3 blobstore
  alone is *not* a restorable Nexus. Set `enable_data_volume_backups = true` to
  create a DLM policy that snapshots the data volume on a schedule
  (`backup_interval_hours` / `backup_time`, keeping `backup_retain_count`
  snapshots). To restore: create a volume from the newest snapshot in the
  instance's AZ, swap it for the data volume, and reboot — the fstab entry
  mounts by filesystem UUID, which snapshots preserve.
- **Monitoring**: set `enable_monitoring = true` for CloudWatch alarms — EC2
  system-check failure with **auto-recover**, instance-check failure, an
  unhealthy-target alarm on the core target group (the Docker-block target
  groups mirror it, so they carry no alarms of their own), ALB-generated 5xx, and
  data-volume disk usage (threshold `data_volume_disk_alarm_threshold`, default
  80%). Point `alarm_sns_topic_arn` at a topic to get notifications. The disk
  metric comes from the CloudWatch agent, which user-data installs at **first
  boot** — enabling monitoring on an already-running instance requires
  replacing it (`terraform apply -replace=...aws_instance.nexus_server`) before
  that one alarm gets data; the other alarms work immediately.
- **Blobstore housekeeping**: the versioned blobstore bucket expires noncurrent
  object versions after `blobstore_noncurrent_version_expiration_days` (default
  90) and aborts incomplete multipart uploads after 7 days.
- **Deletion protection**: `alb_deletion_protection` defaults to `false`; set it
  to `true` in production. The blobstore bucket has `prevent_destroy` and will
  never be deleted by Terraform.
- **Opt-in regions**: ALB access-log delivery uses the regional ELB service
  account, which exists in all standard regions. Opt-in regions launched after
  August 2022 instead require granting the
  `logdelivery.elasticloadbalancing.amazonaws.com` service principal, which this
  module does not currently do — set `enable_alb_access_logs = false` there.

## Limitations

- **Single instance**: no ASG or HA; availability relies on EBS/S3 durability
  and instance recovery. Plan for brief downtime on instance replacement.
- **`additional_ports` is host-local**: extra ports are published on the
  container but are *not* opened in the security group and have no ALB
  listener. They are only reachable via SSM port-forwarding (useful for
  debugging).
- **`external_random_id` is deprecated**: accepted but unused; it will be
  removed in a future major version.

## Development

- `terraform test` runs the suite in [tests/](tests/) against mocked providers
  (no AWS credentials needed; requires Terraform >= 1.7 for mocking).
- CI (GitHub Actions) runs fmt, validate, the tests, tflint, a trivy config
  scan, and a terraform-docs drift check.
- The inputs/outputs tables below are generated: edit variable/output
  descriptions in the `.tf` files and run `terraform-docs .` (config in
  [.terraform-docs.yml](.terraform-docs.yml)), or let pre-commit do it
  (`pre-commit install`).
- Releases are tagged `vX.Y.Z` (see [CHANGELOG.md](CHANGELOG.md)); consumers
  should pin `source = "...?ref=vX.Y.Z"` — always a tag, never a branch.
  Release tags are protected against moves and deletion.
- Branches follow git-flow. Work lands on `develop` through `feature/<name>`
  branches; `main` is the default branch and moves only when a release is
  finished into it. CI runs on pushes to both and on pull requests.
- To release:
  1. Start a release branch from `develop` (`git flow release start X.Y.Z`)
     and move the `[Unreleased]` CHANGELOG section under a new
     `## [X.Y.Z] - date` heading on it.
  2. Finish it into `main` without a git-flow tag
     (`git flow release finish X.Y.Z --notag --push`). That also brings
     `develop` up to date with `main`.
  3. Switch to `main` and run `just release X.Y.Z`, which creates and pushes
     the `vX.Y.Z` tag. The [Release workflow](.github/workflows/release.yml)
     validates the tag, re-runs the test suite, and publishes a GitHub Release
     using that changelog section as its notes.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | >= 5.0 |
| cloudinit | >= 2.3 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 5.0 |
| cloudinit | >= 2.3 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_acm_certificate.nexus_cert](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.nexus_cert_waiter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudwatch_log_group.nexus_waf](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.alb_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.core_tg_unhealthy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.data_volume_disk_usage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.instance_status_check](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.system_status_check](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_dlm_lifecycle_policy.nexus_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dlm_lifecycle_policy) | resource |
| [aws_ebs_volume.nexus_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_eip.nat_eip](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_iam_instance_profile.nexus_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.nexus_s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.dlm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.nexus_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.nexus_secret_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.cw_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.dlm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.nexus_s3_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.nexus_ssm_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.nexus_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_lb.nexus_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.docker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.nexus_core_listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.nexus_http_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.docker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.nexus_core_tg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.docker](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_lb_target_group_attachment.nexus_core_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_nat_gateway.nexus_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route53_record.nexus_alb_alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.nexus_cert_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route_table.private_rt](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private_rt_assoc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_s3_bucket.nexus_blobstore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.nexus_blobstore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.nexus_blobstore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.nexus_blobstore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.nexus_blobstore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_security_group.alb_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.nexus_ec2_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_volume_attachment.nexus_data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment) | resource |
| [aws_wafv2_web_acl.nexus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_association.nexus_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_wafv2_web_acl_logging_configuration.nexus](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration) | resource |
| [aws_ami.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_elb_service_account.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_route53_zone.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_s3_bucket.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/s3_bucket) | data source |
| [aws_secretsmanager_secret.admin_password](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret) | data source |
| [aws_subnets.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_subnets.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |
| [cloudinit_config.nexus](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| admin\_password\_secret\_id | Secrets Manager secret name holding the initial Nexus admin password (fetched by the instance at boot) | `string` | n/a | yes |
| blobstore\_bucket\_name | Name of the S3 bucket this module creates for Nexus blob storage (must be globally unique) | `string` | n/a | yes |
| route53\_zone\_name | The name of the Route 53 hosted zone to create the ALIAS record in | `string` | n/a | yes |
| vpc\_id | The ID of the VPC to deploy Nexus into | `string` | n/a | yes |
| additional\_env\_vars | Additional environment variables to pass to the Nexus container | `map(string)` | `{}` | no |
| additional\_ports | Additional ports to publish from the container onto the host (format: {host=9090, container=9090}). Host-local only: not opened in the security group and not routed by the ALB — reachable via SSM port-forwarding for debugging. | <pre>list(object({<br/>    host      = number<br/>    container = number<br/>  }))</pre> | `[]` | no |
| alarm\_sns\_topic\_arn | SNS topic ARN to notify on alarm and OK transitions. When null, alarms still exist (and the system status-check alarm still auto-recovers the instance) but send no notifications. | `string` | `null` | no |
| alb\_5xx\_alarm\_threshold | Number of ALB-generated 5xx responses within 5 minutes that triggers the 5xx alarm | `number` | `10` | no |
| alb\_deletion\_protection | Enable deletion protection on the ALB. Defaults to false to preserve existing behavior; set to true for production deployments. | `bool` | `false` | no |
| alb\_logs\_bucket\_name | Name of an existing S3 bucket to receive ALB access logs. Required when enable\_alb\_access\_logs is true; ignored otherwise. | `string` | `null` | no |
| alb\_logs\_retention\_days | Number of days to retain ALB access logs in S3 before expiring them | `number` | `90` | no |
| ami\_id | AMI ID to use for the EC2 instance. If null, the latest Amazon Linux 2023 AMI is used. | `string` | `null` | no |
| associate\_public\_ip | Whether to associate a public IP address with the instance | `bool` | `false` | no |
| backup\_interval\_hours | Hours between data-volume snapshots (DLM only accepts 1, 2, 3, 4, 6, 8, 12, or 24) | `number` | `24` | no |
| backup\_retain\_count | Number of data-volume snapshots to retain before DLM deletes the oldest | `number` | `7` | no |
| backup\_time | Time of day (UTC, 24-hour HH:MM) at which the snapshot window starts | `string` | `"03:00"` | no |
| blobstore\_noncurrent\_version\_expiration\_days | Days after which noncurrent (deleted/overwritten) object versions in the blobstore bucket are permanently expired. The bucket is versioned, so without this rule noncurrent versions accumulate forever. | `number` | `90` | no |
| container\_name | Name of the Nexus Docker container | `string` | `"nexus3"` | no |
| data\_volume\_disk\_alarm\_threshold | Percentage of used space on the Nexus data volume that triggers the disk-usage alarm | `number` | `80` | no |
| data\_volume\_size | Size of the EBS data volume for Nexus data in GB | `number` | `50` | no |
| data\_volume\_type | EBS volume type for the data volume (gp3, gp2, io1, io2, st1, sc1) | `string` | `"gp3"` | no |
| docker\_port\_block | Inclusive port range reserved for Nexus Docker registry connectors. Every port in the block gets an ALB HTTPS listener, a target group, and a host->container mapping (identity: ALB port = host port = container port), so repositories built elsewhere can claim any port in the block by setting their connector's HTTP port to it — no infrastructure change needed. | <pre>object({<br/>    from = number<br/>    to   = number<br/>  })</pre> | <pre>{<br/>  "from": 5000,<br/>  "to": 5009<br/>}</pre> | no |
| domain\_name | The domain name for the Nexus server (e.g., nexus) appended to the zone name | `string` | `"nexus"` | no |
| enable\_alb\_access\_logs | When true, enable ALB access logging to the existing S3 bucket named by alb\_logs\_bucket\_name. The bucket is not created by this module, but the module does configure it for log delivery (SSE-S3 encryption, expiration lifecycle, and the ELB delivery bucket policy). | `bool` | `true` | no |
| enable\_data\_volume\_backups | When true, create a Data Lifecycle Manager policy that takes scheduled snapshots of the Nexus data volume (which holds the Nexus database — the S3 blobstore alone is not a restorable Nexus) | `bool` | `false` | no |
| enable\_monitoring | When true, create CloudWatch alarms (EC2 status checks with auto-recover, target-group health, ALB 5xx, data-volume disk usage) and install the CloudWatch agent for disk metrics. NOTE: the agent is installed by user-data at first boot, so enabling this on an already-running instance requires replacing the instance (terraform apply -replace=...aws\_instance.nexus\_server) before the disk alarm receives data. | `bool` | `false` | no |
| external\_random\_id | DEPRECATED: no longer used by this module (callers embed their own uniqueness in the bucket-name inputs). Accepted for backward compatibility; will be removed in a future major version. | `string` | `null` | no |
| image | Nexus Docker image URI. Pinned by default (bump deliberately and replace the instance to upgrade); avoid 'latest' so instance replacement doesn't silently change the Nexus version. | `string` | `"sonatype/nexus3:3.95.0"` | no |
| instance\_name | Name tag for the EC2 instance | `string` | `"nexus-docker-instance"` | no |
| instance\_type | EC2 instance type | `string` | `"t3.medium"` | no |
| java\_max\_heap | Java max heap size for Nexus (e.g., '1200m', '2g') | `string` | `"1200m"` | no |
| java\_min\_heap | Java min heap size for Nexus (e.g., '1200m', '2g') | `string` | `"1200m"` | no |
| manage\_private\_routing | When true, the module creates a NAT gateway, private route table, and associates the Nexus instance's subnet with it. Set to false if the VPC already provides outbound internet egress for the private subnet. | `bool` | `true` | no |
| name\_prefix | Prefix applied to the names of named resources (security groups, ALB, target groups, IAM role/profile/policies, WAF) so multiple copies of this module can coexist in one account/region | `string` | `"nexus"` | no |
| nexus\_port | Host port for the Nexus web UI; the security group, target group, and attachment follow this value (the container side is fixed at 8081) | `number` | `8081` | no |
| restart\_policy | Docker restart policy for the container | `string` | `"unless-stopped"` | no |
| root\_volume\_size | Size of the root EBS volume in GB | `number` | `50` | no |
| tags | Tags to apply to all AWS resources | `map(string)` | `{}` | no |
| waf\_block\_mode | WAF rules block matching requests; if false, rules run in COUNT mode | `bool` | `false` | no |
| waf\_log\_retention\_days | CloudWatch WAF request logs retention period in days (must be a value CloudWatch Logs accepts) | `number` | `90` | no |
| waf\_rate\_limit | Max reqs from a single IP within a 5-minute window | `number` | `2000` | no |

## Outputs

| Name | Description |
|------|-------------|
| acm\_certificate\_arn | The ARN of the validated ACM Certificate |
| alb\_dns\_name | The raw DNS name of the Application Load Balancer |
| alb\_logs\_bucket\_arn | ARN of the S3 bucket receiving ALB access logs. Null when enable\_alb\_access\_logs is false. |
| alb\_logs\_bucket\_name | Name of the S3 bucket receiving ALB access logs. Null when enable\_alb\_access\_logs is false. |
| alb\_security\_group\_id | The ID of the ALB's public-facing security group |
| blobstore\_s3\_bucket\_arn | The ARN of the S3 bucket used for Nexus blob storage |
| blobstore\_s3\_bucket\_name | The name of the S3 bucket used for Nexus blob storage |
| data\_volume\_backup\_policy\_id | ID of the DLM lifecycle policy snapshotting the Nexus data volume. Null when enable\_data\_volume\_backups is false. |
| docker\_port\_block | The reserved Docker connector port range (from/to, inclusive), for downstream modules to validate their port choices against |
| docker\_registry\_urls | Map of every reserved Docker connector port to its public HTTPS URL. A repository claims a port by setting its connector's HTTP port to one of these keys. |
| domain\_name | The domain name used for the Nexus ALB (e.g. nexus.example.com) |
| nat\_gateway\_public\_ip | The public Elastic IP of the NAT Gateway (useful if your corporate firewall requires whitelisting outgoing Nexus traffic). Null when manage\_private\_routing is false. |
| nexus\_docker\_url | Convenience HTTPS URL at the first port of the Docker block (the conventional home for the primary registry). See docker\_registry\_urls for the full block. |
| nexus\_ec2\_role\_arn | The ARN of the IAM role attached to the Nexus EC2 instance (grants S3 blobstore access) |
| nexus\_ec2\_security\_group\_id | The ID of the internal security group attached to the Nexus EC2 instance |
| nexus\_instance\_id | The EC2 Instance ID of the Nexus server (used for SSM Session Manager access) |
| nexus\_instance\_private\_ip | The private IP address of the Nexus EC2 instance |
| nexus\_ui\_url | The public HTTPS URL to access the Nexus Web UI and repository endpoints |
| waf\_log\_group\_name | The CloudWatch log group receiving WAF request logs |
| waf\_web\_acl\_arn | The ARN of the WAFv2 WebACL associated with the Nexus ALB |
<!-- END_TF_DOCS -->
