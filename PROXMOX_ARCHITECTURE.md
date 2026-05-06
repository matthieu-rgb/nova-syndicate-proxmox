# PROXMOX_ARCHITECTURE.md

## Specifications techniques de l'infrastructure Proxmox

Reference complete des bridges, VLANs, VMs, et configurations cloud-init.

---

## 1. Hote Proxmox VE

### Specifications materielles

```
Hyperviseur : Proxmox VE 9.x (bare-metal)
Disque      : NVMe dedie (separation physique du disque Windows)
RAM         : 64 GB
CPU         : AMD Ryzen (12 coeurs / 24 threads)
GPU         : NVIDIA (non utilise par Proxmox, passthrough optionnel)
```

### Configuration reseau bare-metal

A configurer manuellement dans /etc/network/interfaces apres install :

```
auto lo
iface lo inet loopback

# Carte reseau physique
auto eno1
iface eno1 inet manual

# Bridge management (acces UI Proxmox)
auto vmbr0
iface vmbr0 inet static
    address 192.168.1.10/24      # IP a adapter selon ton LAN
    gateway 192.168.1.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

# Bridge LAN Lyon (VLAN-aware, trunk pour FW-INT)
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 15 20 30 50

# Bridge LAN Marseille
auto vmbr2
iface vmbr2 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Bridge DMZ
auto vmbr3
iface vmbr3 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Bridge lien FW-EXT-LYON <-> FW-INT-LYON (point-to-point /30)
auto vmbr4
iface vmbr4 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Bridge WAN Marseille (option C - WAN simulator)
auto vmbr5
iface vmbr5 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

## 2. Template cloud-init Debian 12

### Procedure manuelle de creation du template (a faire 1 fois)

```bash
# Sur l'hote Proxmox, en SSH :
cd /var/lib/vz/template/iso

# Telecharger l'image cloud Debian 12
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

# Creer une VM template
qm create 9000 --name debian-12-cloud-template --memory 2048 --cores 2 \
    --net0 virtio,bridge=vmbr0 --ostype l26 --scsihw virtio-scsi-single

# Importer le disque
qm importdisk 9000 debian-12-genericcloud-amd64.qcow2 local-lvm

# Attacher le disque
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0

# Configurer cloud-init
qm set 9000 --ide2 local-lvm:cloudinit
qm set 9000 --boot order=scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1

# Convertir en template
qm template 9000
```

Le template (VMID 9000) est ensuite clonable a l'infini par Terraform.

### Cloud-init user-data type

Pour chaque VM, Terraform genere ces parametres :

```yaml
#cloud-config
hostname: dc01
manage_etc_hosts: true
fqdn: dc01.nova-syndicate.local

users:
  - name: debian
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... matthieu@lab

  - name: ansible
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... ansible@control

package_update: true
package_upgrade: false

packages:
  - qemu-guest-agent
  - python3
  - sudo

runcmd:
  - systemctl enable --now qemu-guest-agent
```

## 3. Firewalls OPNsense

### FW-EXT-LYON01

```
ISO          : OPNsense-25.1-dvd-amd64.iso
RAM          : 1 GB
CPU          : 2 cores
Disque       : 16 GB
Interfaces   :
  net0 (vmbr0) : vtnet0 = WAN Lyon depuis WAN-SIMULATOR -> 10.0.0.2/30
  net1 (vmbr3) : vtnet1 = DMZ                            -> 172.16.1.1/29
  net2 (vmbr4) : vtnet2 = Lien vers FW-INT               -> 10.0.1.1/30
```

### FW-INT-LYON01

```
ISO          : OPNsense-25.1-dvd-amd64.iso
RAM          : 1 GB
CPU          : 2 cores
Disque       : 16 GB
Interfaces   :
  net0 (vmbr4) : vtnet0 = Depuis FW-EXT       -> 10.0.1.2/30
  net1 (vmbr1) : vtnet1 = Trunk LAN Lyon
                 + sub-interfaces VLAN :
                   vlan15 -> 192.168.15.1/29 (Bastion)
                   vlan20 -> 192.168.20.1/28 (Servers)
                   vlan30 -> 192.168.30.1/26 (Users)
                   vlan50 -> 192.168.50.1/29 (Backup)
```

### FW-EXT-MRS01

```
ISO          : OPNsense-25.1-dvd-amd64.iso
RAM          : 1 GB
CPU          : 2 cores
Disque       : 16 GB
Interfaces   :
  net0 (vmbr5) : vtnet0 = WAN MRS depuis WAN-SIMULATOR  -> 10.0.2.2/30
  net1 (vmbr2) : vtnet1 = LAN MRS                       -> 192.168.40.1/26
```

### WAN-SIMULATOR (option C)

Petit OPNsense ou VyOS qui simule les 2 WAN distincts.

```
ISO          : OPNsense-25.1 (ou VyOS pour plus simple)
RAM          : 512 MB
CPU          : 1 core
Disque       : 8 GB
Interfaces   :
  net0 (vmbr0) : em0 = DHCP depuis ta box (WAN reel)
  net1 (vmbr0) : em1 = 10.0.0.1/30 (gateway FAI Lyon simule)
  net2 (vmbr5) : em2 = 10.0.2.1/30 (gateway FAI Marseille simule)
NAT          : sortant vers em0 (vraie sortie internet)
```

## 4. VMs Linux (Debian 12 cloud-init)

Toutes les VMs sont clonees du template VMID 9000 via Terraform.

### WEB01 (Nginx DMZ)

```
VMID         : 100
Hostname     : web01
RAM          : 1 GB
CPU          : 1 core
Disque       : 16 GB
Network      :
  net0 (vmbr3, no tag) -> 172.16.1.2/29, gw 172.16.1.1
DNS          : 1.1.1.1, 8.8.8.8 (DMZ ne peut pas joindre DC01 directement)
Cloud-init   : cle SSH ansible + qemu-guest-agent
```

### MAIL01 (Postfix + Dovecot)

```
VMID         : 101
Hostname     : mail01
RAM          : 1 GB
CPU          : 1 core
Disque       : 16 GB
Network      :
  net0 (vmbr3, no tag) -> 172.16.1.3/29, gw 172.16.1.1
DNS          : 1.1.1.1, 8.8.8.8
```

### BASTION01 (SSH bastion + MFA TOTP)

```
VMID         : 102
Hostname     : bastion01
RAM          : 1 GB
CPU          : 1 core
Disque       : 16 GB
Network      :
  net0 (vmbr1, tag=15) -> 192.168.15.2/29, gw 192.168.15.1
DNS          : 192.168.20.10 (DC01)
```

### DC01 (Samba AD)

```
VMID         : 103
Hostname     : dc01
RAM          : 2 GB
CPU          : 2 cores
Disque       : 32 GB
Network      :
  net0 (vmbr1, tag=20) -> 192.168.20.10/28, gw 192.168.20.1
DNS          : 127.0.0.1 (lui-meme), 1.1.1.1
```

### FS01 (Samba file server)

```
VMID         : 104
Hostname     : fs01
RAM          : 2 GB
CPU          : 2 cores
Disque       : 64 GB
Network      :
  net0 (vmbr1, tag=20) -> 192.168.20.11/28, gw 192.168.20.1
DNS          : 192.168.20.10 (DC01)
```

### DB01 (MariaDB)

```
VMID         : 105
Hostname     : db01
RAM          : 2 GB
CPU          : 2 cores
Disque       : 32 GB
Network      :
  net0 (vmbr1, tag=20) -> 192.168.20.12/28, gw 192.168.20.1
DNS          : 192.168.20.10 (DC01)
```

### APP01 (Wazuh Manager + Grafana + Vault)

```
VMID         : 106
Hostname     : app01
RAM          : 4 GB
CPU          : 4 cores
Disque       : 32 GB
Network      :
  net0 (vmbr1, tag=20) -> 192.168.20.13/28, gw 192.168.20.1
DNS          : 192.168.20.10 (DC01)
```

### PROXY-LYON01 (Squid forward proxy)

```
VMID         : 107
Hostname     : proxy-lyon01
RAM          : 1 GB
CPU          : 1 core
Disque       : 16 GB
Network      :
  net0 (vmbr1, tag=20) -> 192.168.20.14/28, gw 192.168.20.1
DNS          : 192.168.20.10 (DC01)
```

### PROXY-MRS01 (Squid forward proxy MRS)

```
VMID         : 108
Hostname     : proxy-mrs01
RAM          : 1 GB
CPU          : 1 core
Disque       : 16 GB
Network      :
  net0 (vmbr2, no tag) -> 192.168.40.11/26, gw 192.168.40.1
DNS          : 192.168.20.10 (DC01) via tunnel IPsec
```

### BACKUP01 (BorgBackup + rclone B2)

```
VMID         : 109
Hostname     : backup01
RAM          : 2 GB
CPU          : 1 core
Disque       : 200 GB (espace pour les backups locaux)
Network      :
  net0 (vmbr1, tag=50) -> 192.168.50.2/29, gw 192.168.50.1
DNS          : 192.168.20.10 (DC01)
```

## 5. Recapitulatif des ressources

```
RAM totale (VMs Linux + firewalls) :
  4 firewalls           = 4 GB    (1+1+1+0.5)
  10 VMs Linux          = ~17 GB
  Proxmox host overhead = 2 GB
  TOTAL                 = ~23 GB sur 64 GB disponibles

CPU :
  Au total ~22 vCPU declares pour 24 threads physiques
  (overcommit acceptable car les VMs ne sont pas a 100% en meme temps)

Disque :
  4 firewalls           = 64 GB
  10 VMs Linux          = ~456 GB
  Templates + ISO       = ~10 GB
  TOTAL                 = ~530 GB
```

## 6. Ordre de deploiement Terraform

Pour eviter les dependances cassees :

```
1. Creer le template Debian cloud-init (manuel, 1 fois)
2. terraform apply (proxmox)
   -> Cree les VMs dans cet ordre :
      a. WAN-SIMULATOR (configure manuellement la 1ere fois)
      b. FW-EXT-LYON, FW-INT-LYON (config manuelle 1ere fois)
      c. FW-EXT-MRS (config manuelle 1ere fois)
      d. DC01 (avant tout le reste, c'est le DNS/Kerberos)
      e. Les autres VMs en parallele
3. terraform apply (opnsense)
   -> Configure les regles, NAT, VPN sur les firewalls deja crees
4. ansible-playbook site.yml
   -> Deploie tous les services applicatifs
```

## 7. Generation de l'API token Proxmox

Apres installation de Proxmox, depuis l'UI :

```
Datacenter -> Permissions -> API Tokens -> Add
  User : root@pam
  Token ID : terraform
  Privilege Separation : DECOCHE (le token herite des perms root)
```

Le token genere est de la forme :

```
USER@REALM!TOKENID=UUID
```

A stocker dans `terraform/environments/proxmox/terraform.tfvars` (gitignore !).

---

Fin du PROXMOX_ARCHITECTURE.md
