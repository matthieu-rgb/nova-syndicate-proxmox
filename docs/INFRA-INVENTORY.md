# Nova Syndicate -- Inventaire infrastructure

Dernière mise à jour : 2026-05-19 (T-WAZUH-INDEXER-INSTALL + T-WAZUH-SURICATA-INTEGRATION)

Document de référence pour l'infra Nova Syndicate. Pour les détails de design et les choix d'architecture, voir `docs/adr/`. Pour les procédures opérationnelles, voir `docs/runbook/`.

## Vue d'ensemble

Deux sites interconnectés via tunnel IPsec IKEv2 (4 SAs) :

- **Lyon (siège)** : Proxmox 10 VMs, 4 VLANs internes, 1 DMZ, 1 firewall périmétrique + 1 firewall interne.
- **Marseille (filiale)** : 1 firewall périmétrique (FW-EXT-MRS) + LAN 192.168.40.0/26. VMs MRS hors scope J1/J2.

Site internet exposé : `nova.0xmatthieu.dev` via Cloudflare Tunnel (cf. [ADR-0024](adr/ADR-0024-exposition-publique-cloudflare.md)).

## VMs Proxmox (10 running)

| VMID | Hostname | Role | IP | RAM | OS | Statut |
|---|---|---|---|---|---|---|
| 100 | web01 | (legacy, non utilise) | - | 1 GB | Debian 12 | running |
| 101 | mail01 | Postfix + Dovecot + OpenDKIM (T-MAIL-PROD) | 172.16.1.3 (DMZ) | 2 GB (1G effectif tant que pas reboot) | Debian 12 | running |
| 102 | bastion01 | Bastion SSH + MFA TOTP | 192.168.15.2 | 1 GB | Debian 12 | running |
| 103 | dc01 | Samba AD DC (nova-syndicate.local) | 192.168.20.10 | 2 GB | Debian 12 | running |
| 104 | fs01 | File server SMB | 192.168.20.11 | 2 GB | Debian 12 | running |
| 105 | db01 | MariaDB | 192.168.20.12 | 2 GB | Debian 12 | running |
| 106 | app01 | Web stack (nginx, Authelia, Grafana, Wazuh manager + indexer + filebeat, portail metier, cloudflared) | 192.168.20.13 | 6 GB | Debian 12 | running |
| 107 | proxy-lyon01 | (reserve future) | - | 1 GB | Debian 12 | running |
| 108 | proxy-mrs01 | (reserve future MRS) | - | 1 GB | Debian 12 | running |
| 109 | backup01 | Borg backup repo | 192.168.50.2 | 2 GB | Debian 12 | running |
| 110 | vpn-gw01 | WireGuard road-warriors | 192.168.30.2 | 1 GB | Debian 12 | running |
| 200 | wan-simulator | Simule Internet Lyon-MRS (peering 10.0.x.x) | (interne) | 512 MB | tinycore | running |
| 201 | fw-ext-lyon01 | OPNsense WAN Lyon + IPsec + Suricata #1 | 10.0.0.2 / 192.168.18.51 / 10.0.1.1 / 172.16.1.1 | 4 GB | OPNsense 25.1 | running |
| 202 | fw-int-lyon01 | OPNsense FW interne Lyon + Suricata #2 | 10.0.1.2 / 192.168.99.1 / 192.168.{20,30,50}.1 / 192.168.15.1 | 4 GB | OPNsense 25.1 | running |
| 203 | fw-ext-mrs01 | OPNsense WAN MRS + IPsec + Suricata #3 | 10.0.2.2 / 192.168.40.1 | 4 GB | OPNsense 25.1 | running |

Snapshots conservés comme références (rollback rapide) :
- `pre-portail-metier-mvp-2026-05-17` (avant deploiement portail)
- `pre-exposition-publique-2026-05-18` (VMID 201, 106)
- `pre-suricata-fw-int-2026-05-18` (VMID 202)
- `pre-suricata-fw-ext-mrs-2026-05-18` (VMID 203)
- `post-incident-recovery-2026-05-09` (IPsec 4 SAs baseline)
- `pre-t-wazuh-indexer-install-2026-05-18` (VMID 106 -- avant install indexer)
- `pre-t-wazuh-suricata-integ-2026-05-18` (VMID 201, 202, 203, 106 -- avant Suricata integration)

## Réseaux & VLANs

| Subnet | Usage | Gateway | Site | VLAN | Bridge Proxmox |
|---|---|---|---|---|---|
| 192.168.18.0/24 | LAN Box Huawei + alias FW-EXT-LYON | 192.168.18.1 (Box) | Lyon | (untagged) | vmbr0 |
| 10.0.0.0/30 | Peering Box <-> FW-EXT-LYON | 10.0.0.1 (Box) | Lyon | - | vmbr0 |
| 10.0.1.0/30 | Peering FW-EXT-LYON <-> FW-INT-LYON | 10.0.1.1 (FW-EXT) | Lyon | - | vmbr4 |
| 10.0.2.0/30 | Peering WAN-SIM <-> FW-EXT-MRS | 10.0.2.1 (WAN-SIM) | Inter-sites | - | vmbr2 |
| 172.16.1.0/29 | DMZ Lyon (mail01) | 172.16.1.1 (FW-EXT-LYON) | Lyon | - | vmbr3 |
| 192.168.15.0/29 | Bastion | 192.168.15.1 (FW-INT-LYON) | Lyon | 15 | vmbr1.15 |
| 192.168.20.0/28 | Servers Lyon (DC, FS, DB, APP) | 192.168.20.1 (FW-INT-LYON, **double** sur Proxmox secondary) | Lyon | 20 | vmbr1.20 |
| 192.168.30.0/26 | Users Lyon | 192.168.30.1 (FW-INT-LYON) | Lyon | 30 | vmbr1.30 |
| 192.168.40.0/26 | LAN Marseille | 192.168.40.1 (FW-EXT-MRS) | Marseille | - | vmbr2 |
| 192.168.50.0/29 | Backup | 192.168.50.1 (FW-INT-LYON) | Lyon | 50 | vmbr1.50 |
| 192.168.99.0/29 | Management OPNsense (FW-INT) | 192.168.99.1 (FW-INT-LYON) | Inter-FW | - | vmbr1 |

**Conflit IP connu** : Proxmox a une IP secondary `192.168.20.1/28` sur `vmbr1.20`, en doublon avec FW-INT-LYON vlan03. Origine historique (J0 bootstrap). Pas de symptôme observé : ARP race tolère car les hosts (APP01 etc) utilisent toujours le FW-INT-LYON comme gateway effective. À nettoyer en Phase IV (T-PROXMOX-IP-CLEANUP).

## Services par VM

### DC01 (Samba AD DC)

- `samba-ad-dc` : Domain Controller `nova-syndicate.local`
- DNS interne pour `*.nova-syndicate.local`
- Kerberos KDC (port 88)
- ~85 users provisionnes via Ansible playbook `create_users.yml`
- Verification rapide : `samba-tool domain info 127.0.0.1`

### DB01 (MariaDB)

- `mariadb` : 10.x
- Bases : `nova_portail`, (futur) `nova_logistique`, `nova_rh`
- User : `nova_portail@192.168.20.13` (SELECT/INSERT/UPDATE)
- ~30 tarifs/services enregistres dans `nova_portail.tarifs`
- Verification : `mysql -u root -e "SHOW DATABASES;"`

### APP01 (Web stack -- 6 GB RAM)

- `nginx` : Reverse proxy + sites statiques + vhosts
  - `website.conf` : www.nova-syndicate.local (cert wildcard mkcert)
  - `website-public.conf` : nova.0xmatthieu.dev (cert origin self-signed, expose via Cloudflare Tunnel)
  - `portail.conf` : portail.nova-syndicate.local (Authelia protected)
- `authelia` : Auth + MFA TOTP, backend LDAP DC01
- `grafana-server` : Monitoring frontend (port 3000)
- `prometheus` : Metrics collector (port 9090)
- `wazuh-manager` 4.11.2 : SIEM manager (7 agents Active)
- `wazuh-indexer` 4.11.2 : OpenSearch 2.16.0 single-node, bound 127.0.0.1:9200, JVM 1G heap, cluster `wazuh-cluster-local`
- `filebeat` 7.10.2 : module Wazuh, ship `/var/ossec/logs/alerts/alerts.json` -> indexer
- `nova-portail.service` : Flask gunicorn 4 workers (port 8000)
- `cloudflared` : Tunnel Zero Trust vers Cloudflare (sortie QUIC, no port entrant)

Packages tenus en hold (`dpkg --set-selections`) pour eviter upgrade automatique :
`wazuh-manager`, `wazuh-indexer`, `filebeat` (alignement strict des versions).

Pipeline data flow : `agents -> wazuh-manager -> alerts.json -> filebeat (module wazuh)
-> wazuh-indexer https://127.0.0.1:9200 -> index wazuh-alerts-4.x-YYYY.MM.DD
-> grafana datasource grafana-opensearch-datasource (uid wazuh-opensearch) -> 4 dashboards`.

Pipeline IDS Suricata (T-WAZUH-SURICATA-INTEGRATION 2026-05-19) :
`Suricata 3 OPNsense -> eve.json local -> /usr/local/sbin/suricata-eve-forwarder.sh
(tail -F + nc -u) -> app01:5141/UDP -> /usr/local/sbin/udp-log-receiver.py (User=wazuh)
-> /var/log/suricata-fw.log -> wazuh-logcollector (log_format=json) -> decoder json
-> rules 86600-86699 -> alerts.json -> indexer -> dashboard nova-ids-multi-capteurs`.

Composants additionnels sur app01 : `udp-log-receiver.py` (systemd unit `suricata-fw-receiver`),
nftables rule autorisant UDP 5141 et 514 depuis les 3 sources FW
(`/etc/nftables.d/suricata-syslog.nft`), `net.ipv4.conf.all.rp_filter=2`
(`/etc/sysctl.d/99-rp-filter.conf`).

### FW-EXT-LYON (OPNsense 25.1)

- `pf` : Firewall + NAT
- `strongSwan` : IPsec 4 SAs vers MRS
- `suricata` : IDS WAN (capteur #1, ~3-5k regles ET Open)
- Script auto-recovery IPsec : `/usr/local/sbin/ipsec-recovery.sh` + cron */5
- Alias `192.168.18.51` sur vtnet0 pour dispatch potentiel exposition publique (dormant cf. ADR-0024)

### FW-INT-LYON (OPNsense 25.1)

- `pf` : Firewall + NAT (mode hybrid, ~22 rules user)
- `suricata` : IDS interne (capteur #2, focus lateral movement)
  - Ecoute sur wan + opt2 Bastion + opt3 Servers + opt4 Users
  - Rulesets : emerging-{scan,attack_response,exploit,current_events,malware,mobile_malware}
- Pas de SSH user "debian" (acces uniquement via console / API HTTPS sur 192.168.99.1)

### FW-EXT-MRS (OPNsense 25.1)

- `pf` : Firewall + NAT
- `strongSwan` : IPsec 4 SAs vers Lyon (peer 10.0.0.2 via WAN-SIM)
- `suricata` : IDS WAN + LAN MRS (capteur #3)
- Ecoute sur vtnet0 + vtnet1, rulesets minimum 4 categories

### BASTION01

- SSH MFA TOTP (`pam_google_authenticator`) sur user `debian`
- Pas de mot de passe SSH (clés uniquement)
- ProxyJump destination pour atteindre les VMs internes

### BACKUP01

- BorgBackup repo append-only `/srv/borg-repo`
- Compte `borg` SSH-only
- Pulls quotidiens depuis DC01, DB01, APP01, FS01
- Rclone vers Backblaze B2 pour l'offsite (3-2-1-1-0, cf. ADR-0009)

### VPN-GW01

- WireGuard road-warriors (port 51820/UDP)
- Policy routing pour clients VPN -> VLANs internes
- Cle privee chiffree via Ansible vault

## Accès administratif (3 tiers)

### Tier 0 -- Break-glass

- **Tailscale Proxmox direct** : `ssh root@100.112.113.2`
- Mac Tailscale IP : 100.67.171.31
- Usage : recovery, snapshot rollback, accès quand le bastion est down
- **Aucun MFA** : protection via Tailscale tailnet + clé SSH

### Tier 1 -- SSH bastion MFA

- `ssh debian@192.168.15.2` (TOTP requis)
- ProxyJump via bastion : `ssh -J debian@192.168.15.2 debian@<IP>`
- Usage : admin courante des VMs Linux (DC01, DB01, APP01, FS01, BACKUP01)
- **PAS d'accès SSH** : aux firewalls OPNsense (utiliser API HTTPS)

### Tier 2 -- VPS Hetzner

- `ssh matthieu@100.94.199.97` (Tailscale)
- `ssh root@46.62.138.33` (direct, parfois bloque par FAI side)
- Usage : tests externes (curl publique), pivot d'investigation

### API OPNsense

- FW-EXT-LYON : `https://10.0.1.1/api/` (depuis Lyon LAN) ou `https://172.16.1.1/api/`
- FW-INT-LYON : `https://192.168.99.1/api/` (depuis Proxmox vmbr1)
- FW-EXT-MRS : `https://192.168.40.1/api/` (depuis Proxmox vmbr2)
- Clés API : `~/Documents/Nova-syndicate-Code/nova-iac-secrets/apikey-*.txt`

## Vérifications rapides (invariants)

### Invariants critiques quotidiens

```bash
# Healthcheck complet (10 sections, exit 0 si OK)
bash ~/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/scripts/healthcheck.sh

# IPsec : 4 SAs
ssh opn-fw-ext-lyon "swanctl --list-sas | grep -c 'INSTALLED, TUNNEL'"
# attendu : 4

# Wazuh agents : 7
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  'sudo /var/ossec/bin/agent_control -l | grep -c Active'
# attendu : 7

# Suricata 3 capteurs
bash ~/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/scripts/opnsense/suricata-multi-test.sh
# attendu : 3 passed

# Site public Tunnel
curl -sI https://nova.0xmatthieu.dev/ | head -1
# attendu : HTTP/2 200
```

### Status services par VM

| VM | Commande |
|---|---|
| DC01 | `systemctl is-active samba-ad-dc smbd nmbd` |
| DB01 | `systemctl is-active mariadb` |
| APP01 | `systemctl is-active nginx authelia nova-portail grafana-server prometheus wazuh-manager cloudflared` |
| BACKUP01 | `systemctl is-active borg-receive` (custom unit, ou check `borg info` direct) |
| FW-EXT-LYON | `pgrep strongswan && pgrep suricata` |
| FW-INT-LYON | API `/api/ids/service/status` |
| FW-EXT-MRS | `pgrep strongswan && pgrep suricata` |

## Procédures de recovery

### Si IPsec down (< 4 SAs)

1. `ssh opn-fw-ext-lyon "systemctl status strongswan"`
2. Lancer manuel : `ssh opn-fw-ext-lyon "/usr/local/sbin/ipsec-recovery.sh"`
3. Si echec : `ssh opn-fw-ext-lyon "configctl ipsec reload"`
4. Si toujours echec : rollback snapshot `post-incident-recovery-2026-05-09` (cf. [ADR-0022](adr/ADR-0022-ipsec-stability-script.md))

### Si nova-portail down

1. `systemctl status nova-portail` sur APP01
2. Logs : `journalctl -u nova-portail -n 50` ou `tail /var/log/nova-portail/error.log`
3. Restart : `systemctl restart nova-portail`
4. Verifier DB : `mysql -u nova_portail -h 192.168.20.12 nova_portail -e "SELECT 1;"`

### Si Authelia down

1. Verifier config : `authelia --config /etc/authelia/configuration.yml validate`
2. Restart : `systemctl restart authelia`
3. Verifier session URL : `auth.nova-syndicate.local` doit etre dans config

### Si nova.0xmatthieu.dev renvoie 502

1. Verifier `cloudflared` : `systemctl status cloudflared` sur APP01
2. Si stopped : `systemctl start cloudflared`
3. Logs : `journalctl -u cloudflared -n 50` -- chercher "Registered tunnel connection"
4. Cf. runbook [docs/runbook/nova-website.md](runbook/nova-website.md) section troubleshooting

### Si un firewall (FW-INT ou FW-EXT-MRS) ne boot pas après reboot

1. Console serie via `qm terminal <vmid>` (depuis Proxmox)
2. Rollback snapshot pre-reboot : `qm rollback <vmid> pre-suricata-<fw>-2026-05-18`

## Snapshots Proxmox (politique)

Convention : `pre-<change>-YYYY-MM-DD` ou `pre-<change>-YYYY-MM-DD-HHMMSS` pour les changements multiples le même jour.

Retention :
- `pre-*` : 7 jours
- `post-validated-*` ou snapshots de référence : 30+ jours

Snapshots de référence permanents :
- `post-incident-recovery-2026-05-09` (IPsec 4 SAs baseline)
- `pre-suricata-2026-05-12` (avant Suricata, avant lessons-learned RAM)
- `suricata-actif-ruleset-min-2026-05-17` (etat FW-EXT-LYON valide après hot-add RAM)
- `pre-portail-metier-mvp-2026-05-17` (etat avant deploiement portail)
- `pre-exposition-publique-2026-05-18` (VMID 201, 106 -- avant J2 Combo)
- `pre-suricata-fw-int-2026-05-18` (VMID 202 -- avant J2)
- `pre-suricata-fw-ext-mrs-2026-05-18` (VMID 203 -- avant J2)
- `pre-t-wazuh-indexer-install-2026-05-18` (VMID 106 -- avant install wazuh-indexer + filebeat)
- `pre-t-wazuh-suricata-integ-2026-05-18` (VMID 201, 202, 203, 106 -- avant integration Suricata 3 capteurs)

## Dettes ouvertes (post T-WAZUH-INDEXER-INSTALL)

- ~~**T-WAZUH-SURICATA-INTEGRATION**~~ : RESOLUE 2026-05-19. Les 3 Suricata
  OPNsense forward leur eve.json en JSON pur via UDP 5141 vers un receiver
  Python sur app01 qui ecrit dans `/var/log/suricata-fw.log`. Wazuh
  logcollector decode (json + rules 86600-86699). 4/4 dashboards OK. Voir
  ADR-0030 section "Integration Suricata 3 capteurs".
- **T-SPLIT-MONITORING-VM** : si la charge monte, deplacer
  wazuh-indexer + grafana + prometheus sur une VM dediee (107 ou nouvelle).
  Aujourd'hui app01 6 GB OK pour le labo.
- **T-WAZUH-INDEXER-ALIAS-DAILY** : creer un alias rollover
  `wazuh-alerts -> wazuh-alerts-4.x-*` pour faire taire le health check
  Grafana qui renvoie "Index not found" (cosmetique, queries fonctionnent).
- **T-WAZUH-VAULT-INDEXER-PWD** : ajouter `vault_wazuh_indexer_admin_password`
  au vault Ansible (chiffre) au lieu du fichier env Grafana en clair.
- **T-GRAFANA-AUTHELIA-SSO** : OAuth/OIDC contre Authelia, permissions par
  groupe AD (`Lyon-Staff` viewer, `Lyon-Admins` editor).
- **T-GRAFANA-13-ADMIN-RESET-BUG** : `grafana-cli admin reset-admin-password`
  ne met pas a jour le bon backend en Grafana 13 unified-storage.
  Contournement : update direct du hash PBKDF2 dans `user.password`.

## Roles Ansible (deployés)

| Role | VMs | Description |
|---|---|---|
| `common` | tous | Base hardening + ntp + locale FR + zoneinfo |
| `hardening` | tous | SSH hardening + fail2ban + auditd |
| `dc` | DC01 | Samba AD + users + groupes |
| `fileserver` | FS01 | Samba shares + ACL POSIX |
| `database` | DB01 | MariaDB + bases nova_* |
| `app` | APP01 | Stack web (deprecated, eclate en sous-roles) |
| `website` | APP01 | Site public statique + vhost public exposition |
| `portail` | APP01 | Portail metier Flask gunicorn |
| `bastion` | BASTION01 | SSH MFA TOTP setup |
| `mfa_totp` | BASTION01, (à étendre) | pam_google_authenticator |
| `wazuh_manager` | APP01 | Wazuh manager + dashboards |
| `wazuh_agent` | DC01, FS01, DB01, APP01, BASTION01, BACKUP01 | Wazuh agent enrolment |
| `backup` | BACKUP01 | Borg repo + cron pull + rclone B2 |
| `vpn` | (futur) | OpenVPN serveur (P4) |
| `vpn_gateway` | VPN-GW01 | WireGuard road-warriors + policy routing |
| `proxy` | (futur) | nginx reverse proxy DMZ |

Playbook orchestrateur : `site.yml` (déploie tout dans l'ordre).

## Terraform deployments

- `terraform/environments/lyon/` : VMs Proxmox via `telmate/proxmox` + règles FW via `browningluke/opnsense`
- `terraform/environments/mrs/` : (futur) homologue pour Marseille
- State : local `terraform.tfstate` (non versionné, dans `nova-iac-secrets/`)

Modules :
- VM provisioning (cloud-init)
- OPNsense firewall filter rules
- WireGuard config server-side

## Exposition publique (résumé)

Cf. [ADR-0024](adr/ADR-0024-exposition-publique-cloudflare.md) et [docs/runbook/nova-website.md](runbook/nova-website.md).

- `nova.0xmatthieu.dev` -> CNAME Cloudflare Tunnel auto -> `<tunnel-id>.cfargotunnel.com`
- Tunnel sortant QUIC depuis APP01 cloudflared -> Cloudflare edge Paris CDG (4 conn)
- Aucun port entrant ouvert sur Box Huawei
- Le portail métier reste interne (jamais publié)

## Sécurité : SIEM, IDS, segmentation

- 1 SIEM : Wazuh manager sur APP01, 7 agents Active
- 3 IDS : Suricata sur FW-EXT-LYON, FW-INT-LYON, FW-EXT-MRS (cf. [ADR-0025](adr/ADR-0025-suricata-defense-in-depth.md))
- Segmentation 4 VLANs internes (Bastion / Servers / Users / Backup) avec FW-INT-LYON entre chaque
- MFA TOTP sur bastion SSH ET sur portail Authelia
- Backup 3-2-1-1-0 (Borg + B2 + offline jamais teste)

## Documents associés

- ADRs : `docs/adr/ADR-0001..ADR-0025.md`
- Runbooks : `docs/runbook/{nova-website,nova-portail,cert-wildcard-mkcert,suricata-fw-ext-lyon}.md`
- Scripts ops : `scripts/{healthcheck,health-check,rollback-ipsec-migration}.sh`
- Scripts OPNsense : `scripts/opnsense/{ipsec-recovery,suricata-test,suricata-multi-test,exposition-publique-apply,suricata-homenet-fix}.sh`
- Incident reports : `docs/incidents/`, `docs/AFK-*.md`
