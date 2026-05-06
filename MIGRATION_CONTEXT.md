# MIGRATION_CONTEXT.md

## Pour automation pipeline -- a lire au demarrage de chaque session

Ce fichier est la source de verite du contexte de migration. Le lire en debut
de session permet de cadrer l'objectif et les contraintes sans tatonner.

---

## 1. Contexte du projet

Nova Syndicate est une infrastructure simulee d'entreprise logistique
(85 collaborateurs, secteurs medical/aerospatial/defense). Le projet vise
la conformite NIS2 + RGPD.

L'infrastructure originale a ete deployee dans GNS3 (lab pedagogique).
Le code Ansible et Terraform OPNsense est fonctionnel et versionne dans
ce repo (https://github.com/matthieu-rgb/nova-syndicate-proxmox).

**Migration en cours : GNS3 -> Proxmox VE bare-metal**

## 2. Objectif

Reproduire l'infrastructure complete sur Proxmox VE 9.x installe
en bare-metal sur un disque NVMe dedie, avec :

- Provisionnement automatique des 13-15 VMs via Terraform (provider
  telmate/proxmox-bpg ou bpg/proxmox)
- Configuration des firewalls OPNsense via le provider Terraform existant
  (browningluke/opnsense)
- Configuration des services applicatifs via Ansible (code existant, 10 roles)
- Aucune configuration manuelle hors install initiale Proxmox

## 3. Architecture cible (synthese)

### Bridges reseau Proxmox a creer manuellement

```
vmbr0  WAN Lyon              Uplink physique vers FAI Lyon (eth0)
vmbr1  LAN Lyon (VLAN-aware) Trunk 802.1q tags 15, 20, 30, 50
vmbr2  LAN Marseille         Bridge sans tag pour LAN MRS
vmbr3  DMZ                   Bridge sans tag pour WEB01 + MAIL01
vmbr4  Lien FW-EXT <-> FW-INT Bridge sans tag (point-to-point /30)
vmbr5  WAN Marseille (option C) WAN simule pour FW-EXT-MRS
```

### VMs a deployer (Terraform Proxmox)

| Nom            | VLAN/Net  | IP                | RAM   | CPU | Disque |
|----------------|-----------|-------------------|-------|-----|--------|
| FW-EXT-LYON01  | vmbr0/3/4 | 10.0.0.2/30       | 1 GB  | 2   | 16 GB  |
| FW-INT-LYON01  | vmbr1/4   | 10.0.1.2/30       | 1 GB  | 2   | 16 GB  |
| FW-EXT-MRS01   | vmbr5/2   | 10.0.2.2/30       | 1 GB  | 2   | 16 GB  |
| WAN-SIMULATOR  | vmbr0     | DHCP / NAT        | 512MB | 1   | 8 GB   |
| WEB01          | vmbr3     | 172.16.1.2/29     | 1 GB  | 1   | 16 GB  |
| MAIL01         | vmbr3     | 172.16.1.3/29     | 1 GB  | 1   | 16 GB  |
| BASTION01      | vmbr1/15  | 192.168.15.2/29   | 1 GB  | 1   | 16 GB  |
| DC01           | vmbr1/20  | 192.168.20.10/28  | 2 GB  | 2   | 32 GB  |
| FS01           | vmbr1/20  | 192.168.20.11/28  | 2 GB  | 2   | 64 GB  |
| DB01           | vmbr1/20  | 192.168.20.12/28  | 2 GB  | 2   | 32 GB  |
| APP01          | vmbr1/20  | 192.168.20.13/28  | 4 GB  | 4   | 32 GB  |
| PROXY-LYON01   | vmbr1/20  | 192.168.20.14/28  | 1 GB  | 1   | 16 GB  |
| PROXY-MRS01    | vmbr2     | 192.168.40.11/26  | 1 GB  | 1   | 16 GB  |
| BACKUP01       | vmbr1/50  | 192.168.50.2/29   | 2 GB  | 1   | 200 GB |

Total : 14 VMs principales, ~22 GB RAM, ~520 GB disque

### Plan d'adressage (rappel)

```
WAN Lyon         10.0.0.0/30
WAN Marseille    10.0.2.0/30
Lien FW-FW       10.0.1.0/30
DMZ              172.16.1.0/29
VLAN 15 Bastion  192.168.15.0/29
VLAN 20 Servers  192.168.20.0/28
VLAN 30 Users    192.168.30.0/26
VLAN 40 Users MRS 192.168.40.0/26
VLAN 50 Backup   192.168.50.0/29
WireGuard        10.20.0.0/24 (20 peers)
```

## 4. Choix d'architecture (option C)

L'utilisateur a choisi l'option avec WAN simulator. Concretement :

```
PC bare-metal Proxmox (eth0 -> ta box)
              |
              v
         vmbr0 (uplink physique)
              |
              v
    +---------------------------+
    | WAN-SIMULATOR (OPNsense)  |
    | em0 : DHCP de la box      |
    | em1 : 10.0.0.0/30 (FAI Lyon simule)
    | em2 : 10.0.2.0/30 (FAI MRS simule)
    | NAT vers em0              |
    +---------------------------+
              |
       +------+------+
       |             |
   FW-EXT-LYON   FW-EXT-MRS
```

Pas de routeurs Cisco c2691 (les RTR-LYON01 et RTR-MRS01 du PDF
disparaissent : Proxmox bridge directement les firewalls au WAN simule).

## 5. Ce qui change vs ne change PAS

### NE CHANGE PAS (a preserver tel quel)

- Les 10 roles Ansible (common, hardening, dc, fileserver, database,
  bastion, vpn, proxy, wazuh_manager, wazuh_agent)
- Le code Terraform OPNsense dans terraform/environments/lyon/
- L'inventaire Ansible (sauf corrections d'incoherence ci-dessous)
- Les variables globales group_vars/all/vars.yml (sauf corrections)
- Le vault.yml chiffre AES-256
- Le plan d'adressage IP

### CHANGE (a creer ou adapter)

- Nouveau dossier terraform/environments/proxmox/ pour declarer les VMs
- Templates cloud-init pour les VMs Debian 12
- API token Proxmox (a generer une fois Proxmox installe)
- Documentation README.md (mention de la migration)
- Suppression du dossier gns3/ (plus pertinent)

## 6. Incoherences detectees a corriger

```
group_vars/all/vars.yml :
  nova_ip_bastion01: "192.168.15.10"   <- INCORRECT
  Doit etre : "192.168.15.2"

  nova_ip_backup01: "192.168.50.10"    <- INCORRECT
  Doit etre : "192.168.50.2"

PDF + inventory/hosts.yml sont la verite : 15.2 et 50.2
```

## 7. Roles Ansible manquants

Ces VMs sont declarees dans inventory/hosts.yml mais n'ont PAS de role
Ansible dedie. A creer en Phase II de la migration :

- web01 (Nginx en DMZ)        -> creer roles/web/
- mail01 (Postfix + Dovecot)  -> creer roles/mail/
- backup01 (BorgBackup)       -> creer roles/backup/

## 8. Conventions de travail

### Commits

Format Conventional Commits :

```
feat(proxmox): description    nouveau code Terraform Proxmox
feat(role-X): description     nouveau role Ansible
fix(scope): description       correction
docs: description             documentation
chore: description            menage / refactoring
```

Messages en francais, sans accents (caracteres clavier standard).

### Validation

Avant chaque commit :

```bash
ansible-playbook site.yml --syntax-check
terraform fmt
terraform validate
```

### Branches

Travail direct sur main pour les sessions automation pipeline (le user fait ses
backups et commits frequents). Pas de feature branch.

## 9. Stack technique

- Hyperviseur : Proxmox VE 9.x (bare-metal)
- OS guest : Debian 12 Bookworm cloud-init
- Provider Terraform Proxmox : telmate/proxmox v3.x ou bpg/proxmox
  (a evaluer en debut de session 2)
- Provider Terraform OPNsense : browningluke/opnsense ~> 0.16.0 (existant)
- Ansible : 8.x (existant)
- Vault : ansible-vault AES-256 (existant)
- API Proxmox : token-based (a creer manuellement post-install)

## 10. Restrictions strictes

L'agent automation pipeline doit :

- TOUJOURS lire ce fichier en debut de session
- TOUJOURS lire STATUS.md en debut de session pour reprendre l'avancement
- METTRE A JOUR STATUS.md a la fin de chaque session avec ce qui a ete fait
- JAMAIS modifier les roles Ansible existants sans demande explicite
- JAMAIS modifier inventory/group_vars sans signaler le changement
- TOUJOURS preferer les diffs minimaux (str_replace) plutot que les
  reecritures completes
- COMMITS frequents et cibles (pas de gros commit fourre-tout)
- Demander confirmation avant de detruire des fichiers existants

## 11. Reference

PDF de l'architecture : `docs/nova_syndicate_topo_complete_v4.pdf`
(a copier dans le repo)

Rapport en cours : `Nova_Syndicate_RAPPORT_COMPLET_v11.odt`
(reference pour le contexte mais hors repo)

---

Fin du MIGRATION_CONTEXT.md
