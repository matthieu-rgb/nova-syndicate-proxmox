# ============================================================
# Nova Syndicate -- Aliases OPNsense
# ============================================================
# Definitions reutilisees dans les regles filter / NAT.
# Per-firewall : OPNsense ne partage pas les aliases entre instances.
# Pattern : locals + for_each pour reduire la duplication.
# ============================================================

# ============================================================
# FW-INT-LYON -- aliases pour le routage interne Lyon
# ============================================================

locals {
  fwint_aliases_network = {
    net_lyon_bastion   = { content = ["192.168.15.0/29"], description = "VLAN 15 - Bastion subnet" }
    net_lyon_servers   = { content = ["192.168.20.0/28"], description = "VLAN 20 - Servers subnet" }
    net_lyon_users     = { content = ["192.168.30.0/26"], description = "VLAN 30 - Users subnet" }
    net_lyon_backup    = { content = ["192.168.50.0/29"], description = "VLAN 50 - Backup subnet" }
    net_lyon_internal  = { content = ["192.168.15.0/29", "192.168.20.0/28", "192.168.30.0/26", "192.168.50.0/29"], description = "Tous les VLANs internes Lyon" }
    net_lan_mrs        = { content = ["192.168.40.0/26"], description = "LAN Marseille (cross-site)" }
    net_proxmox_admin  = { content = ["192.168.18.0/24"], description = "Reseau admin Proxmox (poste admin Mac)" }
  }

  fwint_aliases_host = {
    host_dc01         = { content = ["192.168.20.10"], description = "DC01 - Samba AD" }
    host_proxy_lyon01 = { content = ["192.168.20.14"], description = "PROXY-LYON01 - Squid forward proxy" }
    host_app01        = { content = ["192.168.20.13"], description = "APP01 - Wazuh manager + Vault" }
    host_bastion01    = { content = ["192.168.15.2"],  description = "BASTION01 - SSH bastion" }
    host_backup01     = { content = ["192.168.50.2"],  description = "BACKUP01 - BorgBackup" }
  }

  fwint_aliases_port = {
    ports_ad_tcp = { content = ["88", "135", "389", "445", "464", "636", "3268", "3269"], description = "Active Directory TCP (Samba)" }
    ports_ad_udp = { content = ["53", "88", "123", "137", "138", "389", "464"], description = "Active Directory UDP (Samba)" }
    ports_smb    = { content = ["139", "445"], description = "SMB / CIFS file sharing" }
  }
}

resource "opnsense_firewall_alias" "fwint_network" {
  provider    = opnsense.fw_int
  for_each    = local.fwint_aliases_network
  enabled     = true
  name        = each.key
  type        = "network"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwint_host" {
  provider    = opnsense.fw_int
  for_each    = local.fwint_aliases_host
  enabled     = true
  name        = each.key
  type        = "host"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwint_port" {
  provider    = opnsense.fw_int
  for_each    = local.fwint_aliases_port
  enabled     = true
  name        = each.key
  type        = "port"
  description = each.value.description
  content     = each.value.content
}

# ============================================================
# FW-EXT-LYON -- aliases pour DMZ et trafic externe Lyon
# ============================================================

locals {
  fwext_aliases_network = {
    net_dmz_lyon       = { content = ["172.16.1.0/29"], description = "DMZ Lyon (web, mail)" }
    net_lyon_internal  = { content = ["192.168.15.0/29", "192.168.20.0/28", "192.168.30.0/26", "192.168.50.0/29"], description = "Tous les VLANs internes Lyon" }
    net_lan_mrs        = { content = ["192.168.40.0/26"], description = "LAN Marseille (NO-NAT cross-site)" }
  }

  fwext_aliases_host = {
    host_web01  = { content = ["172.16.1.2"], description = "WEB01 - serveur Apache/Nginx DMZ" }
    host_mail01 = { content = ["172.16.1.3"], description = "MAIL01 - Postfix/Dovecot DMZ" }
  }

  fwext_aliases_port = {
    ports_mail_smtp = { content = ["25", "465", "587"], description = "SMTP standard et submission" }
  }
}

resource "opnsense_firewall_alias" "fwext_network" {
  provider    = opnsense.fw_ext
  for_each    = local.fwext_aliases_network
  enabled     = true
  name        = each.key
  type        = "network"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwext_host" {
  provider    = opnsense.fw_ext
  for_each    = local.fwext_aliases_host
  enabled     = true
  name        = each.key
  type        = "host"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwext_port" {
  provider    = opnsense.fw_ext
  for_each    = local.fwext_aliases_port
  enabled     = true
  name        = each.key
  type        = "port"
  description = each.value.description
  content     = each.value.content
}

# ============================================================
# FW-EXT-MRS -- aliases pour LAN Marseille
# ============================================================

locals {
  fwextmrs_aliases_network = {
    net_lan_mrs       = { content = ["192.168.40.0/26"], description = "LAN Marseille local" }
    net_lyon_internal = { content = ["192.168.15.0/29", "192.168.20.0/28", "192.168.30.0/26", "192.168.50.0/29"], description = "VLANs internes Lyon (cross-site via tunnel)" }
  }

  fwextmrs_aliases_host = {
    host_proxy_mrs01 = { content = ["192.168.40.11"], description = "PROXY-MRS01 - Squid forward proxy MRS" }
  }
}

resource "opnsense_firewall_alias" "fwextmrs_network" {
  provider    = opnsense.fw_ext_mrs
  for_each    = local.fwextmrs_aliases_network
  enabled     = true
  name        = each.key
  type        = "network"
  description = each.value.description
  content     = each.value.content
}

resource "opnsense_firewall_alias" "fwextmrs_host" {
  provider    = opnsense.fw_ext_mrs
  for_each    = local.fwextmrs_aliases_host
  enabled     = true
  name        = each.key
  type        = "host"
  description = each.value.description
  content     = each.value.content
}

# ============================================================
# WAN-SIM -- aliases pour les transits ISP
# ============================================================

locals {
  wansim_aliases_network = {
    net_lyon_subnet = { content = ["10.0.0.0/30"], description = "Transit FAI simule cote Lyon" }
    net_mrs_subnet  = { content = ["10.0.2.0/30"], description = "Transit FAI simule cote Marseille" }
  }
}

resource "opnsense_firewall_alias" "wansim_network" {
  provider    = opnsense.wansim
  for_each    = local.wansim_aliases_network
  enabled     = true
  name        = each.key
  type        = "network"
  description = each.value.description
  content     = each.value.content
}
