# T-WG-SERVER-VPS-BACKUP — Log de session

Date : 2026-05-10

## Objectif

Tunnel WireGuard entre VPS Hetzner (concentrateur) et BACKUP01
pour push Borg hors-site de maniere securisee.

## Architecture cible

```
VPS Hetzner (46.62.138.33 / Tailscale 100.94.199.97)
  wg0 : 10.30.0.1/24 -- UDP listen 51820

BACKUP01 (192.168.50.2)
  wg0 : 10.30.0.2/24 -- endpoint 46.62.138.33:51820
```

Subnet WireGuard backup : 10.30.0.0/24
Subnet reserve concentrateur Lyon futur : 10.20.0.0/24

## Etat initial (CHECKPOINT 1)

### VPS Hetzner

- Kernel : 6.8.0-71-generic
- Tailscaled : active
- ip_forward : 1 (deja OK)
- WireGuard : non installe
- UDP 51820 : non ouvert dans UFW
- Firewall : UFW actif (SSH/n8n sur tailscale0, 80/443 public)
- Containers Docker actifs : costwave (caddy/postgres/redis), n8n

### BACKUP01

- Kernel : 6.1.0-45-cloud-amd64
- Disk : 197G / 1.8G utilise / 187G libre
- nftables output : policy accept (WireGuard UDP sortant OK sans modif)
- nftables input : ct established/related accept (retour tunnel OK)
- Internet sortant : OK (HTTP 200 vers wireguard.com)
- WireGuard : non installe

### Invariants pre-run

- IPsec : 4/4 INSTALLED
- Wazuh : 7/7 agents Active

## Installation -- COMPLETE 2026-05-10

### Phase 2 -- VPS Hetzner

- WireGuard installe : `apt install wireguard wireguard-tools`
- Module kernel charge : `modprobe wireguard` OK
- ip_forward : deja 1, pas de modif sysctl
- UFW backup : `/etc/ufw/user.rules.bak-20260510-...`
- UFW : `ufw allow 51820/udp` (v4 + v6) -- regles [5] et [10]
- Cles VPS generees : `/etc/wireguard/server-{private,public}.key` (600/644 root)
- Cle publique VPS : `tNuP7iBH2lYL5KozXewSlcP2/aSzCgI+ubNWNj21uCg=`
- `wg0.conf` : 600 root, PrivateKey injectee depuis fichier (jamais affichee)

### Phase 3 -- BACKUP01

- WireGuard installe via jumpbox bastion
- Cles BACKUP01 generees : `/etc/wireguard/peer-backup01-{private,public}.key` (600/644 root)
- Cle publique BACKUP01 : `+Q5HPOp8fzmRmDIcIzwemRNXfqdT4ddj2Tblo0jAu2U=`
- `wg0.conf` : 600 root, Endpoint=46.62.138.33:51820, PersistentKeepalive=25
- Placeholder BACKUP01_PUBLIC_KEY rempli dans config VPS

### Configs deployees (cles privees masquees)

VPS `/etc/wireguard/wg0.conf` :
```
[Interface]
PrivateKey = XXXXX
Address    = 10.30.0.1/24
ListenPort = 51820
SaveConfig = false

[Peer]  # BACKUP01
PublicKey  = +Q5HPOp8fzmRmDIcIzwemRNXfqdT4ddj2Tblo0jAu2U=
AllowedIPs = 10.30.0.2/32
```

BACKUP01 `/etc/wireguard/wg0.conf` :
```
[Interface]
PrivateKey = XXXXX
Address    = 10.30.0.2/24
SaveConfig = false

[Peer]  # VPS Hetzner
PublicKey          = tNuP7iBH2lYL5KozXewSlcP2/aSzCgI+ubNWNj21uCg=
Endpoint           = 46.62.138.33:51820
AllowedIPs         = 10.30.0.1/32
PersistentKeepalive = 25
```

### Phase 4 -- Activation tunnel

- `systemctl enable --now wg-quick@wg0` : OK sur les 2 noeuds
- Handshake etabli en < 5 secondes (PersistentKeepalive BACKUP01)
- Ping BACKUP01 -> 10.30.0.1 : 3/3 0% loss ~39ms
- Ping VPS -> 10.30.0.2 : 3/3 0% loss ~39ms
- IP publique sortante BACKUP01 observee : 185.55.247.170 (NAT Hetzner)

### Phase 5 -- Persistance + invariants

| Check | Resultat |
|---|---|
| wg-quick@wg0 enabled VPS | OK |
| wg-quick@wg0 enabled BACKUP01 | OK |
| Restart service VPS sans reboot | OK (peer maintenu) |
| Tailscaled VPS | active |
| n8n + Costwave Docker | Up (inchange) |
| IPsec 4 SAs INSTALLED | OK |
| Wazuh 7 agents Active | OK |

## Prochaine etape

T-CLOUD-BACKUP-PREP : configurer Borg server sur VPS (borguser bind sur 10.30.0.1
uniquement), puis tester le premier backup Borg depuis BACKUP01 via le tunnel.

## Procedure ajout futur peer

```bash
# 1. Generer cles sur le nouveau peer
wg genkey | tee /etc/wireguard/peer-NAME-private.key | wg pubkey > /etc/wireguard/peer-NAME-public.key
chmod 600 /etc/wireguard/peer-NAME-private.key

# 2. Ajouter le peer dans wg0.conf VPS (sans restart)
wg set wg0 peer <PUBKEY_DU_PEER> allowed-ips <IP_TUNNEL>/32
# Puis persister dans wg0.conf :
# [Peer]
# PublicKey  = <PUBKEY_DU_PEER>
# AllowedIPs = <IP_TUNNEL>/32

# 3. Creer wg0.conf sur le nouveau peer avec Endpoint=46.62.138.33:51820

# 4. Attribuer une IP dans 10.30.0.0/24 (10.30.0.3, .4, etc.)
# Reserver :
#   10.30.0.1  VPS concentrateur
#   10.30.0.2  BACKUP01
#   10.30.0.3  reserve futur
```

