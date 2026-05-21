# ============================================================
# FW-INT-LYON1 -- Regles filter
# ============================================================
# Role : pare-feu interne Lyon. Filtre les flux inter-VLAN
# (BASTION/SERVERS/USERS/BACKUP) et la sortie internet.
# ============================================================

# ============================================================
# BASTION (VLAN 15) -- admin / Ansible
# ============================================================

resource "opnsense_firewall_filter" "fwint_bastion_to_servers_ssh" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION01 -> servers SSH (admin/ansible)"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "host_bastion01" }
    destination = { net = "net_lyon_servers", port = "22" }
  }
}

resource "opnsense_firewall_filter" "fwint_bastion_to_dc_ad_tcp" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION01 -> DC01 AD TCP"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "host_bastion01" }
    destination = { net = "host_dc01", port = "ports_ad_tcp" }
  }
}

resource "opnsense_firewall_filter" "fwint_bastion_to_dc_ad_udp" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION01 -> DC01 AD UDP (DNS, Kerberos)"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source      = { net = "host_bastion01" }
    destination = { net = "host_dc01", port = "ports_ad_udp" }
  }
}

resource "opnsense_firewall_filter" "fwint_bastion_to_internet" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION01 -> internet (apt, repos)"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "host_bastion01" }
    destination = { net = "any" }
  }
}

resource "opnsense_firewall_filter" "fwint_bastion_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Block + log tout autre trafic depuis BASTION"
  interface   = { interface = ["opt2"] }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source      = { net = "any" }
    destination = { net = "any" }
  }
}

# ============================================================
# SERVERS (VLAN 20) -- DC, FS, DB, APP, proxy-lyon
# ============================================================

resource "opnsense_firewall_filter" "fwint_servers_to_internet" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Servers -> internet (apt, NTP, repos, B2 backup)"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "net_lyon_servers" }
    destination = { net = "any" }
  }
}

resource "opnsense_firewall_filter" "fwint_servers_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Block + log tout autre depuis servers"
  interface   = { interface = ["opt3"] }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source      = { net = "any" }
    destination = { net = "any" }
  }
}

# ============================================================
# USERS (VLAN 30) -- postes
# ============================================================

resource "opnsense_firewall_filter" "fwint_users_to_dc_ad_tcp" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Users -> DC01 AD TCP (auth, GPO)"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_lyon_users" }
    destination = { net = "host_dc01", port = "ports_ad_tcp" }
  }
}

resource "opnsense_firewall_filter" "fwint_users_to_dc_ad_udp" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Users -> DC01 AD UDP (DNS, Kerberos, NTP)"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source      = { net = "net_lyon_users" }
    destination = { net = "host_dc01", port = "ports_ad_udp" }
  }
}

resource "opnsense_firewall_filter" "fwint_users_to_servers_smb" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Users -> servers SMB (partages)"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_lyon_users" }
    destination = { net = "net_lyon_servers", port = "ports_smb" }
  }
}

resource "opnsense_firewall_filter" "fwint_users_to_internet" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Users -> internet (web)"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "net_lyon_users" }
    destination = { net = "any" }
  }
}

resource "opnsense_firewall_filter" "fwint_users_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Block + log tout autre depuis users"
  interface   = { interface = ["opt4"] }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source      = { net = "any" }
    destination = { net = "any" }
  }
}

# ============================================================
# BACKUP (VLAN 50) -- BACKUP01 (BorgBackup + rclone)
# ============================================================

resource "opnsense_firewall_filter" "fwint_backup_to_servers_ssh" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BACKUP01 -> servers SSH (pull borg)"
  interface   = { interface = ["opt1"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "host_backup01" }
    destination = { net = "net_lyon_servers", port = "22" }
  }
}

resource "opnsense_firewall_filter" "fwint_backup_to_internet" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BACKUP01 -> internet (rclone vers B2)"
  interface   = { interface = ["opt1"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "host_backup01" }
    destination = { net = "any" }
  }
}

resource "opnsense_firewall_filter" "fwint_backup_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Block + log tout autre depuis backup"
  interface   = { interface = ["opt1"] }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source      = { net = "any" }
    destination = { net = "any" }
  }
}

# ============================================================
# ADMIN (VLAN 60 / opt5) -- AWX01 + futurs outils d'orchestration
# Plan d'administration segregue du plan SERVERS (NIS2 art.21).
# AWX accede en SSH direct aux VMs cibles (bypass bastion) : trust
# boundary documente dans ADR-0031 (mitigations RBAC + cle dediee
# svc-awx-ssh + audit Wazuh). Pattern : pass specifiques + block/log.
# ============================================================

resource "opnsense_firewall_filter" "fwint_admin_to_dc_ad_tcp" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 10
  description = "ADMIN (VLAN60) -> DC01 AD TCP (LDAPS 636 auth AWX, LDAP)"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_lyon_admin" }
    destination = { net = "host_dc01", port = "ports_ad_tcp" }
  }
}

resource "opnsense_firewall_filter" "fwint_admin_to_dc_ad_udp" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 11
  description = "ADMIN (VLAN60) -> DC01 AD UDP (DNS 53, NTP 123, Kerberos)"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "UDP"
    source      = { net = "net_lyon_admin" }
    destination = { net = "host_dc01", port = "ports_ad_udp" }
  }
}

resource "opnsense_firewall_filter" "fwint_admin_to_internal_ssh" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 12
  description = "ADMIN (VLAN60) -> VMs internes SSH 22 (AWX orchestration, bypass bastion - cf ADR-0031)"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_lyon_admin" }
    destination = { net = "net_lyon_internal", port = "22" }
  }
}

resource "opnsense_firewall_filter" "fwint_admin_to_internet_web" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 13
  description = "ADMIN (VLAN60) -> internet HTTP/HTTPS (K3s install, Helm, registries, apt, git-HTTPS)"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_lyon_admin" }
    destination = { net = "any", port = "ports_web_out" }
  }
}

resource "opnsense_firewall_filter" "fwint_admin_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 90
  description = "Block + log tout autre trafic depuis ADMIN (VLAN60) - audit NIS2"
  interface   = { interface = ["opt5"] }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source      = { net = "any" }
    destination = { net = "any" }
  }
}

# ============================================================
# WAN (transit depuis FW-EXT) -- block les entrants non sollicites
# Le stateful firewall gere automatiquement les retours.
# ============================================================

resource "opnsense_firewall_filter" "fwint_wan_ipsec_decapsulated" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 1
  description = "Trafic IPsec decapsule MRS (192.168.40.0/26) -> VLANs Lyon"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "net_lan_mrs" }
    destination = { net = "net_lyon_internal" }
  }
}

resource "opnsense_firewall_filter" "fwint_admin_to_app01_https" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 1
  description = "Reseau admin (192.168.18.0/24) -> APP01 HTTPS 443 (Authelia/Grafana/Wazuh)"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    source      = { net = "net_proxmox_admin" }
    destination = { net = "host_app01", port = "443" }
  }
}

resource "opnsense_firewall_filter" "fwint_mail01_to_dc01_ldaps" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 1
  description = "T-MAIL-LDAP-FW-RULE: mail01 -> dc01 LDAPS only"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "TCP"
    log       = true
    source      = { net = "host_mail01" }
    destination = { net = "host_dc01", port = "636" }
  }
}

resource "opnsense_firewall_filter" "fwint_wan_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  sequence    = 2
  description = "Block + log tout WAN entrant non sollicite"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source      = { net = "any" }
    destination = { net = "any" }
  }
}
