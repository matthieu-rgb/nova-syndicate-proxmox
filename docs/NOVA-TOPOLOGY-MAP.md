# Nova Syndicate — Topologie réseau complète

Document de référence pour s'orienter dans l'infrastructure.

Dernière mise à jour : 2026-05-11 (post GATE 3)

---

## Vue d'ensemble haute altitude

```
                            INTERNET
                               │
                               │ IP publique : 185.55.247.170
                               │ DNS : nova-vpn.0xmatthieu.dev
                               │       nova-auth.0xmatthieu.dev
                               │       nova.0xmatthieu.dev
                               │
                    ┌──────────▼──────────┐
                    │  Box Huawei         │
                    │  EG8147X6-10        │
                    │  192.168.18.1       │
                    │                     │
                    │  Port-forward       │
                    │  UDP 51820 →        │
                    │  Proxmox            │
                    └──────────┬──────────┘
                               │
                               │
                    ┌──────────▼──────────────────────────┐
                    │  PROXMOX (hyperviseur)              │
                    │  192.168.18.50  (vmbr0 admin)       │
                    │  10.0.0.5       (vmbr0 WAN-sim)     │
                    │  100.112.113.2  (tailscale0)        │
                    │                                     │
                    │  iptables NAT DNAT :                │
                    │    UDP 51820 → 172.16.1.4:51820     │
                    │  MASQUERADE pour VLANs internes     │
                    └─────┬───────┬───────┬───────────────┘
                          │       │       │
                  ┌───────┘       │       └────────┐
                  │               │                │
                  ▼               ▼                ▼
              [WAN-SIM]      [VLANs LAN]      [DMZ vmbr3]
              vmbr0          vmbr1.*          172.16.1.0/29
              10.0.0.0/29    192.168.x.x      VMs DMZ
```

---

## Architecture firewalls + VLANs

```
                  PROXMOX (ip_forward=1, NAT MASQUERADE)
                       │
       ┌───────────────┼───────────────┬──────────────┐
       │               │               │              │
       ▼               ▼               ▼              ▼
   vmbr0 WAN       vmbr1 trunk       vmbr2          vmbr3
   10.0.0.0/29     (VLANs)           192.168.40.0/26 172.16.1.0/29
   (sim Internet)                    LAN MARSEILLE   DMZ Lyon
       │
       │     ┌─────────────────────┐
       │     │ FW-EXT-LYON         │
       └────►│ 10.0.0.2 (WAN)      │
             │ 172.16.1.1 (DMZ)    │
             │ 10.0.1.1 (LAN int)  │
             │ VMID 201            │
             └──────────┬──────────┘
                        │
                        │ 10.0.1.0/30 (LAN externe)
                        │
                  ┌─────▼────────────┐
                  │ FW-INT-LYON      │
                  │ 10.0.1.2 (WAN)   │
                  │ VMID 202         │
                  │                  │
                  │ Multiple VLANs   │
                  │ vers VMs métier  │
                  └───────────┬──────┘
                              │
        ┌──────────┬──────────┼──────────┬──────────┐
        │          │          │          │          │
   VLAN 15    VLAN 20    VLAN 30    VLAN 40    VLAN 50
   BASTION   SERVERS    USERS      LAN MRS    BACKUP
   /29        /28        /26        /26        /29
```

---

## Plan d'adressage détaillé

### VLAN 15 — BASTION (192.168.15.0/29)

```
Réseau    : 192.168.15.0/29  (8 IPs)
Gateway   : 192.168.15.1  (FW-INT-LYON)
Proxmox   : 192.168.15.6  (vmbr1.15, secondary 192.168.15.1)

Hosts :
  192.168.15.2  bastion01    VMID 102   SSH jumpbox + futur MFA TOTP
```

### VLAN 18 — ADMIN (192.168.18.0/24)

```
Réseau    : 192.168.18.0/24
Gateway   : 192.168.18.1  (Box Huawei)
Proxmox   : 192.168.18.50

Hosts :
  192.168.18.1   Box Huawei (admin GUI)
  192.168.18.40  Mac Matthieu (DHCP)
  192.168.18.50  Proxmox host (Web GUI 8006)
  (autres devices DHCP : Mac, iPhone, etc.)
```

### VLAN 20 — SERVERS (192.168.20.0/28)

```
Réseau    : 192.168.20.0/28  (16 IPs)
Gateway   : 192.168.20.1  (FW-INT-LYON)
Proxmox   : 192.168.20.5  (vmbr1.20, secondary 192.168.20.1)

Hosts :
  192.168.20.10  dc01           VMID 103   Samba AD nova-syndicate.local
  192.168.20.11  fs01           VMID 104   Samba file server (shares)
  192.168.20.12  db01           VMID 105   MariaDB (nova_logistique, nova_rh)
  192.168.20.13  app01          VMID 106   Wazuh manager + Prometheus + Grafana
                                            (futur Authelia + LDAP)
  192.168.20.14  proxy-lyon01   VMID 107   Squid proxy
```

### VLAN 30 — USERS (192.168.30.0/26)

```
Réseau    : 192.168.30.0/26  (64 IPs)
Gateway   : 192.168.30.1  (FW-INT-LYON)
Proxmox   : 192.168.30.62  (vmbr1.30)

Hosts :
  (futurs postes utilisateurs)
```

### VLAN 40 — LAN MARSEILLE (192.168.40.0/26)

```
Réseau    : 192.168.40.0/26  (64 IPs)
Gateway   : 192.168.40.1  (FW-EXT-MRS)
Proxmox   : 192.168.40.5  (vmbr2)

Hosts :
  192.168.40.11  proxy-mrs01    VMID 108   Squid proxy MRS
  (futurs postes utilisateurs MRS)
```

### VLAN 50 — BACKUP (192.168.50.0/29)

```
Réseau    : 192.168.50.0/29  (8 IPs)
Gateway   : 192.168.50.1  (FW-INT-LYON)
Proxmox   : 192.168.50.6  (vmbr1.50, secondary 192.168.50.1)

Hosts :
  192.168.50.2  backup01    VMID 109   Borg local + cloud sync via WG
```

### DMZ — vmbr3 (172.16.1.0/29)

```
Réseau    : 172.16.1.0/29  (8 IPs)
Gateway   : 172.16.1.1  (FW-EXT-LYON)
Proxmox   : 172.16.1.5  (vmbr3)

Hosts :
  172.16.1.2  web01      VMID 100   Web server (futur Cloudflare Tunnel)
  172.16.1.3  mail01     VMID 101   Mail server (futur Postfix prod)
  172.16.1.4  vpn-gw01   VMID 110   WireGuard concentrator road-warriors
                                     dnsmasq DNS forwarder
```

### WAN simulé — vmbr0 (10.0.0.0/29)

```
Réseau    : 10.0.0.0/29  (8 IPs, transit Lyon ↔ Internet simulé)
Hosts :
  10.0.0.1  wan-simulator    VMID 200   Simulateur WAN
  10.0.0.2  fw-ext-lyon01    VMID 201   Patte WAN du firewall externe Lyon
  10.0.0.5  proxmox          (vmbr0)
```

### LAN interne Lyon — entre FW-EXT et FW-INT (10.0.1.0/30)

```
Réseau    : 10.0.1.0/30  (4 IPs, point-à-point)
Hosts :
  10.0.1.1  fw-ext-lyon01    Patte LAN du FW-EXT (vers FW-INT)
  10.0.1.2  fw-int-lyon01    Patte WAN du FW-INT (vers FW-EXT)
```

---

## Tunnels VPN actifs

### IPsec Site-to-Site Lyon ↔ Marseille

```
FW-EXT-LYON (10.0.0.2)  <===  4 SAs INSTALLED  ===>  FW-EXT-MRS (10.1.0.2)
                              IKEv2 + strongSwan
                              Protected subnets :
                                - 192.168.15.0/29
                                - 192.168.20.0/28
                                - 192.168.40.0/26
                                - 192.168.50.0/29
```

### WireGuard #2 (concentrateur backup-only)

```
VPS Hetzner Helsinki (46.62.138.33)
  ├── eth0 : IP publique
  ├── tailscale0 : 100.94.199.97
  └── wg0 : 10.30.0.1/24 (server)
                ListenPort UDP 51820
                Peer = backup01

                 ▲
                 │ Internet
                 │
                 ▼

BACKUP01 (192.168.50.2)
  └── wg0 : 10.30.0.2/24 (peer)
                Endpoint : 46.62.138.33:51820
                PersistentKeepalive 25s
                Auth borguser SSH → /srv/borg-repo/nova-syndicate/
```

### WireGuard #1 (concentrateur road-warriors) — EN COURS

```
Internet
    │
    │ UDP 51820 vers nova-vpn.0xmatthieu.dev (185.55.247.170)
    ▼
Box Huawei (192.168.18.1)
    │ Port-forward UDP 51820
    ▼
Proxmox (192.168.18.50)
    │ iptables PREROUTING DNAT
    │ UDP 51820 → 172.16.1.4:51820
    ▼
vpn-gw01 (172.16.1.4) en DMZ
  ├── eth0 : 172.16.1.4/29
  └── wg0 : 10.20.0.1/24 (server)
                ListenPort UDP 51820
                Pubkey : zT9LykWNnobMSYxHV5dSavQpzyLMJ3GUBExCacniszI=
                Subnet road-warriors : 10.20.0.0/24
                DNS forwarder dnsmasq : 10.20.0.1:53 → DC01 (192.168.20.10)

    │
    │ (en cours GATE 4 : ACLs FW-INT-LYON)
    ▼
FW-INT-LYON
    │ Routes statiques + ACLs Terraform
    ▼
Accès ROAD-WARRIORS autorisés :
  ✅ 192.168.20.11 (fs01)    SMB 445, 139, SSH 22
  ✅ 192.168.20.12 (db01)    MariaDB 3306, SSH 22
  ✅ 172.16.1.2 (web01)      HTTP 80, HTTPS 443
  ✅ 172.16.1.3 (mail01)     SMTP/IMAP 25/143/465/587/993
  ✅ 192.168.20.10 (DC01)    DNS 53 ONLY (forwarder)
  ❌ Tout le reste BLOQUÉ (admin, bastion, backup, app01)
```

---

## Tailscale (admin perso, hors prod)

```
Tailnet : tail98861d.ts.net

Devices :
  100.94.199.97   ubuntu-8gb-hel1-1  VPS Hetzner (services perso n8n, Costwave)
  100.67.171.31   macbook-pro        Mac Matthieu
  100.112.113.2   proxmox            Proxmox host
  100.77.25.42    raspberrypi        Pi (portfolio cloudflared)
  100.88.121.92   iphone-matthieu    (offline)
  100.120.25.69   pc-windows         (offline)

Usage : accès admin SSH personnel uniquement, hors prod Nova Syndicate
Tailscale SSH : DESACTIVE sur le VPS Hetzner (T-TAILSCALE-SSH-HARDEN)
```

---

## Cheat sheet SSH

### Hosts directs (depuis Mac via wildcard ProxyJump Proxmox)

```bash
ssh debian@192.168.15.2     # bastion01
ssh debian@192.168.20.10    # dc01
ssh debian@192.168.20.11    # fs01
ssh debian@192.168.20.12    # db01
ssh debian@192.168.20.13    # app01
ssh debian@192.168.20.14    # proxy-lyon01
ssh debian@192.168.40.11    # proxy-mrs01
ssh debian@172.16.1.2       # web01
ssh debian@172.16.1.3       # mail01
ssh debian@172.16.1.4       # vpn-gw01   ← NOUVEAU
```

### Hosts derrière BASTION (jumpbox obligatoire)

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2   # backup01
ssh -J debian@192.168.15.2 debian@172.16.1.4     # vpn-gw01 (si direct ne marche pas)
```

### OPNsense firewalls (aliases SSH)

```bash
ssh opn-fw-ext-lyon
ssh opn-fw-ext-mrs
ssh opn-fw-int-lyon
ssh opn-wansim
```

### Proxmox host

```bash
ssh root@192.168.18.50
```

### VPS Hetzner (via Tailscale)

```bash
ssh matthieu@100.94.199.97
# Puis sudo -i pour root
```

---

## Invariants à vérifier régulièrement

```bash
# IPsec (doit = 4 chaque)
ssh opn-fw-ext-lyon "swanctl --list-sas | grep -c INSTALLED"
ssh opn-fw-ext-mrs  "swanctl --list-sas | grep -c INSTALLED"

# Wazuh agents (doit = 7)
ssh debian@192.168.20.13 "sudo /var/ossec/bin/agent_control -l 2>&1 | grep -c Active"

# Prometheus targets (doit = 7)
ssh debian@192.168.20.13 "curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len([r for r in d[\"data\"][\"result\"] if r[\"value\"][1]==\"1\"]))'"

# WireGuard backup (handshake < 3 min)
ssh debian@192.168.15.2 "ssh debian@192.168.50.2 'sudo wg show wg0 | grep handshake'"

# WireGuard road-warriors (handshake si peer connecté)
ssh -J debian@192.168.15.2 debian@172.16.1.4 'sudo wg show wg0'

# Ansible all hosts (doit = 11 SUCCESS, 0 UNREACHABLE après vpn-gw01)
cd ~/Documents/Nova-syndicate-Code/nova-syndicate-ansible
ansible all -i inventory/hosts.yml -m ping

# Terraform OPNsense (doit = "No changes")
cd ~/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/terraform/environments/opnsense
terraform plan
```

---

## DNS Cloudflare actifs pour Nova Syndicate

```
nova-vpn.0xmatthieu.dev    A   185.55.247.170    (DNS only, gris)
nova-auth.0xmatthieu.dev   A   185.55.247.170    (DNS only, gris)
nova.0xmatthieu.dev        A   185.55.247.170    (DNS only, gris)
```

Pourquoi DNS only (pas proxy Cloudflare) :
- WireGuard est UDP, Cloudflare proxy ne supporte que TCP/HTTPS
- Pour la connexion WG, le client doit atteindre l'IP réelle (pas Cloudflare edge)

Plus tard pour Authelia :
- nova-auth.0xmatthieu.dev pourra basculer en proxy Cloudflare (orange)
- Bénéfice WAF + DDoS protection
- Via Cloudflare Tunnel (cloudflared sortant)

---

## Etat des hôtes (au 2026-05-11)

```
Host          VMID  IP            Statut    Services principaux
─────────────────────────────────────────────────────────────────
proxmox       host  192.168.18.50 Running   Hyperviseur + iptables NAT
wan-simulator 200   10.0.0.1      Running   Sim WAN Internet
fw-ext-lyon01 201   10.0.0.2      Running   OPNsense, IPsec à MRS
fw-int-lyon01 202   10.0.1.2      Running   OPNsense, segmentation interne
fw-ext-mrs01  203   10.1.0.2      Running   OPNsense, IPsec à Lyon
bastion01     102   192.168.15.2  Running   SSH jumpbox
dc01          103   192.168.20.10 Running   Samba AD (50 groupes, 85 users)
fs01          104   192.168.20.11 Running   Samba file server
db01          105   192.168.20.12 Running   MariaDB
app01         106   192.168.20.13 Running   Wazuh + Prometheus + Grafana
proxy-lyon01  107   192.168.20.14 Running   Squid Lyon
proxy-mrs01   108   192.168.40.11 Running   Squid MRS
backup01      109   192.168.50.2  Running   Borg local + cloud WG
web01         100   172.16.1.2    Running   Web server DMZ
mail01        101   172.16.1.3    Running   Mail server DMZ
vpn-gw01      110   172.16.1.4    Running   WireGuard road-warriors  ← NOUVEAU
```

Total VMs : 14 (production) + 1 template (9000)
Ressources allouées : ~22 GB RAM, ~520 GB disque

---

## A FAIRE — Phase 3 en cours

```
GATE 4 → Terraform OPNsense : route 10.20.0.0/24 + ACLs road-warriors
GATE 5 → Premier peer Mac + test depuis 4G

Phase 3 après :
- T-MFA-BASTION (libpam-google-authenticator)
- T-AUTHELIA-DEPLOY + LDAP vers DC01
- T-AUTHELIA-PORTAL-WG (download config WG après MFA)
- T-POSTES-LYON (VM XFCE jointe à AD)
```

---

Référence à conserver. Mettre à jour à chaque étape majeure.
