# ============================================================
# FW-INT-LYON1 - Configuration OPNsense
# ============================================================

# ============================================================
# 1. VLANS SUR FW-INT
# ============================================================

resource "opnsense_vlan" "vlan15_bastion" {
  provider    = opnsense.fw_int
  device      = "vtnet1"
  tag         = 15
  description = "VLAN 15 - Bastion"
}

resource "opnsense_vlan" "vlan20_servers" {
  provider    = opnsense.fw_int
  device      = "vtnet1"
  tag         = 20
  description = "VLAN 20 - Serveurs"
}

resource "opnsense_vlan" "vlan30_users" {
  provider    = opnsense.fw_int
  device      = "vtnet1"
  tag         = 30
  description = "VLAN 30 - Users Lyon"
}

resource "opnsense_vlan" "vlan50_backup" {
  provider    = opnsense.fw_int
  device      = "vtnet1"
  tag         = 50
  description = "VLAN 50 - Backup"
}

# ============================================================
# 2. REGLES PARE-FEU FW-INT
# ============================================================

# Bastion -> Servers (SSH uniquement)
resource "opnsense_firewall_filter" "bastion_to_servers_ssh" {
  provider         = opnsense.fw_int
  interface        = "opt1"
  direction        = "in"
  action           = "pass"
  protocol         = "tcp"
  source           = "192.168.15.0/29"
  destination      = "192.168.20.0/28"
  destination_port = "22"
  description      = "BASTION01 -> Serveurs SSH"
}

# Servers -> DC01 (LDAP, DNS, Kerberos)
resource "opnsense_firewall_filter" "servers_to_dc" {
  provider    = opnsense.fw_int
  interface   = "opt2"
  direction   = "in"
  action      = "pass"
  protocol    = "tcp"
  source      = "192.168.20.0/28"
  destination = "192.168.20.10"
  description = "Serveurs -> DC01 AD"
}

# Users -> Servers (acces partages fichiers)
resource "opnsense_firewall_filter" "users_to_fileserver" {
  provider         = opnsense.fw_int
  interface        = "opt3"
  direction        = "in"
  action           = "pass"
  protocol         = "tcp"
  source           = "192.168.30.0/26"
  destination      = "192.168.20.11"
  destination_port = "445"
  description      = "Users -> FS01 SMB"
}

# Bloquer acces direct Users -> DB01
resource "opnsense_firewall_filter" "block_users_to_db" {
  provider         = opnsense.fw_int
  interface        = "opt3"
  direction        = "in"
  action           = "block"
  protocol         = "tcp"
  source           = "192.168.30.0/26"
  destination      = "192.168.20.12"
  destination_port = "3306"
  description      = "Bloquer Users -> DB01 direct"
}

# Tout -> internet via proxy APP01
resource "opnsense_firewall_filter" "all_to_proxy" {
  provider         = opnsense.fw_int
  interface        = "opt2"
  direction        = "in"
  action           = "pass"
  protocol         = "tcp"
  source           = "192.168.0.0/16"
  destination      = "192.168.20.13"
  destination_port = "3128"
  description      = "Tout -> Squid APP01"
}