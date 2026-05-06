terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name   = var.node_name
  vm_id       = var.vmid
  name        = var.hostname
  description = var.description
  tags        = var.tags

  cpu {
    cores   = var.cpu_cores
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  # Disque principal vide — OPNsense s'installe depuis l'ISO
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    file_format  = "raw"
    discard      = "on"
  }

  # CD-ROM avec l'ISO OPNsense
  cdrom {
    file_id = "${var.iso_datastore}:iso/${var.iso_file}"
  }

  # Interfaces reseau : l'ordre dans la liste = em0, em1, em2...
  dynamic "network_device" {
    for_each = var.network_interfaces
    content {
      bridge   = network_device.value.bridge
      model    = "virtio"
      vlan_id  = network_device.value.vlan_tag > 0 ? network_device.value.vlan_tag : null
      firewall = false
    }
  }

  # Pas d'agent QEMU ni cloud-init pour OPNsense
  agent {
    enabled = false
  }

  operating_system {
    type = "other"
  }

  # Ordre de boot : d'abord le CD-ROM pour la premiere installation,
  # ensuite manuellement changer en scsi0 dans l'UI Proxmox
  boot_order = ["ide2", "scsi0"]

  started = true
  on_boot = false
}
