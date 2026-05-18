# Runbook mail-server (mail01 - Postfix/Dovecot/OpenDKIM)

## Identite

| Cle | Valeur |
|-----|--------|
| VMID Proxmox | 101 |
| IP | 172.16.1.3/29 (DMZ Lyon, vmbr3) |
| Hostname | mail.nova-syndicate.local |
| OS | Debian 12 |
| RAM | 2 GB (effective apres prochain reboot, hotplug=memory non actif) |
| Services | Postfix 3.7, Dovecot 2.3 (IMAP+LMTP), OpenDKIM 2.11 |
| Ports ecoutes | 25/tcp, 587/tcp, 143/tcp, 993/tcp, 8891/tcp (localhost) |
| Ticket creation | T-MAIL-PROD-2026-05-18 |
| ADR | [ADR-0029](../adr/ADR-0029-mail-server-postfix-dovecot.md) |

## Acces

mail01 est en DMZ. Pas d'acces SSH direct depuis le poste admin (bastion
MFA n'a pas de route vers DMZ). Trois canaux d'admin :

1. **Bastion -> mail01** : via FW-INT si la regle BASTION->DMZ est ouverte
   (verifier OPNsense `Firewall > Rules > INT_LAN > to DMZ`).
2. **Console Proxmox** : `qm terminal 101` depuis Proxmox host.
3. **QEMU guest agent** (utilise en deploiement initial) :
   ```sh
   ssh proxmox 'qm guest exec 101 -- /bin/bash -c "<cmd>"'
   ```

## Operations courantes

### Redemarrage propre des services

```sh
systemctl restart opendkim   # toujours avant postfix (milter)
systemctl restart dovecot
systemctl restart postfix
```

### Verifier que tout est UP

```sh
ss -tlnp | grep -E ':(25|587|143|993|8891)'
# Attendu : 5 lignes
systemctl is-active postfix dovecot opendkim
# Attendu : 3x "active"
```

### Tail logs

```sh
tail -f /var/log/mail.log     # Postfix + LMTP delivery
tail -f /var/log/dovecot.log  # IMAP + auth
journalctl -u opendkim -f     # DKIM signing
```

### Ajouter un user virtuel local (mode passwd-file)

Tant que le backend LDAP n'est pas active (cf. ADR-0029, dette
T-MAIL-LDAP-FW-RULE), les users mail sont locaux :

```sh
# 1. Generer un hash BLF-CRYPT
PW=$(openssl rand -base64 16)
HASH=$(doveadm pw -s BLF-CRYPT -p "$PW")

# 2. Append a /etc/dovecot/passwd
echo "alice.dupont@nova-syndicate.local:$HASH::::::" >> /etc/dovecot/passwd

# 3. Append a /etc/postfix/vmailbox + postmap
echo "alice.dupont@nova-syndicate.local  nova-syndicate.local/alice.dupont/" \
  >> /etc/postfix/vmailbox
postmap /etc/postfix/vmailbox

# 4. Verifier
doveadm auth test alice.dupont@nova-syndicate.local "$PW"
```

### Bascule auth LDAP/AD (DONE T-MAIL-LDAP-FW-RULE-2026-05-18)

Mode par defaut : `mail_auth_backend: ldap`. Service account
`svc-mail-ldap` (OU=Service-Accounts, vault `vault_svc_mail_ldap_password`)
bind LDAPS sur dc01:636 via la regle FW-INT
`fwint_mail01_to_dc01_ldaps` (sequence 1, log=true).

```sh
# Verifier connectivite
ssh mail01 'timeout 3 bash -c "echo > /dev/tcp/192.168.20.10/636" && echo OK'

# Verifier auth d'un user AD (sans deployer)
ssh mail01 'doveadm auth test fabien.bonnet <pwd-AD>'

# Forcer fallback temporaire passwd-file (debug)
ansible-playbook playbooks/deploy_mail.yml -e mail_auth_backend=passwdfile
```

### Rotation password svc-mail-ldap

```sh
# 1. Generer nouveau pwd + set sur dc01
NEWPW=$(openssl rand -base64 24 | tr -d '/+=' | head -c 28)
ssh dc01 "samba-tool user setpassword svc-mail-ldap --newpassword='$NEWPW'"

# 2. Mettre a jour vault
ansible-vault edit inventory/group_vars/all/vault.yml
# -> remplacer vault_svc_mail_ldap_password

# 3. Replay role (regenere dovecot-ldap.conf.ext + ldap-aliases.cf)
ansible-playbook playbooks/deploy_mail.yml
```

## Tests fonctionnels (replay Phase 6)

```sh
# T1 : delivery locale
echo "Test 1" | mail -s "T1" fabien.bonnet@nova-syndicate.local
ls /var/vmail/nova-syndicate.local/fabien.bonnet/new/

# T2 : SMTP AUTH 587 + TLS
swaks --to alexandre.gautier@nova-syndicate.local \
      --from fabien.bonnet@nova-syndicate.local \
      --server localhost --port 587 \
      --auth LOGIN --auth-user fabien.bonnet@nova-syndicate.local \
      --auth-password '<pwd>' --tls

# T3 : DKIM
grep DKIM-Signature /var/vmail/nova-syndicate.local/alexandre.gautier/new/* | head -1

# T4 : SPF (depuis dc01)
ssh dc01 'dig +short TXT nova-syndicate.local @127.0.0.1' | grep spf1

# T5 : IMAPS login
echo "a1 LOGIN fabien.bonnet@nova-syndicate.local <pwd>
a2 SELECT INBOX
a3 LOGOUT" | openssl s_client -quiet -connect localhost:993 -crlf
```

## Rollback

Snapshot disponible : `pre-t-mail-prod-2026-05-18` (VMID 101 + 103).

```sh
ssh proxmox 'qm rollback 101 pre-t-mail-prod-2026-05-18'
# Rollback DNS sur dc01 si necessaire :
ssh proxmox 'qm rollback 103 pre-t-mail-prod-2026-05-18'
```

Apres rollback DC01, attention : tous les ajouts DNS post-snapshot
sont perdus. Verifier qu'aucune autre operation n'a modifie la zone
entre temps.

## Troubleshooting

| Symptome | Cause probable | Fix |
|----------|---------------|-----|
| `connect to private/dovecot-lmtp: Permission denied` | socket LMTP mal cree | restart dovecot + verifier `/var/spool/postfix/private/dovecot-lmtp` owner postfix:postfix mode 0600 |
| swaks `TLS not available: requires Net::SSLeay` | perl modules manquants | `apt install libnet-ssleay-perl libio-socket-ssl-perl` |
| OpenDKIM `key data is not secure: keyfile is accessible by other users` | perms cle DKIM | `chmod 600 /etc/opendkim/keys/<domain>/<sel>.private; chown opendkim:opendkim` |
| Mail bloque, log `relay access denied` | `mynetworks` mal configure ou SASL non valide | verifier `postconf mynetworks` + tester swaks --auth |
| `samba-tool dns add ... TXT` plante sur DKIM long | bug Python samba >255 chars | utiliser script LDB direct : `/root/add-dkim.py` sur dc01 (voir ADR-0029) |
| Wazuh agent stuck `Requesting a key from server` | DMZ->VLAN20:1515 bloque | meme dette que LDAP, attendre T-MAIL-LDAP-FW-RULE |

## Donnees sensibles

Les passwords des 3 users locaux (postmaster, fabien.bonnet,
alexandre.gautier) generes en Phase 6 sont temporaires et a rotater
des l'ouverture FW + bascule LDAP. Stockes UNIQUEMENT en hash BLF-CRYPT
dans `/etc/dovecot/passwd` (mode 0640, root:dovecot).

Pour rotation :
```sh
NEWPW=$(openssl rand -base64 16)
HASH=$(doveadm pw -s BLF-CRYPT -p "$NEWPW")
sed -i "s|fabien.bonnet@nova-syndicate.local:[^:]*|fabien.bonnet@nova-syndicate.local:$HASH|" /etc/dovecot/passwd
echo "Nouveau pwd fabien.bonnet : $NEWPW" # transmis au user via canal hors-bande
```
