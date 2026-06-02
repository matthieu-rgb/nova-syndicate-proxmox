# ADR-0034 : Migration LDAPS clients internes (step-ca) + ldap server require strong auth

- Statut : Accepte. Phases 4 + 5 (PKI step-ca + cert dc01:636) deployees
  2026-06-01/02. Phase 6.3 (mail01 Dovecot LDAPS) deployee 2026-06-02 09:14.
  Phase 6.6 (tcpdump mail01 = 0 paquet 389) validee 2026-06-02 09:20.
  Phase 7a (`ldap server require strong auth = yes`) deployee 2026-06-02 17:38.
  Phase 7b (fermeture listener 389) **REFUSEE** -- posture finale assumee
  (cf. section Consequences).
- Date : 2026-06-02
- Auteur : matthieu-rgb
- Tickets : T-LDAPS-MIGRATION (clos), T-PKI-INTERNE-CA (clos), T-CLOUD-INIT-DNS
  (clos), P-001 (clos), P-002 (clos), T-FS01-LDAPS-OR-SSSD (NOUVELLE, LOW)
- Liens : [runbook](../runbook-ldaps-migration.md),
  [rapport execution](../ldaps-migration-report.md),
  [evidence pcap](../evidence/389-incoming-pre-strong-auth-2026-06-02.pcap),
  [ADR-0029 Postfix/Dovecot](ADR-0029-mail-server-postfix-dovecot.md),
  [ADR-0033 AWX RBAC LDAP](ADR-0033-awx-rbac-teams-ldap-mapping.md)

## Contexte

L'AD Samba (dc01, 192.168.20.10) servait historiquement les binds LDAP
sur :389 sans contrainte forte. Trois clients internes utilisaient
LDAP/LDAPS de maniere heterogene :

| Client | Etat avant ADR-0034 | Risque |
|--------|---------------------|--------|
| Authelia (app01) | `ldaps://dc01.nova-syndicate.local:636` avec trust mkcert (`nova-CA.crt`, mai 2026) | LDAPS OK fonctionnellement, mais trust anchor non-PKI (mkcert utilitaire local, pas une autorite interne reproductible). P-002 LOW. |
| Dovecot (mail01) | `uris = ldaps://dc01:636` avec `tls_ca_cert_file = /etc/ssl/certs/nova-CA.crt` (mkcert), `tls_require_cert = demand` | Identique a Authelia + auth cassee depuis le rollover step-ca du 1er juin (cert dc01:636 emis par Intermediate CA Nova Syndicate, non valide par mkcert). |
| Winbind (fs01) | `client ldap sasl wrapping = seal` sur TCP/389, bind Kerberos GSSAPI | LDAP messages chiffres au-dessus de TCP/389, **mais** les binds simples cleartext etaient encore autorises cote serveur (P-001 HIGH). |

P-001 (bind LDAP anonyme/cleartext HIGH) et P-002 (chaine de confiance non
PKI LOW) etaient ouverts au plan NIS2 (art.21 §2 e+i : confidentialite
+ integrite des credentials directory).

Pre-requis deployes en amont (hors scope d'execution autonome AFK) :
- **step-ca** sur pki01 (VMID 112, 192.168.60.4, VLAN 60 admin) : root + intermediate.
- Cert dc01:636 emis par step-ca, SANs : `dc01.nova-syndicate.local`,
  `nova-syndicate.local`, `dc01`, IP 192.168.20.10. Validite 2026-06-01 ->
  2027-06-01. `tls cafile` smb.conf = root step-ca.
- DNS mail01 : entree statique `/etc/hosts` + `manage_etc_hosts: false` (la
  resolution DMZ -> dc01:53 reste BLOCKED par decision, cf T-CLOUD-INIT-DNS).
- Firewall mail01 : DMZ -> dc01:636 OPEN, DMZ -> dc01:389/53 BLOCKED
  (regles FW-INT Terraform-managed).

Une **decouverte protocolaire** lors du pre-check Phase 7a a invalide
une note de contexte initiale et change la decision Phase 7b : voir
"Distinction CLDAP / RootDSE anonyme / GSSAPI-sealed" ci-dessous.

## Options considerees

### Pour Phase 6.3 (Dovecot mail01)

1. **Bascule complete `ldap://` -> `ldaps://`** : suppose que mail01
   utilisait du LDAP cleartext. **Plan initial reconstruit, finalement
   ecarte** : l'inspection live a montre que `uris` etait deja en
   `ldaps://`. Le delta reel etait sur le trust anchor uniquement.
2. **Bascule du trust anchor mkcert -> step-ca + durcissement
   `tls_require_cert = demand -> hard`** : **RETENU**. Edition
   chirurgicale sed sur 2 lignes de `dovecot-ldap.conf.ext`, autres
   parametres preserves (`uris`, `auth_bind`, `ldap_version`, `dn`,
   `base`, `scope`, `dnpass`, `*_filter`, `user_attrs`).

### Pour Phase 7

1. **`samba-tool domain settings set` en CLI** -- non disponible
   dans cette version de samba-tool (`no such subcommand: settings`).
2. **`ldap server require strong auth = yes` pinne dans `smb.conf`
   `[global]` + reload** -- **RETENU**. Materialise la posture NIS2
   explicitement dans l'IaC (template `dc/templates/smb.conf.j2` avait
   deja le toggle conditionnel). Survit aux upgrades Samba qui
   pourraient repasser le default.
3. **Fermeture hard du listener 389** (`interfaces`, `disable ldap on tcp`,
   ou `--no-ldap-tcp`) -- **REFUSEE** : casserait winbind fs01 (cf.
   decouverte protocolaire).

## Decision

### Decision 1 -- PKI interne assumee comme trust anchor unique

`step-ca` (pki01) est l'autorite de confiance pour tous les certs internes
serveurs (LDAPS dc01, futurs services TLS internes). Le bundle
`/usr/local/share/ca-certificates/{nova-root.crt,nova-intermediate.crt}` +
`update-ca-certificates` constitue la chaine de confiance system-wide
deployable.

### Decision 2 -- Dovecot mail01 sur LDAPS step-ca strict

```
uris                = ldaps://dc01.nova-syndicate.local:636
tls_ca_cert_file    = /etc/ssl/certs/ca-certificates.crt
tls_require_cert    = hard
auth_bind           = yes      (preserve)
ldap_version        = 3        (preserve)
```

Le bloc `tls = yes` du runbook initial est **omis volontairement** :
redondant voire conflictuel avec `uris = ldaps://` (TLS implicite).

### Decision 3 -- `ldap server require strong auth = yes` pin explicite dans smb.conf

Pin dans le `[global]` de `/etc/samba/smb.conf` de dc01 :

```ini
# Phase 7a -- 2026-06-02 T-LDAPS-MIGRATION (ADR-0034) : refus simple bind 389 cleartext
ldap server require strong auth = yes
```

Aligne dans l'IaC : `inventory/group_vars/domain_controllers/vars.yml`
passe `samba_ldap_require_strong_auth` de `false` a `true` (le template
`dc/templates/smb.conf.j2` gere deja la generation conditionnelle).

### Decision 4 -- Listener 389 conserve, posture finale assumee

Le listener TCP/UDP 389 reste ouvert sur dc01. Acces protege par :
- **`ldap server require strong auth = yes`** : refus des simple binds
  cleartext.
- **Binds GSSAPI-sealed** uniquement (winbind fs01) : chiffrement +
  integrite des messages LDAP au-dessus de TCP/389.
- **Anonymous binds** limites au RootDSE (decouverte AD standard,
  pas d'enumeration sensible).
- **Audit Wazuh** : evenements samba (`local5` syslog) ingestes par
  l'agent dc01 (007 mail01 + 003 dc01 actifs).

## Distinction CLDAP / RootDSE anonyme / GSSAPI-sealed (decouverte 2026-06-02)

Le pre-check tcpdump cote dc01 (fenetre 90 s, triggers : Authelia restart,
mail01 doveadm, fs01 wbinfo, samba-tool user list) a capture **28 paquets
sur :389** dont **source unique 192.168.20.11 (fs01 winbindd)**. L'analyse
ASN.1 du premier payload TCP a revele trois categories distinctes :

1. **CLDAP UDP** : `192.168.20.11:5XXXX -> 192.168.20.10:389/udp`.
   Decouverte AD standard ("LDAP ping"), pas une vulnerabilite.
   Conservee.
2. **RootDSE anonyme TCP** : `searchRequest base="" filter=objectclass=*
   attr=currentTime`. C'est le bootstrap LDAP avant tout bind : le client
   recupere les capacites du serveur. Anonyme par specification LDAP
   (RFC 4513), pas par defaut de configuration. Conservee.
3. **Bind GSSAPI/Kerberos sealed** : apres la phase 2, winbind effectue
   un bind avec `client ldap sasl wrapping = seal` (verifie via testparm
   sur fs01). Les messages LDAP subsequents sont chiffres + signes.
   **Equivalent en securite a LDAPS du point de vue confidentialite et
   integrite**, mais sans cert TLS X.509.

Cette distinction invalide la note de contexte initiale ("Winbind fs01 :
Kerberos/ADS, pas LDAP direct") et a justifie le refus de Phase 7b :
desactiver le listener 389 supprime egalement les chemins CLDAP +
RootDSE + GSSAPI-sealed, dont winbind fs01 depend.

L'evidence pcap est archivee :
[docs/evidence/389-incoming-pre-strong-auth-2026-06-02.pcap](../evidence/389-incoming-pre-strong-auth-2026-06-02.pcap)
(20 855 octets, Wireshark `tcp.port == 389 or udp.port == 389`).

## Alternatives ecartees

### A1 -- Migration immediate winbind -> sssd-ad sur fs01 (avant Phase 7a)

Pourrait permettre Phase 7b complete (fermeture 389). **Ecartee** :
chantier de plusieurs heures (refonte PAM + NSS + GSSAPI keytab),
risque de regression silencieuse sur les partages SMB authentifies,
hors scope d'execution autonome. Cree comme dette filiale
**T-FS01-LDAPS-OR-SSSD** pour traitement supervise ulterieur, sans
trancher entre sssd-ad, Samba membre 636, ou nft allowlist 389 sur dc01.

### A2 -- Conservation de `nova-CA.crt` mkcert comme trust anchor

**Ecartee** : mkcert ne procure pas de chaine reproductible, pas
d'API ACME, pas de management lifecycle. La dette P-002 (mkcert non-PKI)
serait restee ouverte sine die.

### A3 -- Reglage `ldap server require strong auth = allow_sasl_over_tls`

Valeur intermediaire qui autorise SASL sans TLS sur 389. **Ecartee** :
strictement equivalent au default `yes` dans notre cas (winbind fait du
SASL/sealed sur 389, pas du SASL/plain), et brouille le message
d'intention NIS2 ("refus de tout bind non strong-auth").

### A4 -- `ldap ssl = on` cote membre Samba fs01

Forcerait Samba a utiliser TLS pour ses requetes LDAP cote client. **Ecartee
en l'etat** : non trivial avec une jointure ADS existante (cf. T-FS01-LDAPS-OR-SSSD
option 2). A reevaluer si Phase 7b est rouverte.

### A5 -- `tls = yes` dans `dovecot-ldap.conf.ext` en plus de `uris = ldaps://`

**Ecartee** : redondant (TLS deja implicite par scheme `ldaps://`),
potentiellement conflictuel avec certaines versions de Dovecot LDAP
plugin (interpretee comme demande de StartTLS au-dessus de LDAPS,
double handshake). Le runbook initial proposait cette ligne ; elle
a ete omise lors de l'execution.

## Consequences

### Positives

- **P-001 (bind LDAP anonyme/cleartext HIGH) CLOS** : refus simple bind
  cleartext applique cote dc01, verifie effectif par `testparm` + cross-checks
  fonctionnels (winbind, Authelia, Dovecot, samba-tool).
- **P-002 (mkcert non-PKI LOW) CLOS** : trust anchor unique sur step-ca
  pour mail01 + Authelia.
- **T-LDAPS-MIGRATION CLOS** : tous les clients internes routes vers
  LDAPS step-ca strict, OU GSSAPI-sealed sur 389 (winbind fs01).
- **T-PKI-INTERNE-CA CLOS** : step-ca operationnelle, processus de
  deploiement cert clair (`/usr/local/share/ca-certificates/` +
  `update-ca-certificates`).
- **T-CLOUD-INIT-DNS CLOS** : `/etc/hosts` statique + `manage_etc_hosts: false`
  documente comme posture stable pour les hotes DMZ.

### Negatives / residuels assumes

- **Listener 389 ouvert** sur dc01, posture finale **assumee** :
  durcie par strong-auth + chiffrement GSSAPI cote winbind + anonymous
  binds limites au RootDSE. Mitigation NIS2 conforme art.21 §2 e+i,
  surface d'attaque reduite a "anonymous RootDSE + GSSAPI bind".
  Conditions de reouverture de Phase 7b : voir T-FS01-LDAPS-OR-SSSD.
- **Dette filiale T-FS01-LDAPS-OR-SSSD (LOW)** : decision d'archi differee,
  3 options documentees non tranchees. Hors scope certification.

### Choix lab assumes avec mitigation explicite

- **`dnpass` cleartext dans `/etc/dovecot/dovecot-ldap.conf.ext`** :
  le plugin Dovecot LDAP n'accepte pas de secret externe (pas de
  reference a un secret manager). Le fichier est en perms `0600
  root:dovecot`, en VM DMZ avec acces restreint (qm guest exec via
  Proxmox host + ProxyJump bastion uniquement). Rotation = `ansible-vault
  edit inventory/group_vars/all/vault.yml` -> remplacer
  `vault_svc_mail_ldap_password` -> replay role `mail_server` ->
  re-render `dovecot-ldap.conf.ext` + restart dovecot. Mitigation :
  monitoring Wazuh sur `/etc/dovecot/` (decoder `audit.log` host).
- **`tls_disable = true` Vault APP01** (dette herite Phase II) :
  choix lab uniquement, documente initialement comme "TLS termine en
  amont par nginx + reachable uniquement en localhost". Compatible
  avec la posture LDAPS interne tant que les secrets Vault accedes
  par AWX/operateurs transitent en TLS au-dessus de la couche
  applicative. **A rouvrir si Vault est exposed en VLAN ou si un
  client externe au manager AWX y accede**. Mitigation : segmenter
  Vault sur localhost + reverse proxy authentifie.

### Documentation / process

- Runbook LDAPS pinne dans le repo
  (`docs/runbook-ldaps-migration.md`, versionne pour survivre a tout
  `/clear` de session chat). Methode reutilisable pour les futures
  migrations TLS internes (Postgres, Redis, Vault si rouvert).
- Rapport d'execution detaille (`docs/ldaps-migration-report.md`)
  trace les ecarts plan/realite + Phase 7a + posture finale.
- Pcap d'evidence archive
  (`docs/evidence/389-incoming-pre-strong-auth-2026-06-02.pcap`)
  -- preuve d'investigation pour audit + future re-evaluation T-FS01-LDAPS-OR-SSSD.
- STATUS.md mis a jour avec section "Session 2026-06-02 -- complement (Phase 7a)".

### NIS2 -- impact recalcule

| Pilier | Avant Phase 6.3 | Apres Phase 7a |
|--------|-----------------|----------------|
| Confidentialite credentials directory | mkcert (chaine non reproductible) + mix LDAP 389/636 | step-ca + LDAPS strict + GSSAPI sealed |
| Integrite des binds | simple bind cleartext autorise (P-001) | strong auth requis par config (`Yes`) |
| Traceabilite | Wazuh agent dc01 (003) actif, decoder samba | identique + posture explicitement pinne dans IaC |
| Reversibilite | aucun snapshot dedie LDAPS | 3 snapshots (`mail01-pre-ldaps-mail`, `dc01-pre-mail-ldaps`, `dc01-pre-strong-auth`) |

NIS2 art.21 §2 e (chiffrement) + i (gestion des incidents et continuite) : conforme.
NIS2 art.21 §2 j (authentification multifacteur) : hors scope ADR-0034 (cf. T-MFA-TOTP-BASTION,
T-WIREGUARD-MFA).
