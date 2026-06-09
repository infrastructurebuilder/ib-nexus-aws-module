locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.al2023[0].id

  common_tags = merge(var.tags, {
    Name      = var.instance_name
    ManagedBy = "terraform"
    system    = "nexus"
  })

  sorted_subnet_ids = sort(data.aws_subnets.private.ids)


  # Build docker run port arguments
  port_flags = join(" ", concat(
    ["-p ${var.nexus_port}:8081"],
    ["-p ${var.docker_port}:8082"],
    [for p in var.additional_ports : "-p ${p.host}:${p.container}"]
  ))

  # Build docker run env arguments. The admin password is intentionally NOT
  # here; it is fetched from Secrets Manager at boot and passed via --env-file
  # so it never appears in state, user-data, or the process list.
  env_flags = join(" ", concat(
    [
      "-e INSTALL4J_ADD_VM_PARAMS='-Xms${var.java_min_heap} -Xmx${var.java_max_heap} -XX:MaxDirectMemorySize=2g -Djava.util.prefs.userRoot=/nexus-data/javaprefs'",
    ],
    [for k, v in var.additional_env_vars : "-e ${k}='${v}'"]
  ))
}



# -----------------------------------------------------------------------------
# Cloud-Init User Data
# -----------------------------------------------------------------------------

data "cloudinit_config" "nexus" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    content      = <<-USERDATA
      #!/bin/bash
      set -euo pipefail

      # --- Install Docker ---
      dnf install -y docker
      systemctl enable docker
      systemctl start docker

      # --- Resolve, format, and mount the data volume ---
      # On Nitro instances EBS volumes are exposed as NVMe devices whose kernel
      # names are not guaranteed to match the requested /dev/xvdf, so resolve
      # the data disk dynamically as the only non-root whole disk.
      DATA_MOUNT="/data/nexus"
      ROOT_DISK="$(lsblk -no PKNAME "$(findmnt -no SOURCE /)")"

      DATA_DEVICE=""
      for _ in $(seq 1 60); do
        for d in $(lsblk -dn -o NAME); do
          [ "$d" = "$ROOT_DISK" ] && continue
          DATA_DEVICE="/dev/$d"
          break
        done
        [ -n "$DATA_DEVICE" ] && [ -b "$DATA_DEVICE" ] && break
        DATA_DEVICE=""
        sleep 2
      done

      if [ -z "$DATA_DEVICE" ]; then
        echo "ERROR: data volume did not appear" >&2
        exit 1
      fi

      if ! blkid "$DATA_DEVICE"; then
        mkfs.xfs "$DATA_DEVICE"
      fi

      mkdir -p "$DATA_MOUNT"

      # Persist by filesystem UUID — NVMe device names can change across reboots.
      DATA_UUID="$(blkid -s UUID -o value "$DATA_DEVICE")"
      if ! grep -q "$DATA_UUID" /etc/fstab; then
        echo "UUID=$DATA_UUID $DATA_MOUNT xfs defaults,nofail 0 2" >> /etc/fstab
      fi
      mount "$DATA_MOUNT"

      # Write nexus.properties before first boot so Nexus picks it up on start
      NEXUS_PROPS="$DATA_MOUNT/etc/nexus.properties"
      mkdir -p "$(dirname "$NEXUS_PROPS")"
      echo "nexus.skipDefaultRepositories=true" >> "$NEXUS_PROPS"
      chown 200:200 "$NEXUS_PROPS"

      # Nexus runs as UID 200 inside the container
      chown -R 200:200 "$DATA_MOUNT"

      # --- Fetch the initial admin password from Secrets Manager ---
      # IMDSv2 (token-required) is used to discover the region.
      TOKEN="$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 300")"
      REGION="$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region)"

      if ! command -v aws >/dev/null 2>&1; then
        dnf install -y awscli || {
          dnf install -y unzip
          curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
          unzip -q /tmp/awscliv2.zip -d /tmp
          /tmp/aws/install
        }
      fi

      # Write the password to a root-only env file so it is never visible in the
      # process list and never passed through shell interpolation (no quoting or
      # injection risk regardless of the password's contents).
      NEXUS_ENV_FILE=/root/nexus.env
      umask 077
      printf 'NEXUS_SECURITY_INITIAL_PASSWORD=%s\n' \
        "$(aws secretsmanager get-secret-value \
          --region "$REGION" \
          --secret-id '${var.admin_password_secret_id}' \
          --query SecretString --output text)" > "$NEXUS_ENV_FILE"

      # --- Pull and run Nexus ---
      docker pull ${var.image}
      docker run -d \
        --name ${var.container_name} \
        --restart ${var.restart_policy} \
        --env-file "$NEXUS_ENV_FILE" \
        ${local.port_flags} \
        ${local.env_flags} \
        -v "$DATA_MOUNT":/nexus-data \
        ${var.image}
    USERDATA
  }
}

# ==============================================================================
# 7. EC2 INSTANCE (SONATYPE NEXUS)
# ==============================================================================
resource "aws_instance" "nexus_server" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.sorted_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.nexus_ec2_sg.id]
  associate_public_ip_address = var.associate_public_ip
  user_data                   = data.cloudinit_config.nexus.rendered
  iam_instance_profile        = aws_iam_instance_profile.nexus_profile.name

  # The instance lives in a private subnet and user-data must reach the
  # internet (dnf install, docker pull). Ensure NAT egress routing exists first.
  depends_on = [aws_route_table_association.private_rt_assoc]

  # Require IMDSv2 (token-based). Hop limit of 2 is needed so the Nexus
  # container (one extra network hop via Docker's bridge) can still reach IMDS
  # to obtain the instance-role credentials for the S3 blobstore.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EBS Data Volume
# -----------------------------------------------------------------------------

resource "aws_ebs_volume" "nexus_data" {
  availability_zone = aws_instance.nexus_server.availability_zone
  size              = var.data_volume_size
  type              = var.data_volume_type
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${var.instance_name}-data"
  })
}

resource "aws_volume_attachment" "nexus_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.nexus_data.id
  instance_id = aws_instance.nexus_server.id
}
