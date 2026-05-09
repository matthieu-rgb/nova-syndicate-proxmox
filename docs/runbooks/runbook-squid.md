# Runbook -- Squid Proxy (multi-site)

## Perimetre

| Hote | IP | Site | Subnet servi |
|------|-----|------|-------------|
| proxy-lyon01 | 192.168.20.14 | Lyon | 192.168.20.0/28 + 192.168.30.0/26 |
| proxy-mrs01 | 192.168.40.11 | Marseille | 192.168.40.0/26 |

Port : 3128. Mode proxy explicite (HTTP_PROXY=http://<ip>:3128).

## Differences de configuration Lyon vs MRS

| Parametre | Lyon | MRS |
|-----------|------|-----|
| visible_hostname | (non defini) | proxy-mrs01.nova-syndicate.local |
| acl localnet | 192.168.20.0/28 + 192.168.30.0/26 | 192.168.40.0/26 |
| forwarded_for | off | off |
| via | off | off |
| Logs | /var/log/squid/ | /var/log/squid/ |
| Cache | ufs 1000 MB | ufs 1000 MB |

## Procedure de deploiement multi-site (2026-05-09)

```bash
# 1. Installer squid
sudo apt update && sudo apt install -y squid

# 2. Backup config defaut
sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.bak-$(date +%Y%m%d-%H%M)

# 3. Ecrire la config adaptee au site
sudo tee /etc/squid/squid.conf > /dev/null << 'EOF'
# Nova Syndicate - Squid Proxy
# NIS2 art. 21.2.e - Protection couche 7

http_port 3128

visible_hostname proxy-<site>.nova-syndicate.local

acl localnet src <subnet_lan_site>

forwarded_for off
via off

http_access allow localnet
http_access deny all

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log

cache_dir ufs /var/spool/squid 1000 16 256
maximum_object_size 50 MB
EOF

# 4. Valider la config
sudo squid -k parse

# 5. Demarrer (si squid deja lance via apt : restart)
sudo systemctl restart squid
sleep 5
sudo systemctl is-active squid
sudo ss -tlnp | grep :3128

# 6. Test fonctionnel depuis le proxy lui-meme
curl -x http://<ip_proxy>:3128 -sI --max-time 10 http://www.debian.org | head -3
# Attendu : HTTP/1.1 302 ou 200

# 7. Verifier les logs
sudo tail -5 /var/log/squid/access.log
# Attendu : TCP_MISS (relais) pas TCP_DENIED
```

## Operations courantes

### Verifier le statut

```bash
sudo systemctl status squid
sudo ss -tlnp | grep :3128
```

### Logs acces

```bash
sudo tail -f /var/log/squid/access.log
```

### Recharger la config sans coupure

```bash
sudo squid -k parse && sudo systemctl reload squid
```

### Ajouter un reseau autorise

Modifier `/etc/squid/squid.conf` :
```
acl localnet src 192.168.XX.0/YY
```
Puis recharger.

## Notes NIS2

- `forwarded_for off` : ne pas exposer les IPs internes aux sites distants
- `via off` : ne pas exposer l'existence du proxy
- Retention logs : 30 jours (logrotate default Debian suffit)
- Pour audit NIS2 long terme : centraliser les logs dans Wazuh SIEM

## TODO

- [ ] Wazuh agent sur proxy-mrs01 (non enrole -- hors scope session AFK)
- [ ] Monitoring /var/log/squid/access.log dans Wazuh (les deux sites)
- [ ] Whitelist par VLAN (T-SQUID -- necessite T3 complete, maintenant prerequis OK)
- [ ] Proxy transparent (redirection pf port 80/443 vers Squid)
- [ ] Alerting Prometheus si squid tombe (blackbox exporter ou node_exporter + script)
