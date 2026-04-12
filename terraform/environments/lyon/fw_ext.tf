# ============================================================
# FW-EXT-LYON1 - Regles firewall (provider v0.16 syntaxe correcte)
# ============================================================

resource "opnsense_firewall_filter" "wan_to_dmz_http" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "HTTP WAN vers DMZ"
  interface   = "wan"
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "tcp"
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
  interface   = "wan"
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "tcp"
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
  interface   = "wan"
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "tcp"
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
  interface   = "lan"
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
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
  interface   = "wan"
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    log       = true
    source = {
      net = "any"
    }
    destination = {
      net = "any"
    }
  }
}
