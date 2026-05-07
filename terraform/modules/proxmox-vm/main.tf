terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

locals {
  # Construit l'ipconfig0 en format bpg/proxmox
  ipconfig = "ip=${var.ip_address},gw=${var.gateway}"
}

resource "proxmox_virtual_environment_vm" "vm" {
  node_name   = var.node_name
  vm_id       = var.vmid
  name        = var.hostname
  description = var.description
  tags        = var.tags

  # Clone depuis le template Debian 12 cloud-init
  clone {
    vm_id   = var.template_vmid
    full    = true
    retries = 3
  }

  cpu {
    cores   = var.cpu_cores
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  # Disque principal : redimensionnement du clone
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    file_format  = "raw"
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge   = var.bridge
    model    = "virtio"
    vlan_id  = var.vlan_tag > 0 ? var.vlan_tag : null
    firewall = false
  }

  # Interface cloud-init : stockee sur le meme datastore
  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys = [var.ssh_public_keys]
    }
  }

  # L'agent QEMU doit etre installe par cloud-init avant que Terraform
  # puisse recuperer l'IP. On attend 3 minutes max.
  agent {
    enabled = true
    timeout = "30s"
    trim    = true
  }

  # Evite les recreations inutiles dues au redimensionnement du clone
  lifecycle {
    ignore_changes = [clone]
  }

  operating_system {
    type = "l26"
  }

  vga {
    type = "serial0"
  }

  serial_device {}

  # Demarre automatiquement avec le noeud Proxmox
  started    = true
  on_boot    = true
  boot_order = ["scsi0"]
}
