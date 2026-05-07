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

Statut : `code pret - a tester une fois Proxmox installe`

- [x] terraform/environments/proxmox/ cree
- [x] Provider bpg/proxmox v0.66.x configure
- [x] Module proxmox-vm reutilisable cree
- [x] Module proxmox-opnsense reutilisable cree
- [x] 10 VMs Linux declarees (vms.tf)
- [x] 4 firewalls OPNsense declares (firewalls.tf)
- [x] 10 fichiers cloud-init user-data crees
- [x] terraform.tfvars.example documente
- [x] terraform fmt passe
- [x] terraform validate passe (modules + environnement)
- [ ] terraform init / plan / apply (necessite Proxmox)
- [ ] Test SSH ansible@192.168.20.10 OK
- [x] Commit : feat(proxmox): squelette Terraform complet (a tester)

NOTE : terraform apply n'a PAS ete lance. Proxmox VE 9.1 etait en cours
de telechargement au moment de cette session.

## Phase 2 -- Toutes les autres VMs Linux

Statut : `code pret dans Phase 1 (module + vms.tf contient deja les 10 VMs)`

Les 10 VMs sont deja declarees dans vms.tf via le module proxmox-vm.
La Phase 2 du plan original (sessions separees) a ete fusionnee dans la
Phase 1 lors de la Session 1 offline.

- [x] Module reutilisable terraform/modules/proxmox-vm/ cree
- [x] WEB01 declaree
- [x] MAIL01 declaree
- [x] BASTION01 declaree
- [x] FS01 declaree
- [x] DB01 declaree
- [x] APP01 declaree
- [x] PROXY-LYON01 declaree
- [x] PROXY-MRS01 declaree
- [x] BACKUP01 declaree
- [ ] Toutes les VMs joignables en SSH ansible@<ip> (necessite Proxmox)
- [ ] Commit : feat(proxmox): module reutilisable + 9 VMs Linux (deja dans Phase 1)

## Phase 3 -- Firewalls OPNsense (VMs)

Statut : `code pret - a tester une fois Proxmox installe`

- [x] Module terraform/modules/proxmox-opnsense/ cree
- [x] WAN-SIMULATOR declaree
- [x] FW-EXT-LYON01 declaree
- [x] FW-INT-LYON01 declaree
- [x] FW-EXT-MRS01 declaree
- [ ] ISO OPNsense telechargee sur l'hote Proxmox (manuel)
- [ ] Configuration manuelle 1er boot pour chaque firewall
- [ ] API REST activee + tokens generes
- [ ] Commit : feat(proxmox): module OPNsense + 4 firewalls (deja dans Phase 1)

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

Statut : `corrections IP faites`

- [x] nova_ip_bastion01 corrige : 192.168.15.10 -> 192.168.15.2
- [x] nova_ip_backup01 corrige : 192.168.50.10 -> 192.168.50.2
- [x] backup_nas_ip corrige : 192.168.50.10 -> 192.168.50.2 (bonus)
- [ ] scripts/test-ansible-connectivity.sh cree
- [ ] ansible all -i inventory/hosts.yml -m ping : tout OK
- [ ] ansible-playbook site.yml --syntax-check : OK
- [x] Commit : fix(inventory): harmonise IPs bastion01 et backup01

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

### Session 1 -- Code offline pendant telechargement Proxmox VE 9.1

**Date** : 2026-05-06
**Auteur** : automation pipeline (Sonnet 4.6) + Matthieu
**Contexte** : Proxmox VE 9.1 en cours de telechargement. Aucun apply.

**Realise** :

1. fix(inventory) : 3 IPs corrigees dans group_vars/all/vars.yml
   - nova_ip_bastion01 : 15.10 -> 15.2
   - nova_ip_backup01  : 50.10 -> 50.2
   - backup_nas_ip     : 50.10 -> 50.2 (coherence)

2. chore : dossier gns3/ supprime (2 fichiers obsoletes)

3. feat(proxmox) : squelette Terraform complet
   - Provider bpg/proxmox v0.66.x (choisi vs telmate : meilleure
     maintenance active, cloud-init natif, mieux documente depuis 2024)
   - Module proxmox-vm : clone du template 9000, cloud-init, agent QEMU
   - Module proxmox-opnsense : ISO CD-ROM, interfaces multiples dynamiques
   - 10 VMs Linux + 4 firewalls declarations completes
   - 10 fichiers cloud-init user-data
   - terraform fmt + terraform validate passes

4. chore : .gitignore etendu pour terraform/environments/proxmox/

**terraform apply non lance** : pas d'instance Proxmox disponible.
Le code est valide syntaxiquement (terraform validate = Success).

**Commits de la session** :
- 07f41cb fix(inventory): harmonise IPs bastion01 (15.2) et backup01 (50.2)
- b66f82e chore: supprime le dossier gns3 obsolete (migration Proxmox)
- e538d53 feat(proxmox): squelette Terraform complet (a tester)
- 7d4f450 chore: gitignore pour Terraform Proxmox

**Questions ouvertes a resoudre en Session 2** :
- IP reelle de l'hote Proxmox (placeholder 192.168.1.10 dans tfvars.example)
- Nom reel du noeud Proxmox (placeholder "pve")
- Nom du datastore Proxmox (placeholder "local-lvm")
- Verification que le boot_order de proxmox-opnsense est correct
  ("ide2" vs "cdrom" selon la version du provider bpg)
- Les fichiers cloud-init user-data dans terraform/environments/proxmox/cloud-init/
  ne sont pas utilises directement par le module proxmox-vm (qui utilise le bloc
  initialization{} inline). Decision : les garder comme reference ou les
  connecter via un snippet Proxmox (requiert config SSH sur l'hote).

**A faire en Session 2 (apres install Proxmox)** :
1. Remplir terraform.tfvars avec les vraies valeurs (IP hote, token API, cle SSH)
2. terraform init (deja fait localement)
3. terraform plan -> verifier les 14 ressources attendues
4. terraform apply -> deployer les VMs
5. Tester SSH ansible@ sur chaque IP
6. Adapter terraform/environments/lyon/ aux nouvelles IPs OPNsense

---

### Session 2 -- Phase A : Deploiement 10 VMs Linux Proxmox

**Date** : 2026-05-07
**Auteur** : automation pipeline (Sonnet 4.6) autonome

**Realise** :

1. A0 : verification connectivite (ProxyJump root@192.168.18.50 OK, dc01 pong)
2. A1 : destroy dc01 test (VMID 103) - detruit proprement
3. A2 : terraform plan -target x10 -> "10 to add, 0 to change, 0 to destroy"
4. A3 : terraform apply 10 VMs Linux (web01, mail01, bastion01, dc01, fs01,
         db01, app01, proxy_lyon01, proxy_mrs01, backup01) -> "10 added"
5. A5 : verification qm list -> 10 VMs running (VMIDs 100-109)
6. A6 : ansible ping
         - SUCCESS (7) : dc01, bastion01, db01, fs01, app01, proxy-lyon01, backup01
         - UNREACHABLE (3) : web01, mail01, proxy_mrs01 (DMZ/LAN-MRS sans FW = attendu)

**VMs deployees** :
| VMID | Nom          | IP                | Status Ansible        |
|------|--------------|-------------------|-----------------------|
| 100  | web01        | 172.16.1.2/29     | UNREACHABLE (DMZ)     |
| 101  | mail01       | 172.16.1.3/29     | UNREACHABLE (DMZ)     |
| 102  | bastion01    | 192.168.15.2/29   | SUCCESS               |
| 103  | dc01         | 192.168.20.10/28  | SUCCESS               |
| 104  | fs01         | 192.168.20.11/28  | SUCCESS               |
| 105  | db01         | 192.168.20.12/28  | SUCCESS               |
| 106  | app01        | 192.168.20.13/28  | SUCCESS               |
| 107  | proxy-lyon01 | 192.168.20.14/28  | SUCCESS               |
| 108  | proxy-mrs01  | 192.168.40.11/26  | UNREACHABLE (LAN-MRS) |
| 109  | backup01     | 192.168.50.2/29   | SUCCESS               |

---
