resource "scaleway_instance_ip" "ipv4" {
  type = "routed_ipv4"
  tags = local.tags
}

resource "scaleway_instance_ip" "ipv6" {
  type = "routed_ipv6"
  tags = local.tags
}

resource "scaleway_instance_security_group" "n8n" {
  name                    = "${var.name_prefix}-n8n"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  tags                    = local.tags

  # HTTP and HTTPS from everyone, one rule per address family.
  dynamic "inbound_rule" {
    for_each = setproduct([80, 443], ["0.0.0.0/0", "::/0"])
    content {
      action   = "accept"
      protocol = "TCP"
      port     = inbound_rule.value[0]
      ip_range = inbound_rule.value[1]
    }
  }

  # SSH only from the SSH allowlist.
  dynamic "inbound_rule" {
    for_each = concat(var.ssh_allowlist_ipv4, var.ssh_allowlist_ipv6)
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 22
      ip_range = inbound_rule.value
    }
  }
}
