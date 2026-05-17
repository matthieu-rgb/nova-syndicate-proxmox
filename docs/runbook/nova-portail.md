# Runbook : Portail metier Nova Syndicate

URL : `https://portail.nova-syndicate.local`
Backend : `APP01` (192.168.20.13)
Host VM : Proxmox VMID `106`
ADR : [ADR-0023](../adr/ADR-0023-portail-metier-architecture.md)

## Architecture

```
Navigateur -> nginx 443 (portail.nova-syndicate.local)
            |
            +-- Authelia 127.0.0.1:9091 (MFA TOTP + AD LDAP DC01)
            |
            +-- gunicorn 127.0.0.1:5000 (4 workers, Flask)
                  |
                  +-- mysql-connector-python pool(5) -> DB01:3306 / nova_portail
```

## Composants installes

| Element | Chemin / nom |
|---|---|
| Code Flask | `/opt/nova-portail/app/app.py` |
| Templates HTML | `/opt/nova-portail/templates/` (8 fichiers) |
| Static CSS | `/opt/nova-portail/static/portail.css` |
| Venv Python | `/opt/nova-portail/venv` |
| Env vars (DB creds) | `/opt/nova-portail/.env` (0600 www-data) |
| Service systemd | `/etc/systemd/system/nova-portail.service` |
| Vhost nginx | `/etc/nginx/sites-available/portail.conf` |
| Logs gunicorn | `/var/log/nova-portail/{access,error}.log` |
| Logs nginx | `/var/log/nginx/portail-{access,error}.log` |
| Database | `db01:3306 / nova_portail` user `nova_portail` |

## Routes

| Route | Methode | Auth requis | Role minimum |
|---|---|---|---|
| `/health` | GET | non | -- |
| `/` | GET | Authelia | tout utilisateur |
| `/tarifs` | GET | Authelia | tout utilisateur |
| `/tarifs/<id>` | GET | Authelia | tout utilisateur |
| `/api/tarifs` | GET | Authelia | tout utilisateur |
| `/profil` | GET | Authelia | tout utilisateur |
| `/clients` | GET | Authelia | admin (Domain Admins / Administrators / Logistique Admins) |
| `/historique` | GET | Authelia | admin (idem) |

## Deploiement

```bash
cd ~/Documents/Nova-syndicate-Code/nova-syndicate-ansible
ansible-playbook playbooks/deploy_portail.yml \
  --vault-password-file ~/.ansible/nova_vault_pass
```

Le playbook est idempotent : il peut etre relance sans risque. Les handlers reload nginx et restart nova-portail uniquement si un fichier templated change.

## Operations courantes

### Voir les logs en direct

```bash
ansible app01 -b -m shell -a "journalctl -u nova-portail -f"
# ou directement sur la VM :
ssh debian@192.168.20.13 'sudo tail -f /var/log/nova-portail/error.log'
```

### Redemarrer le service

```bash
ansible app01 -b -m systemd -a "name=nova-portail state=restarted"
```

### Verifier l'etat

```bash
bash scripts/test-nova-portail.sh
```

### Acceder a la DB pour debug (lecture seule)

```bash
ansible app01 -b -m shell \
  -a "source /opt/nova-portail/.env && mysql -h \$DB_HOST -u \$DB_USER -p\$DB_PASSWORD nova_portail -e 'SELECT COUNT(*) FROM tarifs;'"
```

### Verifier l'audit trail

Via le portail (admin) : `https://portail.nova-syndicate.local/historique`.

Directement en SQL :
```sql
SELECT timestamp, user_ad, action, resource_type, resource_id, ip_source
FROM audit_consultations
ORDER BY timestamp DESC
LIMIT 50;
```

## Troubleshooting

### Symptome : page blanche / 502 Bad Gateway

1. `systemctl status nova-portail` -- si `failed`, `journalctl -u nova-portail -n 50`.
2. `ss -lntp | grep 5000` -- gunicorn doit ecouter sur 127.0.0.1:5000.
3. `tail /var/log/nova-portail/error.log` -- traces Python.

Causes frequentes :
- mauvais mot de passe DB (changer dans `vault.yml` + redeployer).
- DB01 down ou MariaDB down (`ansible db01 -m systemd -a "name=mariadb state=started"`).

### Symptome : boucle de redirection vers Authelia

1. Verifier cookie `authelia_session` envoye sur `.nova-syndicate.local`.
2. `curl -k https://auth.nova-syndicate.local/api/state` -- doit etre 200.
3. Le vhost portail doit avoir `error_page 401 =302 ...` (pas autre code).

### Symptome : 403 "Acces interdit" inattendu

Verifier les groupes AD remontes par Authelia :

```bash
ssh debian@192.168.20.13 'sudo tail /var/log/nginx/portail-access.log'
# Cherchez le header Remote-Groups dans Authelia
ssh debian@192.168.20.13 'sudo journalctl -u authelia -n 30'
```

Les groupes admin sont definis dans `app.py` (`ADMIN_GROUPS`).

### Symptome : audit_consultations grandit trop

Strategie de retention (a planifier T-PORTAIL-BACKUP-AUDIT) :
```sql
-- conserver 13 mois glissants
DELETE FROM audit_consultations WHERE timestamp < DATE_SUB(NOW(), INTERVAL 13 MONTH);
```
Le RGPD impose une duree limitee ; NIS2 demande la tracabilite des acces aux ressources critiques sans imposer de duree precise -> 13 mois est un bon compromis (a inscrire dans la PSSI).

## Restauration

Snapshot Proxmox cree avant deploiement : `pre-nova-portail-2026-05-17` sur VM 106.

```bash
ssh root@100.112.113.2 'qm rollback 106 pre-nova-portail-2026-05-17'
```

Pour la DB (table nova_portail), restaurer depuis le backup Borg :
```bash
ssh root@backup01 'borg list /var/backups/borg/db01 | tail -5'
# choisir l'archive, monter, et restaurer le dump mysql
```

## Surveillance

- Grafana : panel a creer pour `nova-portail` (requetes / sec, latence, 5xx) -- T-MON-PORTAIL.
- Wazuh : agent app01 surveille /var/log/nova-portail/*.log.
- Healthcheck externe : pinger `/health` toutes les 60s depuis le bastion.

## Anti-lockout

- Snapshot Proxmox `pre-nova-portail-2026-05-17` (VM 106)
- Tailscale 100.112.113.2 break-glass
- nova-portail.service est independant : un crash ne casse pas nginx ni Authelia
