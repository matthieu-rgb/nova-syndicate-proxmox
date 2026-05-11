# Runbook : Authelia portail MFA (APP01)

## Contexte

Authelia v4.39.19 sur APP01 (192.168.20.13) protege les services web internes par forward authentication Nginx.

Architecture : Client --> Nginx (443) --> Authelia (127.0.0.1:9091) --> LDAP DC01 (LDAPS 636) --> Service backend.

---

## Services et ports

| Service | Port | Acces |
|---|---|---|
| Nginx HTTPS | 443 | Externe VLAN 20 |
| Nginx HTTP redirect | 80 | Externe VLAN 20 |
| Authelia portal | 9091 (localhost) | Interne APP01 uniquement |
| Grafana (protege) | 3000 (localhost) | Via Nginx uniquement |

---

## Procedure : Premier login utilisateur

### Prerequis

- Compte actif dans l'AD nova-syndicate.local (DC01)
- Navigateur web avec acces au VLAN 20 (192.168.20.0/28)
- Application TOTP (Google Authenticator, Authy, Bitwarden)

### Etape 1 : Acceder au portal

```
https://192.168.20.13/
```

Le navigateur affiche un avertissement TLS (certificat autosigne). Accepter l'exception.
Redirection automatique vers `/authelia/?rd=https://...`

### Etape 2 : Login LDAP

Saisir le `sAMAccountName` (ex: `fabien.bonnet`) et le mot de passe AD.

### Etape 3 : Enregistrement TOTP (premier login)

Authelia affiche un QR code pour l'enregistrement TOTP.
Scanner avec l'application TOTP. Valider avec le premier code genere.
L'issuer est `nova-syndicate.local`.

### Etape 4 : Acces Grafana

Apres validation TOTP, redirection vers Grafana. Session valide 1h (inactivite 5 min).

---

## Procedure : Ajout protection nouveau service

Pour proteger un nouveau service web via Authelia :

```nginx
# Dans le server block nginx
location /nouveau-service/ {
    auth_request /authelia/api/verify;
    auth_request_set $target_url $scheme://$http_host$request_uri;
    auth_request_set $user $upstream_http_remote_user;
    error_page 401 =302 https://$http_host/authelia/?rd=$target_url;

    proxy_pass http://127.0.0.1:<PORT_SERVICE>/;
    proxy_set_header Remote-User $user;
}
```

Puis `nginx -t && systemctl reload nginx`.

---

## Procedure : Revocation acces utilisateur

### Revocation immediate (acces AD)

```bash
# Sur DC01 (Proxmox console ou SSH root@192.168.18.50 -> qm guest exec 103)
samba-tool user setpassword <username> --newpassword=$(openssl rand -base64 32)
# Ou desactivation complete :
samba-tool user disable <username>
```

La revocation est immediate : le prochain `auth_request` Authelia echoue, la session existante est invalidee au prochain rafraichissement.

### Revocation de session Authelia active

Si necessite de revoquer immediatement une session active sans modifier AD :

```bash
# Redemarrer Authelia invalide toutes les sessions
ssh debian@192.168.15.2  # via bastion01 + MFA
ssh app01.nova-syndicate.local
sudo systemctl restart authelia
```

Note : cela deconnecte tous les utilisateurs.

---

## Procedure : Troubleshooting connexion LDAP

### Verifier la connectivite DC01

```bash
qm guest exec 106 -- bash -c 'timeout 3 bash -c "echo > /dev/tcp/192.168.20.10/636" && echo LDAPS_OK || echo LDAPS_FAIL'
```

### Tester le bind svc-authelia

```bash
qm guest exec 106 -- bash -c 'LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://192.168.20.10:636 \
  -D "CN=svc authelia,OU=Service-Accounts,DC=nova-syndicate,DC=local" \
  -w "<MOT_DE_PASSE>" \
  -b "DC=nova-syndicate,DC=local" \
  -s base "(objectClass=*)" dn 2>&1'
```

### Verifier les logs Authelia

```bash
qm guest exec 106 -- bash -c 'tail -50 /var/lib/authelia/authelia.log'
```

---

## Procedure : Renouvellement certificat TLS Nginx

Certificat autosigne valide jusqu'au 2028-05-11.

```bash
# Sur APP01
ssh app01 (via bastion01)
sudo openssl req -x509 -nodes -days 730 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/app01.key \
  -out /etc/nginx/ssl/app01.crt \
  -subj "/CN=app01.nova-syndicate.local/O=Nova-Syndicate/C=FR" \
  -addext "subjectAltName=DNS:app01.nova-syndicate.local,IP:192.168.20.13"
sudo nginx -t && sudo systemctl reload nginx
```

---

## Procedure : Sauvegarde et restauration

### Sauvegarde

La base Authelia est a `/var/lib/authelia/db.sqlite3`. Elle contient les TOTP secrets enregistres par les utilisateurs.

```bash
# Sur APP01
sudo cp /var/lib/authelia/db.sqlite3 /var/backup/authelia-db-$(date +%Y%m%d).sqlite3
```

BorgBackup couvre `/var/lib/authelia/` si inclus dans le scope de backup01.

### Restauration

```bash
sudo systemctl stop authelia
sudo cp /var/backup/authelia-db-YYYYMMDD.sqlite3 /var/lib/authelia/db.sqlite3
sudo chown authelia:authelia /var/lib/authelia/db.sqlite3
sudo systemctl start authelia
```

Apres restauration, les utilisateurs retrouvent leurs TOTP enregistres (pas de re-enrollment).

---

## Procedure : Reset TOTP utilisateur

Si un utilisateur perd son device TOTP :

```bash
# Via authelia CLI sur APP01
ssh app01 (via bastion01)
sudo authelia storage totp delete --username <sAMAccountName> --config /etc/authelia/configuration.yml
```

Le prochain login affiche un nouveau QR code pour l'enrollment.

---

## Tests apres modification

Apres toute modification de configuration Authelia ou Nginx :

```bash
# 1. Valider config Authelia
authelia validate-config --config /etc/authelia/configuration.yml

# 2. Valider config Nginx
nginx -t

# 3. Redemarrer avec verification
systemctl restart authelia && sleep 2 && systemctl is-active authelia

# 4. Test fonctionnel depuis APP01 localhost
curl -sk -o /dev/null -w "Grafana: HTTP %{http_code}\n" https://127.0.0.1/
curl -sk -o /dev/null -w "Portal: HTTP %{http_code}\n" https://127.0.0.1/authelia/

# Attendu : Grafana=302, Portal=200
```

---

## Mapping NIS2

| Article NIS2 | Controle |
|---|---|
| Art. 21.b (MFA acces distants) | LDAP AD + TOTP sur tous les services web |
| Art. 21.b (acces privilegies) | Grafana/Prometheus = supervision critique, 2FA obligatoire |
| Art. 21.e (MFA systemes critiques) | Authelia = point d'entree unique pour les web services |
| Art. 21.i (journalisation) | /var/lib/authelia/authelia.log (tentatives, sessions, erreurs LDAP) |

---

## Dette technique

- **T-AUTHELIA-TLS-PKI** : remplacer le certificat autosigne. Phase III.
- **T-AUTHELIA-LDAP-CERT** : `skip_verify: true` -> distribuer CA Samba + `skip_verify: false`. Phase III.
- **T-AUTHELIA-ANSIBLE** : role Ansible `authelia` avec vault pour le mot de passe svc-authelia. Phase IV.
- **T-AUTHELIA-PROMETHEUS** : etendre la protection Nginx a Prometheus (port 9090) et Wazuh dashboard. Phase III.

---

## References

- ADR-0019 : Decision Authelia (ce document est complementaire)
- ADR-0018 : MFA TOTP bastion (complementaire)
- Configuration : `/etc/authelia/configuration.yml` sur APP01 (440 authelia:authelia)
- Logs : `/var/lib/authelia/authelia.log`
- Base donnees TOTP/sessions : `/var/lib/authelia/db.sqlite3`
- Nginx vhost : `/etc/nginx/sites-available/nova-syndicate`
- Authelia documentation : https://www.authelia.com/docs/
