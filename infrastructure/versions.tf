terraform {
  required_version = ">= 1.10.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.87"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }

  # Scaleway Object Storage, reached through the S3 protocol.
  # Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (a Scaleway API key).
  # The variables used here must be known at `tofu init`.
  backend "s3" {
    bucket = var.state_bucket
    key    = "${var.name_prefix}/n8n.tfstate"
    region = local.region

    endpoints = {
      s3 = "https://s3.${local.region}.scw.cloud"
    }

    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
