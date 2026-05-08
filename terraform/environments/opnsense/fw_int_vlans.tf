# ============================================================
# FW-INT-LYON1 -- Sous-interfaces VLAN 802.1Q sur vtnet1
# ============================================================
# Le bridge Proxmox vmbr1 porte un trunk VLAN-aware (vids 15 20 30 50).
# OPNsense doit creer les sous-interfaces pour pouvoir router et
# filtrer chaque VLAN independamment.
#
# IMPORTANT : apres terraform apply, il faut MANUELLEMENT assigner
# ces VLANs comme interfaces logiques OPNsense (opt2/opt3/opt4/opt5)
# via Web UI > Interfaces > Assignments. Le provider browningluke 0.16
# ne supporte pas encore l'automatisation de cet assignment.
# ============================================================

resource "opnsense_interfaces_vlan" "fwint_vlan15_bastion" {
  provider    = opnsense.fw_int
  description = "VLAN 15 - Bastion"
  parent      = "vtnet1"
  tag         = 15
  priority    = 0
}

resource "opnsense_interfaces_vlan" "fwint_vlan20_servers" {
  provider    = opnsense.fw_int
  description = "VLAN 20 - Servers"
  parent      = "vtnet1"
  tag         = 20
  priority    = 0
}

resource "opnsense_interfaces_vlan" "fwint_vlan30_users" {
  provider    = opnsense.fw_int
  description = "VLAN 30 - Users"
  parent      = "vtnet1"
  tag         = 30
  priority    = 0
}

resource "opnsense_interfaces_vlan" "fwint_vlan50_backup" {
  provider    = opnsense.fw_int
  description = "VLAN 50 - Backup"
  parent      = "vtnet1"
  tag         = 50
  priority    = 0
}