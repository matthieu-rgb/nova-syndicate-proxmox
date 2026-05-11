# ============================================================
# Nova Syndicate -- Road-Warriors WireGuard ACLs
# Scope    : acces distants via vpn-gw01 (10.20.0.0/24, DMZ 172.16.1.4)
# Autorise : fs01, db01, web01, mail01, dc01 (DNS uniquement)
# Bloque   : tout le reste (par default block_all existant)
# ============================================================

# ============================================================
# FW-EXT-LYON -- Route retour 10.20.0.0/24 via vpn-gw01
#
# Retour des serveurs internes vers road-warriors :
#   serveur -> FW-INT-LYON -> FW-EXT-LYON (opt1) -> vpn-gw01 (lan)
# FW-EXT-LYON doit savoir router 10.20.0.0/24 vers vpn-gw01 (172.16.1.4).
# Gateway VPN_GW01 creee via API OPNsense (non supportee par provider v0.16).
# ============================================================

resource "opnsense_route" "fwext_to_road_warriors" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors WG subnet (10.20.0.0/24) retour via vpn-gw01"
  network     = "10.20.0.0/24"
  gateway     = "VPN_GW01"
}

# ============================================================
# FW-EXT-LYON -- Transit road-warriors depuis DMZ vers internes
# Interface lan = DMZ (172.16.1.0/29).
# vpn-gw01 envoie src=10.20.0.x (non NATe) vers 192.168.20.0/28.
# FW-EXT-LYON transfère vers FW-INT-LYON via FW_INT_GW (opt1).
# ============================================================

resource "opnsense_firewall_filter" "fwext_rw_to_servers" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors -> VLAN SERVERS (transit vers FW-INT-LYON)"
  interface   = { interface = ["lan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "10.20.0.0/24" }
    destination = { net = "192.168.20.0/28" }
  }
}

resource "opnsense_firewall_filter" "fwext_rw_to_web01" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors -> web01 HTTP/HTTPS (DMZ direct)"
  interface   = { interface = ["lan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "10.20.0.0/24" }
    destination = { net = "172.16.1.2", port = "80" }
  }
}

resource "opnsense_firewall_filter" "fwext_rw_to_web01_https" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors -> web01 HTTPS (DMZ direct)"
  interface   = { interface = ["lan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "10.20.0.0/24" }
    destination = { net = "172.16.1.2", port = "443" }
  }
}

resource "opnsense_firewall_filter" "fwext_rw_to_mail01" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors -> mail01 tous ports mail (DMZ direct)"
  interface   = { interface = ["lan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "10.20.0.0/24" }
    destination = { net = "172.16.1.3", port = "ports_mail_smtp" }
  }
}

resource "opnsense_firewall_filter" "fwext_rw_to_mail01_imap" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors -> mail01 IMAP/IMAPS (143, 993)"
  interface   = { interface = ["lan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "10.20.0.0/24" }
    destination = { net = "172.16.1.3", port = "143" }
  }
}

resource "opnsense_firewall_filter" "fwext_rw_to_mail01_imaps" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "Road-warriors -> mail01 IMAPS (993)"
  interface   = { interface = ["lan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "10.20.0.0/24" }
    destination = { net = "172.16.1.3", port = "993" }
  }
}

# ============================================================
# FW-INT-LYON -- Aliases road-warriors (nouveaux uniquement)
# host_dc01 deja defini dans aliases.tf (fwint_aliases_host).
# ============================================================

locals {
  fwint_aliases_rw_network = {
    net_road_warriors = { content = ["10.20.0.0/24"], description = "Road-warriors WireGuard subnet" }
  }

  fwint_aliases_rw_host = {
    host_fs01 = { content = ["192.168.20.11"], description = "FS01 - serveur de fichiers" }
    host_db01 = { content = ["192.168.20.12"], description = "DB01 - base de donnees MariaDB" }
  }

  fwint_aliases_rw_port = {
    ports_smb_ssh     = { content = ["139", "445", "22"],               description = "SMB (139/445) + SSH (fs01)" }
    ports_db_ssh      = { content = ["3306", "22"],                     description = "MariaDB (3306) + SSH (db01)" }
  }
}

resource "opnsense_firewall_alias" "fwint_rw_network" {
  provider    = opnsense.fw_int
  for_each    = local.fwint_aliases_rw_network
  enabled     = true
  name        = each.key
  type        = "network"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwint_rw_host" {
  provider    = opnsense.fw_int
  for_each    = local.fwint_aliases_rw_host
  enabled     = true
  name        = each.key
  type        = "host"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwint_rw_port" {
  provider    = opnsense.fw_int
  for_each    = local.fwint_aliases_rw_port
  enabled     = true
  name        = each.key
  type        = "port"
  description = each.value.description
  content     = each.value.content
}

# ============================================================
# FW-INT-LYON -- Regles road-warriors sur interface WAN
# Trafic arrive depuis FW-EXT-LYON via transit opt1 (10.0.1.0/30).
# sequence=1 : avant fwint_wan_block_all (sequence=2).
# fwint_wan_ipsec_decapsulated (seq=1, src=192.168.40.0/26) ne conflicte pas.
# ============================================================

resource "opnsense_firewall_filter" "fwint_rw_to_fs01" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 1
  description = "Road-warriors -> fs01 SMB (139/445) + SSH"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_road_warriors" }
    destination = { net = "host_fs01", port = "ports_smb_ssh" }
  }
}

resource "opnsense_firewall_filter" "fwint_rw_to_db01" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 1
  description = "Road-warriors -> db01 MariaDB (3306) + SSH"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_road_warriors" }
    destination = { net = "host_db01", port = "ports_db_ssh" }
  }
}

resource "opnsense_firewall_filter" "fwint_rw_to_dc01_dns" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 1
  description = "Road-warriors -> dc01 DNS (port 53 UDP uniquement)"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source      = { net = "net_road_warriors" }
    destination = { net = "host_dc01", port = "53" }
  }
}
