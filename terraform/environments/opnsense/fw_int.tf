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
  enabled     = false
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
  enabled     = false
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
  enabled     = false
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
  enabled     = false
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
# WAN (transit depuis FW-EXT) -- block les entrants non sollicites
# Le stateful firewall gere automatiquement les retours.
# ============================================================

resource "opnsense_firewall_filter" "fwint_wan_ipsec_decapsulated" {
  provider    = opnsense.fw_int
  enabled     = true
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

resource "opnsense_firewall_filter" "fwint_wan_block_all" {
  provider    = opnsense.fw_int
  enabled     = false
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
