# ============================================================
# WAN-SIMULATOR -- regles filter
# ============================================================
# Role : router transparent entre Lyon, MRS et internet reel.
# Pas de filtrage applicatif ici, juste de la regle de transit.
# ============================================================

resource "opnsense_firewall_filter" "wansim_lan_to_any" {
  provider    = opnsense.wansim
  enabled     = true
  description = "Trafic depuis transit Lyon -> any (internet ou MRS)"
  interface = {
    interface = ["lan"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source = {
      net = "net_lyon_subnet"
    }
    destination = {
      net = "any"
    }
  }
}

resource "opnsense_firewall_filter" "wansim_opt1_to_any" {
  provider    = opnsense.wansim
  enabled     = true
  description = "Trafic depuis transit MRS -> any (internet ou Lyon)"
  interface = {
    interface = ["opt1"]
  }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source = {
      net = "net_mrs_subnet"
    }
    destination = {
      net = "any"
    }
  }
}

resource "opnsense_firewall_filter" "wansim_wan_block_all" {
  provider    = opnsense.wansim
  enabled     = false
  description = "Block tout WAN entrant non sollicite (etat-firewall gere les retours)"
  interface = {
    interface = ["wan"]
  }
  filter = {
    action    = "block"
    direction = "in"
    quick     = true
    protocol  = "any"
    log       = true
    source = {
      net = "any"
    }
    destination = {
      net = "any"
    }
  }
}