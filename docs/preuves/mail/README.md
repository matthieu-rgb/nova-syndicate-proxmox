# Preuves mail01 -- Nova Syndicate

Captures reelles effectuees le **2026-06-05** depuis `mail01` (VMID 101, DMZ 172.16.1.3).
Methode d'acces : `ssh -J root@100.112.113.2 debian@172.16.1.3`

## Fichiers

| Fichier | Contenu |
|---|---|
| `01-services-status.txt` | systemctl status postfix/dovecot/opendkim + versions |
| `02-ports-ecoute.txt` | ss -tlnp : ports 25/143/587/993 en ecoute |
| `03-auth-ldaps-dc01.txt` | doveadm auth test : auth LDAPS contre DC01:636 (step-ca) |
| `04-envoi-reception-interne.txt` | swaks envoi fabien.bonnet->marine.fleury + maildir + contenu |
| `05-mail-log.txt` | /var/log/mail.log : transaction 5B26320AED complete |

## Versions

- Postfix  : 3.7.11
- Dovecot  : 2.3.19.1 (9b53102964)
- OpenDKIM : 2.11.0

## Ce qui est prouve

1. **Services actifs** : postfix enabled+active, dovecot running, opendkim running
2. **Ports** : 25 (SMTP), 587 (submission), 143 (IMAP), 993 (IMAPS)
3. **Auth LDAPS** : Dovecot authentifie via LDAPS:636 contre DC01 (cert step-ca Nova Root CA)
4. **Envoi/reception** : mail fabien.bonnet -> marine.fleury, queue-ID 5B26320AED, livraison LMTP en 0.17s, message dans maildir new/
5. **DKIM** : signature rsa-sha256 presente dans le message recu (domaine nova-syndicate.local, selecteur mail)

## Bug identifie et corrige lors de la capture

`/etc/postfix/ldap-aliases.cf` pointait `tls_ca_cert_file = /etc/ssl/certs/nova-CA.crt`
(ancien cert auto-signe Samba, obsolete depuis migration step-ca ADR-0034).
Corrige le 2026-06-05 vers `ca-certificates.crt` (bundle systeme, inclut Nova Root CA).
**A repercuter dans le role Ansible mail** : variable `postfix_ldap_tls_ca_cert_file`.
Dette tracee : T-MAIL-LDAP-CA-FIX.
