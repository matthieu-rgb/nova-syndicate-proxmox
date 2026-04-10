# ============================================================
# FW-EXT-LYON1 - Configuration OPNsense
# ============================================================

# ============================================================
# 1. VLANS SUR FW-EXT
# ============================================================

resource "opnsense_vlan" "dmz" {
  provider    = opnsense.fw_ext
  device      = "vtnet2"
  tag         = 1
  description = "DMZ - WEB01 + MAIL01"
}

# ============================================================
# 2. REGLES PARE-FEU FW-EXT
# ============================================================

# Autoriser trafic etabli/lie
resource "opnsense_firewall_filter" "wan_established" {
  provider    = opnsense.fw_ext
  interface   = "wan"
  direction   = "in"
  action      = "pass"
  statetype   = "keep state"
  protocol    = "any"
  source      = "any"
  destination = "any"
  description = "Autoriser trafic etabli"
}

# Bloquer tout depuis WAN par defaut
resource "opnsense_firewall_filter" "wan_block_all" {
  provider    = opnsense.fw_ext
  interface   = "wan"
  direction   = "in"
  action      = "block"
  protocol    = "any"
  source      = "any"
  destination = "any"
  description = "Bloquer tout depuis WAN"
}

# Autoriser HTTP/HTTPS vers DMZ depuis WAN
resource "opnsense_firewall_filter" "wan_to_dmz_http" {
  provider         = opnsense.fw_ext
  interface        = "wan"
  direction        = "in"
  action           = "pass"
  protocol         = "tcp"
  source           = "any"
  destination      = "172.16.1.0/29"
  destination_port = "80"
  description      = "HTTP vers DMZ"
}

resource "opnsense_firewall_filter" "wan_to_dmz_https" {
  provider         = opnsense.fw_ext
  interface        = "wan"
  direction        = "in"
  action           = "pass"
  protocol         = "tcp"
  source           = "any"
  destination      = "172.16.1.0/29"
  destination_port = "443"
  description      = "HTTPS vers DMZ"
}

# Autoriser SMTP vers MAIL01
resource "opnsense_firewall_filter" "wan_to_mail" {
  provider         = opnsense.fw_ext
  interface        = "wan"
  direction        = "in"
  action           = "pass"
  protocol         = "tcp"
  source           = "any"
  destination      = "172.16.1.11"
  destination_port = "25"
  description      = "SMTP vers MAIL01"
}

# ============================================================
# 3. NAT SORTANT
# ============================================================

resource "opnsense_nat_outbound" "lan_to_wan" {
  provider    = opnsense.fw_ext
  interface   = "wan"
  source      = "192.168.0.0/16"
  description = "NAT sortant LAN vers WAN"
}

resource "opnsense_nat_outbound" "dmz_to_wan" {
  provider    = opnsense.fw_ext
  interface   = "wan"
  source      = "172.16.1.0/29"
  description = "NAT sortant DMZ vers WAN"
}