# ============================================================
# FW-INT-LYON1 - Regles firewall (provider v0.16 syntaxe finale)
# ============================================================

resource "opnsense_firewall_filter" "bastion_to_servers_ssh" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION1 SSH vers serveurs"
  interface = {
    interface = ["lan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "tcp"
    source = {
      net = "192.168.1.10/32"
    }
    destination = {
      net  = "192.168.1.0/24"
      port = "22"
    }
  }
}

resource "opnsense_firewall_filter" "lan_to_internet" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "LAN vers internet via FW-EXT"
  interface = {
    interface = ["lan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source = {
      net = "192.168.1.0/24"
    }
    destination = {
      net = "any"
    }
  }
}

resource "opnsense_firewall_filter" "block_all_lan" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Block tout trafic non autorise"
  interface = {
    interface = ["lan"]
  }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source = {
      net = "any"
    }
    destination = {
      net = "any"
    }
  }
}
