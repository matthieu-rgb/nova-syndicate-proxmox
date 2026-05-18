# ============================================================
# Nova Syndicate -- Variables OPNsense
# ============================================================

# ============================================================
# CONNEXION FIREWALLS -- 1 trio (ip, key, secret) par firewall
# ============================================================

# WAN-SIMULATOR (VMID 200)
variable "wansim_ip" {
  description = "IP de management de WAN-SIMULATOR"
  type        = string
}

variable "wansim_api_key" {
  description = "Cle API OPNsense WAN-SIMULATOR"
  type        = string
  sensitive   = true
}

variable "wansim_api_secret" {
  description = "Secret API OPNsense WAN-SIMULATOR"
  type        = string
  sensitive   = true
}

# FW-EXT-LYON (VMID 201)
variable "fw_ext_ip" {
  description = "IP de management de FW-EXT-LYON"
  type        = string
}

variable "fw_ext_api_key" {
  description = "Cle API OPNsense FW-EXT-LYON"
  type        = string
  sensitive   = true
}

variable "fw_ext_api_secret" {
  description = "Secret API OPNsense FW-EXT-LYON"
  type        = string
  sensitive   = true
}

# FW-INT-LYON (VMID 202)
variable "fw_int_ip" {
  description = "IP de management de FW-INT-LYON"
  type        = string
}

variable "fw_int_api_key" {
  description = "Cle API OPNsense FW-INT-LYON"
  type        = string
  sensitive   = true
}

variable "fw_int_api_secret" {
  description = "Secret API OPNsense FW-INT-LYON"
  type        = string
  sensitive   = true
}

# FW-EXT-MRS (VMID 203)
variable "fw_ext_mrs_ip" {
  description = "IP de management de FW-EXT-MRS"
  type        = string
}

variable "fw_ext_mrs_api_key" {
  description = "Cle API OPNsense FW-EXT-MRS"
  type        = string
  sensitive   = true
}

variable "fw_ext_mrs_api_secret" {
  description = "Secret API OPNsense FW-EXT-MRS"
  type        = string
  sensitive   = true
}

# ============================================================
# PLAN VLSM -- source de verite des subnets
# ============================================================

variable "vlsm" {
  description = "Plan d'adressage VLSM Nova Syndicate"
  type        = map(string)
  default = {
    # Transits inter-firewalls
    transit_lyon_wan      = "10.0.0.0/30" # WAN-SIM <-> FW-EXT-LYON
    transit_lyon_internal = "10.0.1.0/30" # FW-EXT-LYON <-> FW-INT-LYON
    transit_mrs_wan       = "10.0.2.0/30" # WAN-SIM <-> FW-EXT-MRS

    # Site Lyon
    dmz_lyon       = "172.16.1.0/29"   # DMZ Lyon (web01, mail01)
    vlan15_bastion = "192.168.15.0/29" # VLAN 15 - bastion
    vlan20_servers = "192.168.20.0/28" # VLAN 20 - serveurs (DC, FS, DB, APP, proxy)
    vlan30_users   = "192.168.30.0/26" # VLAN 30 - postes utilisateurs
    vlan50_backup  = "192.168.50.0/29" # VLAN 50 - backup

    # Site Marseille (LAN direct, vmbr2 sans VLAN)
    lan_mrs = "192.168.40.0/26"
  }
}

# ============================================================
# VLAN IDs -- correspondances 802.1Q (trunk vmbr1 Lyon)
# ============================================================

variable "vlan_ids" {
  description = "IDs des VLANs internes Lyon (trunk vmbr1)"
  type        = map(number)
  default = {
    bastion = 15
    servers = 20
    users   = 30
    backup  = 50
  }
}
