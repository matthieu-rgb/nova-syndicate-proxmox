variable "vmid" {
  description = "Identifiant unique de la VM dans Proxmox (100-999)"
  type        = number
}

variable "hostname" {
  description = "Nom court de la VM (ex: dc01)"
  type        = string
}

variable "fqdn" {
  description = "FQDN complet (ex: dc01.nova-syndicate.local)"
  type        = string
}

variable "description" {
  description = "Description affichee dans l'UI Proxmox"
  type        = string
  default     = ""
}

variable "node_name" {
  description = "Nom du noeud Proxmox cible"
  type        = string
  default     = "pve"
}

variable "template_vmid" {
  description = "VMID du template Debian 12 cloud-init a cloner"
  type        = number
  default     = 9000
}

variable "datastore_id" {
  description = "Stockage Proxmox cible (ex: local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "cpu_cores" {
  description = "Nombre de vCPU"
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "RAM en megaoctets"
  type        = number
  default     = 1024
}

variable "disk_size_gb" {
  description = "Taille du disque en gigaoctets"
  type        = number
  default     = 16
}

variable "bridge" {
  description = "Bridge reseau Proxmox (ex: vmbr1)"
  type        = string
}

variable "vlan_tag" {
  description = "Tag VLAN 802.1q (0 = pas de tag)"
  type        = number
  default     = 0
}

variable "ip_address" {
  description = "IP statique avec prefixe CIDR (ex: 192.168.20.10/28)"
  type        = string
}

variable "gateway" {
  description = "Passerelle par defaut"
  type        = string
}

variable "dns_servers" {
  description = "Liste des serveurs DNS"
  type        = list(string)
  default     = ["192.168.20.10", "1.1.1.1"]
}

variable "ssh_public_keys" {
  description = "Cles SSH publiques autorisees (une par ligne)"
  type        = string
  sensitive   = true
}

variable "cloud_init_user_data" {
  description = "Contenu du user-data cloud-init en base64 ou chemin"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags Proxmox pour filtrage dans l'UI"
  type        = list(string)
  default     = []
}
