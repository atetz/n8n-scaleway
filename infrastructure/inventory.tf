resource "local_file" "inventory" {
  filename        = "${path.module}/../provisioning/inventory.ini"
  file_permission = "0644"
  content         = <<-EOT
    [n8n]
    ${scaleway_instance_ip.ipv4.address} ansible_user=deploy backup_bucket=${scaleway_object_bucket.backups.name} backup_region=${local.region}
  EOT
}
