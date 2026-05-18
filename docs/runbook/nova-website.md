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

## Exposition publique `nova.0xmatthieu.dev`

Cf. [ADR-0024](../adr/ADR-0024-exposition-publique-cloudflare.md).

### Architecture retenue : Cloudflare Tunnel

Aucun port entrant ouvert sur la Box. `cloudflared` sur APP01 maintient des connexions QUIC sortantes vers Cloudflare edge ; le trafic public arrive sur Cloudflare et est tiré dans le tunnel.

```
Internet
   -> Cloudflare edge (cert managed, WAF baseline, DDoS L3/L4)
   -> Tunnel QUIC sortant (cloudflared sur APP01, 4 connexions persistantes vers CDG)
   -> APP01 nginx server block website-public.conf (localhost:443)
```

### Fichiers cles

| Element | Chemin |
|---|---|
| Vhost public | `/etc/nginx/sites-available/website-public.conf` |
| Cert origin | `/etc/ssl/certs/nova-public-origin.crt` (self-signed 10 ans, Cloudflare en "No TLS Verify") |
| Key origin  | `/etc/ssl/private/nova-public-origin.key` (mode 600) |
| Logs nginx access | `/var/log/nginx/nova-public-access.log` |
| Logs nginx error  | `/var/log/nginx/nova-public-error.log` |
| Service tunnel | `/etc/systemd/system/cloudflared.service` |
| Logs tunnel | `journalctl -u cloudflared` |

### Tests

```bash
# Depuis l'interieur LAN Lyon
ssh root@100.112.113.2 \
  "curl -k --resolve nova.0xmatthieu.dev:443:127.0.0.1 \
   https://nova.0xmatthieu.dev/ -sI"
# (via Proxmox, redirect localhost APP01)
# HTTP/2 200, server: nginx

# Depuis Internet
ssh matthieu@100.94.199.97
curl -sI https://nova.0xmatthieu.dev/
# HTTP/2 200, server: cloudflare, security headers
```

### Cloudflare dashboard

- Cloudflare Zero Trust : https://one.dash.cloudflare.com
- Networks -> Tunnels -> `nova-public`
- Public Hostname : `nova.0xmatthieu.dev` -> HTTPS `localhost:443`, "No TLS Verify" actif
- Tunnel ID : `8f187072-181f-4bfe-a4c0-3ecb42914267`
- Le record DNS `nova` est un CNAME auto-géré -> `<tunnel-id>.cfargotunnel.com`

### Status du tunnel

```bash
ssh root@100.112.113.2 \
  "qm guest exec 106 -- bash -c 'systemctl status cloudflared --no-pager | head -15'"
```

Doit afficher `Active: active (running)` et au moins 1 `Registered tunnel connection ... cdgXX`.

### Rollback (cas urgence)

1. Stop public : `ssh -J ... debian@192.168.20.13 'sudo systemctl stop cloudflared'` -> tunnel coupe, site externe 502 (Cloudflare ne joint plus l'origin).
2. Suppression complete : `sudo cloudflared service uninstall` puis supprimer le tunnel du dashboard.
3. Si nginx casse : `ssh root@100.112.113.2 'qm rollback 106 pre-exposition-publique-2026-05-18'`.
4. Fallback Box port-forward (dormant, cf. ci-dessous) : reactiver le record A direct Cloudflare proxied + ouvrir Box port-forward. **NE FONCTIONNE PAS** actuellement sur cette Box Huawei (conntrack TCP cassé en NAT inbound) mais peut être réessayé avec un upgrade Box / un autre routeur.

### Fallback dormant : Box port-forward (non fonctionnel sur Huawei actuel)

Les patches FW-EXT-LYON et FW-INT-LYON sont **toujours en place** (idempotents, markers `DESCR_EXPOSITION_PUB_2026_05_18` / `OUTBOUND_NAT_EXPOSITION_PUB_2026_05_18`). Ils permettent un test rapide si la Box est changée ou son firmware mis à jour.

**FW-EXT-LYON** (`/conf/config.xml`) :

- Filter wan : `pass tcp from any to 192.168.20.13 port {80, 443}` (sequence 0)
- Filter wan : `pass icmp from 192.168.18.0/24 to 192.168.18.51`
- NAT rdr : `192.168.18.51:80 -> 192.168.20.13:80` et `192.168.18.51:443 -> 192.168.20.13:443`
- NAT outbound : `nat on opt1 from 192.168.18.0/24 to 192.168.20.0/28 -> 10.0.1.1` (symmetric routing)

**FW-INT-LYON** (via API plugin os-firewall) :

- UUID `40dc8dc8-e7e6-4134-8947-b8fa59c80d53` : pass tcp wan any -> 192.168.20.13:80
- UUID `7e41da05-f524-49f0-bd46-5ac2c6b5c5ac` : pass tcp wan any -> 192.168.20.13:443

Script reproductible : `scripts/opnsense/exposition-publique-apply.sh`.

### Troubleshooting

#### `nova.0xmatthieu.dev` renvoie 502 / unreachable

1. Verifier service tunnel : `qm guest exec 106 -- bash -c 'systemctl status cloudflared'` (doit etre `active`).
2. Si stopped : `systemctl start cloudflared`.
3. Verifier logs tunnel : `journalctl -u cloudflared -n 50`. Chercher `Registered tunnel connection`.
4. Verifier que nginx repond en local : `curl -k -sI --resolve nova.0xmatthieu.dev:443:127.0.0.1 https://nova.0xmatthieu.dev/`.

#### Tunnel actif mais erreur 1033 / 1014 cote Cloudflare

- "Argo Tunnel error 1033" : Public Hostname mal configure sur le dashboard. Verifier que `nova.0xmatthieu.dev` est associe au tunnel `nova-public`.
- "Tunnel error 1014" : conflit de hostname. Verifier qu'aucun autre tunnel ne revendique `nova.0xmatthieu.dev`.

#### IP reelle perdue dans les logs nginx

- Verifier que les directives `set_real_ip_from <cloudflare-ipv4-ranges>` + `real_ip_header CF-Connecting-IP` sont presentes dans `website-public.conf`.
- Verifier que `cloudflared` n'a pas une option `--proxy-protocol` non desiree (par defaut OK).

#### Suricata FW-EXT ne voit pas le trafic externe

C'est **attendu** : le trafic public arrive via cloudflared (sortie QUIC vers Cloudflare), pas via vtnet0. Suricata FW-EXT reste utile pour observer le trafic IPsec et tout flux LAN box -> APP01. Compensation pour l'observation externe :
- Cloudflare Analytics (Security Events tab).
- Future T-SURICATA-COMPENSATE-TUNNEL.
