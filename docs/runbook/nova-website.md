# Runbook : Site public Nova Syndicate

URL : `https://www.nova-syndicate.local` (alias `https://nova-syndicate.local`)
Backend : `APP01` (192.168.20.13)
Host VM : Proxmox VMID `106`

## Architecture

Site vitrine statique (one-page hi-fi corporate) servi par nginx depuis `/var/www/nova-syndicate/`. Aucune authentification, accessible librement au sein du domaine.

## Composants

| Element | Chemin |
|---|---|
| Contenu HTML | `/var/www/nova-syndicate/index.html` (~23 ko) |
| Vhost nginx | `/etc/nginx/sites-available/website.conf` |
| Cert wildcard | `/etc/ssl/certs/nova-syndicate-wildcard.crt` (mkcert, exp. 2028-08-01) |
| Logs | `/var/log/nginx/website-{access,error}.log` |

## Deploiement / mise a jour du contenu

Modifier `roles/website/files/index.html` dans `nova-syndicate-ansible`, puis :

```bash
cd ~/Documents/Nova-syndicate-Code/nova-syndicate-ansible
ansible-playbook playbooks/deploy_website.yml \
  --vault-password-file ~/.ansible/nova_vault_pass
```

Le handler `reload nginx` se declenche automatiquement si le fichier change.

## Operations courantes

### Verifier la disponibilite

```bash
curl -k -I --resolve www.nova-syndicate.local:443:192.168.20.13 \
  https://www.nova-syndicate.local/
# attendu : HTTP/2 200
```

### Verifier les security headers

```bash
curl -k -I --resolve www.nova-syndicate.local:443:192.168.20.13 \
  https://www.nova-syndicate.local/ | grep -E "X-Frame|X-Content|Strict-Transport|Referrer"
```

Doivent etre presents : X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy.

## Cache strategy

Les ressources statiques (`*.css`, `*.js`, `*.png`, `*.svg`, `*.woff2`, `*.ico`) sont cachees 1 an avec `Cache-Control: public, immutable`. Si une ressource doit etre invalidee avant cette echeance, changer son nom (fingerprint URL) plutot que de purger.

## Troubleshooting

### Site non joignable depuis le poste

Verifier le `/etc/hosts` local :
```
192.168.20.13  www.nova-syndicate.local nova-syndicate.local
```

### Certificat invalide

Le cert wildcard mkcert est genere localement ; il est de confiance uniquement sur les postes ou la CA mkcert a ete installee. Sur d'autres postes : `curl -k ...` ou installer la CA mkcert.

### nginx fail

```bash
ansible app01 -b -m shell -a "nginx -t && systemctl status nginx --no-pager"
```

## Restauration

```bash
ssh root@100.112.113.2 'qm rollback 106 pre-nova-portail-2026-05-17'
```

(meme snapshot que le portail metier, deploye en sequence)

## Mise a jour DNS / hosts file

Le site est accessible via :
- `www.nova-syndicate.local` (alias canonique)
- `nova-syndicate.local`

Sur les postes utilisateurs ou DC01, ajouter le mapping vers 192.168.20.13.
