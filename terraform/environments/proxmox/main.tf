terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # bpg/proxmox est prefere a telmate/proxmox : meilleure maintenance,
    # support cloud-init natif, provider officieusement recommande depuis 2024.
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:8006/"
  api_token = var.proxmox_api_token
  insecure  = true

  # Connexion SSH requise par bpg/proxmox pour certaines operations
  # (upload ISO, snippets cloud-init)
  ssh {
    agent       = true
    username    = "root"
    private_key = var.proxmox_ssh_private_key
  }
}
