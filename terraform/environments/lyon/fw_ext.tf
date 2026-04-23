# ============================================================
# FW-EXT-LYON1 - Regles firewall (provider v0.16 syntaxe finale)
# ============================================================

resource "opnsense_firewall_filter" "wan_to_dmz_http" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "HTTP WAN vers DMZ"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source = {
      net = "any"
    }
    destination = {
      net  = "172.16.1.0/29"
      port = "80"
    }
  }
}

resource "opnsense_firewall_filter" "wan_to_dmz_https" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "HTTPS WAN vers DMZ"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source = {
      net = "any"
    }
    destination = {
      net  = "172.16.1.0/29"
      port = "443"
    }
  }
}

resource "opnsense_firewall_filter" "wan_to_mail" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "SMTP WAN vers MAIL1"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source = {
      net = "any"
    }
    destination = {
      net  = "172.16.1.3"
      port = "25"
    }
  }
}

resource "opnsense_firewall_filter" "lan_to_wan" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Transit LAN vers internet"
  interface = {
    interface = ["lan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source = {
      net = "10.0.1.0/24"
    }
    destination = {
      net = "any"
    }
  }
}

resource "opnsense_firewall_filter" "wan_block_all" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Block tout WAN entrant non autorise"
  interface = {
    interface = ["wan"]
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

resource "opnsense_firewall_filter" "dmz_to_lan_ssh" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "SSH depuis DMZ vers BASTION01 pour Ansible"
  interface = {
    interface = ["opt1"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source = {
      net = "172.16.1.0/29"
    }
    destination = {
      net  = "192.168.15.2"
      port = "22"
    }
  }
}
