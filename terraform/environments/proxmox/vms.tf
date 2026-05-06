locals {
  # Chemin absolu vers les fichiers cloud-init
  cloud_init_dir = "${path.module}/cloud-init"
}

# --- DC01 : Controleur de domaine Samba AD ---
module "dc01" {
  source = "../../modules/proxmox-vm"

  vmid          = 103
  hostname      = "dc01"
  fqdn          = "dc01.nova-syndicate.local"
  description   = "Samba AD Domain Controller"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["server", "ad", "vlan20"]

  cpu_cores    = 2
  memory_mb    = 2048
  disk_size_gb = 32

  bridge     = "vmbr1"
  vlan_tag   = 20
  ip_address = "192.168.20.10/28"
  gateway    = "192.168.20.1"
  # DC01 est son propre DNS apres provisionnement Ansible
  dns_servers = ["127.0.0.1", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- FS01 : Serveur de fichiers Samba ---
module "fs01" {
  source = "../../modules/proxmox-vm"

  vmid          = 104
  hostname      = "fs01"
  fqdn          = "fs01.nova-syndicate.local"
  description   = "Samba File Server"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["server", "fileserver", "vlan20"]

  cpu_cores    = 2
  memory_mb    = 2048
  disk_size_gb = 64

  bridge      = "vmbr1"
  vlan_tag    = 20
  ip_address  = "192.168.20.11/28"
  gateway     = "192.168.20.1"
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- DB01 : Base de donnees MariaDB ---
module "db01" {
  source = "../../modules/proxmox-vm"

  vmid          = 105
  hostname      = "db01"
  fqdn          = "db01.nova-syndicate.local"
  description   = "MariaDB Database Server"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["server", "database", "vlan20"]

  cpu_cores    = 2
  memory_mb    = 2048
  disk_size_gb = 32

  bridge      = "vmbr1"
  vlan_tag    = 20
  ip_address  = "192.168.20.12/28"
  gateway     = "192.168.20.1"
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- APP01 : Wazuh Manager + Grafana + Vault ---
module "app01" {
  source = "../../modules/proxmox-vm"

  vmid          = 106
  hostname      = "app01"
  fqdn          = "app01.nova-syndicate.local"
  description   = "Wazuh Manager + Grafana + HashiCorp Vault"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["server", "siem", "vlan20"]

  # APP01 est la VM la plus gourmande (Wazuh indexer + Grafana + Vault)
  cpu_cores    = 4
  memory_mb    = 4096
  disk_size_gb = 32

  bridge      = "vmbr1"
  vlan_tag    = 20
  ip_address  = "192.168.20.13/28"
  gateway     = "192.168.20.1"
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- BASTION01 : SSH Bastion + MFA TOTP ---
module "bastion01" {
  source = "../../modules/proxmox-vm"

  vmid          = 102
  hostname      = "bastion01"
  fqdn          = "bastion01.nova-syndicate.local"
  description   = "SSH Bastion avec MFA TOTP"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["bastion", "security", "vlan15"]

  cpu_cores    = 1
  memory_mb    = 1024
  disk_size_gb = 16

  # VLAN 15 : segment Bastion isole
  bridge      = "vmbr1"
  vlan_tag    = 15
  ip_address  = "192.168.15.2/29"
  gateway     = "192.168.15.1"
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- BACKUP01 : BorgBackup + rclone B2 ---
module "backup01" {
  source = "../../modules/proxmox-vm"

  vmid          = 109
  hostname      = "backup01"
  fqdn          = "backup01.nova-syndicate.local"
  description   = "BorgBackup + rclone Backblaze B2"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["backup", "vlan50"]

  cpu_cores = 1
  memory_mb = 2048
  # Gros disque pour stocker les backups chiffres localement
  disk_size_gb = 200

  bridge      = "vmbr1"
  vlan_tag    = 50
  ip_address  = "192.168.50.2/29"
  gateway     = "192.168.50.1"
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- WEB01 : Nginx en DMZ ---
module "web01" {
  source = "../../modules/proxmox-vm"

  vmid          = 100
  hostname      = "web01"
  fqdn          = "web01.nova-syndicate.local"
  description   = "Nginx Web Server (DMZ)"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["web", "dmz"]

  cpu_cores    = 1
  memory_mb    = 1024
  disk_size_gb = 16

  # DMZ sur vmbr3 sans tag VLAN
  bridge     = "vmbr3"
  vlan_tag   = 0
  ip_address = "172.16.1.2/29"
  gateway    = "172.16.1.1"
  # DMZ ne peut pas joindre DC01 directement
  dns_servers = ["1.1.1.1", "8.8.8.8"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- MAIL01 : Postfix + Dovecot en DMZ ---
module "mail01" {
  source = "../../modules/proxmox-vm"

  vmid          = 101
  hostname      = "mail01"
  fqdn          = "mail01.nova-syndicate.local"
  description   = "Postfix + Dovecot (DMZ)"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["mail", "dmz"]

  cpu_cores    = 1
  memory_mb    = 1024
  disk_size_gb = 16

  bridge      = "vmbr3"
  vlan_tag    = 0
  ip_address  = "172.16.1.3/29"
  gateway     = "172.16.1.1"
  dns_servers = ["1.1.1.1", "8.8.8.8"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- PROXY-LYON01 : Squid forward proxy Lyon ---
module "proxy_lyon01" {
  source = "../../modules/proxmox-vm"

  vmid          = 107
  hostname      = "proxy-lyon01"
  fqdn          = "proxy-lyon01.nova-syndicate.local"
  description   = "Squid Forward Proxy (Lyon)"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["proxy", "vlan20"]

  cpu_cores    = 1
  memory_mb    = 1024
  disk_size_gb = 16

  bridge      = "vmbr1"
  vlan_tag    = 20
  ip_address  = "192.168.20.14/28"
  gateway     = "192.168.20.1"
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}

# --- PROXY-MRS01 : Squid forward proxy Marseille ---
module "proxy_mrs01" {
  source = "../../modules/proxmox-vm"

  vmid          = 108
  hostname      = "proxy-mrs01"
  fqdn          = "proxy-mrs01.nova-syndicate.local"
  description   = "Squid Forward Proxy (Marseille)"
  node_name     = var.proxmox_node
  template_vmid = var.template_vmid
  datastore_id  = var.proxmox_datastore
  tags          = ["proxy", "marseille"]

  cpu_cores    = 1
  memory_mb    = 1024
  disk_size_gb = 16

  # LAN Marseille sur vmbr2 sans tag VLAN
  bridge     = "vmbr2"
  vlan_tag   = 0
  ip_address = "192.168.40.11/26"
  gateway    = "192.168.40.1"
  # DNS via tunnel IPsec Lyon-Marseille (configure par Terraform OPNsense)
  dns_servers = ["192.168.20.10", "1.1.1.1"]

  ssh_public_keys = var.ansible_ssh_public_key
}
