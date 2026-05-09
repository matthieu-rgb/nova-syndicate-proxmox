# ============================================================
# FW-EXT-MRS -- regles filter
# ============================================================
# Role : passerelle externe site Marseille (LAN MRS <-> WAN-SIM).
# IPsec entrant prepare pour Phase IV.
# ============================================================

resource "opnsense_firewall_filter" "fwextmrs_lan_to_any" {
  provider    = opnsense.fw_ext_mrs
  enabled     = true
  description = "LAN MRS -> any (internet ou cross-site Lyon)"
  interface = {
    interface = ["lan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source = {
      net = "net_lan_mrs"
    }
    destination = {
      net = "any"
    }
  }
}

# Regles IPsec WAN entrant -- preparation Phase IV
# Les paquets IKE et ESP doivent pouvoir entrer sur WAN
# pour permettre la negociation et le tunnel.

resource "opnsense_firewall_filter" "fwextmrs_wan_ipsec_ike" {
  provider    = opnsense.fw_ext_mrs
  enabled     = true
  description = "IPsec IKE (UDP 500) depuis Lyon -- prepare Phase IV"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source = {
      net = "10.0.0.2"
    }
    destination = {
      net  = "any"
      port = "500"
    }
  }
}

resource "opnsense_firewall_filter" "fwextmrs_wan_ipsec_natt" {
  provider    = opnsense.fw_ext_mrs
  enabled     = true
  description = "IPsec NAT-T (UDP 4500) depuis Lyon -- prepare Phase IV"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source = {
      net = "10.0.0.2"
    }
    destination = {
      net  = "any"
      port = "4500"
    }
  }
}

resource "opnsense_firewall_filter" "fwextmrs_wan_ipsec_esp" {
  provider    = opnsense.fw_ext_mrs
  enabled     = true
  description = "IPsec ESP (proto 50) depuis Lyon -- prepare Phase IV"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "ESP"
    source = {
      net = "10.0.0.2"
    }
    destination = {
      net = "any"
    }
  }
}

resource "opnsense_firewall_filter" "fwextmrs_wan_block_all" {
  provider    = opnsense.fw_ext_mrs
  enabled     = true
  description = "Block tout autre WAN entrant non autorise"
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