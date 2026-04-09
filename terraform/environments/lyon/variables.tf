# ============================================================
# CONNEXION FIREWALLS
# ============================================================

variable "fw_ext_ip" {
  description = "IP de gestion de FW-EXT-LYON1 (interface LAN OPNsense)"
  type        = string
}

variable "fw_ext_api_key" {
  description = "Cle API OPNsense FW-EXT-LYON1"
  type        = string
  sensitive   = true
}

variable "fw_ext_api_secret" {
  description = "Secret API OPNsense FW-EXT-LYON1"
  type        = string
  sensitive   = true
}

variable "fw_int_ip" {
  description = "IP de gestion de FW-INT-LYON1"
  type        = string
}

variable "fw_int_api_key" {
  description = "Cle API OPNsense FW-INT-LYON1"
  type        = string
  sensitive   = true
}

variable "fw_int_api_secret" {
  description = "Secret API OPNsense FW-INT-LYON1"
  type        = string
  sensitive   = true
}

# ============================================================
# RESEAU
# ============================================================

variable "vlan_ids" {
  description = "IDs des VLANs internes"
  type        = map(number)
  default = {
    bastion = 15
    servers = 20
    users   = 30
    vpn     = 40
    backup  = 50
  }
}

variable "vlsm" {
  description = "Plan d adressage VLSM"
  type        = map(string)
  default = {
    transit_rtr_fwext = "10.0.0.0/30"
    transit_fwext_fwint = "10.0.1.0/30"
    dmz               = "172.16.1.0/29"
    vlan15_bastion    = "192.168.15.0/29"
    vlan20_servers    = "192.168.20.0/28"
    vlan30_users      = "192.168.30.0/26"
    vlan40_vpn        = "192.168.40.0/27"
    vlan50_backup     = "192.168.50.0/29"
  }
}

# ============================================================
# WIREGUARD
# ============================================================

variable "wg_server_privkey" {
  description = "Cle privee WireGuard serveur (FW-EXT)"
  type        = string
  sensitive   = true
}

variable "wg_listen_port" {
  description = "Port UDP WireGuard"
  type        = number
  default     = 51820
}
