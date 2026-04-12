# ============================================================
# FW-EXT-LYON1 - Regles firewall (provider v0.16)
# ============================================================

resource "opnsense_firewall_filter" "wan_to_dmz_http" {
  provider = opnsense.fw_ext
  filter {
    action    = "pass"
    quick     = true
    interface = "wan"
    direction = "in"
    protocol  = "tcp"
    source {
      net = "any"
    }
    destination {
      net  = "172.16.1.0/29"
      port = "80"
    }
    description = "HTTP WAN vers DMZ"
  }
}

resource "opnsense_firewall_filter" "wan_to_dmz_https" {
  provider = opnsense.fw_ext
  filter {
    action    = "pass"
    quick     = true
    interface = "wan"
    direction = "in"
    protocol  = "tcp"
    source {
      net = "any"
    }
    destination {
      net  = "172.16.1.0/29"
      port = "443"
    }
    description = "HTTPS WAN vers DMZ"
  }
}

resource "opnsense_firewall_filter" "wan_to_mail" {
  provider = opnsense.fw_ext
  filter {
    action    = "pass"
    quick     = true
    interface = "wan"
    direction = "in"
    protocol  = "tcp"
    source {
      net = "any"
    }
    destination {
      net  = "172.16.1.3"
      port = "25"
    }
    description = "SMTP WAN vers MAIL1"
  }
}

resource "opnsense_firewall_filter" "lan_to_wan" {
  provider = opnsense.fw_ext
  filter {
    action    = "pass"
    quick     = true
    interface = "lan"
    direction = "in"
    source {
      net = "10.0.1.0/24"
    }
    destination {
      net = "any"
    }
    description = "Transit LAN vers internet"
  }
}

resource "opnsense_firewall_filter" "wan_block_all" {
  provider = opnsense.fw_ext
  filter {
    action    = "block"
    quick     = true
    interface = "wan"
    direction = "in"
    source {
      net = "any"
    }
    destination {
      net = "any"
    }
    log         = true
    description = "Block tout WAN entrant non autorise"
  }
}
