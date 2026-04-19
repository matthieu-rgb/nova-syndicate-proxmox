# =============================================================================
# Nova Syndicate -- nova_syndicate.tf
# Fichier Terraform unique -- configure l'integralite de l'infrastructure
# reseau Nova Syndicate en une seule commande : terraform apply
#
# Pre-requis (3 commandes, 30 secondes) :
#   FW-EXT-LYON01 : ifconfig vtnet0 inet 10.0.0.2/30 && route add default 10.0.0.1
#   FW-INT-LYON01 : ifconfig vtnet0 inet 10.0.1.2/24 && route add default 10.0.1.1
#   FW-EXT-MRS01  : ifconfig vtnet0 inet 10.1.0.2/30 && route add default 10.1.0.1
#
# Ensuite depuis BASTION01 :
#   cd ~/nova-syndicate-ansible/terraform/environments/lyon
#   terraform apply
#
# Ce fichier configure :
#   - NAT outbound sur les 3 firewalls
#   - Routes statiques sur les 3 firewalls
#   - Regles firewall (filtrage)
#   - VLANs sur FW-INT
#   - DNS Unbound (host overrides + forwarders nova.local)
#   - DHCP VLAN 30 Lyon + LAN Marseille
#   - WireGuard agents distants
#   - IPsec IKEv2 Lyon-Marseille (les deux cotes)
# =============================================================================

terraform {
  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.16.1"
    }
  }
}

# =============================================================================
# PROVIDERS -- un par firewall
# =============================================================================

provider "opnsense" {
  alias          = "ext_lyon"
  uri            = "https://${var.fw_ext_lyon_ip}"
  api_key        = var.fw_ext_lyon_api_key
  api_secret     = var.fw_ext_lyon_api_secret
  allow_insecure = true
}

provider "opnsense" {
  alias          = "int_lyon"
  uri            = "https://${var.fw_int_lyon_ip}"
  api_key        = var.fw_int_lyon_api_key
  api_secret     = var.fw_int_lyon_api_secret
  allow_insecure = true
}

provider "opnsense" {
  alias          = "ext_mrs"
  uri            = "https://${var.fw_ext_mrs_ip}"
  api_key        = var.fw_ext_mrs_api_key
  api_secret     = var.fw_ext_mrs_api_secret
  allow_insecure = true
}

# =============================================================================
# VARIABLES
# Les valeurs sensibles sont dans terraform.tfvars (non commite sur GitHub)
# =============================================================================

variable "fw_ext_lyon_ip" { default = "10.0.0.2" }
variable "fw_int_lyon_ip" { default = "10.0.1.2" }
variable "fw_ext_mrs_ip"  { default = "10.1.0.2" }

variable "fw_ext_lyon_api_key"    { sensitive = true }
variable "fw_ext_lyon_api_secret" { sensitive = true }
variable "fw_int_lyon_api_key"    { sensitive = true }
variable "fw_int_lyon_api_secret" { sensitive = true }
variable "fw_ext_mrs_api_key"     { sensitive = true }
variable "fw_ext_mrs_api_secret"  { sensitive = true }

variable "wireguard_server_privkey" { sensitive = true }
variable "wireguard_agent1_pubkey"  {}
variable "wireguard_agent2_pubkey"  { default = "" }
variable "ipsec_psk"               { sensitive = true }

# Plan d'adressage -- modifier ici si changement d'adressage
locals {
  dmz            = "172.16.1.0/29"
  vlan15         = "192.168.15.0/29"
  vlan20         = "192.168.20.0/28"
  vlan30         = "192.168.30.0/26"
  vlan50         = "192.168.50.0/29"
  agents         = "10.20.0.0/24"
  marseille      = "192.168.40.0/26"
  transit        = "10.0.1.0/24"

  # IPs des VMs
  dc01           = "192.168.20.10"
  fs01           = "192.168.20.11"
  db01           = "192.168.20.12"
  app01          = "192.168.20.13"
  bastion01      = "192.168.15.2"
  backup01       = "192.168.50.2"
  web01          = "172.16.1.2"
  mail01         = "172.16.1.3"
  poste_mrs1     = "192.168.40.10"
}

# =============================================================================
# VLANS sur FW-INT-LYON01
# Interface parent : vtnet1 (trunk vers Switch-Lyon OVS)
# =============================================================================

resource "opnsense_interface_vlan" "vlan15" {
  provider    = opnsense.int_lyon
  parent      = "vtnet1"
  vlan_tag    = 15
  description = "VLAN15-Bastion"
}

resource "opnsense_interface_vlan" "vlan20" {
  provider    = opnsense.int_lyon
  parent      = "vtnet1"
  vlan_tag    = 20
  description = "VLAN20-Serveurs"
}

resource "opnsense_interface_vlan" "vlan30" {
  provider    = opnsense.int_lyon
  parent      = "vtnet1"
  vlan_tag    = 30
  description = "VLAN30-Utilisateurs"
}

resource "opnsense_interface_vlan" "vlan50" {
  provider    = opnsense.int_lyon
  parent      = "vtnet1"
  vlan_tag    = 50
  description = "VLAN50-Sauvegarde"
}

# =============================================================================
# NAT OUTBOUND -- FW-EXT-LYON01
# =============================================================================

resource "opnsense_firewall_nat_outbound_rule" "ext_nat_dmz" {
  provider        = opnsense.ext_lyon
  interface       = "wan"
  source_net      = local.dmz
  destination_net = "any"
  description     = "NAT DMZ vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "ext_nat_agents" {
  provider        = opnsense.ext_lyon
  interface       = "wan"
  source_net      = local.agents
  destination_net = "any"
  description     = "NAT agents WireGuard vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "ext_nat_transit" {
  provider        = opnsense.ext_lyon
  interface       = "wan"
  source_net      = local.transit
  destination_net = "any"
  description     = "NAT transit FW-EXT->FW-INT vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "ext_nat_rfc1918" {
  provider        = opnsense.ext_lyon
  interface       = "wan"
  source_net      = "192.168.0.0/16"
  destination_net = "any"
  description     = "NAT RFC1918 catch-all vers internet"
  disabled        = false
  no_nat          = false
}

# =============================================================================
# NAT OUTBOUND -- FW-INT-LYON01
# =============================================================================

resource "opnsense_firewall_nat_outbound_rule" "int_nat_vlan15" {
  provider        = opnsense.int_lyon
  interface       = "wan"
  source_net      = local.vlan15
  destination_net = "any"
  description     = "NAT VLAN15 Bastion vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "int_nat_vlan20" {
  provider        = opnsense.int_lyon
  interface       = "wan"
  source_net      = local.vlan20
  destination_net = "any"
  description     = "NAT VLAN20 Serveurs vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "int_nat_vlan30" {
  provider        = opnsense.int_lyon
  interface       = "wan"
  source_net      = local.vlan30
  destination_net = "any"
  description     = "NAT VLAN30 Utilisateurs vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "int_no_nat_marseille" {
  provider        = opnsense.int_lyon
  interface       = "wan"
  source_net      = local.vlan20
  destination_net = local.marseille
  description     = "Pas de NAT VLAN20 -> Marseille (IPsec)"
  disabled        = false
  no_nat          = true
}

# =============================================================================
# NAT OUTBOUND -- FW-EXT-MRS01
# =============================================================================

resource "opnsense_firewall_nat_outbound_rule" "mrs_nat_lan" {
  provider        = opnsense.ext_mrs
  interface       = "wan"
  source_net      = local.marseille
  destination_net = "any"
  description     = "NAT LAN Marseille vers internet"
  disabled        = false
  no_nat          = false
}

resource "opnsense_firewall_nat_outbound_rule" "mrs_no_nat_vlan20" {
  provider        = opnsense.ext_mrs
  interface       = "wan"
  source_net      = local.marseille
  destination_net = local.vlan20
  description     = "Pas de NAT Marseille -> VLAN20 Lyon (IPsec)"
  disabled        = false
  no_nat          = true
}

resource "opnsense_firewall_nat_outbound_rule" "mrs_no_nat_dmz" {
  provider        = opnsense.ext_mrs
  interface       = "wan"
  source_net      = local.marseille
  destination_net = local.dmz
  description     = "Pas de NAT Marseille -> DMZ Lyon (IPsec)"
  disabled        = false
  no_nat          = true
}

# =============================================================================
# ROUTES STATIQUES -- FW-EXT-LYON01
# Gateway "OPT1_GW" = 10.0.1.2 (FW-INT) -- adapter si nom different dans OPNsense
# Verifier le nom dans : System > Routing > Gateways
# =============================================================================

resource "opnsense_route_static" "ext_route_vlan15" {
  provider    = opnsense.ext_lyon
  network     = local.vlan15
  gateway     = "OPT1_GW"
  description = "Route VLAN15 Bastion via FW-INT"
  disabled    = false
}

resource "opnsense_route_static" "ext_route_vlan20" {
  provider    = opnsense.ext_lyon
  network     = local.vlan20
  gateway     = "OPT1_GW"
  description = "Route VLAN20 Serveurs via FW-INT"
  disabled    = false
}

resource "opnsense_route_static" "ext_route_vlan30" {
  provider    = opnsense.ext_lyon
  network     = local.vlan30
  gateway     = "OPT1_GW"
  description = "Route VLAN30 Utilisateurs via FW-INT"
  disabled    = false
}

resource "opnsense_route_static" "ext_route_vlan50" {
  provider    = opnsense.ext_lyon
  network     = local.vlan50
  gateway     = "OPT1_GW"
  description = "Route VLAN50 Backup via FW-INT"
  disabled    = false
}

# =============================================================================
# ROUTES STATIQUES -- FW-INT-LYON01
# Gateway "WAN_GW" = 10.0.1.1 (FW-EXT)
# =============================================================================

resource "opnsense_route_static" "int_route_marseille" {
  provider    = opnsense.int_lyon
  network     = local.marseille
  gateway     = "WAN_GW"
  description = "Route LAN Marseille via FW-EXT (IPsec)"
  disabled    = false
}

resource "opnsense_route_static" "int_route_agents" {
  provider    = opnsense.int_lyon
  network     = local.agents
  gateway     = "WAN_GW"
  description = "Route agents WireGuard via FW-EXT"
  disabled    = false
}

# =============================================================================
# ROUTES STATIQUES -- FW-EXT-MRS01
# Gateway "WAN_GW" = 10.1.0.1 (RTR-MRS01)
# =============================================================================

resource "opnsense_route_static" "mrs_route_vlan20" {
  provider    = opnsense.ext_mrs
  network     = local.vlan20
  gateway     = "WAN_GW"
  description = "Route VLAN20 Lyon via IPsec"
  disabled    = false
}

resource "opnsense_route_static" "mrs_route_dmz" {
  provider    = opnsense.ext_mrs
  network     = local.dmz
  gateway     = "WAN_GW"
  description = "Route DMZ Lyon via IPsec"
  disabled    = false
}

# =============================================================================
# REGLES FIREWALL -- FW-EXT-LYON01
# =============================================================================

resource "opnsense_firewall_filter_rule" "ext_wg_in" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "udp"
  source      = { net = "any" }
  destination = { net = "wan", port = "51820" }
  description = "WireGuard entrant UDP 51820"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "ext_http_web01" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = "any" }
  destination = { net = local.web01, port = "80" }
  description = "HTTP vers WEB01"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "ext_https_web01" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = "any" }
  destination = { net = local.web01, port = "443" }
  description = "HTTPS vers WEB01"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "ext_smtp_mail01" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = "any" }
  destination = { net = local.mail01, port = "25" }
  description = "SMTP entrant vers MAIL01"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "ext_imap_mail01" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = "any" }
  destination = { net = local.mail01, port = "993" }
  description = "IMAP TLS vers MAIL01"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "ext_ipsec_esp" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "esp"
  source      = { net = "any" }
  destination = { net = "wan" }
  description = "IPsec ESP entrant Lyon-Marseille"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "ext_ike_500" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "udp"
  source      = { net = "any" }
  destination = { net = "wan", port = "500" }
  description = "IKE UDP 500 entrant"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "ext_ike_4500" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "udp"
  source      = { net = "any" }
  destination = { net = "wan", port = "4500" }
  description = "IKE NAT-T UDP 4500 entrant"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "ext_vlans_out" {
  provider    = opnsense.ext_lyon
  type        = "pass"
  interface   = "opt2"
  direction   = "in"
  protocol    = "any"
  source      = { net = "opt2" }
  destination = { net = "any" }
  description = "Trafic sortant VLANs internes vers internet"
  enabled     = true
  log         = false
}

# =============================================================================
# REGLES FIREWALL -- FW-INT-LYON01
# =============================================================================

resource "opnsense_firewall_filter_rule" "int_ssh_bastion_vlan20" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "opt1"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = local.bastion01 }
  destination = { net = local.vlan20, port = "22" }
  description = "SSH BASTION01 -> VLAN20"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "int_ssh_bastion_vlan50" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "opt1"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = local.bastion01 }
  destination = { net = local.vlan50, port = "22" }
  description = "SSH BASTION01 -> VLAN50 Backup"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "int_api_bastion" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "opt1"
  direction   = "in"
  protocol    = "tcp"
  source      = { net = local.bastion01 }
  destination = { net = var.fw_int_lyon_ip, port = "443" }
  description = "API OPNsense FW-INT depuis BASTION01 (Terraform)"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "int_marseille_vlan20" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "any"
  source      = { net = local.marseille }
  destination = { net = local.vlan20 }
  description = "Marseille -> VLAN20 via IPsec"
  enabled     = true
  log         = true
}

resource "opnsense_firewall_filter_rule" "int_agents_vlan20" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "any"
  source      = { net = local.agents }
  destination = { net = local.dc01 }
  description = "Agents WireGuard -> DC01 (AD)"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "int_vlan20_out" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "opt2"
  direction   = "in"
  protocol    = "any"
  source      = { net = local.vlan20 }
  destination = { net = "any" }
  description = "VLAN20 Serveurs vers internet (MAJ, paquets)"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "int_vlan15_out" {
  provider    = opnsense.int_lyon
  type        = "pass"
  interface   = "opt1"
  direction   = "in"
  protocol    = "any"
  source      = { net = local.vlan15 }
  destination = { net = "any" }
  description = "VLAN15 Bastion vers internet (Git, Terraform)"
  enabled     = true
  log         = false
}

# =============================================================================
# REGLES FIREWALL -- FW-EXT-MRS01
# =============================================================================

resource "opnsense_firewall_filter_rule" "mrs_lan_out" {
  provider    = opnsense.ext_mrs
  type        = "pass"
  interface   = "lan"
  direction   = "in"
  protocol    = "any"
  source      = { net = local.marseille }
  destination = { net = "any" }
  description = "LAN Marseille sortant (internet + Lyon via IPsec)"
  enabled     = true
  log         = false
}

resource "opnsense_firewall_filter_rule" "mrs_ipsec_in" {
  provider    = opnsense.ext_mrs
  type        = "pass"
  interface   = "wan"
  direction   = "in"
  protocol    = "esp"
  source      = { net = "any" }
  destination = { net = "wan" }
  description = "IPsec ESP depuis Lyon"
  enabled     = true
  log         = false
}

# =============================================================================
# DNS UNBOUND -- FW-INT-LYON01
# Host overrides : resolution des VMs Nova Syndicate par nom
# Forward nova.local -> DC01 (Samba AD gere le DNS du domaine)
# =============================================================================

resource "opnsense_unbound_host_override" "dns_dc01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "dc01"
  domain      = "nova.local"
  server      = local.dc01
  description = "DC01 - Controleur de domaine"
}

resource "opnsense_unbound_host_override" "dns_fs01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "fs01"
  domain      = "nova.local"
  server      = local.fs01
  description = "FS01 - Serveur de fichiers"
}

resource "opnsense_unbound_host_override" "dns_db01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "db01"
  domain      = "nova.local"
  server      = local.db01
  description = "DB01 - MariaDB"
}

resource "opnsense_unbound_host_override" "dns_app01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "app01"
  domain      = "nova.local"
  server      = local.app01
  description = "APP01 - Squid + Vault"
}

resource "opnsense_unbound_host_override" "dns_bastion01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "bastion01"
  domain      = "nova.local"
  server      = local.bastion01
  description = "BASTION01 - SSH + Ansible"
}

resource "opnsense_unbound_host_override" "dns_backup01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "backup01"
  domain      = "nova.local"
  server      = local.backup01
  description = "BACKUP01 - BorgBackup"
}

resource "opnsense_unbound_host_override" "dns_web01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "web01"
  domain      = "nova.local"
  server      = local.web01
  description = "WEB01 - Nginx DMZ"
}

resource "opnsense_unbound_host_override" "dns_mail01" {
  provider    = opnsense.int_lyon
  enabled     = true
  host        = "mail01"
  domain      = "nova.local"
  server      = local.mail01
  description = "MAIL01 - Postfix + Dovecot DMZ"
}

resource "opnsense_unbound_forward" "nova_local" {
  provider = opnsense.int_lyon
  enabled  = true
  domain   = "nova.local"
  server   = local.dc01
  port     = 53
}

resource "opnsense_unbound_forward" "dns_cloudflare" {
  provider = opnsense.int_lyon
  enabled  = true
  domain   = ""
  server   = "1.1.1.1"
  port     = 53
}

resource "opnsense_unbound_forward" "dns_google" {
  provider = opnsense.int_lyon
  enabled  = true
  domain   = ""
  server   = "8.8.8.8"
  port     = 53
}

# =============================================================================
# DNS UNBOUND -- FW-EXT-MRS01
# Forward nova.local vers DC01 Lyon via le tunnel IPsec
# =============================================================================

resource "opnsense_unbound_forward" "mrs_nova_local" {
  provider = opnsense.ext_mrs
  enabled  = true
  domain   = "nova.local"
  server   = local.dc01
  port     = 53
}

resource "opnsense_unbound_forward" "mrs_dns_public" {
  provider = opnsense.ext_mrs
  enabled  = true
  domain   = ""
  server   = "1.1.1.1"
  port     = 53
}

resource "opnsense_unbound_host_override" "dns_poste_mrs1" {
  provider    = opnsense.ext_mrs
  enabled     = true
  host        = "poste-mrs1"
  domain      = "nova.local"
  server      = local.poste_mrs1
  description = "POSTE-MRS1 - Poste Marseille"
}

# =============================================================================
# DHCP -- FW-INT-LYON01 : VLAN 30 Utilisateurs Lyon
# Pool : 192.168.30.20 - 192.168.30.62 (43 IPs, 40 postes + marge)
# DNS primaire : DC01 pour resolution nova.local immediate
# =============================================================================

resource "opnsense_dhcpv4_server" "dhcp_vlan30" {
  provider   = opnsense.int_lyon
  interface  = "opt3"
  enabled    = true

  range = {
    from = "192.168.30.20"
    to   = "192.168.30.62"
  }

  gateway     = "192.168.30.1"
  dns_servers = [local.dc01, "1.1.1.1"]
  domain      = "nova.local"
  lease_time  = 86400
}

# =============================================================================
# DHCP -- FW-EXT-MRS01 : LAN Marseille
# Pool : 192.168.40.20 - 192.168.40.62 (43 IPs, 25 postes + marge)
# DNS primaire : DC01 Lyon via IPsec -- le tunnel doit etre etabli en premier
# =============================================================================

resource "opnsense_dhcpv4_server" "dhcp_marseille" {
  provider   = opnsense.ext_mrs
  interface  = "lan"
  enabled    = true

  range = {
    from = "192.168.40.20"
    to   = "192.168.40.62"
  }

  gateway     = "192.168.40.1"
  dns_servers = [local.dc01, "1.1.1.1"]
  domain      = "nova.local"
  lease_time  = 86400
}

# =============================================================================
# WIREGUARD -- FW-EXT-LYON01 : agents distants
# Reseau : 10.20.0.0/24, interface wg0 = 10.20.0.1/24, port UDP 51820
# =============================================================================

resource "opnsense_wireguard_server" "agents" {
  provider      = opnsense.ext_lyon
  enabled       = true
  name          = "NovaAgents"
  tunneladdress = "10.20.0.1/24"
  port          = 51820
  privatekey    = var.wireguard_server_privkey
  dns           = [local.dc01]
  description   = "VPN WireGuard agents commerciaux distants"
}

resource "opnsense_wireguard_peer" "agent1" {
  provider       = opnsense.ext_lyon
  enabled        = true
  name           = "AGENT-1"
  server_address = opnsense_wireguard_server.agents.id
  tunneladdress  = "10.20.0.2/32"
  publickey      = var.wireguard_agent1_pubkey
  description    = "Agent commercial itinerant 1"
}

resource "opnsense_wireguard_peer" "agent2" {
  provider       = opnsense.ext_lyon
  enabled        = var.wireguard_agent2_pubkey != "" ? true : false
  name           = "AGENT-2"
  server_address = opnsense_wireguard_server.agents.id
  tunneladdress  = "10.20.0.3/32"
  publickey      = var.wireguard_agent2_pubkey != "" ? var.wireguard_agent2_pubkey : "PLACEHOLDER"
  description    = "Agent commercial itinerant 2"
}

# =============================================================================
# IPSEC IKEV2 -- COTE LYON (FW-EXT-LYON01)
# =============================================================================

resource "opnsense_ipsec_pre_shared_key" "lyon_psk" {
  provider     = opnsense.ext_lyon
  ident        = "0.0.0.0"
  remote_ident = "0.0.0.0"
  psk          = var.ipsec_psk
  type         = "PSK"
}

resource "opnsense_ipsec_phase1" "lyon_p1" {
  provider             = opnsense.ext_lyon
  enabled              = true
  description          = "Lyon-Marseille IKEv2 site-a-site"
  connection_type      = "site-to-site"
  protocol_version     = "inet"
  iketype              = "ikev2"
  interface            = "wan"
  proposal             = "aes256gcm-sha256-modp2048"
  local_gateway        = ""
  remote_gateway       = var.fw_ext_mrs_ip
  authentication_method = "pre_shared_key"
  pre_shared_key       = var.ipsec_psk
  lifetime             = 28800
  rekey_time           = 28000
  dpd_action           = "restart"
  dpd_delay            = 10
  dpd_maxfail          = 5
  mobike               = false
}

resource "opnsense_ipsec_phase2" "lyon_p2" {
  provider    = opnsense.ext_lyon
  enabled     = true
  description = "Lyon tunnel VLAN20+DMZ <-> Marseille"
  phase1      = opnsense_ipsec_phase1.lyon_p1.id
  proposal    = "aes256gcm-sha256"
  pfs_group   = "14"
  lifetime    = 3600

  local_ts  = [local.vlan20, local.dmz]
  remote_ts = [local.marseille]
}

# =============================================================================
# IPSEC IKEV2 -- COTE MARSEILLE (FW-EXT-MRS01)
# Miroir exact du cote Lyon avec local_ts et remote_ts inverses
# =============================================================================

resource "opnsense_ipsec_pre_shared_key" "mrs_psk" {
  provider     = opnsense.ext_mrs
  ident        = "0.0.0.0"
  remote_ident = "0.0.0.0"
  psk          = var.ipsec_psk
  type         = "PSK"
}

resource "opnsense_ipsec_phase1" "mrs_p1" {
  provider             = opnsense.ext_mrs
  enabled              = true
  description          = "Marseille-Lyon IKEv2 site-a-site"
  connection_type      = "site-to-site"
  protocol_version     = "inet"
  iketype              = "ikev2"
  interface            = "wan"
  proposal             = "aes256gcm-sha256-modp2048"
  local_gateway        = ""
  remote_gateway       = var.fw_ext_lyon_ip
  authentication_method = "pre_shared_key"
  pre_shared_key       = var.ipsec_psk
  lifetime             = 28800
  rekey_time           = 28000
  dpd_action           = "restart"
  dpd_delay            = 10
  dpd_maxfail          = 5
  mobike               = false
}

resource "opnsense_ipsec_phase2" "mrs_p2" {
  provider    = opnsense.ext_mrs
  enabled     = true
  description = "Marseille tunnel <-> VLAN20+DMZ Lyon"
  phase1      = opnsense_ipsec_phase1.mrs_p1.id
  proposal    = "aes256gcm-sha256"
  pfs_group   = "14"
  lifetime    = 3600

  local_ts  = [local.marseille]
  remote_ts = [local.vlan20, local.dmz]
}
