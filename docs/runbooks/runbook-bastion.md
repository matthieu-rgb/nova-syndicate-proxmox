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

## Notes techniques

- SSH port : 22
- Cle d'admin Ansible : /home/debian/.ssh/id_ansible (cle de rebond vers les autres hotes)
- Wazuh agent actif (surveille les acces SSH)
- node_exporter actif (port 9100, scrape par Prometheus sur APP1)
- Config fail2ban : /etc/fail2ban/jail.local
