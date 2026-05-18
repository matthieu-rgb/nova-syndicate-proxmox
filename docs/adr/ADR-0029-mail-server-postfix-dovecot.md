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
