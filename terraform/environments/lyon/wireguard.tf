# ============================================================
# WIREGUARD - VPN agents distants
# ============================================================

resource "opnsense_wireguard_server" "agents" {
  provider    = opnsense.fw_ext
  name        = "nova-agents"
  tunnel_address = ["192.168.40.1/27"]
  port        = 51820
  private_key = var.wg_server_privkey
  description = "VPN agents commerciaux distants"
}