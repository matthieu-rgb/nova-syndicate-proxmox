# ============================================================
# Nova Syndicate -- Configuration OPNsense via Terraform
# Provider : browningluke/opnsense
# Scope    : 4 firewalls (WAN-SIM, FW-EXT-LYON, FW-INT-LYON, FW-EXT-MRS)
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.16.0"
    }
  }
}

# ============================================================
# PROVIDER -- WAN-SIMULATOR (VMID 200, https://10.0.0.1)
# Role : simule le transit ISP entre Lyon et Marseille
# ============================================================
provider "opnsense" {
  alias          = "wansim"
  uri            = "https://${var.wansim_ip}"
  api_key        = var.wansim_api_key
  api_secret     = var.wansim_api_secret
  allow_insecure = true
}

# ============================================================
# PROVIDER -- FW-EXT-LYON (VMID 201, https://172.16.1.1)
# Role : firewall externe Lyon (WAN -> DMZ -> FW-INT)
# ============================================================
provider "opnsense" {
  alias          = "fw_ext"
  uri            = "https://${var.fw_ext_ip}"
  api_key        = var.fw_ext_api_key
  api_secret     = var.fw_ext_api_secret
  allow_insecure = true
}

# ============================================================
# PROVIDER -- FW-INT-LYON (VMID 202, https://192.168.99.1)
# Role : firewall interne Lyon (transit FW-EXT -> VLANs internes)
# ============================================================
provider "opnsense" {
  alias          = "fw_int"
  uri            = "https://${var.fw_int_ip}"
  api_key        = var.fw_int_api_key
  api_secret     = var.fw_int_api_secret
  allow_insecure = true
}

# ============================================================
# PROVIDER -- FW-EXT-MRS (VMID 203, https://192.168.40.1)
# Role : firewall site Marseille (WAN -> LAN MRS)
# ============================================================
provider "opnsense" {
  alias          = "fw_ext_mrs"
  uri            = "https://${var.fw_ext_mrs_ip}"
  api_key        = var.fw_ext_mrs_api_key
  api_secret     = var.fw_ext_mrs_api_secret
  allow_insecure = true
}