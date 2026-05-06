variable "proxmox_host" {
  description = "IP ou FQDN de l'hote Proxmox (sans port ni schema)"
  type        = string
  default     = "192.168.1.10"
}

variable "proxmox_api_token" {
  description = "Token API Proxmox au format 'USER@REALM!TOKENID=UUID'"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key" {
  description = "Cle SSH privee pour les operations root sur Proxmox (chemin ou contenu)"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_node" {
  description = "Nom du noeud Proxmox (visible dans l'UI, generalement 'pve')"
  type        = string
  default     = "pve"
}

variable "proxmox_datastore" {
  description = "Stockage Proxmox pour les disques VM (ex: local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "template_vmid" {
  description = "VMID du template Debian 12 cloud-init (a creer manuellement)"
  type        = number
  default     = 9000
}

variable "opnsense_iso_file" {
  description = "Nom du fichier ISO OPNsense dans le stockage Proxmox"
  type        = string
  default     = "OPNsense-25.1-dvd-amd64.iso"
}

variable "opnsense_iso_datastore" {
  description = "Stockage Proxmox contenant l'ISO OPNsense"
  type        = string
  default     = "local"
}

# Cle SSH publique pour l'utilisateur ansible (injectee par cloud-init)
variable "ansible_ssh_public_key" {
  description = "Cle SSH publique pour l'utilisateur ansible sur les VMs Linux"
  type        = string
  sensitive   = true
}
