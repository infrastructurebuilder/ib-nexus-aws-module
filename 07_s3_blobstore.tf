resource "aws_s3_bucket" "nexus_blobstore" {
  bucket = var.blobstore_bucket_name

  # The blobstore holds all Nexus artifacts; never let Terraform destroy it.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.base_tags, {
    Name = var.blobstore_bucket_name
  })
}

# Enable versioning for artifact version control
resource "aws_s3_bucket_versioning" "nexus_blobstore" {
  bucket = aws_s3_bucket.nexus_blobstore.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "nexus_blobstore" {
  bucket = aws_s3_bucket.nexus_blobstore.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The bucket is versioned, so expired/overwritten blobs linger as noncurrent
# versions; expire them after a grace period, and clean up multipart uploads
# that Nexus (or a client) abandoned mid-transfer.
resource "aws_s3_bucket_lifecycle_configuration" "nexus_blobstore" {
  bucket = aws_s3_bucket.nexus_blobstore.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.blobstore_noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Provider docs recommend waiting for versioning before attaching
  # noncurrent-version rules.
  depends_on = [aws_s3_bucket_versioning.nexus_blobstore]
}

# Block public access to prevent accidental exposure
resource "aws_s3_bucket_public_access_block" "nexus_blobstore" {
  bucket = aws_s3_bucket.nexus_blobstore.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Standalone managed policy for Nexus S3 access
resource "aws_iam_policy" "nexus_s3_access" {
  name        = "${var.name_prefix}-s3-access"
  description = "Allows full access to the Nexus blobstore S3 bucket"

  # Scoped to the actions Sonatype documents for an S3 blobstore — bucket-level
  # operations on the bucket ARN, object-level operations on its contents.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BucketLevel"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = [aws_s3_bucket.nexus_blobstore.arn]
      },
      {
        Sid    = "ObjectLevel"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging",
          "s3:DeleteObjectTagging",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = ["${aws_s3_bucket.nexus_blobstore.arn}/*"]
      }
    ]
  })
}
