# ADR-0029 : Mail server interne (Postfix + Dovecot + OpenDKIM) sur mail01

- Statut : Accepte (deploiement partiel - bascule LDAP differee)
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-MAIL-PROD-2026-05-18
- Lien : voir runbook [`runbook-mail-server.md`](../runbook/mail-server.md)

## Contexte

mail01 (VMID 101, 172.16.1.3/29 en DMZ) etait provisionne mais Postfix non
configure. Besoin operationnel : permettre des envois mails **internes**
entre les 85 utilisateurs Samba AD, avec :

- Signature DKIM (anti-spoofing)
- Records SPF + DMARC publies dans la zone AD `nova-syndicate.local`
- TLS sur ports 25/587/993
- Auth SASL sur le port submission (587)
- Ingestion des logs mail dans Wazuh (NIS2 art. 21.2.b)

Architecture cible :
```
[Postes Lyon VLAN30]      [DC01 Samba AD VLAN20]
        |                          |
        v                          v
   [FW-INT-LYON]<-- LDAP/AD lookup (PORT 389/636) -- BLOQUE actuellement
        |
        v
   [mail01 DMZ 172.16.1.3]
        |
        +-- Postfix :25 / :587 (SASL+TLS)
        +-- Dovecot :143 / :993 (IMAP+IMAPS) + LMTP socket
        +-- OpenDKIM :8891 (milter)
```

## Decision

**1. Stack** : Postfix 3.7 + Dovecot 2.3 + OpenDKIM 2.11 sur Debian 12.
Virtual users `vmail` (uid/gid 5000), maildir `/var/vmail/<domaine>/<user>/`,
livraison via LMTP socket Unix entre Postfix et Dovecot.

**2. Auth backend - degradation deliberee** : Le design initial prevoyait
auth LDAP directe contre dc01 (192.168.20.10:389). La regle de firewall
FW-INT bloque DMZ -> VLAN20 par design (isolement NIS2). Deux options :

- **A** : Ouvrir une regle FW-INT specifique mail01 -> dc01:636 (LDAPS)
- **B** : Auth locale `passwd-file` (Dovecot), users provisionnes via
  ansible-vault

Nous choisissons **option B en deploiement initial** pour ne pas degrader
l'isolement DMZ. Le role `mail_server` est ecrit avec `mail_auth_backend`
parametrable (`passwdfile` ou `ldap`), donc la bascule est triviale apres
ouverture FW (cf. dette `T-MAIL-LDAP-FW-RULE`).

**3. TLS** : self-signed avec `CN=mail.nova-syndicate.local` (rsa 2048,
SAN sur le hostname). Acceptable pour usage interne. Wildcard mkcert
sera deploye en V2 quand la chaine sera diffusee sur les postes Lyon.

**4. DKIM** : selecteur `mail`, RSA 2048, mode test (`t=y`) initial. La
publication TXT dans la zone AD doit utiliser un LDB write direct
(`samba.dnsp.string_list` chunke en 255 chars) car `samba-tool dns add`
plante sur les TXT > 255 caracteres (Python `samba.dcerpc.dnsserver`
overflow).

**5. SPF / DMARC** : publies dans la zone Samba AD via `samba-tool dns add`
classique (longueur OK).

```
MX     @                  10 mail.nova-syndicate.local
A      mail               172.16.1.3
TXT    @                  v=spf1 ip4:172.16.1.3 -all
TXT    _dmarc             v=DMARC1; p=quarantine; rua=mailto:postmaster@...
TXT    mail._domainkey    v=DKIM1; h=sha256; k=rsa; t=y; p=<chunk1><chunk2>
```

**6. Observabilite** : wazuh-agent installe sur mail01, localfiles ingest
`/var/log/mail.log`, `/var/log/mail.err`, `/var/log/dovecot.log`.
Nouvelles regles custom NIS2 :
- `100011` (level 8) : echec auth SMTP (`SASL .* authentication failed`)
- `100012` (level 13) : brute force SMTP (correlation 100011 + same_source_ip)

**7. Codification Ansible** : role `mail_server` cree avec templates Jinja
pour Postfix/Dovecot/OpenDKIM. Playbook `playbooks/deploy_mail.yml`,
integre dans `site.yml` etape 8bis. Idempotent.

## Tests valides (Phase 6)

| # | Test | Resultat |
|---|------|----------|
| 1 | Delivery locale `mail` -> maildir | PASS (status=sent via LMTP) |
| 2 | swaks SMTP AUTH 587 + TLS | PASS (sasl_method=LOGIN, dsn=2.0.0) |
| 3 | DKIM-Signature presente dans header recu | PASS |
| 4 | SPF TXT visible dans DNS Samba | PASS (`v=spf1 ip4:172.16.1.3 -all`) |
| 5 | Dovecot IMAPS login + SELECT INBOX | PASS (1 EXISTS, 1 RECENT) |

## Bascule LDAP/AD -- Trade-off et mitigations (T-MAIL-LDAP-FW-RULE-2026-05-18)

### Constat (apres deploiement initial T-MAIL-PROD)

L'isolation DMZ stricte (aucun flux vers VLAN20) etait parfaite du point de
vue NIS2 art. 21.2.e (segmentation), mais empechait les 85 utilisateurs AD
d'utiliser leur boite mail : seuls les 3 users provisionnes en local
(`fabien.bonnet`, `alexandre.gautier`, `postmaster`) pouvaient s'authentifier.
La valeur metier du mail server etait donc proche de zero tant que le canal
LDAP/AD restait ferme.

### Decision (acceptee)

**Ouvrir un flux unique et restrictif** sur FW-INT-LYON :
`pf pass in proto tcp from host_mail01 to host_dc01 port 636 (log)` (sequence 1).
Toute autre tentative `mail01 -> VLAN20` reste bloquee par la regle par defaut
`block any any` (sequence 2 sur l'interface WAN).

### Mitigations en place

1. **Service account dedie read-only** : `svc-mail-ldap` (CN=svc-mail-ldap,
   OU=Service-Accounts) avec mot de passe random 28 chars stocke en vault
   (`vault_svc_mail_ldap_password`). Compte `--noexpiry` mais flag par defaut
   = pas de permissions Modify.
2. **DENY explicite sur Tier0_Admins** : ACE `(D;CI;RP;;;<svc-mail-ldap-SID>)`
   ajoute sur `OU=Tier0_Admins`. Verifie par `ldapsearch` -> retourne empty.
3. **LDAPS uniquement (port 636 direct, pas STARTTLS)** : `tls_require_cert =
   demand` cote Dovecot/Postfix, CA Samba (`/etc/ssl/certs/nova-CA.crt`)
   verifiee. Connexion par hostname (`dc01.nova-syndicate.local` resolu via
   `/etc/hosts` mail01) pour validation CN.
4. **Logging firewall actif** : tous les paquets matchant la regle sont
   logges (`log=1`). Ingest possible par Wazuh via parser pfsense.
5. **Detection pivot mail01** : rules Wazuh custom :
   - `100013` (level 8) : tentative `src=172.16.1.3` vers autre que
     `dst=192.168.20.10:636` -> compromise/pivot suspect.
   - `100014` (level 5) : echec bind LDAP depuis mail01 -> creds
     `svc-mail-ldap` compromis ou brute force.

### Risque residuel

Si mail01 est compromis (ex. RCE Postfix), l'attaquant peut :
- ENUMERER l'annuaire (sAMAccountName, mail) des OUs Lyon/Marseille
  (read-only via svc-mail-ldap). PAS d'acces a Tier0_Admins (DENY ACE).
- NE PEUT PAS modifier de comptes (insufficient access).
- NE PEUT PAS pivot vers d'autres serveurs (FW reste bloquant).

Plan de detection : rule 100013 alerte dans la minute (level 8) toute
connexion mail01 sortante hors flux autorise.

### Tests valides (Bascule LDAP, T-MAIL-LDAP-FW-RULE Phase 5)

| # | Test | Resultat |
|---|------|----------|
| 1 | swaks SMTP AUTH 587 + TLS avec creds AD `fabien.bonnet` | PASS (queued) |
| 2 | IMAPS login + LIST avec creds AD `fabien.bonnet` | PASS (Logged in) |
| 3 | mail01 -> dc01:22 / dc01:389 / fs01:445 / app01:1514 | BLOCKED (4/4) |
| 4 | mail01 -> app01:443 | PASS pre-existant (NAT public Authelia, non regression) |

`doveadm auth test fabien.bonnet` -> `passdb auth succeeded`. Idem
`alexandre.gautier`. `postmap -q .. ldap:/etc/postfix/ldap-aliases.cf`
retourne le sAMAccountName.

### Dettes resolues

- ~~T-MAIL-LDAP-FW-RULE~~ : ferme par cette ADR.
- T-MAIL-WAZUH-ENROLL : reste ouverte (necessite regle equivalente
  mail01 -> app01:1514/1515, hors scope T-MAIL-LDAP-FW-RULE).

### Dette ajoutee

- **T-MAIL-LDAP-FW-RULE-TF-DRIFT** : la regle FW-INT et l'alias
  `host_mail01` ont ete ajoutes via API OPNsense directement (pas via
  Terraform). Un `terraform plan` sur
  `nova-syndicate-proxmox/terraform/environments/opnsense/` les detectera
  comme drift. A codifier dans `aliases.tf` + `fw_int.tf` avant prochain
  `terraform apply`.

## Consequences

Positives :
- Mail server fonctionnel pour envois inter-users AD (canal de
  notification interne, prerequis pour alerting Wazuh).
- Stack standard Debian (Postfix/Dovecot), facile a operer / former.
- Isolation DMZ preservee (pas d'ouverture FW supplementaire).
- DKIM + SPF + DMARC publies = passe les checks anti-spoofing internes.

Negatives / dettes :
- **T-MAIL-LDAP-FW-RULE** : la regle FW-INT mail01 -> dc01:636 doit etre
  ouverte pour basculer sur l'auth AD reelle (sinon, 85 users AD ne
  peuvent pas se loguer sur leur boite). Tant que la regle n'est pas
  ouverte, seuls les users provisionnes en local (fabien.bonnet,
  alexandre.gautier, postmaster) peuvent envoyer/recevoir.
- **T-MAIL-RAM-REBOOT** : hot-add memory 1G->2G non actif (hotplug=memory
  non configure sur la VM 101). Sera applique au prochain reboot. Pas
  bloquant pour la charge actuelle.
- **T-MAIL-WAZUH-ENROLL** : agent-auth wazuh sur mail01 echoue car
  mail01(DMZ) -> app01(VLAN20):1515 egalement bloque par FW-INT. La
  config ossec.conf + localfiles est en place, l'enrollement se fera
  apres ouverture FW (meme dette que ci-dessus, regle commune).
- **T-MAIL-TLS-WILDCARD** : cert self-signed pour l'instant. A remplacer
  par wildcard mkcert quand la chaine sera ajoutee aux postes Lyon.

## Alternatives ecartees

- **Exchange / O365** : viole l'objectif "infra interne".
- **Postfix-only + procmail** : pas d'IMAP, pas d'utilisable pour les
  postes Outlook/Thunderbird des users finaux.
- **Roundcube embarque** : sera la V2 (webmail), pas dans le scope T-MAIL-PROD.
- **Ouverture FW DMZ->VLAN20** : refusee initialement pour preserver
  l'isolement NIS2 a chaud. Sera traitee dans T-MAIL-LDAP-FW-RULE avec
  cible LDAPS uniquement (TCP/636) + ACL source mail01 only.

## Annexes

- Role Ansible : `nova-syndicate-ansible/roles/mail_server/`
- Playbook : `nova-syndicate-ansible/playbooks/deploy_mail.yml`
- Runbook : `nova-syndicate-proxmox/docs/runbook/mail-server.md`
- Regles Wazuh : `nova-syndicate-ansible/roles/wazuh_manager/vars/nis2_rules.yml`
  (rules 100011, 100012)
