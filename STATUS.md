# Nova Syndicate - Status & Plan (8 mai 2026)

## SOURCE DE VERITE
**Cet etat reflete l'INFRA REELLE en service.** En cas de discordance avec
PROXMOX_ARCHITECTURE.md ou bootstrap_nova.sh (Phase I obsolete sur GNS3),
ce STATUS.md prevaut.

---

## IPs reelles en service (verifiees 7 mai 2026)

### VMs Linux (10)
- DC01:        192.168.20.10/28 (VLAN 20)
- FS01:        192.168.20.11/28
- DB01:        192.168.20.12/28
- APP01:       192.168.20.13/28 (Wazuh Manager)
- BASTION01:   192.168.15.2/29 (VLAN 15)
- PROXY-LYON:  192.168.20.14/28
- BACKUP01:    192.168.50.2/29 (VLAN 50)
- WEB01:       172.16.1.2/29 (DMZ, role pas applique)
- MAIL01:      172.16.1.3/29 (DMZ, role pas applique)
- PROXY-MRS:   192.168.40.11/26 (LAN MRS)

### OPNsense Firewalls (4) - IPs reelles + acces web UI
- WAN-SIMULATOR (200) :
    WAN  vtnet0 sur vmbr0 -> 192.168.18.47/24 (DHCP box)
    LAN  vtnet1 sur vmbr0 -> 10.0.0.1/29 (TEMPORAIRE, voir dette #3)
    OPT1 vtnet2 sur vmbr5 -> 10.0.2.1/30
    Acces web UI : https://10.0.0.1 (root/opnsense)
    Acces possible car Proxmox a une IP secondaire 10.0.0.5/29 sur vmbr0

- FW-EXT-LYON (201) :
    WAN  vtnet0 sur vmbr0 -> 10.0.0.2/30 (gw 10.0.0.1, default route)
    LAN  vtnet1 sur vmbr3 -> 172.16.1.1/29 (DMZ)
    OPT1 vtnet2 sur vmbr4 -> 10.0.1.1/30 (lien vers FW-INT-LYON)
    Acces web UI : https://172.16.1.1 (root/opnsense)

- FW-INT-LYON (202) :
    WAN  vtnet0 sur vmbr4 -> 10.0.1.2/30 (gw 10.0.1.1, default route)
    LAN  vtnet1 sur vmbr1 -> 192.168.99.1/29 (mgmt temporaire)
    Acces web UI : https://192.168.99.1 (root/opnsense)
    Note : ce /29 192.168.99 a ete CHOISI hier pour eviter conflit avec
    vmbr1.20 (Proxmox sous-interface VLAN 20 = 192.168.20.1/28).
    Plus tard : configurer LAN en VLAN-aware avec sous-interfaces taggees.

- FW-EXT-MRS (203) :
    WAN  vtnet0 sur vmbr5 -> 10.0.2.2/30 (gw 10.0.2.1, default route)
    LAN  vtnet1 sur vmbr2 -> 192.168.40.1/26
    Acces web UI : https://192.168.40.1 (root/opnsense)

### Proxmox host
- vmbr0 mgmt : 192.168.18.50/24 (gw 192.168.18.1)
- IP secondaires temporaires (acces firewalls via Tailscale) :
    172.16.1.5/29 sur vmbr3 (acces FW-EXT-LYON)
    192.168.40.5/26 sur vmbr2 (acces FW-EXT-MRS)
    192.168.99.5/29 sur vmbr1 (acces FW-INT-LYON)
    10.0.0.5/29 sur vmbr0 (acces WAN-SIMULATOR)
- Tailscale : 100.112.113.2 (annonce toutes les routes Nova)

---

## ETAT FONCTIONNEL VALIDE

- 10 VMs Linux deployees + Ansible roles applique
- Wazuh Manager + 6 agents enroles actifs
- Routage Lyon -- WAN-SIM -- MRS valide (ping bidirectionnel OK)
- 4 OPNsense web UI accessibles via Tailscale

---

## DETTE TECHNIQUE A CORRIGER

1. **pfctl -d temporaire** sur WAN-SIM et FW-EXT-MRS
   -> firewall desactive, NAT outbound desactive
   -> a reactiver apres regles propres en place

2. **Route statique manuelle** sur WAN-SIM
   -> route add -net 10.0.1.0/30 10.0.0.2 fait en console (volatile)
   -> a perenniser en Terraform (opnsense_route)

3. **WAN-SIM LAN en /29 au lieu de /30** (asymetrique avec FW-EXT-LYON /30)
   -> change pour permettre acces management Proxmox 10.0.0.5/29
   -> SOLUTION PROPRE : revenir au /30 + ajouter interface MGMT
      dediee sur WAN-SIM (vmbr0 + IP 192.168.18.48/24)

4. **Regles firewall "allow all" temporaires** sur OPT1/WAN
   -> Pass any temporaire pour debloquer routage
   -> a remplacer par regles fines en Terraform

5. **SSH desactive sur les 4 OPNsense**
   -> a activer via web UI (System > Settings > Administration)
   -> requis pour ansibleguy.opnsense + workflow IaC

6. **API keys non generees**
   -> 1 par firewall, requise pour provider browningluke/opnsense
   -> a stocker dans terraform.tfvars (gitignore)

7. **Doc obsolete** : bootstrap_nova.sh = Phase I GNS3 (a re-ecrire Phase VI)
   PROXMOX_ARCHITECTURE.md a updater (192.168.99.1, interface MGMT, etc.)

---

## PLAN PROCHAINE SESSION (Phase II.5 - IaC OPNsense)

### Phase 1 - Preparation (30 min)
1. Activer SSH sur les 4 OPNsense (web UI)
2. Generer API keys via web UI : System > Access > Users > root > API keys
3. Stocker keys dans terraform.tfvars (gitignore)

### Phase 2 - Code Terraform (2-3h)
4. Configurer providers browningluke/opnsense (1 alias par firewall)
5. Coder les ressources :
   - opnsense_firewall_alias (groupes IPs, services)
   - opnsense_firewall_filter (regles WAN/LAN/OPT1)
   - opnsense_firewall_nat (NAT outbound + port forward)
   - opnsense_route (route statique 10.0.1.0/30 sur WAN-SIM)
6. terraform plan + apply

### Phase 3 - Validation (30 min)
7. Reactiver pf : pfctl -e sur WAN-SIM et FW-EXT-MRS
8. Tests connectivite end-to-end
9. Snapshot Proxmox + commit + push

---

## ROADMAP COMPLETE

### Phase III - Suricata (defense in depth)
Decision : pas de Suricata sur WAN-SIM (juste NAT outbound)
- FW-EXT-LYON : Suricata IPS inline (perimeter Lyon)
- FW-INT-LYON : Suricata IDS passif (lateral movement)
- FW-EXT-MRS  : Suricata IPS inline (perimeter MRS)
Implementation : Terraform browningluke/opnsense pour install+activation,
Ansible ansibleguy.opnsense pour tuning + syslog forward vers Wazuh APP01:514

### Phase IV - VPN site-to-site et users
- Tunnel IPSec Lyon <-> MRS (via WAN-SIM)
- WireGuard server sur FW-EXT-LYON pour 20 agents distants
- MFA TOTP pour acces SSH bastion

### Phase V - Bastion zero-trust (refonte)
- Reecrire role bastion (MFA TOTP simple, Teleport supprime)
- Installer ansible+terraform sur bastion01
- rsyslog forward vers Wazuh
- Workflow : Mac --SSH MFA--> BASTION01 --ansible/terraform--> VMs

### Phase VI - Bootstrap script idempotent
Reecrire bootstrap_nova.sh pour deployer TOUT from-scratch en 1 commande :
0. Prereqs (terraform, ansible, jq, virt-customize)
1. SSH key Mac -> Proxmox
2. Bridges Proxmox + sous-interfaces VLAN
3. Repos no-subscription + libguestfs-tools
4. Image template debian12 + virt-customize + qm template
5. API token Proxmox + write terraform.tfvars
6. Mac SSH config ProxyJump + id_ansible link
7. terraform init/plan/apply (VMs Linux + OPNsense)
8. Configuration auto OPNsense (SSH, API keys, regles via Terraform)
9. ansible-playbook site.yml (roles applicatifs)
10. Tests post-deploy + generate deployment report

### Phase VII - Cartographie auto
- Mermaid diagrams generes depuis inventory Ansible
- Optionnel : NetBox pour DCIM/IPAM pro

### Phase VIII - Tests pentest externes
- Depuis WAN-SIMULATOR -> tests sur FW-EXT-LYON / FW-EXT-MRS
- Validation regles + Suricata IPS
- Rapport CVE + remediations

---

## CONVENTIONS PROJET

- Caracteres clavier standard uniquement (pas de tirets cadratins)
- Francais naturel sans tics LLM
- Conventional Commits francais sans accents
- VS Code, GitHub matthieu-rgb
- Vault Ansible AES-256, password [REDACTED-OLD-PASSWORD]
- Step-by-step, "Don't touch what works" pour code legacy

## A documenter dans rapport Phase II final
- MFA TOTP sur bastion (Phase V)
- 3-tier backup avec retention 10 ans (medical sector)
- Regle 3-2-1-1-0 backup
- tls_disable=true = LAB ONLY (a documenter explicitement)
- NIS2 + RGPD compliance
- vault.yml encryption AES256
- forwarded_for off dans Squid (layer 7 protection)
- Suricata 3-tier (IPS Lyon, IDS interne, IPS MRS)

## GitHub
matthieu-rgb/nova-syndicate-proxmox (dernier commit c2e8768)
