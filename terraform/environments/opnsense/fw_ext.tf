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

resource "opnsense_firewall_filter" "transit_to_wan" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Transit interne (depuis FW-INT) vers internet"
  interface = {
    interface = ["opt1"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source = {
      net = "10.0.1.0/30"
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

resource "opnsense_firewall_filter" "dmz_to_bastion_ssh" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "SSH depuis DMZ vers BASTION01 (Ansible)"
  interface = {
    interface = ["lan"]
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
# ============================================================
# IPsec WAN entrant -- prepare Phase IV (tunnel vers MRS)
# ============================================================

resource "opnsense_firewall_filter" "fwext_wan_ipsec_ike" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "IPsec IKE (UDP 500) depuis MRS -- prepare Phase IV"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source = {
      net = "10.0.2.2"
    }
    destination = {
      net  = "any"
      port = "500"
    }
  }
}

resource "opnsense_firewall_filter" "fwext_wan_ipsec_natt" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "IPsec NAT-T (UDP 4500) depuis MRS -- prepare Phase IV"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source = {
      net = "10.0.2.2"
    }
    destination = {
      net  = "any"
      port = "4500"
    }
  }
}

resource "opnsense_firewall_filter" "fwext_wan_ipsec_esp" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "IPsec ESP (proto 50) depuis MRS -- prepare Phase IV"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "ESP"
    source = {
      net = "10.0.2.2"
    }
    destination = {
      net = "any"
    }
  }
}

# Au passage : enrichir wan_to_mail avec l'alias ports_mail_smtp
# (deja en code, on rajoute juste une regle pour les ports submission/465)
# Cette regle complete wan_to_mail qui ne gere que le port 25.

resource "opnsense_firewall_filter" "fwext_wan_to_mail_submission" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Mail submission ports (465, 587) WAN vers MAIL01"
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
      net  = "host_mail01"
      port = "ports_mail_smtp"
    }
  }
}