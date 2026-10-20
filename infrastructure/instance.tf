resource "scaleway_instance_server" "n8n" {
  name              = "${var.name_prefix}-n8n"
  type              = var.instance_type
  image             = var.image
  security_group_id = scaleway_instance_security_group.n8n.id
  ip_ids            = [scaleway_instance_ip.ipv4.id, scaleway_instance_ip.ipv6.id]
  tags              = local.tags

  root_volume {
    size_in_gb = var.root_volume_size_gb
  }

  # Runs once, on first boot: Deploy user and SSH hardening.
  user_data = {
    cloud-init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      ssh_public_key = trimspace(data.scaleway_iam_ssh_key.deploy.public_key)
    })
  }

  lifecycle {
    # The root volume holds the live database. Remove this guard on purpose to rebuild.
    prevent_destroy = true
    # A newer image behind the label, or edited cloud-init, must never replace the VM.
    ignore_changes = [image, user_data]
  }
}
