# Runbook -- MAIL01 (172.16.1.3)

## Perimetre

MAIL01 (172.16.1.3), serveur de messagerie DMZ. Postfix + Dovecot.
Etat actuel : mode sandbox loopback-only. Pas d'ecoute externe.
Config production (LDAP, TLS, DKIM, ecoute externe) a faire avec Matthieu.

## Acces

```bash
ssh debian@172.16.1.3
```

## Etat actuel (2026-05-09)

| Service | Version | Port | Ecoute | Statut |
|---------|---------|------|--------|--------|
| Postfix | 3.7.x | 25 | 127.0.0.1 uniquement | active |
| Dovecot | 2.3.19 | 143 (IMAP) | 127.0.0.1 uniquement | active |

Verification :
```bash
sudo ss -tlnp | grep -E ":25|:143"
# Attendu : 127.0.0.1:25 et 127.0.0.1:143 (pas 0.0.0.0)
```

## Configuration Postfix (main.cf)

Parametres cles appliques via `postconf -e` :
```
myhostname = mail01.nova-syndicate.local
mydomain = nova-syndicate.local
myorigin = $mydomain
inet_interfaces = loopback-only
mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain
mynetworks = 127.0.0.0/8 [::1]/128
smtpd_relay_restrictions = permit_mynetworks defer_unauth_destination
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
```

## Configuration Dovecot

Parametres appliques :
- `protocols = imap` (/etc/dovecot/dovecot.conf)
- `listen = 127.0.0.1, ::1` (/etc/dovecot/dovecot.conf)
- `mail_location = maildir:~/Maildir` (/etc/dovecot/conf.d/10-mail.conf)
- `disable_plaintext_auth = no` (/etc/dovecot/conf.d/10-auth.conf - OK car loopback uniquement)
- `auth_mechanisms = plain`
- `!include auth-system.conf.ext` (auth via /etc/passwd local)

## Test de livraison locale (sandbox)

```bash
# Depuis MAIL01 :
echo "Test $(date)" | mail -s "Test Nova Syndicate" debian@localhost
# Verifier la boite :
sudo tail -20 /var/mail/debian
```

Test valide 2026-05-09 : mail livre, en-tete "mail01.nova-syndicate.local" confirme.

## Operations courantes

### Verifier les services

```bash
sudo systemctl status postfix dovecot
sudo ss -tlnp | grep -E ":25|:143"
```

### File d'attente postfix

```bash
sudo mailq
sudo postfix flush
```

### Logs

```bash
sudo journalctl -u postfix -n 20
sudo journalctl -u dovecot -n 20
```

## TODO production (a faire avec Matthieu)

- [ ] LDAP auth Dovecot (choix architecture : AD/Samba ou OpenLDAP)
- [ ] Ouvrir ports 25/587/993 uniquement apres TLS + auth en place
- [ ] TLS : certificat interne (PKI Nova Syndicate) ou Let's Encrypt (necessite DNS)
- [ ] DKIM/SPF/DMARC : necessite domaine DNS public (nova-syndicate.fr)
- [ ] Pointer DNS MX : nova-syndicate.local MX -> mail01
- [ ] postscreen pour antispam (si mail externe prevu)
- [ ] Integraton Wazuh : /var/log/mail.log dans ossec.conf agent (installer agent d'abord)
- [ ] Installer Wazuh agent sur MAIL01 (non enrole)
- [ ] Backup config Postfix/Dovecot dans Ansible playbooks
- [ ] Tester avec maildir format pour Dovecot IMAP (actuellement livraison mbox /var/mail/)
