# Runbook -- Migration LDAPS Dovecot mail01 (Phase 6.3)

Ticket : **T-LDAPS-MIGRATION**
Date plan : 2026-06-02
Statut : en cours
ADR de cloture : ADR-0034 (a creer)

Ce runbook est le plan d'execution autoritatif de la Phase 6.3. Il est
versionne explicitement pour survivre a tout `/clear` ou perte de contexte
chat. Toute reprise se fait depuis ce fichier.

---

## Objectif

Basculer le backend d'authentification Dovecot de mail01 de LDAP cleartext
(`ldap://dc01:389`) vers LDAPS (`ldaps://dc01.nova-syndicate.local:636`)
avec verification stricte de la chaine PKI interne step-ca. Ferme P-001
(bind LDAP anonyme HIGH) et finalise T-LDAPS-MIGRATION.

---

## Contexte PKI / Certs (deja en place avant Phase 6.3)

- **step-ca** deployee sur pki01 (VMID 112, 192.168.60.4). Root + Intermediate
  CA presents dans `/home/step/.step/certs/{root_ca.crt,intermediate_ca.crt}`.
- **dc01** sert un cert step-ca sur :636.
  - `CN = dc01.nova-syndicate.local`
  - Issuer : `O = Nova Syndicate Root CA, CN = Nova Syndicate Root CA Intermediate CA`
  - Validite : `notBefore = 2026-06-01 20:59:05 GMT`, `notAfter = 2027-06-01`
  - SANs : `dc01.nova-syndicate.local, nova-syndicate.local, dc01, IP 192.168.20.10`
  - Chain verify system trust = `Verify return code 0 (ok)`.
- Clients deja migres et valides en amont (hors scope Phase 6.3) :
  - Authelia : `ldaps://dc01.nova-syndicate.local:636` skip_verify=false.
  - Wazuh : pas de backend LDAP (LDAP utilise via integration AWX/Authelia uniquement).
  - Winbind fs01 : Kerberos/ADS (pas LDAP direct).
  - AWX : auth locale (pas de backend LDAP).
- **mail01 DNS** : resolu via `/etc/hosts` (`192.168.20.10 dc01.nova-syndicate.local dc01`),
  `manage_etc_hosts: false` persistant (cf cloud-init-fix-report.md). `getent
  hosts dc01` -> `192.168.20.10`. Design DMZ conserve : aucune ouverture
  DMZ -> VLAN20:53.
- **Firewall mail01** :
  - DMZ -> dc01:636 OPEN (regle FW-INT `fwint_mail01_to_dc01_ldaps`, Terraform-managed).
  - DMZ -> dc01:389 BLOCKED (deliberement, NIS2).
  - DMZ -> dc01:53 BLOCKED (deliberement, NIS2).

---

## Voies d'acces (sans MFA, AFK-safe)

Toutes les operations transitent par `proxmox-hypervisor` (Tailscale,
100.112.113.2 / 192.168.18.50). **Aucune session bastion + TOTP requise.**

| Cible | Methode | Commande type |
|-------|---------|---------------|
| Proxmox host (snapshots) | SSH direct via Tailscale | `ssh proxmox-hypervisor 'qm snapshot ...'` |
| dc01 (VMID 103, 192.168.20.10) | SSH ProxyJump proxmox-hypervisor | `ssh -J proxmox-hypervisor debian@192.168.20.10` |
| pki01 (VMID 112, 192.168.60.4) | SSH ProxyJump proxmox-hypervisor | `ssh -J proxmox-hypervisor debian@192.168.60.4` |
| mail01 (VMID 101, 172.16.1.3 DMZ) | qm guest exec via Proxmox host | `ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "..."'` |

Le pattern "dc01-jump" mentionne dans le plan original (`ProxyCommand ssh
debian@192.168.20.10 -W %h:%p`) suppose que VLAN20 -> DMZ:22 est ouvert.
**Non requis** : `qm guest exec 101` est la voie privilegiee pour mail01
(pas de dependance reseau, agent guest deja en place).

---

## Plan 10 etapes

### Etape 1 -- Double snapshot Proxmox (DESTRUCTIVE-PROTECT)

Snapshots non negociables avant toute modification.

```sh
ssh proxmox-hypervisor 'qm snapshot 101 mail01-pre-ldaps-mail --description "Pre Phase 6.3 LDAPS migration (T-LDAPS-MIGRATION) -- 2026-06-02"'
ssh proxmox-hypervisor 'qm snapshot 103 dc01-pre-mail-ldaps   --description "Pre Phase 6.3 LDAPS migration mail-side (T-LDAPS-MIGRATION) -- 2026-06-02"'
```

**Verif** : `ssh proxmox-hypervisor 'qm listsnapshot 101; qm listsnapshot 103'`
doit afficher les deux noms.

### Etape 2 -- Deploiement CA bundle sur mail01

Recuperer root + intermediate depuis pki01, deposer dans
`/usr/local/share/ca-certificates/` sur mail01.

```sh
# 2a. Recuperer les certs depuis pki01 vers le Mac (temporaire)
ssh -J proxmox-hypervisor debian@192.168.60.4 'sudo cat /home/step/.step/certs/root_ca.crt' > /tmp/nova-root.crt
ssh -J proxmox-hypervisor debian@192.168.60.4 'sudo cat /home/step/.step/certs/intermediate_ca.crt' > /tmp/nova-intermediate.crt

# 2b. Injecter dans mail01 via qm guest file-write
ssh proxmox-hypervisor "qm guest file-write 101 /usr/local/share/ca-certificates/nova-root.crt -content '$(cat /tmp/nova-root.crt | base64 -w0)' -encode base64" 2>/dev/null \
  || ssh proxmox-hypervisor "qm guest exec 101 -- /bin/bash -c 'cat > /usr/local/share/ca-certificates/nova-root.crt'" -e "$(cat /tmp/nova-root.crt)"
# Note: qm guest file-write n'existe pas dans toutes les versions de PVE.
# Fallback portable :
B64ROOT=$(base64 -w0 < /tmp/nova-root.crt)
B64INT=$(base64 -w0 < /tmp/nova-intermediate.crt)
ssh proxmox-hypervisor "qm guest exec 101 -- /bin/bash -c \"echo $B64ROOT | base64 -d > /usr/local/share/ca-certificates/nova-root.crt\""
ssh proxmox-hypervisor "qm guest exec 101 -- /bin/bash -c \"echo $B64INT  | base64 -d > /usr/local/share/ca-certificates/nova-intermediate.crt\""

# 2c. Nettoyer le Mac
shred -u /tmp/nova-root.crt /tmp/nova-intermediate.crt
```

**Verif** :
```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "ls -l /usr/local/share/ca-certificates/nova-*.crt && openssl x509 -in /usr/local/share/ca-certificates/nova-root.crt -noout -subject -issuer"'
```

### Etape 3 -- update-ca-certificates sur mail01

```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /usr/sbin/update-ca-certificates'
```

Attendu : `2 added, 0 removed`.

**Verif** :
```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "grep -c \"Nova Syndicate\" /etc/ssl/certs/ca-certificates.crt"'
# Attendu : >= 2
```

### Etape 4 -- Handshake test depuis mail01 vers dc01:636

```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "echo | openssl s_client -connect dc01.nova-syndicate.local:636 -servername dc01.nova-syndicate.local -CAfile /etc/ssl/certs/ca-certificates.crt 2>&1 | grep -E \"Verify return code|subject=|issuer=\""'
```

Attendu :
- `Verify return code: 0 (ok)`
- `subject=CN = dc01.nova-syndicate.local`
- `issuer=O = Nova Syndicate Root CA, CN = ...Intermediate CA`

**STOP** si `Verify return code != 0` (rollback non necessaire a ce stade,
Dovecot n'a pas encore ete modifie). Investigation : SAN, hostname, FW, cert
expire.

### Etape 5 -- Backup config Dovecot

Le fichier reel est `/etc/dovecot/conf.d/auth-ldap.conf.ext` (verifie avant
ecriture du runbook). Il `include` `/etc/dovecot/dovecot-ldap.conf.ext`.

```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "
  cp -av /etc/dovecot/conf.d/auth-ldap.conf.ext /etc/dovecot/conf.d/auth-ldap.conf.ext.bak-preldaps-2026-06-02 ;
  cp -av /etc/dovecot/dovecot-ldap.conf.ext       /etc/dovecot/dovecot-ldap.conf.ext.bak-preldaps-2026-06-02 ;
  cp -av /etc/dovecot/conf.d/10-auth.conf         /etc/dovecot/conf.d/10-auth.conf.bak-preldaps-2026-06-02
"'
```

Verifier que les .bak sont presents (`ls -l`).

### Etape 6 -- Modification Dovecot (bascule LDAPS)

Cible : `dovecot-ldap.conf.ext` (le fichier `passdb/userdb args` pointe).

Edition : remplacer le bloc transport (uris/hosts + tls).

```ini
# Avant
hosts = 192.168.20.10
port = 389
# tls = no

# Apres
uris = ldaps://dc01.nova-syndicate.local
tls = yes
tls_ca_cert_file = /etc/ssl/certs/ca-certificates.crt
tls_require_cert = hard
# auth_bind = yes (conserve si deja present)
```

Pattern sed (applique en place via qm guest exec, idempotent) :

```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "
  set -e
  F=/etc/dovecot/dovecot-ldap.conf.ext
  # Supprimer toute ligne uris/hosts/port/tls existante non commentee
  sed -i -E \"s|^[[:space:]]*hosts[[:space:]]*=.*|#&|; s|^[[:space:]]*uris[[:space:]]*=.*|#&|; s|^[[:space:]]*port[[:space:]]*=.*|#&|; s|^[[:space:]]*tls[[:space:]]*=.*|#&|; s|^[[:space:]]*tls_ca_cert_file[[:space:]]*=.*|#&|; s|^[[:space:]]*tls_require_cert[[:space:]]*=.*|#&|\" \$F
  # Ajouter le bloc LDAPS si absent
  grep -q \"^uris = ldaps://dc01\" \$F || cat >> \$F <<EOF

# === T-LDAPS-MIGRATION 2026-06-02 ===
uris = ldaps://dc01.nova-syndicate.local
tls = yes
tls_ca_cert_file = /etc/ssl/certs/ca-certificates.crt
tls_require_cert = hard
EOF
"'
```

**Verif** : `grep -E '^uris|^tls' /etc/dovecot/dovecot-ldap.conf.ext` doit montrer
les 4 lignes ldaps + tls=yes + ca_cert_file + require_cert=hard.

### Etape 7 -- Restart Dovecot

```sh
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "
  systemctl restart dovecot
  sleep 2
  systemctl is-active dovecot
  ss -tlnp 2>/dev/null | grep -E \":(143|993|24|10024)\" | head -5
"'
```

Attendu : `active`, ports 143/993 LISTEN.

### Etape 8 -- doveadm auth test

Compte de service : `svc-mail-ldap@nova-syndicate.local`. Password dans
`vault_svc_mail_ldap_password` (ansible-vault `inventory/group_vars/all/vault.yml`).

```sh
# Recuperer le password depuis le Mac (ansible-vault view)
SVC_PW=$(cd /Users/matthieu/Dev/Nova-syndicate-Code/nova-syndicate-ansible \
  && ansible-vault view inventory/group_vars/all/vault.yml \
  | awk '/vault_svc_mail_ldap_password/ {print $2}' | tr -d '"')

ssh proxmox-hypervisor "qm guest exec 101 -- /bin/bash -c 'doveadm auth test svc-mail-ldap@nova-syndicate.local \"$SVC_PW\" 2>&1'"
```

Attendu : `passdb: svc-mail-ldap@nova-syndicate.local auth succeeded`.

### Etape 9 -- Si KO -> rollback IMMEDIAT

Si l'etape 8 echoue OU si dovecot ne redemarre pas OU si le handshake casse :

```sh
ssh proxmox-hypervisor 'qm rollback 101 mail01-pre-ldaps-mail'
# (Le rollback Proxmox effectue un stop/start automatique.)
ssh proxmox-hypervisor 'qm status 101'
```

**STOP execution** apres rollback. Aucun apply Terraform. Aucun commit
config. Documenter la cause dans le rapport de fin de chantier
(`ldaps-migration-report.md`).

### Etape 10 -- Cross-checks securite (si OK)

```sh
# 10a. Wazuh : 8 agents Active (incluant mail01)
ssh -J proxmox-hypervisor debian@192.168.20.13 'sudo /var/ossec/bin/agent_control -ls 2>&1 | grep -c "Active"'
# Attendu : 8

# 10b. Authelia : HTTP 200 sur /api/health
ssh -J proxmox-hypervisor debian@192.168.20.13 'curl -sS -o /dev/null -w "%{http_code}\n" https://authelia.nova-syndicate.local/api/health -k'
# Attendu : 200

# 10c. AD samba-tool user list (joignabilite + LDAP service)
ssh -J proxmox-hypervisor debian@192.168.20.10 'sudo samba-tool user list 2>&1 | wc -l'
# Attendu : 94 (lignes), invariant connu
```

Si l'un des trois cross-checks echoue -> STOP + rapport (mail01 reste sur
LDAPS, le cross-check echoue probablement pour une cause independante).

---

## Phase 6.6 -- Verification absence bind 389 residuel

Apres Etape 10 OK, capture tcpdump sur mail01 pour confirmer qu'aucun
binaire ne tente encore une connexion vers `dc01:389` (residu Dovecot mais
aussi LDAP-only Postfix, NSS, etc.).

```sh
# Capture 60s sur eth0 mail01, filtre dst dc01:389
ssh proxmox-hypervisor 'qm guest exec 101 -- /bin/bash -c "timeout 60 tcpdump -nn -i eth0 \"dst host 192.168.20.10 and dst port 389\" -c 50 2>&1"' &
PID=$!
# Pendant ce temps, generer du trafic auth :
sleep 5
ssh proxmox-hypervisor "qm guest exec 101 -- /bin/bash -c 'doveadm auth test svc-mail-ldap@nova-syndicate.local \"$SVC_PW\" >/dev/null 2>&1'"
ssh proxmox-hypervisor "qm guest exec 101 -- /bin/bash -c 'doveadm user svc-mail-ldap@nova-syndicate.local >/dev/null 2>&1'"
wait $PID
```

Attendu : `0 packets captured` (ou tcpdump timeout sans match).
Sinon : identifier le processus emetteur (`ss -tnp | grep 389`,
`lsof -i :389`) et corriger avant Phase 7.

---

## STOP OBLIGATOIRE avant Phase 7

Apres Phase 6.6 OK : **arret execution**. NE PAS lancer la Phase 7
(`samba-tool` désactivation listener LDAP 389 + require strong auth).
Cette phase est le point de non-retour cross-clients, validee
manuellement par l'operateur principal au retour. Un snapshot dc01 dedie
sera a prevoir (`dc01-pre-disable-389`), mais **non applique** par
l'execution autonome.

---

## STOP SPONTANE (a tout moment du runbook)

Arret immediat + rapport si :
- Wazuh tombe sous 8/8 agents Active.
- Authelia ne repond plus (pas de HTTP 200 sur /api/health).
- AD injoignable (`samba-tool user list` echoue).
- toute derive securite imprevue ou etat runtime inattendu vs IaC.

---

## Sortie attendue en fin de chantier

- `ldaps-migration-report.md` a la racine du repo (ou docs/) avec :
  - tableau etapes / statut / timestamp / preuve.
  - cross-checks finaux.
  - dettes decouvertes en passant.
- Mise a jour `STATUS.md` : T-LDAPS-MIGRATION RESOLU, P-001 RESOLU, P-002 RESOLU,
  T-PKI-INTERNE-CA RESOLU, T-CLOUD-INIT-DNS RESOLU.
- Reference future ADR-0034 (a creer separement) :
  `docs/adr/ADR-0034-ldaps-migration-dovecot-stepca.md`.

---

## Annexe -- Identifiants ressources

| Ressource | ID / IP | Role |
|-----------|---------|------|
| mail01 | VMID 101, 172.16.1.3 (DMZ Lyon, vmbr3) | Postfix/Dovecot |
| dc01 | VMID 103, 192.168.20.10 (VLAN 20 servers) | Samba AD-DC, LDAP/LDAPS |
| pki01 | VMID 112, 192.168.60.4 (VLAN 60 admin) | step-ca |
| app01 | VMID 106, 192.168.20.13 | Wazuh manager + Authelia |
| proxmox-hypervisor | 192.168.18.50 / 100.112.113.2 (Tailscale) | host PVE 9.1 |
