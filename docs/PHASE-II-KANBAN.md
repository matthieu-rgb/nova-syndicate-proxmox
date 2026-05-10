# Phase II -- KANBAN Nova Syndicate OPNsense IaC
# Date : 2026-05-08

## Taches

### [x] T-MIGRATION -- IPsec legacy -> Connections moderne

Migration complete sur FW-EXT-LYON (initiator) et FW-EXT-MRS (responder).
4 Child SAs separes avec reqids distincts. Backend moderne natif.
Legacy Phase1/Phase2 supprimes. Scripts fix_ipsec_children supprimes.
Ref : docs/SESSION-LOG.md Phases 1-3.

### [x] T2 -- Internet BASTION -- CLOSED 2026-05-08

Diagnostic Phase 1 a revele que fwint_bastion_to_internet (enabled=true)
etait deja en place depuis Phase II IaC. BASTION01 (192.168.15.2)
atteignait internet sans modification :
- curl https://github.com -> HTTP/2 200
- DNS : 140.82.121.3 github.com (Unbound FW-INT-LYON)
- Route : default via 192.168.15.1 (vlan02 FW-INT-LYON)

Note : SERVERS/USERS/BACKUP ont aussi un acces internet "raw" via
leurs regles to_internet respectives (besoins legaux : apt, NTP, rclone B2).
Le filtrage granulaire par VLAN est reporte en T-SQUID.
Ref : docs/runbook-bastion-internet.md

### [x] T3 -- Durcissement firewall block_all + regles pass explicites COMPLETE 2026-05-09

Scope : remettre block_all=true sur les 8 interfaces avec regles pass
specifiques pour le trafic legitime AVANT de fermer.

Interfaces concernees (8 block_all actuellement false) :
- FW-INT-LYON : vtnet0 (WAN/transit) + opt1/opt2/opt3/opt4 (VLANs)
- FW-EXT-LYON : vtnet0 (WAN)
- FW-EXT-MRS : vtnet0 (WAN)
- WAN-SIM : vtnet0 (WAN)

Trafic a autoriser explicitement avant de fermer :
- IPsec : UDP 500, 4500 + ESP entre 10.0.0.2 (LYON) et 10.0.2.2 (MRS)
- Transit FW-INT <-> FW-EXT sur 10.0.1.0/30
- IKE management interfaces OPNsense (SSH, HTTPS admin)
- DNS/NTP sortants depuis VLANs internes
- Replies IPsec decapsules (192.168.40.0/26 -> VLANs Lyon et inverse)
- BASTION -> internet (fwint_bastion_to_internet deja OK)
- SERVERS/USERS/BACKUP -> internet (conserve pour apt/NTP/web/rclone,
  durcissement final en T-SQUID via proxy filtrant)

Risques critiques :
- Casser les 4 tunnels IPsec si oubli d'une regle pass ESP/IKE
- Se couper l'acces SSH management depuis le Mac si regle WAN trop stricte

Approche (une interface a la fois) :
1. Importer les regles existantes (IMPORT-ONLY) -> plan = No changes
2. Ecrire toutes les regles pass necessaires en Terraform
3. terraform plan -> revue complete du diff avant apply
4. Activer block_all sur UNE interface, tester immediatement :
   - 4 pings IPsec cross-site
   - SSH management OK
   - Si KO : ajouter regle pass manquante, reprendre
5. Repeter interface par interface
6. Supprimer en meme temps les 5 routes PARASITES (DT-1 audit)

Precautions operationnelles :
- Garder un terminal SSH OPNsense ouvert en permanence
- Avoir le script rollback-ipsec-migration.sh disponible
- Faire en debut de journee frais, pas en fin de session

Effort estime : 60-90 min (reel : ~3h session 2026-05-09)

Interfaces fermees (8/8) :
| Interface | FW | UUID block_all | Notes |
|---|---|---|---|
| vtnet0 WAN | WAN-SIM | e480ceaa | Clean |
| opt1 BACKUP | FW-INT-LYON | ac3427cc | Placeholder (pass-all avant block) |
| opt4 USERS | FW-INT-LYON | 17883b5f | Placeholder (pass-all avant block) |
| vtnet0 WAN | FW-EXT-MRS | e16e4a40 | Clean |
| vtnet0 WAN | FW-EXT-LYON | fa96cb54 | -replace fix (mauvais ordering initial) |
| opt3 SERVERS | FW-INT-LYON | b19da746 | Placeholder (pass-all avant block) |
| opt2 BASTION | FW-INT-LYON | ea6cf741 | Clean (regles granulaires) |
| vtnet0 WAN | FW-INT-LYON | 730f9aeb | Fix sequence via API (prepend bug) |

### Findings T3 -- Lecons systemiques OPNsense

#### Lecon 1 : -replace ne repositionne pas si OPNsense recycle le slot

Quand un block_all etait cree entre deux regles pass (config.xml creation order),
le -replace pouvait recycler le meme slot de sequence (position identique). Symptome :
block_all apparait en milieu de pfctl entre des pass rules. Detection : verifier
pfctl -sr | nl apres chaque apply. Fix : API setRule sequence ou double -replace
avec depends_on dans le bon sens.

#### Lecon 2 : OPNsense PREPEND les nouvelles regles (insere en tete)

Contrairement a ce qu'on attend (append), OPNsense place les nouvelles regles en tete
de la liste utilisateur. Consequence : la regle creee EN DERNIER apparait EN PREMIER
dans pfctl. Impact sur le double -replace avec depends_on : il faut creer la regle
la plus basse (prioritaire) EN DERNIER pour qu'elle se retrouve EN PREMIER.

#### Lecon 3 : champ sequence= expose par le provider v0.16

Le champ sequence (integer) est disponible dans opnsense_firewall_filter. Utiliser
sequence=1/2/N pour garantir l'ordre de maniere declarative et idem-potente.
Terraform plan = No changes quand sequence aligne avec OPNsense.

---

### [ ] T-FAIL2BAN-CLEANUP -- Debannissement BASTION01 (hors scope T3)

Identifie pendant T3 Interface 7. Fail2ban sur DC1/FS1/DB1/APP1/BACKUP01 a banni
192.168.15.2 (BASTION01) suite aux tests SSH automatises des sessions precedentes.
DB1 a aussi un host key change non accepte par BASTION.

Actions :
1. Sur chaque serveur : sudo fail2ban-client set sshd unbanip 192.168.15.2
2. Sur BASTION01 : ssh-keyscan 192.168.20.12 >> ~/.ssh/known_hosts (DB1 host key)
3. Retest depuis BASTION : ssh dc01/fs01/db01/app01/backup01 "hostname"

Effort estime : 15 min

---

## Dette technique restante

### [x] DT-1 -- 9 routes Terraform-orphan dans OPNsense -- CLOSED 2026-05-08

9 routes importees dans le state Terraform (terraform import x9).
terraform plan = "No changes" confirme.
Audit: 5 routes PARASITES identifiees, 4 NECESSAIRES conservees.
Routes parasites a supprimer lors de T3-DURCISSEMENT :
- wansim_to_lyon_internal_subnets
- wansim_to_mrs_lan
- wansim_to_lyon_transit
- fwext_to_mrs_lan
- fwextmrs_to_lyon
Ref : docs/SESSION-LOG.md section "T-IMPORT" + runbook section "Audit des routes statiques"

### DT-2 -- 8 block_all=false sur interfaces WAN/OPT

Etat actuel : block_all desactivees (debug) pour maintenir les tunnels UP.
Fichiers : fw_ext.tf, fw_ext_mrs.tf, fw_int.tf, fw_wansim.tf.
Cf. T3 ci-dessus pour le plan de durcissement.

### DT-3 -- IKE SA orphelin con1 (legacy)

SA #2 (con1) encore etablie sur FW-EXT-LYON (~82800s de lifetime restante).
Children 26-29 installes mais aucun trafic entrant. Expiration naturelle.
Aucune action requise, surveiller via swanctl --list-sas.

### DT-4 -- Terraform : aucun state IPsec/Connections

Les connexions IPsec modernes (UUIDs 78112723/cbe685dd) ne sont pas
gerees par Terraform. Migration faite manuellement via API Python.
A documenter ou ignorer (hors scope browningluke/opnsense v0.16).

---

## Nouvelles taches

### [ ] T-SQUID -- Forward proxy avec whitelist par VLAN

ALERTE T3 INTERFACE 3 (2026-05-09) : fwint_users_to_internet (UUID 435d8df8)
est un pass-all net_lyon_users -> any. Il se positionne AVANT fwint_users_block_all
dans pfctl (quick => le block ne s'active jamais pour les users). VLAN 30 non
filtre en l'etat. Meme audit a faire pour :
- fwint_servers_to_internet (VLAN 20, rule fwint_servers_to_internet)
- fwint_backup_to_internet  (VLAN 50, rule fwint_backup_to_internet)

Action T-SQUID obligatoire :
1. Remplacer fwint_*_to_internet par : source VLAN -> proxy-lyon01 port 3128 uniquement
2. Supprimer les regles to_internet pass-all apres validation Squid
3. La destination "any" doit rester uniquement pour BASTION (besoin dev tools valide)

Prerequis : T3 termine (block_all=true). Sans T3, Squid ne sert a rien
car le trafic peut bypasser le proxy par d'autres chemins.

Scope : deployer Squid sur proxy-lyon01 (deja dans alias host_proxy_lyon01,
192.168.20.x) avec politique differenciee par VLAN source.

Whitelist par VLAN :
- BASTION (15.0/29) : whitelist large dev tools
  github.com, registry.terraform.io, deb.debian.org, security.debian.org,
  pypi.org, hub.docker.com, registry-1.docker.io, galaxy.ansible.com,
  packages.debian.org, pythonhosted.org
- SERVERS (20.0/28) : whitelist stricte ops
  deb.debian.org, security.debian.org, pool.ntp.org,
  registry-1.docker.io, github.com, packages.microsoft.com,
  registry.terraform.io
- USERS (30.0/26) : categories Squid (work + news),
  blacklist streaming / social / gambling
- BACKUP (50.0/29) : whitelist minimale B2
  api.backblazeb2.com, f001.backblazeb2.com .. f100.backblazeb2.com

Configuration Squid :
- forwarded_for off (protection L7 -- ne pas exposer IP interne aux sites)
- access_log format JSON (ingestion Wazuh SIEM)
- Retention logs 30 jours (RGPD minimisation)
- TLS interception decline (preserve confidentialite, evite la complexite PKI)
- Mode : proxy explicite d'abord (HTTP_PROXY=http://proxy:3128),
  puis transparent si besoin (redir pf port 80/443 -> Squid)

Sequence :
1. Deployer et configurer Squid sur proxy-lyon01
2. Tester en mode explicite depuis chaque VLAN (curl --proxy)
3. Modifier FW-INT-LYON : rediriger port 80/443 des VLANs vers Squid
4. Basculer les regles *_to_internet de "to any" vers "to proxy-lyon01 port 3128"
5. Supprimer les regles to_internet "raw" apres validation

Effort estime : ~3h (réévalué T3 2026-05-09)
  - 60 min règles granulaires par VLAN (AD/Wazuh/Prometheus/intra-VLAN)
  - 90 min déploiement Squid + config
  - 30 min tests validation par VLAN

Raison du report des règles granulaires (décision T3 2026-05-09) :
Faire les règles granulaires maintenant sans Squid = double travail.
Quand Squid arrivera, les règles *_to_internet seront remplacées et les
granulaires devront tenir compte du passage proxy. Cohérent avec T3
Option A pour USERS et SERVERS (block_all placeholder).

### Dette T3 -- Pass-all a remplacer par granulaire en T-SQUID

| Interface     | Règle pass-all UUID | Flux à granulariser |
|---------------|---------------------|---------------------|
| opt4 USERS (vlan04)   | 435d8df8 | DC AD (53,88,389,445,464,636,3268) + FS SMB (445) + APP1 Wazuh (1514,1515) + Squid proxy (3128) -- supprime internet direct |
| opt3 SERVERS (vlan03) | 7c8e2113 | DC AD complet + intra-VLAN (DC<->FS<->DB<->APP) + BACKUP rsync (22) + APP1 Wazuh/Prom (1514,1515,9100) + cross-site MRS + Squid proxy -- supprime internet direct |
| opt1 BACKUP (vlan01)  | 502bd253 | Sortie internet via Squid uniquement (rclone B2 + apt + NTP) -- supprime pass-all |

Action pour chaque VLAN lors de T-SQUID :
1. Creer règles granulaires spécifiques (apply séparé)
2. Tester chaque flux avec pass-all encore actif
3. Supprimer la règle pass-all
4. Vérifier que block_all (déjà enabled) bloque bien le reste
5. Valider via pflog0 pendant 24h

---

## Session AFK 2026-05-09 -- Taches T-AFK-1 a T-AFK-7

### [>] T-AFK-1 -- Validation T3 + tag + prep

En cours. Validation croisee : 8/8 interfaces block_all actives, 4 tunnels
IPsec INSTALLED, cross-site Lyon<->MRS OK, services metier OK.

### [ ] T-AFK-2 -- Whitelist fail2ban BASTION

fail2ban sur DC1/FS1/APP1/BACKUP01 -- whitelist 192.168.15.0/29 (subnet BASTION).
Idempotent via /etc/fail2ban/jail.d/00-nova-whitelist.conf.

### [ ] T-AFK-3 -- Cle SSH BASTION vers 6 hotes

Deploy pubkey BASTION01 sur DC1, FS1, APP1, BACKUP01, proxy-lyon01, WEB01.
Authorized_keys uniquement (pas de sshd_config change).

### [ ] T-AFK-4 -- nginx WEB01 + page placeholder

WEB01 (172.16.1.2) : nginx start + page placeholder Nova Syndicate.
Headers securite basiques (sans HSTS/TLS). Loopback only = non, DMZ interne.

### [ ] T-AFK-5 -- Squid PROXY-MRS01

proxy-mrs01 (192.168.40.11) : config copiee de proxy-lyon01, ACL adaptees
pour LAN MRS (192.168.40.0/26). Port 3128.

### [ ] T-AFK-6 -- Postfix + Dovecot MAIL01 minimal

MAIL01 (172.16.1.3) : inet_interfaces=loopback-only. Pas d'ecoute externe.
Config sandbox uniquement, prod avec LDAP/DKIM apres retour.

### [ ] T-AFK-7 -- Grafana imports dashboards

APP1 (192.168.20.13) : import dashboards officiels + custom Nova Overview.
Datasource Prometheus si non configure.

---

## Backup hors-site

### [x] T-WAZUH-NFT -- Perenniser regle nftables port 1514 dans Ansible -- DONE 2026-05-10

Regle tactique post-incident IPsec perennisee via wazuh_manager_listeners dans
host_vars/app01.yml. Template nftables.conf.j2 etendu avec boucle conditionnelle.
1514 retire de la regle unrestricted dans app_servers/vars.yml.
Drifts detectes et corriges en passant : 9100 perennise, SSH /24->/29 bastion,
192.168.18.0/24 Proxmox admin ajoutee.
Ref : commit cebb6c2

### [x] T-WG-SERVER-VPS-BACKUP -- WireGuard concentrateur backup VPS Hetzner -- DONE 2026-05-10

Tunnel WireGuard 10.30.0.0/24 entre VPS (10.30.0.1) et BACKUP01 (10.30.0.2).
wg-quick@wg0 enabled et active sur les 2 noeuds. Ping bidirectionnel OK ~39ms.
PersistentKeepalive=25 cote BACKUP01. Cohabitation Tailscale preservee.
Ref : docs/T-WG-SERVER-VPS-BACKUP-LOG.md + docs/runbook-wireguard-vps.md

### [x] T-CLOUD-BACKUP-PREP -- Borg server sur VPS -- DONE 2026-05-10

- borgbackup 1.2.8 installe sur VPS
- borguser cree, /srv/borg-repo/nova-syndicate/ (700 borguser:borguser)
- sshd Match borguser : ForceCommand borg serve --append-only, PermitTTY no
- Cle SSH dediee /root/.ssh/id_ed25519_borg-cloud generee sur BACKUP01
- authorized_keys : from="10.30.0.2" + command= (double restriction)
- UFW : SSH TCP 22 sur wg0 ajoutee pour le tunnel
- Repo init repokey-blake2, passphrase dans /etc/borg/passphrase
- Premier backup test-2026-05-10-1740 OK (0.09s, append-only)
- Quota monitoring cron 23h00 (alerte si > 15 GB dans syslog)
- DETTE T-TAILSCALE-SSH-HARDEN : Tailscale SSH bypasse sshd ForceCommand
Ref : docs/T-CLOUD-BACKUP-PREP-LOG.md + docs/runbook-borg-cloud.md

### [x] T-CLOUD-BACKUP-DEPLOY -- Cron backup Borg + script production -- DONE 2026-05-10

Script /usr/local/bin/borg-cloud-sync.sh production sur BACKUP01.
Sources : /var/backups/borg, /var/backups/from-db1, /etc. Compression zstd.
Cron /etc/cron.d/borg-cloud-backup : 23h30 daily. Retention 7d/4w/6m.
Lock file anti-concurrence. Mode --dry-run. Logging syslog + fichier.
Premier backup reel pousse (backup01-2026-05-10-2110, 13.32 MB compresse).
Ref : docs/T-CLOUD-BACKUP-DEPLOY-LOG.md + docs/runbook-borg-cloud.md

### [x] T-RESTORE-DRILL -- Valider restauration depuis VPS Hetzner -- DONE 2026-05-10

Restore complet (836 fichiers, 14.92 MB) en 14.6s depuis backup01-2026-05-10-2110.
5/5 checksums MD5 OK. Comptage fichiers exact (borg: 48, db1: 12).
Restore partiel (etc/borg uniquement) : isolation parfaite.
3 procedures DR documentees dans runbook-borg-cloud.md (complet, partiel, from-scratch).
Ref : docs/T-RESTORE-DRILL-LOG.md + docs/runbook-borg-cloud.md

## Phase II BACKUP cloud -- ENTIEREMENT BOUCLEE 2026-05-10

T-WG-SERVER-VPS-BACKUP + T-CLOUD-BACKUP-PREP + T-CLOUD-BACKUP-DEPLOY + T-RESTORE-DRILL
