# Runbook -- Bastion SSH (bastion01)

## Perimetre

bastion01 (192.168.15.2), point d'entree SSH unique vers le LAN Nova Syndicate. VLAN BASTION 192.168.15.0/29.

## Acces initial

```bash
ssh debian@192.168.15.2
# Depuis bastion, rebond vers les serveurs internes :
ssh debian@192.168.20.10  # DC1
ssh debian@192.168.20.11  # FS1
ssh debian@192.168.20.12  # DB1
ssh debian@192.168.20.13  # APP1
ssh debian@192.168.50.2   # BACKUP01
```

## Acces internet depuis le bastion

Le bastion route vers internet via le proxy Squid sur proxy-lyon01 (192.168.20.1 ou selon routing VLAN).

```bash
export http_proxy=http://192.168.15.1:3128   # adapter selon config OPNsense
export https_proxy=http://192.168.15.1:3128
curl -s https://example.com | head -5
```

## fail2ban

fail2ban protege le port SSH du bastion (et de tous les hotes).

```bash
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip <ip>
sudo tail -f /var/log/fail2ban.log
```

## Operations courantes

### Verifier la connectivite vers les serveurs internes

```bash
for host in 192.168.20.10 192.168.20.11 192.168.20.12 192.168.20.13 192.168.50.2; do
  ping -c1 -W2 $host &>/dev/null && echo "$host OK" || echo "$host FAIL"
done
```

### Verifier les tunnels IPsec (depuis bastion)

```bash
ssh debian@192.168.20.10   # ou depuis un hote avec acces au FW
# Tunnels geres par OPNsense / FW-EXT-LYON -- ne pas modifier
```

### Ajouter une cle SSH autorisee

```bash
# Sur bastion :
echo "<public_key>" >> /home/debian/.ssh/authorized_keys
chmod 600 /home/debian/.ssh/authorized_keys
```

## Diagnostic

### SSH refuse les connexions

```bash
sudo systemctl status ssh
sudo journalctl -u ssh -n 20
# Verifier fail2ban :
sudo fail2ban-client status sshd
```

### Port forwarding (acces temporaire a un service interne)

```bash
# Depuis le poste local :
ssh -L 8080:192.168.20.13:3000 debian@192.168.15.2
# Grafana accessible sur localhost:8080
```

## SSH key deployment (2026-05-09)

Cle ed25519 generee sur bastion01 : `~/.ssh/id_ed25519`
Empreinte : `SHA256:55x6DFsTZ9owpAUJqRAaDxBDwwtEwgHyJc7mDWZlb3A bastion01@nova-syndicate.local`

### Hotes accessibles sans password depuis bastion01

| Hote | IP | Statut |
|------|-----|--------|
| dc01 | 192.168.20.10 | cle deployee 2026-05-09 |
| fs01 | 192.168.20.11 | cle deployee 2026-05-09 |
| app01 | 192.168.20.13 | cle deployee 2026-05-09 |
| backup01 | 192.168.50.2 | cle deployee 2026-05-09 |
| proxy-lyon01 | 192.168.20.14 | cle deployee 2026-05-09 |
| web01 | 172.16.1.2 | cle deployee 2026-05-09 |
| db01 | 192.168.20.12 | SKIP -- probleme SSH agent pre-existant |
| proxy-mrs01 | 192.168.40.11 | TODO retour (scope MRS) |
| mail01 | 172.16.1.3 | TODO retour |

### Procedure de deploiement cle BASTION sur nouvel hote

```bash
# 1. Recuperer la cle pub depuis bastion
BASTION_PUBKEY=$(ssh debian@192.168.15.2 'cat ~/.ssh/id_ed25519.pub')

# 2. Verifier si deja presente (idempotent)
ssh debian@<host> "grep -F '$BASTION_PUBKEY' ~/.ssh/authorized_keys 2>/dev/null && echo PRESENT || echo ABSENT"

# 3. Deployer si absente
ssh debian@<host> "echo '$BASTION_PUBKEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# 4. Tester depuis bastion (sans password)
ssh debian@192.168.15.2 "ssh -o BatchMode=yes -o ConnectTimeout=5 debian@<host> 'hostname'"
```

Ne jamais modifier sshd_config pour cette operation. Authorized_keys append uniquement.

## Notes techniques

- SSH port : 22
- Cle jumpbox : /home/debian/.ssh/id_ed25519 (deploye 2026-05-09)
- Wazuh agent actif (surveille les acces SSH)
- node_exporter actif (port 9100, scrape par Prometheus sur APP1)
- Config fail2ban : /etc/fail2ban/jail.local + /etc/fail2ban/jail.d/00-nova-whitelist.conf
