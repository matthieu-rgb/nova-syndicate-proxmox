# --- WAN-SIMULATOR ---
# OPNsense simulant 2 WAN distincts (Lyon 10.0.0.0/30 et MRS 10.0.2.0/30)
# avec NAT sortant vers la box physique (option C de l'architecture).
module "wan_simulator" {
  source = "../../modules/proxmox-opnsense"

  vmid        = 200
  hostname    = "wan-simulator"
  description = "WAN Simulator - OPNsense avec NAT double WAN"
  node_name   = var.proxmox_node
  tags        = ["firewall", "wan-simulator"]

  cpu_cores    = 1
  memory_mb    = 512
  disk_size_gb = 8

  iso_datastore = var.opnsense_iso_datastore
  iso_file      = var.opnsense_iso_file
  datastore_id  = var.proxmox_datastore

  network_interfaces = [
    { bridge = "vmbr0", vlan_tag = 0 }, # em0 : WAN reel (DHCP box)
    { bridge = "vmbr0", vlan_tag = 0 }, # em1 : 10.0.0.1/30 (FAI Lyon simule)
    { bridge = "vmbr5", vlan_tag = 0 }, # em2 : 10.0.2.1/30 (FAI MRS simule)
  ]
}

# --- FW-EXT-LYON01 ---
# Pare-feu externe Lyon : entre WAN-SIMULATOR et la DMZ
module "fw_ext_lyon01" {
  source = "../../modules/proxmox-opnsense"

  vmid        = 201
  hostname    = "fw-ext-lyon01"
  description = "Pare-feu externe Lyon (WAN -> DMZ -> lien FW-FW)"
  node_name   = var.proxmox_node
  tags        = ["firewall", "lyon", "external"]

  cpu_cores    = 2
  memory_mb    = 1024
  disk_size_gb = 16

  iso_datastore = var.opnsense_iso_datastore
  iso_file      = var.opnsense_iso_file
  datastore_id  = var.proxmox_datastore

  network_interfaces = [
    { bridge = "vmbr0", vlan_tag = 0 }, # em0 (vtnet0) : WAN depuis WAN-SIMULATOR -> 10.0.0.2/30
    { bridge = "vmbr3", vlan_tag = 0 }, # em1 (vtnet1) : DMZ -> 172.16.1.1/29
    { bridge = "vmbr4", vlan_tag = 0 }, # em2 (vtnet2) : lien FW-EXT <-> FW-INT -> 10.0.1.1/30
  ]
}

# --- FW-INT-LYON01 ---
# Pare-feu interne Lyon : entre FW-EXT et le LAN trunk VLAN-aware
module "fw_int_lyon01" {
  source = "../../modules/proxmox-opnsense"

  vmid        = 202
  hostname    = "fw-int-lyon01"
  description = "Pare-feu interne Lyon (lien FW-FW -> trunk LAN VLAN 15/20/30/50)"
  node_name   = var.proxmox_node
  tags        = ["firewall", "lyon", "internal"]

  cpu_cores    = 2
  memory_mb    = 1024
  disk_size_gb = 16

  iso_datastore = var.opnsense_iso_datastore
  iso_file      = var.opnsense_iso_file
  datastore_id  = var.proxmox_datastore

  network_interfaces = [
    { bridge = "vmbr4", vlan_tag = 0 }, # em0 (vtnet0) : depuis FW-EXT -> 10.0.1.2/30
    { bridge = "vmbr1", vlan_tag = 0 }, # em1 (vtnet1) : trunk LAN Lyon (VLAN 15/20/30/50)
    # Les sous-interfaces VLAN sont configurees manuellement dans OPNsense
    # apres le premier boot (Interfaces > Other Types > VLAN)
  ]
}

# --- FW-EXT-MRS01 ---
# Pare-feu externe Marseille : entre WAN-SIMULATOR et le LAN MRS
module "fw_ext_mrs01" {
  source = "../../modules/proxmox-opnsense"

  vmid        = 203
  hostname    = "fw-ext-mrs01"
  description = "Pare-feu Marseille (WAN MRS simule -> LAN MRS)"
  node_name   = var.proxmox_node
  tags        = ["firewall", "marseille"]

  cpu_cores    = 2
  memory_mb    = 1024
  disk_size_gb = 16

  iso_datastore = var.opnsense_iso_datastore
  iso_file      = var.opnsense_iso_file
  datastore_id  = var.proxmox_datastore

  network_interfaces = [
    { bridge = "vmbr5", vlan_tag = 0 }, # em0 (vtnet0) : WAN MRS -> 10.0.2.2/30
    { bridge = "vmbr2", vlan_tag = 0 }, # em1 (vtnet1) : LAN MRS -> 192.168.40.1/26
  ]
}
