# Runbook -- WEB01 (172.16.1.2)

## Perimetre

WEB01 (172.16.1.2), serveur web DMZ. nginx sur port 80. Pas de TLS pour l'instant.
Accessible depuis BASTION et le LAN Lyon via les regles firewall DMZ.

## Acces

```bash
ssh debian@172.16.1.2
# Ou depuis bastion sans password (cle deployee 2026-05-09) :
ssh debian@192.168.15.2 "ssh debian@172.16.1.2 'hostname'"
```

## Procedure de deploiement (2026-05-09)

```bash
# 1. Installation nginx
sudo apt update && sudo apt install -y nginx

# 2. Page placeholder
sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Nova Syndicate - Service Web</title>
  ...
</head>
</html>
EOF

# 3. Config site
sudo tee /etc/nginx/sites-available/default > /dev/null << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name web01.nova-syndicate.local;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    location / { try_files $uri $uri/ =404; }
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

# 4. Test et demarrage
sudo nginx -t && sudo systemctl enable --now nginx

# 5. Verification depuis BASTION
ssh debian@192.168.15.2 "curl -sI http://172.16.1.2 | head -3"
```

## Operations courantes

### Verifier nginx

```bash
sudo systemctl status nginx
sudo nginx -t
sudo ss -tlnp | grep :80
```

### Logs nginx

```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Recharger config sans coupure

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Etat actuel (2026-05-09)

- nginx 1.22.1 actif, ecoute 80
- Page placeholder Nova Syndicate deployee
- Headers securite basiques : X-Frame-Options, X-Content-Type-Options, Referrer-Policy
- Accessible depuis BASTION (HTTP 200 confirme)
- Pas de TLS (reserve pour production)
- Pas de Wazuh agent (voir TODO ci-dessous)

## TODO production (a faire avec Matthieu)

- [ ] TLS : Let's Encrypt (necessite DNS public et Cloudflare Tunnel)
- [ ] Cloudflare Tunnel : cloudflared install OK mais enrollment a faire
- [ ] Wazuh agent : installer et enroller WEB01 dans le SIEM
- [ ] Monitoring nginx logs dans Wazuh : ajouter /var/log/nginx/access.log dans ossec.conf agent
- [ ] Header HSTS : apres TLS uniquement (Strict-Transport-Security)
- [ ] Header CSP : Content-Security-Policy selon le contenu final
- [ ] Deployer le contenu de production (remplacer la page placeholder)
- [ ] Backup configuration nginx dans Ansible playbooks
