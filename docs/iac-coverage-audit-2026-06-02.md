# Audit de couverture IaC -- Nova Syndicate (2026-06-02)

**Auteur** : audit AFK READ-ONLY
**Scope** : ecart entre l'infra runtime (Proxmox + 17 VMs + 4 OPNsense) et le code
reproductible (Terraform + Ansible).
**Lecture seule strict** : aucun apply, aucun snapshot, aucun commit, aucune
modification d'infra. Sources : `qm list/config`, SSH read-only, `terraform state
list`, lecture des repos.
**Question centrale** : a quel point un "rebuild une commande" est-il atteignable ?

---

## TL;DR -- ce que l'audit revele

- Couverture IaC reelle : **~75 %** en volume de composants, mais **~30 %**
  en sequencabilite (rebuild from-scratch enchainable).
- 4 composants critiques restent **manuels par design** ou par dette (template
  Debian 9000, bridges Proxmox, ISO + bootstrap OPNsense, step-ca root key).
  Ces 4 cassent la chaine.
- 3 VMs sur 17 sont creees **hors Terraform** (vpn-gw01, awx01, pki01), avec OS
  config en Ansible mais provisionnement non-IaC.
- 4 stacks applicatives sur app01 (Authelia, Grafana, Vault, AWX K3s) n'ont
  **aucun role Ansible** -- elles sont documentees par ADR + runbook mais pas
  scripted.
- Posture **realiste** : rebuild un site complet = **2-3 jours en mode supervise**
  aujourd'hui ; cible atteignable du "rebuild one-command" en **~4 chantiers de
  taille M** sans toucher au scope NIS2/certification.

---

## 1. Methode

1. `ssh proxmox-hypervisor 'qm list'` puis `qm config <vmid>` sur les 18 entrees
   pour cartographier ressources + reseau + cloud-init + tags.
2. `cat /etc/network/interfaces` Proxmox + `cat /etc/pve/storage.cfg` pour le
   substrat host (bridges, VLAN sub-interfaces, storage backend).
3. `terraform state list` sur les 2 environnements Terraform actifs
   (`environments/proxmox` + `environments/opnsense`).
4. Inventaire des roles + playbooks Ansible (`ls roles/`, `head` ciblees, `grep`
   recursive sur Authelia/Grafana/Vault/AWX).
5. Cross-reference avec [STATUS.md](../STATUS.md) (dettes connues), ADRs
   0001-0034, runbooks `docs/runbook-*.md`.
6. **Aucun** `terraform plan/apply`, **aucun** `ansible-playbook` (meme `--check`).
   **Aucune** lecture de secret en clair (`ansible-vault view` seulement pour
   diff de cles dans la session precedente, hors scope de ce rapport).

---

## 2. Inventaire runtime

### 2.1. Substrat Proxmox host

| Element | Etat | Source de creation |
|---------|------|---------------------|
| Proxmox host (Tailscale `100.112.113.2` / `192.168.18.50`) | PVE 9.1.0, 1 noeud, kernel 6.17.2-1-pve | **MANUEL** (install ISO Proxmox sur fer) |
| Bridges `vmbr0`..`vmbr5` | 6 bridges configures | **MANUEL** `/etc/network/interfaces` (dette Phase II `5. Bootstrap manuel template 9000 + interfaces Proxmox`) |
| Sub-interfaces VLAN `vmbr1.15`, `.20`, `.50`, `.60` | 4 sub-IPs config (mgmt host plane par VLAN) | **MANUEL** idem |
| Storage `local-lvm` (LVM thin pool) | 1 storage, thin pool `data` sur VG `pve` | **MANUEL** (cree par installateur Proxmox) |
| Token API `root@pam!terraform` | en place, utilise par bpg/proxmox provider | **MANUEL** (Proxmox UI) |

### 2.2. VMs Linux (13 + 1 template)

| VMID | Nom | IP | Reseau Proxmox | Description | TF state | Roles Ansible |
|------|-----|----|----|-------------|----------|---------------|
| 100 | web01 | 172.16.1.2/29 | vmbr3 (DMZ) | Nginx Web Server | ✅ | common, hardening, website |
| 101 | mail01 | 172.16.1.3/29 | vmbr3 (DMZ) | Postfix + Dovecot | ✅ | common, hardening, mail_server, wazuh_agent |
| 102 | bastion01 | 192.168.15.2/29 | vmbr1 tag=15 | SSH Bastion + MFA TOTP | ✅ | common, hardening, bastion, mfa_totp, wazuh_agent |
| 103 | dc01 | 192.168.20.10/28 | vmbr1 tag=20 | Samba AD-DC | ✅ | common, hardening, dc, pki_client, wazuh_agent |
| 104 | fs01 | 192.168.20.11/28 | vmbr1 tag=20 | Samba File Server | ✅ | common, hardening, fileserver, wazuh_agent |
| 105 | db01 | 192.168.20.12/28 | vmbr1 tag=20 | MariaDB | ✅ | common, hardening, database, wazuh_agent |
| 106 | app01 | 192.168.20.13/28 | vmbr1 tag=20 | Wazuh + Grafana + Vault + Authelia + portail | ✅ | common, hardening, swap_file, wazuh_manager, wazuh_indexer, wazuh_filebeat, portail (mais **PAS** Grafana/Vault/Authelia, voir 5.2) |
| 107 | proxy-lyon01 | 192.168.20.14/28 | vmbr1 tag=20 | Squid Lyon | ✅ | common, hardening, proxy |
| 108 | proxy-mrs01 | 192.168.40.11/26 | vmbr2 | Squid MRS | ✅ | common, hardening, proxy |
| 109 | backup01 | 192.168.50.2/29 | vmbr1 tag=50 | Borg + rclone B2 | ✅ | common, hardening (+ Borg manuel, voir 5.2) |
| 110 | vpn-gw01 | 172.16.1.4/29 | vmbr3 (DMZ) | WireGuard + IPsec gateway | ❌ **hors TF** | common, hardening, vpn_gateway |
| 111 | awx01 | 192.168.60.2/29 | vmbr1 tag=60 | AWX K3s | ❌ **hors TF** | common, hardening (mais K3s + AWX = manuel, voir 5.2) |
| 112 | pki01 | 192.168.60.4/29 | vmbr1 tag=60 | step-ca PKI interne | ❌ **hors TF** | common, hardening, pki_server (verification only) |
| 9000 | debian-12-cloud-template-nova | (stopped) | vmbr0 | Template cloud-init base | ❌ **hors TF, MANUEL** | -- |

### 2.3. OPNsense (4 VMs)

| VMID | Nom | Reseau | Role | TF state | Code |
|------|-----|--------|------|----------|------|
| 200 | wan-simulator | vmbr0×2 + vmbr5 | WAN simule double-FAI | ✅ creation VM | ✅ regles (`fw_wansim.tf`) |
| 201 | fw-ext-lyon01 | vmbr0 + vmbr3 + vmbr4 | Pare-feu externe Lyon | ✅ creation VM | ✅ regles (`fw_ext.tf`) |
| 202 | fw-int-lyon01 | vmbr4 + vmbr1 (trunk VLAN 15/20/30/50) | Pare-feu interne Lyon | ✅ creation VM | ✅ regles (`fw_int.tf` + `fw_int_vlans.tf` + `fw-int-lyon-road-warriors.tf`) |
| 203 | fw-ext-mrs01 | vmbr5 + vmbr2 | Pare-feu MRS | ✅ creation VM | ✅ regles (`fw_ext_mrs.tf`) |

OPNsense ISO + bootstrap initial (web installer) = **MANUEL** (dette Phase II
`5.`). Apres installation, API keys generees, Terraform peut piloter le reste.

### 2.4. Reseaux / topologie

| Reseau | Bridge Proxmox | VLAN tag | Subnet | Geree par |
|--------|----------------|----------|--------|-----------|
| Management Proxmox | vmbr0 | -- | 192.168.18.0/24 | manuel host |
| Trunk interne (FW-INT-LYON) | vmbr1 | 802.1q trunk | (transport) | manuel host + bpg/proxmox via TF |
| MGMT Internal FW | vmbr1 | -- | 192.168.99.0/29 | manuel host |
| Bastion VLAN | vmbr1.15 | 15 | 192.168.15.0/29 | manuel host + OPNsense TF |
| Servers VLAN | vmbr1.20 | 20 | 192.168.20.0/28 | manuel host + OPNsense TF |
| Users VLAN | (vmbr1.30 ?) | 30 | (Lyon Users, pas de VM) | OPNsense TF |
| Backup VLAN | vmbr1.50 | 50 | 192.168.50.0/29 | manuel host + OPNsense TF |
| Admin VLAN | vmbr1.60 | 60 | 192.168.60.0/29 | manuel host + OPNsense TF |
| LAN MRS | vmbr2 | -- | 192.168.40.0/26 | manuel host + OPNsense TF |
| DMZ Lyon | vmbr3 | -- | 172.16.1.0/29 | manuel host + OPNsense TF |
| Link FW-EXT ↔ FW-INT | vmbr4 | -- | 10.0.1.0/30 | manuel host |
| Link FW-EXT ↔ WAN-SIM | vmbr5 | -- | 10.0.2.0/30 | manuel host |

---

## 3. Code IaC existant

### 3.1. Terraform

**Repos actifs** (state present, recents) :

| Path | Provider | Scope | Resources |
|------|----------|-------|-----------|
| `nova-syndicate-proxmox/terraform/environments/proxmox/` | `bpg/proxmox ~> 0.66` | Creation des 14 VMs (10 Linux + 4 OPNsense) via 2 modules (`proxmox-vm`, `proxmox-opnsense`). Tous clones du template 9000. | 14 |
| `nova-syndicate-proxmox/terraform/environments/opnsense/` | `browningluke/opnsense ~> 0.16` | Aliases (35+), regles filter (40+), interfaces VLAN (5), routes (4+). 4 providers (alias par firewall). | ~85 |

**Repos legacy / candidats nettoyage** :

| Path | Statut suspect |
|------|---------------|
| `nova-syndicate-ansible/terraform/environments/lyon/` | Apparente Phase II initiale ; STATUS.md II.IV indique "renomme depuis lyon/" -> opnsense/. Pas de tfstate visible. **A archiver ou supprimer**. |
| `terraform/environments/lyon/` (top-level) | Doublon ou ancetre ; pas de tfstate visible. **Idem**. |
| `nova-syndicate-proxmox/terraform/modules/cloud-init/` | Module avec son propre `.terraform` mais semble peu utilise. **Verifier**. |

### 3.2. Ansible

20 roles : `bastion`, `common`, `database`, `dc`, `fileserver`, `hardening`,
`mail_server`, `mfa_totp`, `pki_client`, `pki_server`, `portail`, `proxy`,
`swap_file`, `vpn`, `vpn_gateway`, `wazuh_agent`, `wazuh_filebeat`,
`wazuh_indexer`, `wazuh_manager`, `website`.

22+ playbooks dans `playbooks/`, orchestrateur principal `site.yml` (10 etapes
plus 2 pre-etapes PKI ajoutees en Phase 7 ADR-0034).

`site.yml` mapping :

| Etape | Hosts | Roles |
|-------|-------|-------|
| 0 | nova_all | pki_client |
| 0bis | pki | pki_server (validation only) |
| 1 | nova_all | common |
| 2 | nova_all | hardening |
| 3 | domain_controllers | dc |
| 4 | fileservers | fileserver |
| 5 | databases | database |
| 6 | bastions | bastion |
| 7 | domain_controllers (?) | vpn / vpn_gateway (mismatch host probable) |
| 8 | proxies | proxy |
| 8bis | mailservers | mail_server |
| 09 | app_servers | wazuh_manager |
| 10 | nova_all | wazuh_agent |

**Anomalie ETAPE 7** : `hosts: domain_controllers` alors qu'il devrait probablement
etre `vpn_gateways`. A verifier / corriger -- pas de risque actif puisque le role
`vpn_gateway` tournerait sur dc01 (echec attendu) mais aucun apply recent ne
mentionne cet effet.

### 3.3. Cloud-init

Le template 9000 utilise un cloud-init injecte par Proxmox (`ide2 cloudinit cdrom`)
avec :
- IP statique via `ipconfig0`
- Cle SSH publique `jedha-lab` (commune a toutes les VMs)
- Pas de user-data custom au-dela de Proxmox-cloud-init (pas d'`#cloud-config`
  versionne dans le repo TF a part le `cloud-init/` dir module)

---

## 4. Classification par composant (4 categories)

Categories :
- **[IAC-COMPLET]** -- reproductible par code existant.
- **[IAC-PARTIEL]** -- code existe mais incomplet ou drift documente.
- **[BOOTSTRAP-MANUEL-IRREDUCTIBLE]** -- ne peut pas etre IaC par nature.
- **[CANDIDAT-AUTOMATISABLE]** -- manuel aujourd'hui mais codable.
  Effort : **S** (~1 jour), **M** (~1 semaine), **L** (~1 mois).

### 4.1. Substrat hyperviseur

| Composant | Cat | Detail | Effort si CANDIDAT |
|-----------|-----|--------|----|
| Install Proxmox PVE 9.1 sur le fer | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | Installer ISO sur fer = pre-requis physique. Pas IaC. | -- |
| Bridges `vmbr0..5` + sub-VLAN | **CANDIDAT-AUTOMATISABLE** | `/etc/network/interfaces` parse-able. Ansible-on-Proxmox-host possible. Mentionne dette Phase II §5. | **S** -- 1 jour. Risque : si mauvaise config, hote injoignable -> Tailscale fallback. |
| Storage `local-lvm` (LVM thin) | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | LVM cree par installeur Proxmox. Re-creer = `pvcreate/vgcreate/lvcreate`. Scripted possible mais sur installation neuve uniquement. | -- |
| Token API `root@pam!terraform` | **CANDIDAT-AUTOMATISABLE** | `pveum user token add` scriptable. Mais necessite credentials initiaux root. | **S** -- 0.5 jour. Output sensible (secret a stocker). |
| Cle SSH root Proxmox -> awx-runner | **CANDIDAT-AUTOMATISABLE** | Ajout manuel `authorized_keys`. Trivial a scripter. | **S** -- 0.5 jour. |

### 4.2. Template Debian VMID 9000

| Composant | Cat | Detail |
|-----------|-----|--------|
| Template 9000 cloud-init | **CANDIDAT-AUTOMATISABLE** | Documente comme dette Phase II §5. Script ciblable : `qm create 9000 + qm importdisk + qm set --ide2 cloudinit + qm template`. Cloud-init template officiel Debian + customisation NIS2 (apt repos, systemd-resolved fix cf memory `nova-cloud-init-template-dns-issue`). | **M** -- 3-5 jours (modif systemd-resolved, qm set --sshkeys, validation idempotence + recreation test). |

### 4.3. VMs Linux

| Composant | Cat | Detail | Si IAC-PARTIEL/CANDIDAT : effort |
|-----------|-----|--------|----|
| 10 VMs creation (web/mail/bastion/dc/fs/db/app/proxies×2/backup) | **IAC-COMPLET** | Module TF `proxmox-vm`, clone template 9000, ipconfig0 + sshkeys cloud-init. | -- |
| 10 VMs OS base + hardening | **IAC-COMPLET** | Roles `common` + `hardening` couvrent les 10. | -- |
| dc01 Samba AD provision | **IAC-COMPLET** (avec nuance) | `roles/dc/tasks/samba_provision.yml` -> `samba-tool domain provision` si `sam.ldb` absent. Idempotent. Mot de passe admin via vault. | -- |
| dc01 DNS forwarder + records | **IAC-COMPLET** (corrige ce soir T-DC-DNS-FORWARDER-ANSIBLE) | Creds Administrator passes en argv, evite hang TTY. | -- |
| fs01, db01, mail01, web01, proxies, backup01 | **IAC-COMPLET** | Roles dedies, validated par cross-checks repetes. | -- |
| **vpn-gw01 creation** | **CANDIDAT-AUTOMATISABLE** | OS config via role `vpn_gateway` (existant), mais creation VM manuelle. Aligner sur le pattern Terraform `proxmox-vm`. | **S** -- 1 jour. Risque : reseau DMZ deja IaC en TF. |
| **awx01 creation + K3s + AWX Operator + objets AWX** | **IAC-PARTIEL** + **CANDIDAT-AUTOMATISABLE** | Creation VM manuelle. K3s + AWX Operator + Helm + AWX CR + Teams + Job Templates documentes dans `runbook-awx.md` + ADR-0031, mais procedure CLI a la main. Pas de role Ansible. | **M** -- 5-10 jours. Risque : AWX CR + Operator + jobs sont vraiment specifiques, ne pas casser la prod en testant. |
| **pki01 creation + step-ca init** | **IAC-PARTIEL** | Creation VM manuelle. `pki_server` role = validation only ("V1 manuel" inscrit dans le role). Root CA key + intermediate generation manuels. Si re-init, perte de tous les certs emis (incl. dc01:636). | **L** -- 10+ jours. Risque : Root CA = trust anchor, decisions tres sensibles. **CANDIDAT douteux** (cf section 7). |

### 4.4. OPNsense

| Composant | Cat | Detail |
|-----------|-----|--------|
| 4 VMs OPNsense creation (CPU/RAM/disque/network_interfaces) | **IAC-COMPLET** | Module TF `proxmox-opnsense` + state confirme. ISO source : `OPNsense-25.1-dvd-amd64.iso` dans storage `local`. |
| OPNsense ISO install + premier boot | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | Premier boot OPNsense = configuration interactive (web installer ou console). Pas d'`cloud-init` natif. **Sauf** : ZTP via le futur `opnsense-25.x` cloud-init experimental, hors scope. |
| 4 OPNsense API keys | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | Generer 1 user `terraform` + 1 paire API par firewall via UI. Stocke hors repo (`nova-iac-secrets/apikey-*.txt`). |
| 35+ aliases + 40+ regles filter | **IAC-COMPLET** | Code dans `terraform/environments/opnsense/*.tf` + state. Pattern "pass + block all" par interface. |
| VLAN interfaces FW-INT (5 sub-IF) | **IAC-COMPLET** | `fw_int_vlans.tf`, resources `opnsense_interfaces_vlan`. |
| Gateways OPNsense (pour routes statiques) | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** ou **CANDIDAT** | Provider browningluke 0.16 ne supporte pas `opnsense_gateway` -> creation manuelle (dette Phase II §2). Code OPNsense propre cote upstream a attendre. |
| Routes statiques cross-site (Lyon ↔ MRS) | **IAC-PARTIEL** | `opnsense_route` resources existent dans le state mais depend des Gateways manuels. |
| Tunnel IPsec FW-EXT-LYON ↔ FW-EXT-MRS | **IAC-PARTIEL** | strongSwan present, regles UDP 500/4500/ESP codees Terraform, **daemon non demarre** (config heritee de GNS3 obsolete). Dette Phase II §4. |

### 4.5. Stacks applicatives sur app01

| Composant | Cat | Detail | Effort si CANDIDAT |
|-----------|-----|--------|----|
| Wazuh Manager (SIEM) | **IAC-COMPLET** | `roles/wazuh_manager/tasks/{install,config,rules,service}.yml`. Idempotent. | -- |
| Wazuh Indexer (OpenSearch) | **IAC-COMPLET** | `roles/wazuh_indexer/tasks/main.yml` (128 lignes). | -- |
| Wazuh Filebeat | **IAC-COMPLET** | `roles/wazuh_filebeat/tasks/main.yml` (102 lignes). | -- |
| Wazuh Dashboard (OpenSearch Dashboards) | **IAC-PARTIEL** | Reference dans `inventory/group_vars/app_servers/vars.yml` (commit ce soir, ADR-0013) mais **role dedie absent**. Credentials definis, install manuelle. | **S** -- 1-2 jours. Pattern similaire aux 3 autres roles wazuh. |
| **Authelia** | **CANDIDAT-AUTOMATISABLE** | **Aucun role Ansible**. Documente ADR-0019. Config `/etc/authelia/configuration.yml` actuellement edite a la main. | **M** -- 3-5 jours (role `authelia` template + secrets vault + sync AD). |
| **Grafana** | **CANDIDAT-AUTOMATISABLE** | **Aucun role Ansible**. ADR-0030 (single-pane-of-glass). Install + provisioning datasources + dashboards = manuel. | **M** -- 5-7 jours (role + datasources Wazuh + Prometheus + dashboards). |
| **HashiCorp Vault APP01** | **CANDIDAT-AUTOMATISABLE** | **Aucun role Ansible**. ADR-0026 documente le `tls_disable=true` lab. Install + storage + policies = manuel. | **M** -- 5-7 jours (role + audit + policies + un-seal automation = risque securite). |
| nginx reverse proxy + cert wildcard mkcert | **IAC-PARTIEL** | Pas de role dedie nginx ; cert wildcard distribue via `_certs-LOCAL-DO-NOT-COMMIT/`. Config nginx editee a la main. | **S** -- 1-2 jours. |
| Portail metier Flask | **IAC-COMPLET** | `roles/portail/tasks/main.yml` (124 lignes), venv + Flask + gunicorn + systemd. | -- |
| nova-portail systemd | **IAC-COMPLET** | Idem (templates dans `roles/portail/templates/`). | -- |

### 4.6. Backup01

| Composant | Cat | Detail | Effort |
|-----------|-----|--------|----|
| OS base + hardening | **IAC-COMPLET** | common + hardening. | -- |
| Borg repo + Borg client config | **IAC-PARTIEL** | Pas de role Ansible `borg` dedie. Procedure documentee dans `runbook-borg-cloud.md`. Mentionne dans ADR-0008/0009 (`repokey-append-only`, strategie 3-2-1-1-0). | **M** -- 3-5 jours. |
| rclone Backblaze B2 | **CANDIDAT-AUTOMATISABLE** | Manuel + secrets dans `nova-iac-secrets/`. | **S** -- 1-2 jours. |

### 4.7. Bastion01

| Composant | Cat | Detail |
|-----------|-----|--------|
| Teleport install | **IAC-COMPLET** | `roles/bastion/tasks/main.yml` -- apt repo + install + config + service. |
| MFA TOTP (Google Auth PAM + sshd config) | **IAC-COMPLET** | `roles/mfa_totp/tasks/main.yml` (11 lignes seulement, peut etre stub a verifier) ; runbook `runbook-mfa-bastion.md` complet. **A verifier en pratique** (STATUS mentionne T-BASTION-TAILSCALE-CLEANUP en suspens). |

### 4.8. WireGuard

| Composant | Cat | Detail | Effort |
|-----------|-----|--------|----|
| WireGuard road warriors (gateway vpn-gw01) | **IAC-PARTIEL** | Role `vpn_gateway` + `vpn`, mais `wireguard.tf` (ou `ireguard.tf`) dans 2 dirs Terraform candidats legacy. Doute sur source de verite. | **S** -- 1 jour pour reconciliation. |
| IPsec Lyon ↔ MRS site-to-site | **IAC-PARTIEL** | strongSwan present, regles UDP 500/4500/ESP codees Terraform, daemon non demarre (Phase II §4). | **M** -- 3-5 jours. |

### 4.9. AWX01 (orchestrateur Ansible)

| Composant | Cat | Detail |
|-----------|-----|--------|
| Creation VM | **CANDIDAT-AUTOMATISABLE** | Ajouter module `awx01` dans `terraform/environments/proxmox/vms.tf`. **S**. |
| K3s install + config (`disable: [traefik]`) | **CANDIDAT-AUTOMATISABLE** | Role `k3s` ou tasks dans `roles/awx_k3s/` a creer. Files presents (`files/awx/k3s-config.yaml`). **S** -- 1 jour. |
| AWX Operator (Helm) | **CANDIDAT-AUTOMATISABLE** | `kubernetes_helm_release` Terraform ou role Ansible. **S**. |
| AWX CR (custom resource) + objets (Org, Credentials, Project, Inventory, Job Templates, Teams, AUTH_LDAP_TEAM_MAP) | **CANDIDAT-AUTOMATISABLE** | Documente runbook-awx + ADR-0031 + ADR-0033. Modelisable en YAML/jq via API. Mais **risque** : objets crees a chaud + drift attendu. | **M** -- 5-10 jours. |

### 4.10. PKI step-ca (pki01)

| Composant | Cat | Detail |
|-----------|-----|--------|
| Creation VM pki01 | **CANDIDAT-AUTOMATISABLE** | Ajouter module TF (comme awx01). **S**. |
| step-cli + step-ca install (binaires + user step) | **CANDIDAT-AUTOMATISABLE** | Role `pki_server` actuellement validation only. Etendre install + setup. **S-M** -- 2-4 jours. |
| Root CA + Intermediate CA generation | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | `step ca init` interactif (root password, key type, name, etc.). Apres init = root CA key materiel sensible. Re-init = invalidation totale de tous les certs emis (mail01, Authelia, etc.) -> rotation cross-clients. **NE PAS AUTOMATISER** sans plan de rotation. |
| ca.json + provisioners | **CANDIDAT-AUTOMATISABLE** | Apres init, `step ca provisioner add` scriptable. Mais depend de la phase precedente. **S**. |

### 4.11. Secrets et clefs

| Composant | Cat | Detail |
|-----------|-----|--------|
| `inventory/group_vars/all/vault.yml` (ansible-vault) | **IAC-COMPLET** | 21 secrets vault, chiffres au repo. Vault password file `~/.ansible/nova_vault_pass` (off-repo). |
| 4 cles API OPNsense (`nova-iac-secrets/apikey-*.txt`) | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | Generation via UI OPNsense. Off-repo strict (`.gitignore`). |
| Token API Proxmox | **BOOTSTRAP-MANUEL-IRREDUCTIBLE** | UI Proxmox / `pveum`. Off-repo (`terraform.tfvars` + `gitignore`). |
| Cles SSH host (`/etc/ssh/ssh_host_*`) | **IAC-COMPLET** (post cloud-init) | Re-generees a chaque rebuild cloud-init. `host-keys-reference.txt` documente les fingerprints stables actuels. |
| Cle SSH `awx-runner` / `nova-agents` | **IAC-COMPLET (deploiement)** + **MANUEL (creation)** | Cle privee initiale = creee manuellement, mais distribution via playbook idempotent. |

---

## 5. Sequence de rebuild theorique (avec ruptures)

```
A. PROXMOX HOST (manuel)
   |
   +-- A.1 Install PVE sur fer (manuel ISO)
   +-- A.2 Configurer bridges vmbr0..5 + sub-VLAN /etc/network/interfaces  [RUPTURE 1 -- MANUEL]
   +-- A.3 Verifier storage local-lvm
   +-- A.4 Generer token API Terraform + cle SSH root  [RUPTURE 2 -- MANUEL/CANDIDAT-S]
   |
B. TEMPLATE 9000 DEBIAN  [RUPTURE 3 -- MANUEL/CANDIDAT-M]
   |
   +-- B.1 Download Debian cloud image
   +-- B.2 qm create 9000 + import disk + cloud-init + qm template
   +-- B.3 Customisation (systemd-resolved fix, sshkeys, etc.)
   |
C. OPNSENSE BOOTSTRAP  [RUPTURE 4 -- MANUEL]
   |
   +-- C.1 4× qm create OPNsense via TF (creation VM OK)
   +-- C.2 Premier boot, configuration interactive WAN/LAN  [MANUEL irreductible]
   +-- C.3 Generer user terraform + API keys × 4  [MANUEL irreductible]
   +-- C.4 Stocker les 4 API keys dans nova-iac-secrets/ + tfvars  [MANUEL]
   |
D. PKI step-ca  [RUPTURE 5 -- MANUEL/CANDIDAT-L]
   |
   +-- D.1 Creer VM pki01 (manuel ou candidat TF)
   +-- D.2 Installer step-cli + step-ca
   +-- D.3 step ca init (interactif)  [BOOTSTRAP-MANUEL-IRREDUCTIBLE par design]
   +-- D.4 Emettre cert dc01.nova-syndicate.local (LDAPS)
   |
E. TERRAFORM CREATE VMs
   |
   +-- E.1 terraform/environments/proxmox apply -> 10 Linux VMs + 4 OPNsense
   +-- E.2 terraform/environments/opnsense apply -> 35 aliases + 40 regles + VLANs + routes
   |  (3 VMs hors TF a creer : vpn-gw01, awx01, pki01 -- ce dernier deja en place via D)
   |
F. ANSIBLE OS BASE
   |
   +-- F.1 ansible-playbook site.yml --tags role:pki_client (deploiement bundle Nova CA)
   +-- F.2 site.yml --tags role:common,role:hardening
   +-- F.3 site.yml --tags role:dc (provision Samba AD)  [DEPEND DE D.4 si LDAPS prevu]
   +-- F.4 site.yml --tags role:fileserver,role:database,role:bastion,role:proxy,role:mail_server,role:website
   +-- F.5 site.yml --tags role:wazuh_manager,role:wazuh_indexer,role:wazuh_filebeat,role:wazuh_agent
   |
G. STACKS APPLICATIVES MANUELLES  [RUPTURE 6 -- CANDIDAT-M chacune]
   |
   +-- G.1 AWX K3s install + Operator + objets (manuel runbook-awx)
   +-- G.2 Authelia install + config + LDAP backend
   +-- G.3 Grafana install + datasources + dashboards
   +-- G.4 Vault install + storage + policies (lab tls_disable=true)
   |
H. VPN
   |
   +-- H.1 vpn-gw01 OS + WireGuard config (role IaC OK)
   +-- H.2 IPsec strongSwan Lyon <-> MRS  [RUPTURE 7 -- daemon non demarre, dette Phase II §4]
   |
I. BACKUPS
   |
   +-- I.1 backup01 Borg + rclone B2  [RUPTURE 8 -- pas de role Ansible Borg dedie]
   |
J. MFA bastion + clients AD
   |
   +-- J.1 MFA TOTP bastion (role IaC partiel, finalisation TODO)
   +-- J.2 Comptes AD via IAM playbooks (AWX Job Templates)
```

### 5.1. Ruptures de la chaine (8 identifiees)

| # | Etape | Type | Pourquoi ca casse "une commande" |
|---|-------|------|-----------------------------------|
| 1 | Bridges vmbr0..5 + sub-VLAN | MANUEL | Pre-requis hote, pas IaC. Dette Phase II §5. |
| 2 | Token API Proxmox + cle SSH root | MANUEL | Initialisation hors repo. Output sensible. |
| 3 | Template 9000 Debian | MANUEL | Pre-requis Terraform, dette Phase II §5. |
| 4 | OPNsense ISO bootstrap + API keys | MANUEL irreductible | OPNsense ne supporte pas cloud-init / ZTP. |
| 5 | step-ca Root CA init | MANUEL irreductible | Root CA = trust anchor, decision humaine. |
| 6 | Stacks Authelia + Grafana + Vault + AWX K3s | MANUEL / CANDIDAT-M | Pas de role Ansible. |
| 7 | IPsec daemon | DETTE Phase II §4 | Code TF present, config strongSwan obsolete. |
| 8 | Borg repo + policies | DETTE | Pas de role Ansible dedie. |

### 5.2. Dependances critiques

```
A.* (host) ───> B (template) ───> E.1 (TF VMs)
                                  │
              D (PKI) ─────────┐  │
                               │  ▼
           C (OPNsense) ──> E.2 (TF rules)
                               │  │
                               ▼  ▼
                          F (Ansible base)
                               │
                ┌──────────────┼─────────────┐
                ▼              ▼             ▼
              G (stacks)    H (VPN)        I (Borg)
                                              │
                                              ▼
                                          J (MFA + IAM)
```

**Sequence minimale de re-jeu sans rupture** : depuis le point E (TF apply) jusqu'a
F (Ansible base) inclus = ~30 minutes + cross-checks. C'est le "rebuild une
commande" qui marche **deja**, mais conditionne par A-D pre-existants.

---

## 6. Conclusion : faisabilite "rebuild une commande"

**Aujourd'hui** : un rebuild complet d'un site demande :
- ~6 heures de manuel (A + B + C + D) si on connait le run-book.
- ~30 minutes d'automatise (E + F).
- ~4-6 heures de manuel post-deploiement (G + H + I + J).

Total realiste : **10-12 heures supervisees** pour un seul site Lyon (sans MRS).
MRS depend de Lyon (IPsec) + son propre fw-ext-mrs01 + proxy-mrs01.

**Cible "une commande"** : pas atteignable strictement. Mais "une commande **par
phase**" est atteignable avec ~4 chantiers M :

| Cible realiste | Manuel residuel | Achievable en |
|----------------|-----------------|---------------|
| "une commande par site Proxmox-pret" | 0 (sauf install PVE initial) | 2 chantiers M (template + bridges) |
| "une commande par stack app01" | 0 (sauf Vault initial unsealing) | 3 chantiers M (Authelia + Grafana + Vault + AWX K3s) |
| "une commande par PKI" | step-ca init (decision humaine NIS2) | irreductible |
| "une commande par OPNsense" | ISO install + API keys (×4) | irreductible (limite OPNsense) |

### 6.1. Chantiers prioritaires (3-5)

Classes par ratio **valeur certification / cout** :

1. **T-IAC-BRIDGES-PROXMOX-HOST** (effort S, valeur ELEVEE)
   - Scripter `/etc/network/interfaces` Proxmox via Ansible-on-Proxmox-host
     (un mini-role + playbook hors `site.yml`, target `proxmox` group avec
     `ansible_user=root`).
   - Pourquoi : **ferme la dette Phase II §5 partiellement**, narrative
     certification "bridges versionnes". Risque bas (rollback /etc/network/interfaces).

2. **T-IAC-TEMPLATE-9000-BUILD** (effort M, valeur ELEVEE)
   - Script `build-template-9000.sh` consomme par bootstrap_nova.sh : download
     Debian cloud image -> qm create -> qm set --sshkeys -> qm template.
     Inclut le fix systemd-resolved DNS (cf memory `nova-cloud-init-template-dns-issue`).
   - Pourquoi : sans ca, terraform apply ne tourne pas. **Cle de voute Phase VI.**

3. **T-IAC-AWX01-K3S-AWX** (effort M, valeur MOYENNE)
   - 3 sous-roles Ansible :
     - `k3s_server` (binaire + config `disable: [traefik]`).
     - `awx_operator` (helm + CR YAML).
     - `awx_objects` (Org + Credentials + Project + Inventory + JT + Teams +
       AUTH_LDAP_TEAM_MAP via API REST).
   - Pourquoi : AWX = orchestrateur central de l'IAM. Sa re-creation manuelle
     est aujourd'hui un point unique de fragilite (cf runbook-awx + ADR-0031).

4. **T-IAC-AUTHELIA-ROLE** (effort M, valeur MOYENNE)
   - Role `authelia` (install + config.yml + secrets vault + LDAP backend).
   - Pourquoi : touche tout l'acces SSO (Grafana, futur Wazuh dashboard,
     portail metier). Faible risque techniquement, gros gain narratif NIS2.

5. **T-IAC-BORG-ROLE** (effort S-M, valeur MOYENNE)
   - Role `borg_repo` + `borg_client` (init repo, append-only, policies retention,
     B2 sync). Documente ADR-0008/0009.
   - Pourquoi : sans ca, le DRP est partiellement manuel. Gain : couverture
     RPO/RTO veritablement reproductible.

### 6.2. Ce qui NE vaut PAS l'effort

| Composant | Pourquoi laisser manuel |
|-----------|------------------------|
| step-ca Root CA init | Decision humaine NIS2, irreductible. Scripter = anti-pattern. |
| OPNsense ISO + premier boot + API keys | Limite produit (pas de cloud-init OPNsense). Effort L pour gain nul. |
| Install PVE sur le fer | Pre-requis physique. Si le fer change, install ISO est trivial vs script. |
| 4 cles API OPNsense | Generation interactive UI, stockage off-repo. Pas d'API pour creer les API keys. |
| 4 paires bridges manuels (vmbr0/2/3/5 sans sub-VLAN) | Apres T-IAC-BRIDGES-PROXMOX-HOST = couvert. Inutile de splitter. |
| Vault APP01 unsealing | Si tls_disable=true reste choix lab, l'unsealing automatique = anti-pattern securite. A garder manuel jusqu'a passage en prod TLS. |

---

## 7. Dettes non encore documentees (issues du croisement)

### 7.1. Decouvertes pendant l'audit

1. **T-IAC-SITE-YML-ETAPE-7** (LOW) : `ETAPE 7 -- VPN WireGuard + IPsec` cible
   `hosts: domain_controllers` alors qu'elle devrait cibler `vpn_gateways`.
   Probable copier-coller. Aucun apply recent ne semble avoir tourne cette
   etape (rollover snapshot non observe sur dc01 lie a wireguard). A corriger
   trivialement.

2. **T-IAC-WIREGUARD-DRIFT** (MEDIUM) : `wireguard.tf` est present dans 2 dirs
   candidats `legacy` (`nova-syndicate-ansible/terraform/environments/lyon/`
   + `terraform/environments/lyon/` top-level), avec un `ireguard.tf` (typo)
   vide. **Source de verite ambigue**. A consolider dans
   `nova-syndicate-proxmox/terraform/environments/opnsense/` (ou ailleurs)
   apres decision.

3. **T-IAC-CLEAN-LEGACY-TF** (LOW) : 2 dirs `terraform/environments/lyon/`
   sans tfstate visible -- candidats nettoyage / archive (orphelin Phase II
   pre-renommage).

4. **T-IAC-APP01-STACKS-NOT-CODED** (HIGH valeur, MEDIUM effort) :
   Authelia, Grafana, Vault, nginx reverse-proxy = pas de role Ansible.
   Dette importante en termes de NIS2 "reproductibilite".

5. **T-IAC-WAZUH-DASHBOARD-ROLE** (LOW) : credentials Wazuh Dashboard ajoutes
   ce soir (commit `b095635`, ADR-0013) mais pas de role dedie. Pattern a
   ajouter par analogie avec wazuh_manager.

### 7.2. Snapshots Proxmox -- volumetrie

| VMID | Nombre snapshots | Commentaire |
|------|------------------|-------------|
| 100 web01 | 0 | -- |
| 101 mail01 | 2 | dont `mail01-pre-ldaps-mail` (Phase 6.3) |
| 102 bastion01 | 2 | dont `pre-awx-nftallowlist-2026-05-23` (T-AFK-DETTES) |
| 103 dc01 | 8 | accumulation Phase 4/5/6.3/7a + iac-reformat (ce soir) ; **a nettoyer apres validation finale** |
| 104 fs01 | 6 | accumulation T-AFK-MEGA + T-AGENTS-KEY-DEPLOY |
| 105 db01 | 3 | -- |
| 106 app01 | 4 | dont `pre-app01-swap-add` |
| 107 proxy-lyon01 | 0 | -- |
| 108 proxy-mrs01 | 0 | -- |
| 109 backup01 | 6 | -- |
| 110 vpn-gw01 | 4 | dont `pre-awx-vpngw-nft` |
| 111 awx01 | 3 | dont `pre-awx-rbac` |
| 112 pki01 | 0 | nouveau (1er juin) |
| 200/201/202/203 | 0/1/0/1 | OPNsense, peu de snapshots |
| 9000 template | 0 | -- |

Snapshots non nettoyes accumules sur 6 VMs (dc01, fs01, backup01, mail01,
bastion01, vpn-gw01) -- dette de menage hors scope IaC.

---

## 8. Synthese executive

| Question | Reponse |
|----------|---------|
| Combien de composants IAC-COMPLET ? | 35+ (10 VMs Linux x roles communs + role-applicatifs dedies + 4 OPNsense VM create + 85+ resources OPNsense rules + Wazuh stack + portail + mail_server + bastion Teleport + ...) |
| Combien IAC-PARTIEL ? | 8 (Wazuh Dashboard, IPsec daemon, Routes Gateway-dependent, MFA TOTP final, Borg policies, wireguard.tf drift, MFA bastion-tailscale-cleanup, app01 nginx) |
| Combien BOOTSTRAP-MANUEL-IRREDUCTIBLE ? | 6 (Install PVE, Storage LVM, OPNsense ISO+1er boot, OPNsense API keys ×4, step-ca Root CA init, Vault un-sealing) |
| Combien CANDIDAT-AUTOMATISABLE ? | 9 (Bridges Proxmox, Token API PVE, Template 9000, AWX01 K3s+AWX+objets, Authelia, Grafana, Vault role, vpn-gw01 creation, Borg role) |
| Rebuild "une commande" atteignable aujourd'hui ? | NON. 8 ruptures dans la chaine. |
| Rebuild "une commande par phase" atteignable ? | OUI. ~4 chantiers M (bridges + template + AWX + Authelia) ferment ~80 % de la dette IaC restante. |
| Quel pourcentage de l'infra est code aujourd'hui ? | **~75 %** en volume, **~30 %** en sequencabilite. |
| Chantiers a NE PAS poursuivre ? | step-ca Root CA, OPNsense ISO bootstrap, Install PVE -- effort eleve, gain nul. |

**Posture recommandee** : poursuivre les 5 chantiers de la section 6.1 dans
l'ordre. Le passage de 30 % a ~70 % en sequencabilite est atteignable en 4-6
semaines de travail focalise, sans elargir le scope NIS2 / certification.

---

## Annexes -- references croisees

- [STATUS.md](../STATUS.md) -- dette Phase II §1-§7, §8 (T-AWX-DEPLOY filles)
- [runbook-ldaps-migration.md](runbook-ldaps-migration.md) -- LDAPS migration plan
- [ldaps-migration-report.md](ldaps-migration-report.md) -- Phase 6.3+6.6+7a
- [runbook-awx.md](runbook-awx.md) -- AWX procedures
- [docs/adr/ADR-0001..0034](adr/) -- 34 ADRs cumulees
- [bootstrap_nova.sh](../bootstrap_nova.sh) -- script post-bastion (228 lignes,
  6 etapes) -- **note** : ne couvre PAS A-E mais seulement F (ansible bootstrap
  apres reboot).
- Memoires Claude pertinentes : `nova-cloud-init-template-dns-issue` (template
  9000), `nova-vlan60-admin-ip-layout` (admin IP), `ansible-control-plane-nova-vms`
  (SSH patterns), `winbind-fs01-uses-ldap-389` (post-Phase 7a).
