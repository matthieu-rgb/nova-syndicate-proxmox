# Knowledge Base : Realisations Nova Syndicate (etat 2026-05-27)

Etat factuel verifie a partir de STATUS.md, docs/INFRA-INVENTORY.md, docs/adr/INDEX.md,
des 33 ADRs et des outputs d'audit agents (agents/outputs/). Toute affirmation du
dossier projet doit pouvoir se rattacher a une ligne de ce fichier ou a un fichier du repo.

## Chiffres factuels verifies (source de verite - ne pas inventer)

### Inventaire VMs Proxmox (verifie via 'qm list' le 27 mai 2026)

VMs Linux de service (12 au total) :
- 100 web01 (DMZ, 1 GB)
- 101 mail01 (DMZ, 1 GB)
- 102 bastion01 (BASTION, 1 GB)
- 103 dc01 (SERVERS, 2 GB) - Active Directory Samba
- 104 fs01 (SERVERS, 2 GB) - Serveur de fichiers
- 105 db01 (SERVERS, 2 GB) - MariaDB
- 106 app01 (SERVERS, 6 GB) - Authelia + Grafana + Wazuh + Prometheus
- 107 proxy-lyon01 (1 GB) - [ROLE A CONFIRMER]
- 108 proxy-mrs01 (1 GB) - [ROLE A CONFIRMER]
- 109 backup01 (BACKUP, 2 GB) - Borg backup
- 110 vpn-gw01 (DMZ, 1 GB)
- 111 awx01 (ADMIN, 8 GB) - AWX K3s

Pare-feux OPNsense (3, pas 4) :
- 201 fw-ext-lyon01 - perimetre Lyon
- 202 fw-int-lyon01 - interne Lyon (defense en profondeur)
- 203 fw-ext-mrs01 - perimetre Marseille (pas d'interne car bureau regional)

Simulation reseau :
- 200 wan-simulator
- 9000 debian-12-cloud-template-nova (template, stopped)

### Roles Ansible (11 verifies)

backup, bastion, common, database, dc, fileserver, hardening, proxy, vpn, 
wazuh_agent, wazuh_manager

### Audit auto - findings (12 au total)

- 6 findings du pentest light (pentest-findings.json) dont 1 HIGH (LDAP anon 
  bind dc01)
- 6 findings de l'audit de regles (rules-conformity.json) dont R-006 MEDIUM 
  (debian NOPASSWD:ALL = least-privilege)

### Suricata

0 sonde active. Prototype tente sur FW-EXT-LYON, retire apres incident OOM 
(rollback Proxmox snapshot). Reintroduction sur VM dediee = roadmap residuelle.

### Score NIS2 article 21

Global : 7,9/10
- Segmentation : 9,5/10
- Access control : 8/10
- Logging : 8/10
- Least-privilege : 6/10

---

INSTRUCTION POUR LES FUTURES GENERATIONS : tout chiffre qui n'est pas dans cette 
section "Chiffres factuels verifies" doit etre marque [A VERIFIER] dans le 
draft plutot qu'invente.

## 1. Infrastructure deployee

- Plateforme : Proxmox VE 8.x bare-metal (ADR-0001), un seul hyperviseur physique.
- VMs : 12 VMs Linux (VMID 100-111, dont web01/proxy-lyon01/proxy-mrs01 legacy ou
  reservees) + 4 appliances OPNsense 25.1 (VMID 200-203, dont wan-simulator).
  Coeur operationnel : 10 VMs Linux avec roles Ansible appliques + 4 OPNsense.
- 2 sites simules : Lyon (siege) et Marseille (bureau regional), reseaux separes
  relies par un transit WAN simule (wan-simulator, VMID 200).
- Tunnels site-to-site : IPsec IKEv2, 4 child SAs (ADR-0005). Backend swanctl moderne,
  script d'auto-recovery `ipsec-recovery.sh` + cron */5 (ADR-0022). Invariant
  healthcheck : `swanctl --list-sas | grep -c 'INSTALLED, TUNNEL'` = 4.
- Acces distant : WireGuard road-warriors sur vpn-gw01 (port 51820/UDP, ADR-0006,
  ADR-0016) + Tailscale break-glass pour l'admin (ADR-0007, ADR-0021).

### Note de reconciliation -- etat IPsec

L'audit agents du 2026-05-26 (rules-auditor, report-writer) note "IPsec declare en IaC,
tunnel non operationnel". C'est une INFERENCE depuis le scanner awx01 (VLAN 60 ADMIN
Lyon) qui ne peut pas joindre le LAN Marseille -- segmentation attendue, pas une preuve
que le tunnel est down. Les docs operationnelles (INFRA-INVENTORY, invariant healthcheck
`swanctl`, ADR-0022 et son snapshot de reference `post-incident-recovery-2026-05-09`
= "IPsec 4 SAs baseline") traitent les 4 SAs comme l'invariant live supervise.
=> Dans le dossier : IPsec operationnel (4 SAs, auto-recovery), avec mention honnete
du caveat de vantage de l'audit. La dette technique #4 de STATUS.md ("strongSwan non
demarre, config GNS3 obsolete") est un reliquat de redaction Phase II, anterieur a
la stabilisation IPsec.

### Note de reconciliation -- plan d'adressage

Les ADRs de design (ex. ADR-0002, ADR-0005) citent un plan planifie en 10.0.x.x.
Le plan REELLEMENT deploye (INFRA-INVENTORY = verite terrain) est en 192.168.x.x.
=> Utiliser les adresses deployees dans le dossier ; citer ADR-0002 pour le principe
VLSM, pas pour les adresses 10.0.x.x obsoletes.

## 2. Topologie reseau deployee (verite terrain INFRA-INVENTORY)

VLANs internes Lyon (FW-INT-LYON comme gateway inter-VLAN) :

| Subnet | Zone | VLAN | Site |
|---|---|---|---|
| 192.168.15.0/29 | Bastion | 15 | Lyon |
| 192.168.20.0/28 | Servers (dc01, fs01, db01, app01) | 20 | Lyon |
| 192.168.30.0/26 | Users | 30 | Lyon |
| 192.168.50.0/29 | Backup (backup01) | 50 | Lyon |
| 192.168.60.0/29 | Admin / automation (awx01) | 60 | Lyon |
| 192.168.99.0/29 | Management OPNsense | - | inter-FW |
| 172.16.1.0/29 | DMZ Lyon (mail01, web01, vpn-gw01) | - | Lyon |
| 192.168.40.0/26 | LAN Marseille | - | Marseille |

Peerings : 10.0.0.0/30 (Box <-> FW-EXT-LYON), 10.0.1.0/30 (FW-EXT <-> FW-INT Lyon),
10.0.2.0/30 (WAN-SIM <-> FW-EXT-MRS).

Firewalls : double firewall Lyon (FW-EXT-LYON perimetre/WAN/IPsec + FW-INT-LYON
inter-VLAN) + FW-EXT-MRS perimetre Marseille. Pattern par interface : `pass`
specifiques puis `block all + log` final (default-deny trace pour audit NIS2).
Etat Terraform OPNsense : 55 regles filter (46 pass / 9 block), 12 alias, 5 routes.

## 3. VMs et services (extrait INFRA-INVENTORY)

- **dc01** (192.168.20.10) : Samba AD DC `nova-syndicate.local`, DNS interne, Kerberos KDC.
  ~94 users provisionnes (85 employes + comptes service/test). Verif :
  `samba-tool domain info 127.0.0.1`.
- **fs01** (192.168.20.11) : serveur de fichiers Samba, partages + ACL POSIX.
- **db01** (192.168.20.12) : MariaDB 10.x, bases `nova_portail` (+ futur `nova_logistique`,
  `nova_rh`), acces scope `nova_portail@192.168.20.13`.
- **app01** (192.168.20.13, 6 GB) : nginx reverse proxy, Authelia (MFA TOTP, backend LDAP),
  Grafana (4 dashboards), Prometheus, Wazuh manager 4.11.2 + indexer + filebeat,
  portail metier Flask (gunicorn), cloudflared. +2 GB swap ajoute (mitigation OOM).
- **bastion01** (192.168.15.2) : SSH MFA TOTP (pam_google_authenticator), ProxyJump.
- **backup01** (192.168.50.2) : depot Borg append-only `/srv/borg-repo`, pulls quotidiens
  dc01/db01/app01/fs01, rclone vers offsite (3-2-1-1-0).
- **vpn-gw01** (172.16.1.4 / wg0 10.20.0.1/24) : WireGuard road-warriors + policy routing.
- **awx01** (192.168.60.2, 8 GB) : K3s + AWX Operator, automation IAM, auth LDAP.
- **OPNsense** : FW-EXT-LYON (IPsec + Suricata #1), FW-INT-LYON (inter-VLAN + Suricata #2),
  FW-EXT-MRS (IPsec + Suricata #3), wan-simulator (transit ISP simule).

## 4. Decisions architecturales cles (33 ADRs, docs/adr/INDEX.md)

Les 12 ADRs les plus structurants pour le dossier :

- **ADR-0001** -- Proxmox VE comme hyperviseur (open source AGPL, API REST scriptable,
  cloud-init, snapshots ; rejets : ESXi free arrete par Broadcom, libvirt sans provider
  Terraform mature, VirtualBox).
- **ADR-0002** -- Plan d'adressage VLAN avec VLSM (RFC 1519/CIDR ; sizing par zone vs
  /24 uniforme ; reduit le blast radius ; /29 pour bastion et backup).
- **ADR-0003** -- Architecture dual firewall + transit DMZ (defense en profondeur : la
  compromission de FW-EXT laisse l'attaquant sur le transit, pas sur SERVERS ; clarte
  des rulesets : perimetre vs segmentation interne).
- **ADR-0004** -- OPNsense vs pfSense (provider Terraform browningluke couvre regles,
  IPsec, WireGuard, alias ; pfSense CE n'a pas d'equivalent ; API REST versionnee).
- **ADR-0005** -- IPsec IKEv2 site-to-site (4 child SAs, 1 par VLAN ponte ; isolation
  crypto par zone ; IKEv2 = RFC 7296, standard entreprise ; rejet WireGuard pour
  site-to-site multi-SA).
- **ADR-0008** -- BorgBackup repokey-blake2 + append-only (chiffrement client-side,
  immutabilite cote depot contre rancongiciel ; deduplication ; zstd).
- **ADR-0009** -- Strategie 3-2-1-1-0 (3 copies, 2 supports, 1 hors-site, 1 immutable,
  0 erreur non detectee via `borg check` + restore drill).
- **ADR-0013** -- Wazuh SIEM (NIS2 art.21.f : collecte centralisee, correlation, FIM,
  regles NIS2 custom 100001-100010 sur app01 ; rejet Elastic SIEM trop lourd, Splunk free limite).
- **ADR-0015** -- Role hardening Ansible custom (vs CIS automatise : ~100 lignes
  comprehensibles et soutenables vs 300+ taches opaques ; sshd, nftables, fail2ban,
  auditd, sysctl ; extensions per-host).
- **ADR-0018** -- MFA TOTP bastion (libpam-google-authenticator, RFC 6238 ; 2 facteurs
  SSH = cle + TOTP ; sudo = password + TOTP ; NIS2 art.21.b).
- **ADR-0019** -- Authelia portail MFA web (forward auth nginx, 1er facteur LDAP DC01,
  2e facteur TOTP ; SSO sur Grafana/Prometheus/Wazuh ; revocation centralisee via AD).
- **ADR-0020** -- Acces admin two-tier (Tier 1 operationnel MFA via bastion ; Tier 2
  break-glass Tailscale direct Proxmox ; verrou iptables FORWARD contre le bypass).
- **ADR-0025** -- Suricata multi-capteurs (3 IDS : perimetre Lyon, inter-VLAN Lyon,
  perimetre MRS ; couvre le lateral movement et les angles morts geographiques).
- **ADR-0031** -- AWX Operator sur K3s (plan d'automation IAM isole en VLAN 60 ; 7 job
  templates ; auth LDAP ; cle SSH dediee non-humaine ; audit -> Wazuh).
- **ADR-0033** -- AWX RBAC 4 Teams + mapping LDAP (separation of duties NIS2 :
  Officers create/enable, Managers full IAM, Auditors read-only ; AUTH_LDAP_TEAM_MAP).

Tous les ADRs sont au statut "Accepte".

## 5. Pipeline IaC

- **Terraform** : provider OPNsense browningluke 0.16 (regles FW, alias, interfaces VLAN,
  IPsec prep) + provider Proxmox (VMs cloud-init). 33+ ressources deployees.
- **Ansible** : 19 roles (common, hardening, dc, fileserver, database, app, website,
  portail, bastion, mfa_totp, mail_server, swap_file, vpn, vpn_gateway, proxy,
  wazuh_agent, wazuh_manager, wazuh_indexer, wazuh_filebeat). Vault AES-256, host_vars
  par VM. Playbook orchestrateur `site.yml`.
- **AWX** : K3s + Operator + auth LDAP + 4 Teams (RBAC NIS2) + 7 Job Templates IAM
  (user_create, user_delete, user_enable, user_grant_privilege, user_revoke_privilege,
  user_reset_password, users_rotate_bulk).
- **Qualite** : pre-commit hooks + CI gitleaks (ADR-0028). Conventional commits
  (sans attribution Claude/Anthropic). 33 ADRs documentes.

## 6. Automatisation (exigence 5.7 -- les DEUX options couvertes)

- **Creation utilisateurs depuis CSV** : `playbooks/create_users.yml` -- "Creation
  utilisateurs Samba AD depuis CSV", lit `files/new_users.csv` via `read_csv`, boucle
  `samba-tool user create` + `samba-tool group addmembers`. Industrialise dans AWX
  (job template `iam-user-create`).
- **Supervision seuil disque** : `playbooks/disk_alert.yml` -- `df -h /` parse l'usage,
  envoie un mail d'alerte si >= 80% (variable `seuil_alerte`).
- Bonus : `user_report.yml`, `backup_check.yml`, `maintenance/{update_all,rotate_secrets,
  backup_test}.yml`.

## 7. Supervision (exigence 5.5)

- Metriques systeme : Prometheus + node_exporter -> Grafana (CPU / memoire / disque).
- Uptime services : Wazuh manager + 7 agents Active (FIM, rootcheck, regles NIS2).
- Detection reseau : 3 IDS Suricata (perimetre + inter-VLAN + MRS), pipeline eve.json
  -> receiver UDP app01 -> wazuh-logcollector -> dashboard nova-ids-multi-capteurs.
- Single-pane-of-glass : 4 dashboards Grafana sur datasource OpenSearch (ADR-0030).

## 8. Conformite (audit auto -- PoC agents)

- 4 agents read-only : network-mapper (inventaire + drawio), pentest-light (nmap safe,
  ssh-audit, testssl, nuclei), rules-auditor (regles OPNsense vs ADRs + NIS2),
  report-writer (consolidation docx). Scanner = awx01 (VLAN 60).
- Outputs : AUDIT-NOVA-2026-05-26.{md,docx}, network-inventory.json,
  pentest-findings.{md,json}, rules-conformity.{md,json}, network-map.drawio.
- **Score NIS2 art.21 (heuristique PoC) : 7.9/10** -- segmentation 9, access control 8,
  least privilege 6.5, logging/detection 8.
- **Findings pentest : 6** (0 critical, 1 high, 3 medium, 2 low) + CVE heuristiques info.
  - HIGH : bind LDAP anonyme sur dc01 (root DSE expose, enumeration sous-arbre refusee).
  - MEDIUM : algos SSH faibles sur web01/mail01 (DMZ), cert mkcert dev sur app01:443,
    chaines PKI incompletes.
  - LOW : ordre des ciphers, cert auto-signe GUI OPNsense (attendu).
- **Findings conformite : 5** -- R-002 road-warriors trop larges (medium), R-001 IPsec
  prep (low), R-005 lab/prod (low), R-003 bypass SSH VLAN60 (info accepte, compense),
  R-004 (positif : 55/55 regles documentees, 0 orphan).
- Dette ouverte structurante : R-006 (sudoers NOPASSWD:ALL sur les SERVERS via la cle
  agents -> least-privilege 6/10), suivie dans STATUS.md.

## 9. Retours d'experience reels (gotchas a citer pour l'authenticite)

- OOM app01 : Grafana tuee par l'OOM-killer (stack lourde sur 6 GB), mitige par +2 GB
  swap (role `swap_file`), dette T-SPLIT-MONITORING-VM (sortir l'indexer).
- Watchdog wazuh-agent : l'unit `Type=forking RemainAfterExit=yes` ne se recupere pas
  avec `Restart=always` seul -> timer watchdog 30s.
- IAM espaces : `samba-tool` via `shell:` echouait sur les groupes a espace
  ("Domain Admins") -> passage en `argv:` (commit ansible 86fc623).
- nft vpn-gw01 : flush global wipait le mangle WireGuard -> flush chirurgical
  filter-only + handler `reloaded` (atomique) au lieu de `restarted`.
- Hypothese NAT double-firewall : une seule regle FW-INT suffit pour VLAN60 -> DMZ
  (NAT auto transparent), aucune regle FW-EXT necessaire.
- ssh_config catch-all et dedup, ansible-core 2.19 et le comportement des tags.
