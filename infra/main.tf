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

resource "random_password" "deployer_password" {
  count   = var.server_count
  length  = 16
  special = true
}

resource "hcloud_ssh_key" "default" {
  name       = "first-time-provisioning-key"
  public_key = trimspace(file("../secrets/first-time-provisioning-ssh-key.public"))
}

resource "hcloud_server" "app" {
  count       = var.server_count
  name        = "first-time-provisioning-app-${count.index + 1}"
  image       = "ubuntu-22.04"
  server_type = "cx23"

  ssh_keys = [hcloud_ssh_key.default.id]

  # We pass the password and ssh key to cloud-init
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    root_password     = random_password.root_password[count.index].result
    deployer_password = random_password.deployer_password[count.index].result
    ssh_key           = trimspace(file("../secrets/first-time-provisioning-ssh-key.public"))
  })

  # Prevent accidental replacements if user_data changes slightly.
  # Deployment of the app is handled via 'make deploy' which doesn't touch user_data.
  lifecycle {
    ignore_changes = [user_data]
  }

  # Absolute Best Practice 2026: Cleanup known_hosts on server destruction
  # This prevents "REMOTE HOST IDENTIFICATION HAS CHANGED" errors when IPs are reused.
  provisioner "local-exec" {
    when    = destroy
    # We use a robust command that works in bash-like environments (WSL/Linux/macOS)
    command = "if [ -f ../secrets/known_hosts ]; then ssh-keygen -f ../secrets/known_hosts -R ${self.ipv4_address} && rm -f ../secrets/known_hosts.old; fi || true"
  }
}

output "ips" {
  value = hcloud_server.app[*].ipv4_address
}

output "passwords" {
  value     = random_password.root_password[*].result
  sensitive = true
}

output "deployer_passwords" {
  value     = random_password.deployer_password[*].result
  sensitive = true
}