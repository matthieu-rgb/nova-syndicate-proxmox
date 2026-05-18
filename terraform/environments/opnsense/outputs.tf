# ============================================================
# Nova Syndicate -- Outputs OPNsense
# Affiches apres terraform apply
# ============================================================

# ============================================================
# URLs API des 4 firewalls -- debug et integration externe
# ============================================================

output "firewalls_api_urls" {
  description = "URLs des APIs OPNsense pour les 4 firewalls Nova"
  value = {
    wansim     = "https://${var.wansim_ip}/api"
    fw_ext     = "https://${var.fw_ext_ip}/api"
    fw_int     = "https://${var.fw_int_ip}/api"
    fw_ext_mrs = "https://${var.fw_ext_mrs_ip}/api"
  }
}

# ============================================================
# Plan VLSM applique -- documentation runtime
# ============================================================

output "vlsm_summary" {
  description = "Plan d'adressage VLSM Nova Syndicate (source : var.vlsm)"
  value       = var.vlsm
}

# ============================================================
# VLANs Lyon -- recap lisible
# ============================================================

output "vlans_lyon" {
  description = "VLANs configures sur le trunk Lyon (vmbr1)"
  value = {
    bastion = "VLAN ${var.vlan_ids.bastion} - ${var.vlsm.vlan15_bastion}"
    servers = "VLAN ${var.vlan_ids.servers} - ${var.vlsm.vlan20_servers}"
    users   = "VLAN ${var.vlan_ids.users} - ${var.vlsm.vlan30_users}"
    backup  = "VLAN ${var.vlan_ids.backup} - ${var.vlsm.vlan50_backup}"
  }
}
