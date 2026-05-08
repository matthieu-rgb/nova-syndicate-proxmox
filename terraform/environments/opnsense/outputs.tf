# ============================================================
# OUTPUTS - Informations utiles apres terraform apply
# ============================================================

output "fw_ext_api_url" {
  description = "URL API FW-EXT-LYON1"
  value       = "https://${var.fw_ext_ip}/api"
}

output "fw_int_api_url" {
  description = "URL API FW-INT-LYON1"
  value       = "https://${var.fw_int_ip}/api"
}

output "wireguard_port" {
  description = "Port WireGuard agents"
  value       = 51820
}

output "vlans_configures" {
  description = "VLANs configures sur FW-INT"
  value = {
    bastion = "VLAN 15 - 192.168.15.0/29"
    servers = "VLAN 20 - 192.168.20.0/28"
    users   = "VLAN 30 - 192.168.30.0/26"
    backup  = "VLAN 50 - 192.168.50.0/29"
  }
}