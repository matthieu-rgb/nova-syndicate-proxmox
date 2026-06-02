# Rapport -- Migration LDAPS Dovecot mail01 (Phase 6.3 + 6.6)

**Date** : 2026-06-02
**Ticket** : T-LDAPS-MIGRATION
**Runbook autoritatif** : [runbook-ldaps-migration.md](runbook-ldaps-migration.md)
**ADR de cloture (a creer)** : ADR-0034
**Statut** : RESOLU (Phase 6.3 + 6.6 OK ; **STOP avant Phase 7**, validation manuelle requise)

---

## Resume executif

Bascule du trust anchor LDAPS de Dovecot (mail01) de l'ancienne CA mkcert
(`/etc/ssl/certs/nova-CA.crt`) vers la chaine PKI interne step-ca
(`/etc/ssl/certs/ca-certificates.crt`, incluant Nova Root + Intermediate),
et durcissement `tls_require_cert = demand -> hard`. L'auth `svc-mail-ldap`
qui etait **cassee depuis le rollover step-ca du 1er juin** (cert dc01:636
emis par Intermediate CA, non valide par mkcert) est restauree.

Aucun residu LDAP cleartext (port 389) ne subsiste cote mail01 (tcpdump 25 s
+ trafic auth force : 0 paquet).

---

## Ecart vs plan reconstruit (declare en transparence)

Le plan reconstruit decrivait une bascule `ldap://` -> `ldaps://`. L'etat
runtime au demarrage etait deja `uris = ldaps://dc01.nova-syndicate.local:636`
(verifie). Le delta reel etait :

| Cle | Avant | Apres |
|-----|-------|-------|
| `uris` | `ldaps://dc01.nova-syndicate.local:636` | inchange |
| `auth_bind` | `yes` | inchange |
| `ldap_version` | `3` | inchange |
| `tls_require_cert` | `demand` | **`hard`** |
| `tls_ca_cert_file` | **`/etc/ssl/certs/nova-CA.crt`** (mkcert) | **`/etc/ssl/certs/ca-certificates.crt`** (system trust : step-ca Root + Intermediate) |

Le bloc `tls = yes` du runbook a ete **volontairement omis** : redondant
voire conflictuel avec `uris = ldaps://` (TLS implicite). Edition chirurgicale
via `sed` sur les 2 lignes ci-dessus uniquement, le reste du fichier
preserve. Diff capture (etape 6).

---

## Chronologie executive

| Etape | Action | Resultat | Timestamp UTC+2 |
|-------|--------|----------|-----------------|
| 1 | Snapshot Proxmox `mail01-pre-ldaps-mail` (VMID 101) + `dc01-pre-mail-ldaps` (VMID 103) | OK, listsnapshot verifie | 09:14:04 |
| 2 | Deploiement `nova-root.crt` + `nova-intermediate.crt` sur mail01 via `qm guest exec` + base64 (root_ca 700 B, intermediate 757 B) depuis pki01 (192.168.60.4) | OK, subject/issuer corrects | 09:14 |
| 3 | `update-ca-certificates` sur mail01 | `2 added, 0 removed; done.` ; hashes `9cd999c5.0`, `a907fcab.0` crees | 09:15 |
| 4 | `openssl s_client -connect dc01.nova-syndicate.local:636` depuis mail01 | **`Verify return code: 0 (ok)`** ; subject `CN=dc01.nova-syndicate.local` ; issuer Nova Intermediate CA | 09:16 |
| 5 | Backup `auth-ldap.conf.ext` + `dovecot-ldap.conf.ext` + `10-auth.conf` -> `.bak-preldaps-2026-06-02` | OK, 3 fichiers presents | 09:16 |
| 6 | Edit chirurgical `dovecot-ldap.conf.ext` (sed sur 2 lignes seulement) | Diff conforme, autres cles preservees | 09:17 |
| 7 | `systemctl restart dovecot` | `active` ; ports 143/993 LISTEN (IPv4 + IPv6) | 09:17 |
| 8 | `doveadm auth test svc-mail-ldap@nova-syndicate.local` | **`passdb: ... auth succeeded`** (etat AVANT : `auth failed code=temp_fail`, cause confirmee dans `/var/log/dovecot.log` : `Can't connect to server: ldaps://dc01...:636` a 07:17:12) | 09:18 |
| 9 | Rollback (si KO) | **Non requis** (etape 8 OK) | -- |
| 10 | Cross-checks (Wazuh / Authelia / AD) | tous verts (detail ci-dessous) | 09:19 |
| 6.6 | tcpdump 25 s `dst dc01:389` + 10 binds auth generes | **0 packets captured** | 09:20 |

---

## Cross-checks Phase 6.3 etape 10

### Wazuh : 8/8 Active

Depuis app01 (192.168.20.13) :
```
000,app01 (server),127.0.0.1,Active/Local,
001,backup01,any,Active,
002,proxy-lyon01,any,Active,
003,dc01,any,Active,
004,fs01,any,Active,
005,db01,any,Active,
006,bastion01,any,Active,
007,mail01,any,Active,
```

### Authelia : HTTP 200

Endpoint direct (`http://127.0.0.1:9091/api/health`) -> `200`.
Unit `authelia.service` = `active`. Authelia partage le meme step-ca
trust anchor pour son bind LDAPS dc01:636 (configure par migration anterieure
hors Phase 6.3).

### AD samba-tool

```sh
sudo samba-tool user list | wc -l
# 95 (= 94 users invariants + 1 ligne finale)
```

Sortie complete non capturee (PII).

---

## Phase 6.6 -- absence bind 389

Capture `tcpdump -nn -i eth0 dst host 192.168.20.10 and dst port 389`
pendant 25 s sur mail01, avec 10 binds auth forces (5 x `doveadm auth test`
+ 5 x `doveadm user`) :

```
tcpdump: listening on eth0, link-type EN10MB ...
0 packets captured
0 packets received by filter
0 packets dropped by kernel
```

Aucun fallback LDAP cleartext residuel cote Dovecot. La sortie firewall
(FW-INT-LYON, regle `DMZ -> dc01:389 BLOCKED`) confirme deja l'impossibilite
reseau, mais on a verifie l'absence cote applicatif egalement (pas de
tentative).

---

## Findings clos par cette migration

| Finding | Description | Statut |
|---------|-------------|--------|
| **P-001** | Bind LDAP anonyme HIGH (ouverture historique) | RESOLU : plus de path 389 utilise cote mail01 ; **fermeture finale au niveau AD attend Phase 7** (desactivation listener 389 sur dc01). Pour mail01 seul : RESOLU. |
| **P-002** | mkcert non-PKI LOW (chaine de confiance non operationnelle) | RESOLU : la chaine step-ca Nova Syndicate est desormais le trust anchor utilise par Dovecot (et Authelia anterieurement). |
| **T-PKI-INTERNE-CA** | step-ca operationnelle, certs deployes sur clients | RESOLU : root + intermediate dans system trust mail01 ; certs valides sur dc01:636. |
| **T-LDAPS-MIGRATION** | Bascule Dovecot vers LDAPS step-ca | RESOLU. |
| **T-CLOUD-INIT-DNS** | mail01 ne resolvait pas `dc01.nova-syndicate.local` | RESOLU (pre-existant a cette session) : `/etc/hosts` statique, `manage_etc_hosts: false`, verifie via `getent hosts dc01` -> `192.168.20.10`. |

---

## Phase 7 -- STOP OBLIGATOIRE

Conformement a la consigne AFK, **la Phase 7 (desactivation listener LDAP
389 sur dc01 + `require_strong_auth`) n'est PAS executee**. Point de
non-retour cross-clients (tous les VLANs internes seraient affectes en
un seul changement). Validation manuelle requise au retour de l'operateur.

Pre-requis a preparer (sans appliquer) :
- Snapshot dedie `dc01-pre-disable-389` (a creer juste avant l'apply Phase 7).
- Inventaire complet des clients LDAP residuels (autres que ceux deja audites :
  Authelia, Dovecot, Winbind fs01, AWX, Wazuh -- tous OK ou non-LDAP).
- ADR-0034 redige avec plan de bascule + rollback.

---

## Dettes decouvertes en passant

1. **T-ANSIBLE-MUX-CORRUPTION** (non observe ce jour, signale en historique) :
   ControlMaster bastion-nova absent (socket `~/.ssh/cm-debian@192.168.15.2:22`
   inexistant au demarrage). Mitigation effective : execution autonome via
   `proxmox-hypervisor` (Tailscale, pas de MFA), pattern documente dans le
   runbook section "Voies d'acces". A trancher : faut-il un demon
   reverse-tunnel persistant ou conserver la pattern Proxmox-jump comme
   nominale pour les operations Claude/AWX ?

2. **TCP/53 DMZ follow-up (low prio)** : `manage_etc_hosts: false` + entree
   statique `192.168.20.10 dc01.nova-syndicate.local` sur mail01 fonctionne,
   mais si un autre service DMZ (vpn-gw01, web01) doit resoudre dc01, la
   meme bidouille devra etre repliquee. Alternative : autoriser DMZ -> dc01:53
   en regle FW-INT (ouverture LOW au plan NIS2 -- segment DMZ a peu de
   besoins de noms internes, mais non-zero). Decision a documenter,
   non bloquant.

3. **Wazuh "8 agents" vs declaratif "7 agents" anterieur** : STATUS.md du
   27 mai listait "7 agents Active". Maintenant 8 (000 app01 self-managed +
   001-007). Le 000 = app01 server etait deja la (statut "Active/Local") mais
   non compte dans les anciens decomptes. Mise a jour STATUS.md.

4. **`dnpass` cleartext dans dovecot-ldap.conf.ext** : pratique courante pour
   Dovecot LDAP (le plugin n'accepte pas de secret externe), perms `0600
   root:dovecot` correctes. Pas une vulnerabilite mais a documenter explicitement
   dans ADR-0034 (rotation = `ansible-vault edit` + replay role + ce fichier
   regen).

---

## Snapshots a nettoyer (post-validation manuelle de la migration)

- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (2026-06-02 09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps` (2026-06-02 09:14:04)

Backup configs locales sur mail01 (a conserver tant que la Phase 7 n'est
pas validee, **rollback de proximite** rapide sans toucher au snapshot
LVM) :
- `/etc/dovecot/conf.d/auth-ldap.conf.ext.bak-preldaps-2026-06-02`
- `/etc/dovecot/dovecot-ldap.conf.ext.bak-preldaps-2026-06-02`
- `/etc/dovecot/conf.d/10-auth.conf.bak-preldaps-2026-06-02`

---

## Suite

- **Cote operateur** : valider Phase 7 (snapshot dc01 + `samba-tool
  ldapserver` no-389 + `--ldap-require-strong-auth=yes`).
- **File de dettes** : item 1 traite, items 2-6 reportes (analyse de blast
  radius ci-dessous).

---

## Compte-rendu consolide file de dettes (post Phase 6.3)

### Dette 1 -- healthcheck.sh PVE 9.x bug -- **RESOLU**

Commit `9b49de0`. Bug racine : PVE 9.x serialise systematiquement
`"out-data" : "<value>\n"` (newline echappe avant la quote fermante).
Les patterns `grep -q '"active"'` (sections 4, 6) et over-escape
`'"[0-9]+\\\\n"'` (compteur AD users) ne matchaient plus.

Fix : helper `qm_exec_out()` jq-prioritaire avec fallback awk/sed,
refactor 4 call-sites, invariant Wazuh `7 -> 8` (post enrollment mail01).

Avant : 13 OK / 8 WARN / 3 FAIL. Apres : 17 OK / 6 WARN / 1 FAIL
(le residuel = IPsec 0 SAs, dette Phase IV documentee).

Evidence + methode PDCA pour D.7 :
[docs/healthcheck-pve9-fix-evidence.md](healthcheck-pve9-fix-evidence.md).

### Dette 2 -- T-LEAST-PRIVILEGE-DEBIAN (R-006 MEDIUM) -- **REPORTE**

Analyse menee. Etat actuel sur app01 (representatif) :
- `/etc/sudoers.d/90-cloud-init-users` : `debian ALL=(ALL) NOPASSWD:ALL` (cloud-init).
- `/etc/sudoers.d/ansible` : `debian ALL=(ALL) NOPASSWD:ALL` + `ansible ALL=(ALL) NOPASSWD: ALL` (doublon, dette de menage).
- `/etc/sudoers.d/nova-agents-readonly` : `debian ALL=(root) NOPASSWD: /usr/sbin/nft list ruleset, ...` (scope deja tenu pour la cle agents).

Fermeture stricte de R-006 (scope sudo a une whitelist de commandes)
exigerait :
1. Audit complet des `become: yes` dans toutes les tasks Ansible
   (50+ playbooks, role `common` + `hardening` + 10 autres).
2. Construction d'une whitelist : `apt`, `dpkg`, `systemctl`, `update-rc.d`,
   `chmod`, `chown`, `mkdir`, `cp`, `mv`, `rm`, `tee`, `useradd`, `groupadd`,
   `sed -i`, ... -> en pratique tres proche de `ALL:ALL`.
3. Test E2E sur les 6 VMs via AWX (sinon casse silencieuse de tout playbook
   qui touche une commande hors whitelist).

**Decision proposee (a valider)** : R-006 se ferme **architecturalement**,
pas par sudoers. Defense en profondeur deja effective :
- SSH key only (password login disabled cloud-init + hardening).
- `from=192.168.60.0/29` + `restrict` sur `authorized_keys` cle nova-agents.
- nft host allowlist VLAN60 only.
- ProxyJump bastion pour sessions humaines + MFA TOTP.
- Pas d'acces direct DMZ -> SERVERS pour cle debian.

Action recommandee : ADR-0035 "Politique compte d'administration debian -
defense en profondeur" qui documente le residuel R-006 comme acceptable
selon NIS2 art.21 §2.j (mesure de gestion d'identite + supervision Wazuh
des actions sudo via `actiontype=root`). **Hors scope d'execution autonome**,
necessite trade-off NIS2 vs operabilite a trancher.

Menage trivial possible (sans risque) : supprimer le doublon
`debian ALL=(ALL) NOPASSWD:ALL` du fichier `/etc/sudoers.d/ansible` (deja
present via `90-cloud-init-users`). A faire dans un commit dedie,
hors session AFK.

### Dette 3 -- T-WAZUH-OPNSENSE-INGESTION (R-004 LOW) -- **REPORTE**

Pre-requis non valides :
- 3 des 4 OPNsense sont injoignables depuis le Mac (T-TF-WANSIM-CONNECTIVITY,
  T-TF-FWEXTMRS-CONNECTIVITY, T-TF-FWEXTLYON-CONNECTIVITY -- ouverts dans
  STATUS.md).
- Seul FW-INT-LYON (192.168.99.1) est joignable via Tailscale.
- Ingestion syslog cross-firewall = besoin de pousser config sur les 4
  -> impossible en autonomie.

Action faisable ce jour : configurer **uniquement FW-INT-LYON ->
Wazuh manager app01:514** (ouverture syslog UDP/514 + decoder Wazuh
`opnsense-firewall`). Mais l'ingestion partielle (1 FW sur 4) n'est pas
representative -> valeur SIEM degradee, NIS2 traceabilite incomplete.

**Decision proposee** : attendre que les 3 connectivites Terraform soient
restaurees (cf dettes T-TF-* -- WAN-SIMULATOR via Tailscale dedie ou via
le bastion administrative ; FW-EXT-LYON / FW-EXT-MRS pareillement) ->
ouverture syslog en masse coherente, ADR-0035 unique. Hors scope ce jour.

### Dette 4 -- T-SPLIT-MONITORING-VM (extraction app01) -- **REPORTE**

Chantier majeur :
1. Provisionnement Terraform nouvelle VM (VMID + IP VLAN20 ou nouveau VLAN
   monitoring) -> tres lourd en pre-requis (template, ressources Proxmox,
   firewall update).
2. Migration **sans downtime** de wazuh-indexer (etat OpenSearch ~GB) :
   snapshot indexer + restore sur nouvelle VM + bascule du `output`
   wazuh-manager + redirect.
3. Migration Grafana : sauvegarde db sqlite/mariadb + restore + bascule
   datasource Prometheus/Wazuh.
4. Test E2E dashboards + alertes + permissions Authelia SSO (qui n'existe
   pas encore d'ailleurs -- T-GRAFANA-AUTHELIA-SSO ouvert).

Estimation realiste : 6-8h de session supervisee avec rollback testes.
Non-autonome.

**Decision proposee** : session dediee planifiee, snapshot etat app01
+ Terraform plan/apply atomiques. ADR-0036 a rediger en parallele.

### Dette 5 -- T-SURICATA-VM-DEDIEE (4 GB) -- **REPORTE**

Pre-requis : memes contraintes que dette 4 (provisionnement VM + ruleset
+ tap port mirroring depuis OPNsense vers la VM Suricata). En sus :
configuration tap network (vmbr mirror, type-specific) qui peut necessiter
des ajustements coeur Proxmox host.

Le ruleset cible (emerging-malware, exploit, trojan, attack-response,
current-events) est concret et chargeable. Mais le pipe `eve.json ->
Wazuh manager` depend de la dette 4 (extraction monitoring) ou non,
selon si Wazuh manager reste sur app01.

**Decision proposee** : a sequencer apres dette 4 (split monitoring) pour
ne pas re-aggraver la charge app01.

### Dette 6 -- T-DRP-DRILL-PERTE-SITE -- **REPORTE**

Exercice de continuite, pas une operation IaC. Pre-requis :
- Acces Hetzner cible (cle SSH, projet, capacite reservation).
- Plan DRP valide (RTO/RPO definis, sequencage restore Borg backup ->
  Hetzner -> bascule DNS).
- Communication des etapes (mode "dry-run" vs "fail-over reel").

Aucun de ces pre-requis n'est verifie en session AFK. Lancer un drill
DRP en autonomie = risque de cascade incontrolee si la simulation
basculait reellement les enregistrements DNS publics.

**Decision proposee** : session dediee, mode dry-run d'abord, validation
manuelle a chaque etape.

---

## Synthese executive

| Item | Statut session 2026-06-02 | Decision |
|------|---------------------------|----------|
| Phase 6.3 Dovecot LDAPS | **RESOLU** | Trust anchor step-ca effectif, auth restauree. |
| Phase 6.6 tcpdump 389 | **RESOLU** | 0 packet residuel. |
| Phase 7 (desactivation 389) | **STOP OBLIGATOIRE** | Validation manuelle. |
| Dette 1 healthcheck PVE 9 | **RESOLU** | 17/24 checks OK, evidence D.7 livree. |
| Dette 2 R-006 sudoers debian | **REPORTE** | Decision architecturale (ADR-0035 a rediger). |
| Dette 3 syslog OPNsense | **REPORTE** | Bloque par 3 dettes T-TF-*-CONNECTIVITY. |
| Dette 4 split monitoring | **REPORTE** | 6-8h session supervisee. |
| Dette 5 Suricata VM | **REPORTE** | Sequencer apres dette 4. |
| Dette 6 DRP drill | **REPORTE** | Pre-requis Hetzner + decision dry-run vs reel. |

3 chantiers menes a terme (Phase 6.3 + 6.6 + dette 1), 5 reports
documentes avec analyse de blast radius et conditions de reprise. Aucun
chantier laisse en demi-teinte ou rollback partiel. Snapshots Proxmox
preserves pour validation differee (mail01 + dc01).

Tous les commits respectent la convention francaise sans accents + tag
ticket + zero attribution Claude/Anthropic (pre-commit hook respecte).
Sequence : `a50fc3d` (runbook), `1ab73fa` (Phase 6.3+6.6 cloture),
`9b49de0` (healthcheck PVE 9.x fix).
