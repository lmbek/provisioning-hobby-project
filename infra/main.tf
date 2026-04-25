terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

variable "hcloud_token" {}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "default" {
  name       = "dev-key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "hcloud_server" "app" {
  name        = "hello-app"
  image       = "ubuntu-22.04"
  server_type = "cx11"

  ssh_keys = [hcloud_ssh_key.default.id]

  user_data = file("${path.module}/cloud-init.yaml")
}

output "ip" {
  value = hcloud_server.app.ipv4_address
}