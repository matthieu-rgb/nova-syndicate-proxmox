# ============================================================
# WIREGUARD - Agents commerciaux distants
# ============================================================

resource "opnsense_wireguard_server" "agents" {
  provider   = opnsense.fw_ext
  enabled    = true
  name       = "nova-agents"
  public_key = var.wg_server_pubkey
  private_key = var.wg_server_privkey
  tunnel_address = ["10.10.0.1/24"]
  port       = 51820
  dns        = ["192.168.1.20"]
}

# Regle firewall : autoriser WireGuard entrant
resource "opnsense_firewall_filter" "wg_inbound" {
  provider    = opnsense.fw_ext
  enabled     = true
  action      = "pass"
  quick       = true
  interface   = ["wan"]
  direction   = "in"
  protocol    = "udp"
  source = {
    net = "any"
  }
  destination = {
    net  = "any"
    port = "51820"
  }
  description = "WireGuard agents distants"
}
