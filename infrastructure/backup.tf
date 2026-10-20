# Backup bucket, plus a write-only identity for the backup job on the VM.
# Scaleway needs both layers: IAM grants Object Storage access at all, the
# bucket policy narrows it. The application can only write objects, and any
# bucket with its own policy (like the State bucket) stays closed to it.

resource "scaleway_object_bucket" "backups" {
  name = "${var.name_prefix}-n8n-backups"
  tags = { setup = var.name_prefix }

  lifecycle_rule {
    id      = "retention"
    enabled = true

    expiration {
      days = var.backup_retention_days
    }
  }

  lifecycle_rule {
    id                                     = "abort-incomplete-uploads"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 1
  }
}

resource "scaleway_iam_application" "backup" {
  name        = "${var.name_prefix}-n8n-backup"
  description = "Uploads n8n Backups from the VM to ${scaleway_object_bucket.backups.name}"
}

resource "scaleway_iam_policy" "backup" {
  name           = "${var.name_prefix}-n8n-backup"
  description    = "Write-only Object Storage access for the n8n backup job"
  application_id = scaleway_iam_application.backup.id

  rule {
    project_ids          = [var.project_id]
    permission_set_names = ["ObjectStorageObjectsWrite"]
  }
}

resource "scaleway_iam_api_key" "backup" {
  application_id     = scaleway_iam_application.backup.id
  default_project_id = var.project_id
  description        = "n8n backup job on ${var.name_prefix}-n8n"
}

# Who runs OpenTofu, so the bucket policy doesn't lock them out.
data "scaleway_iam_api_key" "operator" {
  access_key = var.operator_access_key
}

locals {
  operator_user_id = try(coalesce(data.scaleway_iam_api_key.operator.user_id), "")
  operator_principal = (
    local.operator_user_id != ""
    ? "user_id:${local.operator_user_id}"
    : "application_id:${data.scaleway_iam_api_key.operator.application_id}"
  )
}

resource "scaleway_object_bucket_policy" "backups" {
  bucket = scaleway_object_bucket.backups.id

  policy = jsonencode({
    Version = "2023-04-17"
    Statement = [
      {
        Sid       = "BackupJobWriteOnly"
        Effect    = "Allow"
        Principal = { SCW = "application_id:${scaleway_iam_application.backup.id}" }
        Action    = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource  = ["${scaleway_object_bucket.backups.name}/*"]
      },
      {
        Sid       = "OperatorFullAccess"
        Effect    = "Allow"
        Principal = { SCW = local.operator_principal }
        Action    = "*"
        Resource  = [scaleway_object_bucket.backups.name, "${scaleway_object_bucket.backups.name}/*"]
      },
    ]
  })
}
