locals {
  ipv6_address = one([for ip in scaleway_instance_server.n8n.public_ips : ip.address if ip.family == "inet6"])
}

output "ipv4_address" {
  description = "Public IPv4 address. Create an A record for the domain."
  value       = scaleway_instance_ip.ipv4.address
}

output "ipv6_address" {
  description = "Public IPv6 address. Create an AAAA record for the domain."
  value       = local.ipv6_address
}

output "backup_bucket" {
  description = "Backup bucket name."
  value       = scaleway_object_bucket.backups.name
}

output "backup_region" {
  description = "Region of the Backup bucket."
  value       = local.region
}

output "backup_access_key" {
  description = "Access key for the backup job. Copy into the Secrets file as BACKUP_ACCESS_KEY."
  value       = scaleway_iam_api_key.backup.access_key
}

output "backup_secret_key" {
  description = "Secret key for the backup job. Copy into the Secrets file as BACKUP_SECRET_KEY."
  value       = scaleway_iam_api_key.backup.secret_key
  sensitive   = true
}

output "next_steps" {
  description = "What to do before running the Provisioning stage."
  value       = <<-EOT
    1. DNS for your domain:
         A     ${scaleway_instance_ip.ipv4.address}
         AAAA  ${local.ipv6_address}
    2. Secrets file (.env):
         BACKUP_ACCESS_KEY = $(tofu output -raw backup_access_key)
         BACKUP_SECRET_KEY = $(tofu output -raw backup_secret_key)
    3. Run the Provisioning stage once DNS resolves.
  EOT
}
