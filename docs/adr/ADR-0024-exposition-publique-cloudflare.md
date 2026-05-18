# ADR-0024 : Exposition publique du site vitrine via Cloudflare Tunnel

- Statut : Accepté
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-NOVA-EXPOSITION-PUBLIQUE

## Contexte

Le site vitrine `www.nova-syndicate.local` (cf. [ADR-0023](ADR-0023-portail-metier-architecture.md) pour le contexte applicatif) n'était accessible que sur le LAN interne et au travers du VPN d'admin. Pour la soutenance jury et les démos client, on a besoin d'un endpoint Internet `https://nova.0xmatthieu.dev` qui :

- ne révèle pas l'IP publique (185.55.247.170, box Huawei ISP non-pro)
- bénéficie d'une protection DDoS / WAF baseline gratuite
- est servi via cert TLS publiquement validé (pas mkcert)
- **n'expose pas** le portail métier `portail.nova-syndicate.local` (Authelia + données RGPD), qui reste strictement interne

L'IPv4 publique unique (185.55.247.170) et la Box Huawei (modèle ISP B315s/B528) restreignent les options : pas de BGP, pas d'IP supplémentaires. Le NAT inbound de la Box (port-forward TCP 80/443) s'est révélé **non fonctionnel** lors des tests : le SYN entrant traverse correctement Box → FW-EXT-LYON → FW-INT-LYON → APP01, APP01 répond avec un SYN-ACK qui revient avec reverse-NAT correct sur FW-EXT (`192.168.18.51:443 > 46.62.138.33`), mais la Box ne forwarde pas le SYN-ACK vers Internet (conntrack TCP cassé ou reverse-NAT non symétrique côté Box). Le test UDP 51820 (WireGuard) fonctionne lui correctement — donc le souci est spécifiquement le NAT TCP entrant de la Box.

## Décision

**Cloudflare Tunnel (cloudflared)** sur APP01 comme egress vers Cloudflare edge, **sans aucun port entrant ouvert sur la Box**.

```
Internet
   |
   v
Cloudflare edge (cert *.0xmatthieu.dev managed, WAF baseline, DDoS L3/L4)
   |
   v
Tunnel QUIC sortant (cloudflared sur APP01, 4 connexions persistantes vers CDG)
   |
   v
APP01 (192.168.20.13)
   |
   v
nginx server block "website-public.conf" sur localhost:443
```

### Points clés

- **DNS** : `nova.0xmatthieu.dev` CNAME (auto-géré) → `<tunnel-id>.cfargotunnel.com`. Cloudflare ajoute son cert edge.
- **Egress** : cloudflared se connecte en sortie sur 443/QUIC vers les POPs Cloudflare (Paris CDG observé : cdg01, cdg07, cdg08, cdg17). Aucun port entrant nécessaire.
- **TLS edge** : cert Cloudflare gratuit (renouvellement auto, validité 90j, géré par Cloudflare).
- **TLS origin** : self-signed `/etc/ssl/certs/nova-public-origin.crt` (10 ans) avec **No TLS Verify** côté Cloudflare. Le client final ne le voit pas (il voit le cert edge Cloudflare).
- **Public Hostname** : `nova.0xmatthieu.dev` → `https://localhost:443`, HTTP Host Header : `nova.0xmatthieu.dev` (matche le `server_name` nginx).
- **Real IP** : `set_real_ip_from <ranges Cloudflare>` + `real_ip_header CF-Connecting-IP` côté nginx. Logue l'IP réelle, pas l'edge ni le tunnel.
- **Security headers** : HSTS 1 an, X-Frame-Options SAMEORIGIN, X-Content-Type-Options nosniff, CSP restrictif, Permissions-Policy.
- **Cloisonnement** : seul `nova.0xmatthieu.dev` est routé via le tunnel. `portail.nova-syndicate.local` n'est jamais publié, reste invisible depuis l'extérieur.
- **Service systemd** : `/etc/systemd/system/cloudflared.service`, autostart `enabled`, restart automatique.

### Tests validation externe (2026-05-18 12:18 UTC)

Depuis VPS Hetzner (46.62.138.33), 3 essais consécutifs :

```
HTTP/2 200
server: cloudflare
content-security-policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'
strict-transport-security: max-age=31536000; includeSubDomains
x-frame-options: SAMEORIGIN
referrer-policy: strict-origin-when-cross-origin
permissions-policy: geolocation=(), microphone=(), camera=()
```

DNS résout vers les IPs Cloudflare anycast : `172.67.167.126`, `104.21.90.7`.

### Approche initiale Box port-forward (rejetée — explicité ci-dessous)

Tentative initiale : Cloudflare proxied DNS (orange cloud) → 185.55.247.170 → Box port-forward TCP 80/443 → 192.168.18.51 (alias vtnet0 FW-EXT-LYON) → NAT rdr → 192.168.20.13.

Configuration appliquée (toujours en place côté FW, dormante) :

- **FW-EXT-LYON** (`/conf/config.xml`, marker `DESCR_EXPOSITION_PUB_2026_05_18`) : 3 floating pass rules WAN (sequence 0 : TCP 80/443 + ICMP), 2 NAT rdr (80/443 → 192.168.20.13), 1 SNAT outbound `from 192.168.18.0/24 to 192.168.20.0/28 -> 10.0.1.1` pour symmetric routing.
- **FW-INT-LYON** (via API plugin `os-firewall`, UUIDs `40dc8dc8-...`, `7e41da05-...`) : 2 pass rules WAN `from any to 192.168.20.13 port 80/443`.

Diagnostic : SYN traverse complètement, SYN-ACK retour quitte FW-EXT correctement re-NATé, mais Box drop le retour. Hypothèse : conntrack TCP buggy ou reverse-NAT non symétrique. Test UDP 51820 (WireGuard) fonctionne en parallèle → c'est spécifique au NAT TCP entrant Box. Pas la peine de creuser : Tunnel résout définitivement.

## Alternatives évaluées

| Option | Verdict |
|---|---|
| **Cloudflare Tunnel** (cloudflared sur APP01) | **Retenu**. Aucun port entrant, pas de dépendance au comportement NAT Box, cert managé, pro pour la démo jury. Cloudflare connaît déjà l'op (Matthieu utilise la même approche pour son portfolio `0xmatthieu.dev`). |
| **Cloudflare Proxied + Box port-forward** | Rejeté après tests : Box Huawei drop les SYN-ACK retour TCP entrant. Garderait Suricata FW-EXT comme observateur du trafic externe — perdu avec Tunnel (cf. dette dérivée). |
| **Reverse proxy VPS Hetzner** (nginx public sur 46.62.138.33) | Bonne option défense-in-depth (deuxième couche TLS, IP publique chez un VPS). Ajoute un saut réseau et un opérateur tiers. Garde pour Phase IV si on veut découpler. |
| **Port-forward direct sans Cloudflare** | IP publique exposée, pas de DDoS protection, cert Let's Encrypt à gérer. Rejeté avant même les tests : Cloudflare gratuit fait mieux sans coût. |

## Conséquences

### Bénéfices

- DDoS L3/L4 absorbé par Cloudflare (réseau anycast 250+ POPs).
- WAF baseline (managed rules : SQLi, XSS, RCE basic) sans action.
- **Aucun port entrant ouvert sur Box** → surface d'attaque externe minimale.
- IP publique (185.55.247.170) jamais associée à un service HTTP/HTTPS public.
- Cert TLS auto-renouvelé, 0 maintenance.
- Headers de sécurité robustes (HSTS preload-ready).
- Le portail métier reste interne (pas de risque de surface d'attaque accrue sur Authelia / DB).
- Indépendant des limitations NAT de la Box ISP (qui peut changer à tout moment au gré du firmware ISP).

### Coûts / risques

- Le ruleset WAF Cloudflare gratuit est limité. Une attaque ciblée applicative peut passer.
- Cloudflare gratuit n'offre pas le bot management avancé, ni le rate limiting fin.
- En cas de panne Cloudflare (rare mais documenté : juin 2022, octobre 2025), le site est inaccessible. Le portail métier reste joignable car interne.
- Cert origin self-signed → pas de TLS bout-en-bout vérifiable, mais le client ne le voit pas et Cloudflare est en mode "No TLS Verify".
- **Suricata FW-EXT ne voit plus le trafic Internet** (cloudflared ouvre des connexions QUIC sortantes vers Cloudflare, pas de SYN entrant sur vtnet0). Compensation : Cloudflare Analytics (Security Events tab dans le dashboard) + Suricata reste opérationnel pour le trafic IPsec et le LAN box.
- Le tunnel a une dépendance forte au démon `cloudflared` (single point of failure local). Compensation : `Restart=always` systemd + 4 connexions persistantes (panne d'un edge = bascule auto).

### Dette dérivée

- **T-SURICATA-COMPENSATE-TUNNEL** : configurer Cloudflare WAF custom rules (geo-block hors UE, challenge JS sur paths sensibles, rate limiting). Étendre Wazuh pour ingester les Cloudflare Logpush si un jour on prend Pro.
- **T-CLOUDFLARED-MONITORING** : ajouter check Prometheus/blackbox-exporter sur `nova.0xmatthieu.dev` et alerte si HTTP/2 200 perdu > 60s. Le tunnel expose des métriques sur `localhost:20241/metrics` (à scraper).
- **T-CLOUDFLARED-IAC** : porter l'install cloudflared en role Ansible (idempotent, token via vault) au lieu de `cloudflared service install <TOKEN>` manuel.
- **T-EXPOSITION-BOX-CLEANUP** : décider si on garde les patches FW-EXT/FW-INT (Box port-forward) comme fallback ou si on les retire. Pour l'instant gardés dormants (idempotents, marqués `DESCR_EXPOSITION_PUB_2026_05_18`).

## Validation

### Tests externes (depuis VPS Hetzner, validés 2026-05-18)

```bash
ssh matthieu@100.94.199.97
dig +short nova.0xmatthieu.dev
# 172.67.167.126
# 104.21.90.7

curl -sI https://nova.0xmatthieu.dev/
# HTTP/2 200
# server: cloudflare
# (security headers complets)
```

### Tests internes (Lyon LAN, inchangés)

```bash
ssh root@100.112.113.2 \
  "curl -k --resolve www.nova-syndicate.local:443:192.168.20.13 \
   https://www.nova-syndicate.local/ -sI"
# HTTP/2 200 (nginx, cert wildcard mkcert)

ssh root@100.112.113.2 \
  "curl -k --resolve portail.nova-syndicate.local:443:192.168.20.13 \
   https://portail.nova-syndicate.local/ -sI"
# HTTP/2 302 (Authelia redirect)
```

### Status du tunnel

```bash
ssh root@100.112.113.2 \
  "qm guest exec 106 -- bash -c 'systemctl status cloudflared --no-pager | head -15'"
# Active: active (running)
# Tunnel connection: 4 connexions QUIC vers cdgXX (Paris)
```

## Références

- Runbook : [docs/runbook/nova-website.md](../runbook/nova-website.md) section "Exposition publique via Cloudflare Tunnel"
- Runbook : [docs/runbook/suricata-fw-ext-lyon.md](../runbook/suricata-fw-ext-lyon.md) — note sur perte d'observation du trafic externe
- [ADR-0023 portail métier architecture](ADR-0023-portail-metier-architecture.md) — cloisonnement public/privé
- [ADR-0017 NAT asymmetry policy routing](ADR-0017-nat-asymmetry-policy-routing.md) — précédent sur les flux asymétriques cross-FW
- Cloudflare Zero Trust Tunnels : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- Service systemd : `/etc/systemd/system/cloudflared.service`
- Tunnel ID : `8f187072-181f-4bfe-a4c0-3ecb42914267` (visible dans le token, partie `t`)
