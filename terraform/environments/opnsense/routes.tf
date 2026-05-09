# ============================================================
# Nova Syndicate -- Routes statiques
# Seules les routes NECESSAIRES sont conservees.
# 5 routes PARASITES supprimees lors de T3 (2026-05-09) :
#   - wansim_to_lyon_internal_subnets (WAN-SIM, 192.168.0.0/16)
#   - wansim_to_lyon_transit (WAN-SIM, 10.0.1.0/30)
#   - wansim_to_mrs_lan (WAN-SIM, 192.168.40.0/26)
#   - fwext_to_mrs_lan (FW-EXT-LYON, 192.168.40.0/26)
#   - fwextmrs_to_lyon (FW-EXT-MRS, 192.168.0.0/16)
# Audit de validation : docs/SESSION-LOG.md section T-IMPORT
# ============================================================

# ============================================================
# FW-EXT-LYON -- routes vers VLANs FW-INT-LYON
#
# Gateway FW_INT_GW = interface opt1, gateway 10.0.1.2 (FW-INT-LYON)
# Ces 4 routes sont NECESSAIRES : apres decryptage IPsec, FW-EXT-LYON
# doit router les replies vers FW-INT-LYON et non vers la default GW WAN.
# ============================================================

resource "opnsense_route" "fwext_to_bastion" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "VLAN BASTION (15.0/29) via FW-INT-LYON -- requis IPsec reply routing"
  network     = "192.168.15.0/29"
  gateway     = "FW_INT_GW"
  # NECESSAIRE : apres decryptage IPsec, FW-EXT-LYON doit router les replies vers
  # FW-INT-LYON (10.0.1.2) et non vers la default gateway WAN.
  # Prouve en session 2026-05-08 : sans ces routes, replies dropped.
}

resource "opnsense_route" "fwext_to_servers" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "VLAN SERVERS (20.0/28) via FW-INT-LYON -- requis IPsec reply routing"
  network     = "192.168.20.0/28"
  gateway     = "FW_INT_GW"
  # NECESSAIRE : meme raison que fwext_to_bastion
}

resource "opnsense_route" "fwext_to_users" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "VLAN USERS (30.0/26) via FW-INT-LYON -- requis IPsec reply routing"
  network     = "192.168.30.0/26"
  gateway     = "FW_INT_GW"
  # NECESSAIRE : meme raison que fwext_to_bastion
}

resource "opnsense_route" "fwext_to_backup" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "VLAN BACKUP (50.0/29) via FW-INT-LYON -- requis IPsec reply routing"
  network     = "192.168.50.0/29"
  gateway     = "FW_INT_GW"
  # NECESSAIRE : meme raison que fwext_to_bastion
}

