terraform {
  backend "local" {
    path = "state/terraform.tfstate"
  }
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

variable "hcloud_token" {}
variable "server_count" {
  default = 2
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "random_password" "root_password" {
  count   = var.server_count
  length  = 16
  special = true
}

resource "hcloud_ssh_key" "default" {
  name       = "dev-key"
  public_key = trimspace(file("../secrets/first-time-provisioning-ssh-key.public"))
}

resource "hcloud_server" "app" {
  count       = var.server_count
  name        = "hello-app-${count.index + 1}"
  image       = "ubuntu-22.04"
  server_type = "cx23"

  ssh_keys = [hcloud_ssh_key.default.id]

  # We pass the password to cloud-init to set it
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    root_password = random_password.root_password[count.index].result
  })
}

output "ips" {
  value = hcloud_server.app[*].ipv4_address
}

output "passwords" {
  value     = random_password.root_password[*].result
  sensitive = true
}