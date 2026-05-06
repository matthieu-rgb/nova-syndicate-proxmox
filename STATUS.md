# STATUS.md

## Etat d'avancement de la migration GNS3 -> Proxmox

Ce fichier est mis a jour a la fin de chaque session automation pipeline.
Il sert de point de reprise pour les sessions suivantes.

---

## Phase 0 -- Preparation manuelle (utilisateur)

- [ ] Proxmox VE 9.x installe en bare-metal sur NVMe dedie
- [ ] Acces UI Proxmox via https://IP-PROXMOX:8006 fonctionnel
- [ ] /etc/network/interfaces configure avec vmbr0 a vmbr5
- [ ] Template Debian 12 cloud-init cree (VMID 9000)
- [ ] API token Proxmox genere et sauvegarde
- [ ] Cle SSH ed25519 disponible (~/.ssh/nova_ansible_ed25519)

## Phase 1 -- Squelette Terraform Proxmox

Statut : `pas commence`

- [ ] terraform/environments/proxmox/ cree
- [ ] Provider bpg/proxmox configure
- [ ] DC01 deploye en VM de test
- [ ] terraform.tfvars.example documente
- [ ] README.md du dossier proxmox cree
- [ ] Test SSH ansible@192.168.20.10 OK
- [ ] Commit : feat(proxmox): squelette Terraform + VM DC01 de test

## Phase 2 -- Toutes les VMs Linux

Statut : `pas commence`

- [ ] Module reutilisable terraform/modules/proxmox-vm/ cree
- [ ] WEB01 deployee
- [ ] MAIL01 deployee
- [ ] BASTION01 deployee
- [ ] FS01 deployee
- [ ] DB01 deployee
- [ ] APP01 deployee
- [ ] PROXY-LYON01 deployee
- [ ] PROXY-MRS01 deployee
- [ ] BACKUP01 deployee
- [ ] Toutes les VMs joignables en SSH ansible@<ip>
- [ ] Commit : feat(proxmox): module reutilisable + 9 VMs Linux

## Phase 3 -- Firewalls OPNsense (VMs)

Statut : `pas commence`

- [ ] ISO OPNsense telechargee sur l'hote Proxmox
- [ ] Module terraform/modules/proxmox-opnsense/ cree
- [ ] WAN-SIMULATOR deployee + configuration manuelle 1er boot
- [ ] FW-EXT-LYON01 deployee + configuration manuelle 1er boot
- [ ] FW-INT-LYON01 deployee + configuration manuelle 1er boot
- [ ] FW-EXT-MRS01 deployee + configuration manuelle 1er boot
- [ ] API REST activee + tokens generes pour chaque firewall
- [ ] Commit : feat(proxmox): module OPNsense + 4 firewalls

## Phase 4 -- Configuration des firewalls (Terraform OPNsense existant)

Statut : `pas commence`

- [ ] terraform/environments/lyon/ adapte aux nouvelles IPs management
- [ ] terraform plan : aucune erreur
- [ ] terraform apply : regles, NAT, VPN configures
- [ ] Tunnel IPsec Lyon-Marseille up
- [ ] WireGuard server up (port 51820 ouvert)
- [ ] Test ping de DC01 vers PROXY-MRS01 (via IPsec)
- [ ] Commit : fix(opnsense-tf): adapte les IPs management pour Proxmox

## Phase 5 -- Corrections inventory + Ansible

Statut : `pas commence`

- [ ] nova_ip_bastion01 corrige : 192.168.15.10 -> 192.168.15.2
- [ ] nova_ip_backup01 corrige : 192.168.50.10 -> 192.168.50.2
- [ ] scripts/test-ansible-connectivity.sh cree
- [ ] ansible all -i inventory/hosts.yml -m ping : tout OK
- [ ] ansible-playbook site.yml --syntax-check : OK
- [ ] Commit : fix(inventory): harmonise IPs bastion01 et backup01

## Phase 6 -- Deploiement Ansible

Statut : `pas commence` (a faire manuellement par l'utilisateur)

- [ ] Etape 1 : common -> OK
- [ ] Etape 2 : hardening -> OK
- [ ] Etape 3 : dc -> OK (Samba AD provisionne)
- [ ] Etape 4 : fileserver -> OK (FS01 jointe au domaine)
- [ ] Etape 5 : database -> OK
- [ ] Etape 6 : bastion -> OK (MFA TOTP fonctionnel)
- [ ] Etape 7 : vpn -> OK
- [ ] Etape 8 : proxy -> OK
- [ ] Etape 9 : wazuh_manager -> OK (10 regles NIS2 deployees)
- [ ] Etape 10 : wazuh_agent -> OK (8 agents connectes)

## Phase 7 -- Documentation et finalisation

Statut : `pas commence`

- [ ] README.md global mis a jour (mention Proxmox au lieu de GNS3)
- [ ] Procedure complete de deploiement documentee
- [ ] Captures d'ecran rafraichies pour le rapport
- [ ] Schemas draw.io adaptes (icones Proxmox au lieu de GNS3)
- [ ] Section "Migration GNS3 -> Proxmox" ajoutee au rapport ODT
- [ ] Push final sur GitHub avec tag v2.0-proxmox

## Phase 8 (optionnelle) -- Roles Ansible manquants

Statut : `pas commence`

- [ ] role/web/ cree (Nginx sur WEB01)
- [ ] role/mail/ cree (Postfix + Dovecot sur MAIL01)
- [ ] role/backup/ cree (BorgBackup + rclone B2 sur BACKUP01)
- [ ] site.yml etendu avec ETAPE 11/12/13

---

## Journal des sessions

### Session 0 -- Preparation des fichiers de brief

**Date** : 2026-05-06
**Auteur** : automation (chat web) + Matthieu

**Realise** :
- Creation de MIGRATION_CONTEXT.md (brief principal)
- Creation de PROXMOX_ARCHITECTURE.md (specs techniques)
- Creation de AUTOMATION_PIPELINE_PROMPTS.md (sequence de prompts)
- Creation de STATUS.md (ce fichier)
- Repo nova-syndicate-proxmox cree sur GitHub depuis fork de
  nova-syndicate-ansible

**Prochaine session** : Session 1 (Squelette Terraform + DC01 de test)
A demarrer une fois Proxmox installe sur le NVMe.

---

(Les sessions suivantes seront documentees ici par automation pipeline
en fin de session)
