variable "vmid" {
  description = "Identifiant unique de la VM dans Proxmox"
  type        = number
}

variable "hostname" {
  description = "Nom de la VM OPNsense (ex: fw-ext-lyon01)"
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

variable "iso_datastore" {
  description = "Stockage contenant l'ISO OPNsense (ex: local)"
  type        = string
  default     = "local"
}

variable "iso_file" {
  description = "Nom du fichier ISO dans le stockage (ex: OPNsense-25.1-dvd-amd64.iso)"
  type        = string
}

variable "datastore_id" {
  description = "Stockage Proxmox pour le disque de la VM"
  type        = string
  default     = "local-lvm"
}

variable "cpu_cores" {
  description = "Nombre de vCPU"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM en megaoctets"
  type        = number
  default     = 1024
}

variable "disk_size_gb" {
  description = "Taille du disque systeme en gigaoctets"
  type        = number
  default     = 16
}

# Interfaces reseau : liste ordonnee de { bridge, vlan_tag }
# L'ordre correspond a em0, em1, em2... dans OPNsense
variable "network_interfaces" {
  description = "Liste des interfaces reseau dans l'ordre OPNsense"
  type = list(object({
    bridge   = string
    vlan_tag = number
  }))
}

variable "tags" {
  description = "Tags Proxmox pour filtrage dans l'UI"
  type        = list(string)
  default     = ["firewall", "opnsense"]
}
