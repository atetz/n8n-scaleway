variable "state_bucket" {
  description = "Name of the existing State bucket. Needed at `tofu init`."
  type        = string
}

variable "project_id" {
  description = "Scaleway project the Setup lives in. The project must have an IAM SSH key."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every resource name of this Setup."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "Use 3-32 lowercase letters, digits or hyphens, not starting or ending with a hyphen."
  }
}

variable "zone" {
  description = "Scaleway zone for the VM and IPs. The region (for buckets) is derived from it."
  type        = string
  default     = "fr-par-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]{3}-[0-9]$", var.zone))
    error_message = "Use a zone like fr-par-1, nl-ams-1 or pl-waw-1."
  }
}

variable "image" {
  description = "Marketplace image label. `docker` is Scaleway's Docker InstantApp."
  type        = string
  default     = "docker"
}

variable "instance_type" {
  description = "Instance commercial type."
  type        = string
  default     = "DEV1-M"
}

variable "root_volume_size_gb" {
  description = "Size of the root volume in GB."
  type        = number
  default     = 40
}

variable "ssh_key_name" {
  description = "Name of the IAM SSH key in the project. Its public key is given to the Deploy user."
  type        = string
}

variable "ssh_allowlist_ipv4" {
  description = "IPv4 CIDRs allowed to reach SSH (port 22)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.ssh_allowlist_ipv4 : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "Every entry must be an IPv4 CIDR, e.g. 203.0.113.10/32."
  }
}

variable "ssh_allowlist_ipv6" {
  description = "IPv6 CIDRs allowed to reach SSH (port 22)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.ssh_allowlist_ipv6 : can(cidrhost(c, 0)) && strcontains(c, ":")])
    error_message = "Every entry must be an IPv6 CIDR, e.g. 2001:db8::/64."
  }
}

variable "operator_access_key" {
  description = "Access key ID of the API key you run OpenTofu with, so the Backup bucket policy keeps you in. Set in the Secrets file as TF_VAR_operator_access_key=$(scw config get access-key)."
  type        = string
}

variable "backup_retention_days" {
  description = "Days a Backup is kept before Object Storage deletes it."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Retention must be at least 1 day."
  }
}
