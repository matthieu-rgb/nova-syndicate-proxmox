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
# PROVIDER - FW-EXT-LYON1
# ============================================================
provider "opnsense" {
  alias    = "fw_ext"
  uri      = "https://${var.fw_ext_ip}"
  api_key  = var.fw_ext_api_key
  api_secret = var.fw_ext_api_secret
  allow_insecure = true
}

# ============================================================
# PROVIDER - FW-INT-LYON1
# ============================================================
provider "opnsense" {
  alias    = "fw_int"
  uri      = "https://${var.fw_int_ip}"
  api_key  = var.fw_int_api_key
  api_secret = var.fw_int_api_secret
  allow_insecure = true
}
