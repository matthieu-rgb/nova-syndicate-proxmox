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
- **File de dettes** : engagee a la suite de ce rapport (consigne AFK).
  Compte-rendu consolide ajoute en queue de ce document apres traitement
  de la file (items 1 -> 6).
