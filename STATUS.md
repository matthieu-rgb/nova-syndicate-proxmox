# Reprise Nova Syndicate Phase II - 8 mai 2026

## Etat actuel (apres session 7 mai)
- 10 VMs Linux deployees + Ansible roles applique (DC, FS, DB, App, Bastion, Proxy, Backup)
- Wazuh Manager + 6 agents actifs
- Tailscale OK (proxmox = 100.112.113.2)
- 4 OPNsense installes via Terraform :
  - WAN-SIMULATOR (200)  https://10.0.0.1      root/opnsense
  - FW-EXT-LYON  (201)   https://172.16.1.1    root/opnsense
  - FW-INT-LYON  (202)   https://192.168.99.1  root/opnsense
  - FW-EXT-MRS   (203)   https://192.168.40.1  root/opnsense
- Routage Lyon -> WAN-SIM -> MRS valide (ping bidirectionnel OK)

## Dette technique a corriger
- pfctl -d temporaire sur WAN-SIM et FW-EXT-MRS (firewall desactive)
- Route statique 10.0.1.0/30 via 10.0.0.2 manuelle sur WAN-SIM (a perenniser)
- Acces web UI WAN-SIM via subnet elargi /29 (asymetrique avec FW-EXT-LYON /30)
- Pas de regles firewall propres (juste "allow all" temporaires)

## Plan session
1. Activer SSH sur les 4 OPNsense (web UI)
2. Generer API keys (1 par firewall)
3. Configurer le provider Terraform browningluke/opnsense
4. Coder les regles firewall en Terraform (filter, NAT, alias, route)
5. terraform apply -> reactiver pf -> valider connectivite

## GitHub
matthieu-rgb/nova-syndicate-proxmox (a jour, dernier commit c2e8768)
