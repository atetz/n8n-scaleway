locals {
  # fr-par-1 -> fr-par
  region = regex("^([a-z]{2}-[a-z]{3})-[0-9]$", var.zone)[0]

  tags = ["n8n", var.name_prefix]
}

provider "scaleway" {
  project_id = var.project_id
  zone       = var.zone
  region     = local.region
}

data "scaleway_iam_ssh_key" "deploy" {
  name       = var.ssh_key_name
  project_id = var.project_id
}
