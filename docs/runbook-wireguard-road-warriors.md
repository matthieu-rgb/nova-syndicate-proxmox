# Runbook : WireGuard Road-Warriors (vpn-gw01)

## Contexte et architecture

Concentrateur VPN WireGuard pour acces distant des road-warriors (NIS2 Art. 21.b).
VM dediee `vpn-gw01` (VMID 110) en DMZ, geree par le role Ansible `vpn_gateway`.

```
Internet
    |
    | UDP 51820 (port-forward box Huawei)
    v
+-------------------+
| Proxmox vmbr3     |  172.16.1.5/29
| DNAT -> 172.16.1.4|  iptables PREROUTING
+-------------------+
    |
    | 172.16.1.0/29 (DMZ)
    v
+-------------------+
| FW-EXT-LYON       |  172.16.1.1 (OPNsense)
| (pass WG traffic) |
+-------------------+
    |
    v
+-------------------+
| vpn-gw01          |  172.16.1.4
| ens18: DMZ        |  Interface physique
| wg0: 10.20.0.1/24 |  Interface WireGuard
| dnsmasq: :53      |  Forwardeur DNS
+-------------------+
    |
    | 10.20.0.0/24 (tunnel chiffre)
    v
+------------------+     +-------------------+
| matthieu-mac     |     | VPS-Hetzner-test  |
| 10.20.0.10/32    |     | 10.20.0.20/32     |
+------------------+     +-------------------+
    |
    | [via FW-EXT-LYON -> FW-INT-LYON ACLs]
    v
+-------------------+
| SERVERS VLAN      |  192.168.20.0/28
| DC01, APP01, etc. |
+-------------------+
```

**Points critiques** :
- Reponses WG reroutees via Proxmox (172.16.1.5) par policy routing pour eviter l'asymetrie NAT OPNsense (detail : ADR-0017)
- DNS road-warriors : 10.20.0.1:53 (dnsmasq) -> DC01 192.168.20.10

## IPs, ports et variables cles

| Ressource | Valeur |
|---|---|
| vpn-gw01 DMZ IP | 172.16.1.4 |
| vpn-gw01 WG IP | 10.20.0.1 |
| Subnet road-warriors | 10.20.0.0/24 |
| Port UDP | 51820 |
| DNS forwarder (dnsmasq) | 10.20.0.1:53 -> 192.168.20.10 (DC01) |
| Search domain | nova-syndicate.local |
| Proxmox DMZ IP | 172.16.1.5 |
| Policy routing table | 100 (wg-reply) |
| Policy routing fwmark | 0x1 |
| Fichier cle privee | /etc/wireguard/server-private.key |
| Fichier cle publique | /etc/wireguard/server-public.key |
| Config WG | /etc/wireguard/wg0.conf |
| Script policy routing | /usr/local/sbin/wg-policy-routing.sh |

## Etat courant des peers

| Peer | IP tunnel | Cle publique | Notes |
|---|---|---|---|
| matthieu-mac | 10.20.0.10/32 | XTG8TL36x4fG2xyjp1jLZYjmvkvDfI/ZSbNMjY6MuUA= | PersistentKeepalive 25s |
| vps-hetzner-test | 10.20.0.20/32 | fPVzZDtvUydP4gi+4yNulEwuG9+JFtVjdZtYAKbvx3o= | - |

---

## Procedure : Ajout d'un peer road-warrior

### Prerequis

- Acces SSH a vpn-gw01 (via bastion01 ProxyCommand)
- Role dans le repo `nova-syndicate-ansible`

### Etape 1 : Generation des cles cote client

Sur le poste du peer (ou sur vpn-gw01 pour lui) :

```bash
# Generer la paire de cles
wg genkey | tee peer-private.key | wg pubkey > peer-public.key
chmod 600 peer-private.key

# Afficher pour copier
cat peer-private.key   # garder secret, ne jamais envoyer en clair
cat peer-public.key    # a communiquer a l'administrateur VPN
```

### Etape 2 : Choisir une IP tunnel disponible

Consulter `host_vars/vpn-gw01.yml` pour trouver la prochaine IP libre dans 10.20.0.0/24.
Convention : 10.20.0.10 matthieu-mac, 10.20.0.20 vps-hetzner, 10.20.0.30+ pour les suivants.

### Etape 3 : Ajouter le peer dans host_vars

```yaml
# host_vars/vpn-gw01.yml
vpn_gw_peers:
  - name: matthieu-mac
    pubkey: XTG8TL36x4fG2xyjp1jLZYjmvkvDfI/ZSbNMjY6MuUA=
    allowed_ips: 10.20.0.10/32
    keepalive: 25
  # Nouveau peer :
  - name: nouveau-peer
    pubkey: <cle-publique-du-peer>
    allowed_ips: 10.20.0.30/32
    keepalive: 25   # optionnel, utile si peer derriere NAT
```

### Etape 4 : Deployer via Ansible

```bash
cd nova-syndicate-ansible
ansible vpn_gateways -m ping   # etablir ControlMaster SSH
ansible-playbook playbooks/deploy_vpn_gw.yml --limit vpn_gateways
# Verifier : changed=1 (wg0.conf mis a jour), pas d'erreur
# 2e run : changed=0 (idempotence)
```

Le handler `restart wireguard` recharge wg0.conf via `systemctl restart wg-quick@wg0`.

### Etape 5 : Generer et transmettre le fichier .conf au client

```ini
[Interface]
PrivateKey = <peer-private.key>
Address = 10.20.0.30/32
DNS = 10.20.0.1
MTU = 1420

[Peer]
PublicKey = <cle-publique-vpn-gw01>
AllowedIPs = 10.20.0.0/24, 192.168.20.0/28
Endpoint = <IP-publique-box>:51820
PersistentKeepalive = 25
```

Pour obtenir la cle publique de vpn-gw01 :

```bash
ssh debian@172.16.1.4 'cat /etc/wireguard/server-public.key'
```

**Transmission securisee** : Signal, SFTP chiffre, ou remise en main propre. Ne jamais envoyer la cle privee par email ou chat non chiffre.

---

## Procedure : Revocation d'un peer

### Etape 1 : Supprimer le peer de host_vars

```yaml
# host_vars/vpn-gw01.yml
vpn_gw_peers:
  - name: matthieu-mac
    # ...
  # Supprimer le bloc du peer revoque
```

### Etape 2 : Deployer

```bash
ansible vpn_gateways -m ping
ansible-playbook playbooks/deploy_vpn_gw.yml --limit vpn_gateways
```

Le peer est retire de wg0.conf et le service est recharge. La connexion du peer revoque est immediatement terminee. Les cles WireGuard etant generees par le client, il n'y a pas de PKI a revoquer.

### Etape 3 : Verification

```bash
ssh debian@172.16.1.4 'sudo wg show wg0'
# Le peer revoque ne doit plus apparaitre
```

---

## Troubleshooting : Handshake echoue

### Diagnostic systematique (5 niveaux)

**Niveau 1 : Port-forwarding ISP**

```bash
# Depuis un poste externe, verifier que le port est ouvert
nc -zu <IP-publique-box> 51820 && echo "port open" || echo "filtered"
# Si filtered : verifier la config port-forward de la box Huawei
```

**Niveau 2 : DNAT Proxmox**

```bash
ssh root@192.168.18.50 'iptables -t nat -L PREROUTING -n -v | grep 51820'
# Doit montrer : DNAT -> 172.16.1.4:51820
# Si absent : le DNAT a ete perdu (reboot Proxmox sans persistence iptables-save)
```

**Niveau 3 : Paquets sur vpn-gw01**

```bash
# Via bastion ou depuis le meme reseau
ssh debian@172.16.1.4 'sudo tcpdump -i ens18 -n udp port 51820 -c 20'
# Pendant que le client tente un handshake
# Si aucun paquet : probleme niveau 1 ou 2
# Si paquets entrants mais pas sortants : probleme nftables INPUT
```

**Niveau 4 : Regles nftables vpn-gw01**

```bash
ssh debian@172.16.1.4 'sudo nft list ruleset'
# Verifier :
# chain input : udp dport 51820 ct state new accept
# chain forward : iifname "wg0" oifname "eth0" accept
#                 iifname "eth0" oifname "wg0" ct state established,related accept
```

**Niveau 5 : Policy routing (asymetrie NAT)**

```bash
ssh debian@172.16.1.4 'ip rule list | grep fwmark; ip route show table 100; sudo iptables -t mangle -L OUTPUT -n'
# Doit montrer :
# ip rule : fwmark 0x1 lookup 100
# table 100 : default via 172.16.1.5
# mangle OUTPUT : MARK set 0x1 sur udp sport 51820
# Si absent : wg-quick@wg0 n'a pas applique le PostUp
```

**Regenerer le policy routing manuellement** :

```bash
ssh debian@172.16.1.4 'sudo /usr/local/sbin/wg-policy-routing.sh up'
# Puis tester le handshake immediatement
```

**Regenerer en redemarrant wg-quick** :

```bash
ssh debian@172.16.1.4 'sudo systemctl restart wg-quick@wg0'
# PostUp execute automatiquement le script
```

### Verification de l'etat complet

```bash
ssh debian@172.16.1.4 'sudo wg show wg0'
# Doit montrer pour chaque peer :
# latest handshake: X seconds ago  (si actif)
# transfer: X received, Y sent      (si trafic passe)
```

---

## Procedure : Rotation des cles serveur

Necessaire en cas de compromission supposee de la cle privee serveur.

```bash
# 1. Supprimer les cles existantes (force la regeneration Ansible)
ssh debian@172.16.1.4 'sudo rm /etc/wireguard/server-private.key /etc/wireguard/server-public.key'

# 2. Regenerer via Ansible
ansible-playbook playbooks/deploy_vpn_gw.yml --limit vpn_gateways

# 3. Obtenir la nouvelle cle publique
ssh debian@172.16.1.4 'cat /etc/wireguard/server-public.key'

# 4. Communiquer la nouvelle cle publique (PublicKey dans [Peer]) a TOUS les peers
# Les peers doivent mettre a jour leurs fichiers .conf
```

---

## Procedure : Ajout d'un concentrateur HA (Phase III)

Pour la haute disponibilite, deux concentrateurs partageant une VIP DMZ via keepalived/VRRP.

```bash
# 1. Cloner depuis template VMID 9000 (maintenant propre -- voir runbook-proxmox-template.md)
ssh root@192.168.18.50 'qm clone 9000 111 --name vpn-gw02 --full 1'

# 2. Configurer IP statique DMZ alternative (ex: 172.16.1.6)
# Modifier cloud-init ou netplan post-boot

# 3. Ajouter vpn-gw02 a l'inventaire Ansible
# inventory/hosts.yml : sous [vpn_gateways]

# 4. Creer host_vars/vpn-gw02.yml avec les memes peers mais IP differente

# 5. Deployer
ansible-playbook playbooks/deploy_vpn_gw.yml --limit vpn-gw02

# 6. Configurer keepalived sur vpn-gw01 et vpn-gw02
# VIP : 172.16.1.7 (IP virtuelle partagee)
# Modifier le DNAT Proxmox et la config peers pour pointer vers la VIP
```

---

## Maintenance courante

### Verification hebdomadaire

```bash
# Etat WireGuard
ssh debian@172.16.1.4 'sudo wg show wg0'

# Policy routing en place
ssh debian@172.16.1.4 'ip rule list | grep fwmark && ip route show table 100'

# Service actif
ssh debian@172.16.1.4 'systemctl is-active wg-quick@wg0'
```

### Apres reboot de vpn-gw01

```bash
# Verifier que le policy routing a ete reapplique (via PostUp)
ssh debian@172.16.1.4 'ip rule list | grep fwmark'
# Si absent : systemctl restart wg-quick@wg0

# Verifier les peers actifs
ssh debian@172.16.1.4 'sudo wg show wg0 | grep handshake'
```

### Apres reboot de Proxmox

```bash
# Verifier que le DNAT est toujours present
ssh root@192.168.18.50 'iptables -t nat -L PREROUTING -n | grep 51820'
# Si absent : appliquer les regles iptables (non persistees par defaut)
# Commande Proxmox DNAT :
# iptables -t nat -A PREROUTING -p udp --dport 51820 -j DNAT --to-destination 172.16.1.4:51820
```

---

## Mapping NIS2

| Article NIS2 | Controle mis en oeuvre |
|---|---|
| Art. 21.b (acces a distance) | Concentrateur WireGuard, tunnel chiffre ChaCha20-Poly1305 |
| Art. 21.b (authentification) | Cle publique WireGuard par peer (facteur "device") |
| Art. 21.e (MFA) | Phase III : Teleport ou Authelia (ADR-0014) |
| Art. 21.b (controle d'acces) | AllowedIPs par peer, ACLs FW-INT-LYON par VLAN |
| Art. 21.i (journalisation) | Logs nftables Proxmox + wg show handshake |

---

## References

- ADR-0016 : Architecture concentrateur VPN road-warriors
- ADR-0017 : Resolution asymetrie NAT par policy routing
- ADR-0009 : WireGuard backup VPS Hetzner (concentrateur frere)
- Role Ansible : `ansible/roles/vpn_gateway/`
- Peers config : `ansible/host_vars/vpn-gw01.yml`
- Debug log : `docs/T-WG-HANDSHAKE-DEBUG.md`
- Template Proxmox : `docs/runbook-proxmox-template.md`
- WireGuard whitepaper : https://www.wireguard.com/papers/wireguard.pdf
