# ============================================================
# Nova Syndicate -- Routes statiques
# Import-only -- ces routes existent dans OPNsense.
# Ne pas modifier/supprimer sans audit prealable (voir etape 5
# du runbook-ipsec-multi-vlan.md section "Audit des routes").
# ============================================================

# ============================================================
# WAN-SIM -- routes vers subnets Lyon et MRS
#
# Statut : SUSPECTE-A-AUDITER
# WAN-SIM est un transit passif (10.0.0.x <-> 10.0.2.x).
# Le trafic IPsec (ESP) est adresse a 10.0.0.2/10.0.2.2 --
# WAN-SIM n'a pas besoin de connaitre les subnets internes
# pour acheminer les paquets chiffres.
# A valider via desactivation temporaire (Phase III).
# ============================================================

resource "opnsense_route" "wansim_to_lyon_internal_subnets" {
  provider    = opnsense.wansim
  enabled     = true
  description = "Subnets internes Lyon (VLANs) via FW-EXT-LYON"
  network     = "192.168.0.0/16"
  gateway     = "FW_EXT_LYON_GW"
  # SUSPECTE-A-AUDITER : WAN-SIM transit passif, ne devrait pas router vers 192.168.0.0/16
}

resource "opnsense_route" "wansim_to_lyon_transit" {
  provider    = opnsense.wansim
  enabled     = true
  description = "Transit interne Lyon 10.0.1.0/30 via FW-EXT-LYON"
  network     = "10.0.1.0/30"
  gateway     = "FW_EXT_LYON_GW"
  # SUSPECTE-A-AUDITER : 10.0.1.0/30 est derriere FW-EXT-LYON, opaque a WAN-SIM
}

resource "opnsense_route" "wansim_to_mrs_lan" {
  provider    = opnsense.wansim
  enabled     = true
  description = "LAN Marseille via FW-EXT-MRS"
  network     = "192.168.40.0/26"
  gateway     = "FW_EXT_MRS_GW"
  # SUSPECTE-A-AUDITER : meme raisonnement que wansim_to_lyon_internal_subnets
}

# ============================================================
# FW-EXT-LYON -- routes vers VLANs FW-INT-LYON + cross-site
#
# Gateway FW_INT_GW = interface opt1, gateway 10.0.1.2 (FW-INT-LYON)
# ============================================================

resource "opnsense_route" "fwext_to_mrs_lan" {
  provider    = opnsense.fw_ext
  enabled     = true
  description = "LAN Marseille via WAN-SIM"
  network     = "192.168.40.0/26"
  gateway     = "WAN_GW"
  # SUSPECTE-A-AUDITER : IPsec route via SPD kernel, pas via table de routage.
  # FW-EXT-LYON initie le tunnel, le trafic vers 192.168.40.0/26 passe par SPD -> ESP.
  # Cette route statique vers WAN_GW pourrait etre redondante ou conflictuelle.
}

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

# ============================================================
# FW-EXT-MRS -- route cross-site
# ============================================================

resource "opnsense_route" "fwextmrs_to_lyon" {
  provider    = opnsense.fw_ext_mrs
  enabled     = true
  description = "Subnets internes Lyon via WAN-SIM"
  network     = "192.168.0.0/16"
  gateway     = "WAN_GW"
  # SUSPECTE-A-AUDITER : FW-EXT-MRS est responder -- le trafic vers Lyon passe par
  # le tunnel IPsec (SPD). Route statique vers WAN_GW pourrait etre redondante.
  # Symetrique de fwext_to_mrs_lan sur LYON.
}
