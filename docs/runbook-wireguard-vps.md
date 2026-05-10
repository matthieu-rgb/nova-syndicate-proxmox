# Runbook WireGuard VPS Hetzner

## Architecture

```
VPS Hetzner (46.62.138.33)
  wg0 : 10.30.0.1/24   -- concentrateur backup-only
  tailscale0 : 100.94.199.97  -- acces admin (ne pas toucher)

BACKUP01 (192.168.50.2)
  wg0 : 10.30.0.2/24   -- peer backup
  keepalive : 25s (BACKUP01 derriere NAT Hetzner)
```

Subnet WireGuard backup : 10.30.0.0/24
Subnet reserve concentrateur Lyon futur : 10.20.0.0/24

## Connexion au VPS

```bash
# Via Tailscale (toujours disponible)
ssh matthieu@100.94.199.97   # ou root@100.94.199.97

# SSH direct (depuis IPs autorisees dans UFW si Tailscale indisponible)
ssh matthieu@46.62.138.33
```

## Verifier l'etat du tunnel

```bash
# Sur VPS
ssh root@100.94.199.97 "wg show"

# Sur BACKUP01 (via bastion)
ssh -J debian@192.168.15.2 debian@192.168.50.2 "sudo wg show"

# Attendu :
#   latest handshake: X seconds/minutes ago
#   transfer: ... received, ... sent
```

## Diagnostiquer un tunnel down

Ordre de diagnostic :

### 1. Service actif ?

```bash
# VPS
ssh root@100.94.199.97 "systemctl status wg-quick@wg0"

# BACKUP01
ssh -J debian@192.168.15.2 debian@192.168.50.2 "sudo systemctl status wg-quick@wg0"
```

### 2. UDP 51820 accessible depuis BACKUP01 ?

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "bash -c 'echo > /dev/tcp/46.62.138.33/51820' && echo OPEN || echo BLOCKED"
# Note : /dev/tcp ne teste que TCP, pas UDP -- utiliser nc si disponible
```

### 3. UFW VPS bloque ?

```bash
ssh root@100.94.199.97 "ufw status numbered | grep 51820"
# Doit afficher ALLOW IN pour UDP 51820 v4 + v6
```

### 4. Cles publiques coherentes ?

```bash
# VPS : cle pubkey configuree pour le peer BACKUP01
ssh root@100.94.199.97 "wg show wg0 peers"

# Verifier que c'est bien la pubkey de BACKUP01 :
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo cat /etc/wireguard/peer-backup01-public.key"
```

### 5. Forcer reconnexion

```bash
# Depuis BACKUP01 -- ping declenche le handshake
ssh -J debian@192.168.15.2 debian@192.168.50.2 "ping -c 1 10.30.0.1"

# Restart service si necessaire (VPS d'abord)
ssh root@100.94.199.97 "systemctl restart wg-quick@wg0"
ssh -J debian@192.168.15.2 debian@192.168.50.2 "sudo systemctl restart wg-quick@wg0"
```

## Ajouter un peer

```bash
# 1. Generer cles sur le nouveau peer
sudo bash -c 'cd /etc/wireguard && \
  wg genkey | tee peer-NAME-private.key | wg pubkey > peer-NAME-public.key && \
  chmod 600 peer-NAME-private.key'
PUBKEY=$(sudo cat /etc/wireguard/peer-NAME-public.key)

# 2. Ajouter dans wg0.conf VPS -- section [Peer] a la fin
# PublicKey  = <PUBKEY>
# AllowedIPs = 10.30.0.X/32   (choisir X libre : .3, .4, ...)
ssh root@100.94.199.97 "systemctl reload wg-quick@wg0 || systemctl restart wg-quick@wg0"

# 3. wg0.conf du nouveau peer
# [Interface]
# PrivateKey = <PRIVATE_KEY_DU_PEER>
# Address    = 10.30.0.X/24
# SaveConfig = false
#
# [Peer]
# PublicKey          = tNuP7iBH2lYL5KozXewSlcP2/aSzCgI+ubNWNj21uCg=
# Endpoint           = 46.62.138.33:51820
# AllowedIPs         = 10.30.0.1/32
# PersistentKeepalive = 25   (si derriere NAT)
```

IPs attribuees :
- 10.30.0.1  VPS concentrateur
- 10.30.0.2  BACKUP01

## Rollback

```bash
# Arreter WireGuard sur les 2 noeuds
ssh root@100.94.199.97 "systemctl disable --now wg-quick@wg0"
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo systemctl disable --now wg-quick@wg0"

# Restaurer UFW si necessaire
ssh root@100.94.199.97 "cp /etc/ufw/user.rules.bak-<DATE> /etc/ufw/user.rules && ufw reload"

# Supprimer les configs (apres rollback confirme)
ssh root@100.94.199.97 "rm /etc/wireguard/wg0.conf"
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo rm /etc/wireguard/wg0.conf"
```

## DR -- Si VPS inaccessible via Tailscale

```bash
# Acces SSH direct sur IP publique (UFW autorise depuis partout sur port 22 via tailscale0 seulement)
# --> SSH direct non disponible par defaut (SSH lie a tailscale0)
# --> Utiliser la console Hetzner Cloud (web UI)
# URL : console.hetzner.cloud
```
