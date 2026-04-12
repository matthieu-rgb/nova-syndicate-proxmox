# ============================================================
# FW-INT-LYON1 - Regles firewall reseau interne
# ============================================================

# BASTION1 -> Serveurs SSH
resource "opnsense_firewall_filter" "bastion_to_servers_ssh" {
  provider    = opnsense.fw_int
  enabled     = true
  action      = "pass"
  quick       = true
  interface   = ["lan"]
  direction   = "in"
  protocol    = "tcp"
  source = {
    net = "192.168.1.10/32"
  }
  destination = {
    net  = "192.168.1.0/24"
    port = "22"
  }
  description = "BASTION1 SSH vers serveurs"
}

# Serveurs -> DC1 DNS/LDAP
resource "opnsense_firewall_filter" "servers_to_dc" {
  provider    = opnsense.fw_int
  enabled     = true
  action      = "pass"
  quick       = true
  interface   = ["lan"]
  direction   = "in"
  source = {
    net = "192.168.1.0/24"
  }
  destination = {
    net = "192.168.1.20"
  }
  description = "Serveurs vers DC1 DNS/LDAP"
}

# LAN -> Internet (sortie)
resource "opnsense_firewall_filter" "lan_to_internet" {
  provider    = opnsense.fw_int
  enabled     = true
  action      = "pass"
  quick       = true
  interface   = ["lan"]
  direction   = "in"
  source = {
    net = "192.168.1.0/24"
  }
  destination = {
    net = "any"
  }
  description = "LAN vers internet via FW-EXT"
}

# Bloquer tout le reste
resource "opnsense_firewall_filter" "block_all_lan" {
  provider    = opnsense.fw_int
  enabled     = true
  action      = "block"
  quick       = true
  interface   = ["lan"]
  direction   = "in"
  source = {
    net = "any"
  }
  destination = {
    net = "any"
  }
  log         = true
  description = "Block tout trafic non autorise"
}
