# Runbook : vpn (WireGuard Road-Warrior + tunnels)

## 1. Perimetre

Le role `vpn` genere les configurations WireGuard pour le VPN road-warrior du projet Nova Syndicate. Il installe `wireguard-tools`, genere le fichier `/etc/wireguard/wg0.conf` a partir d'un template Jinja2, et produit la documentation de configuration IPsec pfsense pour le site-to-site Lyon-MRS (reference documentaire uniquement, car la configuration IPsec est geree par le Terraform OPNsense).

Ce runbook couvre trois perimetre distincts mais lies :

1. **Role Ansible `vpn`** : generation des configs WireGuard road-warrior (clients distants). L'interface `wg0` ecoute sur le port UDP 51820 avec le subnet 192.168.40.0/24. Les clients WireGuard se voient attribuer des adresses dans ce subnet et utilisent dc01 (192.168.20.10) comme DNS.

2. **Tunnel WireGuard backup (deploye manuellement)** : tunnel dedie entre backup01 (192.168.50.2, wg0 = 10.30.0.2/24) et le VPS Hetzner (10.30.0.1) pour la synchronisation Borg cloud. Ce tunnel a ete deploye manuellement, hors du role Ansible `vpn`. Il est documente ici pour le contexte operationnel global.

3. **IPsec site-to-site Lyon-MRS** : gere via le Terraform OPNsense dans `terraform/environments/opnsense/`. Non couvert par le role Ansible `vpn`, reference uniquement dans ce runbook.

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `vpn`.
- La machine qui heberge le serveur WireGuard road-warrior doit etre definie dans l'inventaire (groupe `vpn_servers`). Dans l'architecture actuelle, le role est prevu pour tourner sur une VM dediee ou sur proxy-lyon01 (192.168.20.14) si mutualisee.

### Reseau

- Port UDP 51820 ouvert via nftables sur la VM qui fait serveur WireGuard.
- La gateway OPNsense FW-INT-LYON (192.168.20.1) doit router le subnet 192.168.40.0/24 vers la VM serveur WireGuard.
- Les clients road-warrior ont besoin d'une route vers les subnets internes via le tunnel.

### Packages

`wireguard-tools`

### Kernel

Le module kernel WireGuard (`wireguard`) est integre au kernel Linux depuis 5.6. Sur Debian Bookworm (kernel 6.1+), aucun package kernel supplementaire n'est requis.

### Acces

- Serveur WireGuard (exemple sur proxy-lyon01) : `ssh -J debian@192.168.15.2 debian@192.168.20.14`
- backup01 (tunnel Borg cloud) : `ssh -J debian@192.168.15.2 debian@192.168.50.2`

## 3. Installation

### Role Ansible vpn (WireGuard road-warrior)

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Dry-run
ansible-playbook -i inventory/hosts.yml site.yml \
  -l vpn_servers \
  --tags vpn \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass

# Deploiement
ansible-playbook -i inventory/hosts.yml site.yml \
  -l vpn_servers \
  --tags vpn \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes (role vpn)

1. Installation de `wireguard-tools`
2. Generation de la cle privee serveur (si absente)
3. Deploiement `wg0.conf` depuis le template
4. Enable + start `wg-quick@wg0`
5. Generation de la documentation `ipsec-pfsense.conf` (reference documentaire)

### Ajout d'un peer (client road-warrior)

1. Generer les cles du client :
```bash
# Sur la machine du client
wg genkey | tee client_privatekey | wg pubkey > client_pubkey
cat client_pubkey  # A fournir au serveur
```

2. Ajouter le peer dans `wireguard_peers` dans `group_vars/vpn_servers/vars.yml` :
```yaml
wireguard_peers:
  - name: "matthieu-mac"
    public_key: "AAAA...cle_publique_client..."
    allowed_ips: "192.168.40.2/32"
  - name: "admin-laptop"
    public_key: "BBBB...cle_publique_admin..."
    allowed_ips: "192.168.40.3/32"
```

3. Rejouer le role :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l vpn_servers \
  --tags vpn,config \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

4. Generer le fichier de configuration client :
```ini
[Interface]
PrivateKey = <client_privatekey>
Address = 192.168.40.2/24
DNS = 192.168.20.10

[Peer]
PublicKey = <server_pubkey>
Endpoint = <IP_publique_serveur>:51820
AllowedIPs = 192.168.20.0/28, 192.168.30.0/26, 192.168.50.0/29
PersistentKeepalive = 25
```

## 4. Configuration

### Variables par defaut (defaults/main.yml)

```yaml
wireguard_interface: "wg0"
wireguard_port: 51820
wireguard_server_ip: "192.168.40.1/24"
wireguard_dns: "192.168.20.10"
wireguard_peers: []
```

### Variables du groupe (group_vars/vpn_servers/vars.yml)

```yaml
wireguard_interface: "wg0"
wireguard_port: 51820
wireguard_server_ip: "192.168.40.1/24"
wireguard_dns: "192.168.20.10"
wireguard_peers:
  - name: "matthieu-mac"
    public_key: "vault_wg_peer_matthieu_pubkey"
    allowed_ips: "192.168.40.2/32"
```

### wg0.conf serveur (template genere)

```ini
[Interface]
Address = 192.168.40.1/24
ListenPort = 51820
PrivateKey = <server_private_key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# matthieu-mac
PublicKey = AAAA...
AllowedIPs = 192.168.40.2/32
```

### Tunnel WireGuard backup (backup01 <-> VPS Hetzner, deploye manuellement)

```
Interface wg0 sur backup01 (192.168.50.2) :
  Address = 10.30.0.2/24
  ListenPort = 51820
  PrivateKey = <backup01_private_key> (dans /etc/wireguard/wg0.conf mode 600)

Peer (VPS Hetzner) :
  PublicKey = <vps_public_key>
  Endpoint = <VPS_IP>:51820
  AllowedIPs = 10.30.0.0/24
  PersistentKeepalive = 25
```

Cle SSH Borg cloud : `/root/.ssh/id_ed25519_borg-cloud` sur backup01.
Depots Borg remote : `borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/`

## 5. Validation post-deploiement

### Verifier WireGuard road-warrior (serveur)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg show wg0"
```

Resultat attendu : interface wg0 presente, listening port 51820, liste des peers.

### Verifier l'interface wg0 active

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl is-active wg-quick@wg0 && \
   ip addr show wg0"
```

### Tester la connectivite depuis un client road-warrior

Depuis la machine du client (Mac M4 Pro) avec le profil WireGuard active :
```bash
# L'IP client doit etre 192.168.40.2 (ou selon allocation)
ip addr show utun0   # macOS

# Ping vers le DC
ping 192.168.20.10

# Resolution DNS interne
dig dc01.nova-syndicate.local @192.168.20.10
```

### Verifier le tunnel Borg cloud (backup01)

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo wg show wg0 | grep -E 'interface|latest handshake|transfer'"

# Tester la connectivite vers le VPS
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo ping -c 3 10.30.0.1"
```

### Verifier l'acces SSH Borg vers le VPS

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo ssh -i /root/.ssh/id_ed25519_borg-cloud \
   -o BatchMode=yes \
   borguser@10.30.0.1 'borg list /srv/borg-repo/nova-syndicate/' 2>&1 | head -5"
```

## 6. Operations courantes

### Demarrer/arreter le tunnel WireGuard road-warrior

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl start wg-quick@wg0"

ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl stop wg-quick@wg0"
```

### Ajouter un peer a chaud (sans redemarrage)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg set wg0 peer <PUBLIC_KEY> allowed-ips 192.168.40.4/32"

# Sauvegarder la config
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg-quick save wg0"
```

Ne pas oublier d'ajouter le peer dans `wireguard_peers` et de rejouer le role pour rendre la modification persistante via Ansible.

### Supprimer un peer (depart d'un administrateur)

```bash
# Supprimer le peer a chaud
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg set wg0 peer <PUBLIC_KEY> remove && \
   sudo wg-quick save wg0"

# Supprimer de wireguard_peers dans group_vars et rejouer le role
```

### Verifier les bytes transferes par peer

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg show wg0 transfer"
```

### Reinitialiser le tunnel Borg cloud

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo systemctl restart wg-quick@wg0 && \
   sudo wg show wg0"
```

### Regenerer les cles WireGuard du serveur (rotation)

```bash
# Sur le serveur, generer une nouvelle paire de cles
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | \
   sudo tee /etc/wireguard/publickey"

# Mettre a jour wg0.conf et distribuer la nouvelle cle publique aux clients
# Rejouer le role vpn
```

Attention : la rotation des cles invalide tous les peers existants qui doivent mettre a jour leur configuration.

## 7. Troubleshooting

### Incident 1 : Interface wg0 absente au demarrage

**Symptome :** `ip link show wg0` retourne `Device "wg0" does not exist`. Le service `wg-quick@wg0` est en echec.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl status wg-quick@wg0 && \
   sudo journalctl -u wg-quick@wg0 -n 30 --no-pager"
```

**Fix :**
```bash
# Verifier que le module kernel wireguard est charge
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo modprobe wireguard && lsmod | grep wireguard"

# Verifier la syntaxe de wg0.conf
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg-quick up wg0"
```

Si l'erreur est `RTNETLINK answers: Operation not supported`, le kernel ne supporte pas WireGuard (kernel trop ancien). Mettre a jour le kernel Debian.

### Incident 2 : Le client road-warrior se connecte mais n'atteint pas les VMs internes

**Symptome :** La connexion WireGuard s'etablit (handshake OK), mais les pings vers 192.168.20.10 echouent depuis le client.

**Diagnostic :**
```bash
# Sur le serveur, verifier le forwarding IP
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo sysctl net.ipv4.ip_forward"

# Verifier les regles iptables/nftables PostUp
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo iptables -t nat -L POSTROUTING -v -n"
```

**Fix :**
- `net.ipv4.ip_forward` doit etre 1 sur le serveur WireGuard. Sur proxy-lyon01, c'est deja le cas (proxy necessite le forwarding). Sur une VM dediee, surcharger `common_sysctl` dans `group_vars/vpn_servers/vars.yml`.
- Verifier que les regles PostUp dans wg0.conf creent bien le NAT et le FORWARD.
- Verifier que la gateway OPNsense route 192.168.40.0/24 vers le serveur WireGuard.

### Incident 3 : Tunnel Borg cloud (backup01 <-> VPS) tombe periodiquement

**Symptome :** `wg show wg0` sur backup01 montre un `latest handshake` de plus de 5 minutes. La sync cloud echoue.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo wg show wg0 && \
   sudo ping -c 5 10.30.0.1 && \
   sudo traceroute 10.30.0.1"
```

**Fix :**
- Verifier que `PersistentKeepalive = 25` est bien dans la config du peer (cote backup01). Ce parametre maintient le tunnel actif en envoyant un paquet keepalive toutes les 25 secondes.
- Si le VPS est injoignable, verifier l'etat du VPS Hetzner (interface web Hetzner Cloud).
- Redemarrer le tunnel :
```bash
sudo systemctl restart wg-quick@wg0
```

### Incident 4 : Erreur "RTNETLINK answers: File exists" au demarrage de wg-quick

**Symptome :** `wg-quick up wg0` retourne `RTNETLINK answers: File exists`. L'interface wg0 est partiellement montee.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "ip link show wg0 && ip addr show wg0"
```

**Fix :**
```bash
# Detruire l'interface orpheline et remonter
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo ip link delete wg0 && sudo wg-quick up wg0"
```

### Incident 5 : Cle privee WireGuard lisible par un utilisateur non-root

**Symptome :** Audit de securite : `/etc/wireguard/wg0.conf` a des permissions incorrectes (644 ou 640 au lieu de 600).

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "ls -la /etc/wireguard/wg0.conf"
```

**Fix :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo chmod 600 /etc/wireguard/wg0.conf && \
   sudo chown root:root /etc/wireguard/wg0.conf"
```

Le role Ansible applique ces permissions ; si elles ont derive, rejouer `--tags vpn`.

### Incident 6 : Peer road-warrior compromis (cle privee volée)

**Symptome :** Suspicion de compromission de la cle privee d'un client road-warrior.

**Diagnostic :** Verifier les logs WireGuard pour des connexions depuis des IPs inattendues :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo journalctl -u wg-quick@wg0 | grep 'Received handshake' | tail -20"
```

**Fix :**
```bash
# Supprimer immediatement le peer compromis
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo wg set wg0 peer <CLEPUBLIQUE_COMPROMISE> remove && \
   sudo wg-quick save wg0"

# Renouveler les cles du client legitime et re-ajouter le peer
```

## 8. Disaster Recovery

### Contexte DR

Le role `vpn` gere les acces administrateurs distants. Sa perte n'impacte pas les services internes (les VMs continuent). L'impact est la perte d'acces VPN pour les administrateurs distants. Le bastion SSH (192.168.15.2) reste disponible comme acces de secours. RTO cible : 30 minutes. RPO : N/A (configuration as-code).

### Procedure de restauration (WireGuard road-warrior)

**Etape 1 : Acces au parc via SSH ProxyJump (contournement)**

Pendant la reconstruction du VPN, utiliser le bastion SSH :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14
```

**Etape 2 : Reprovisioner le serveur WireGuard**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  -l vpn_servers \
  --tags common,hardening,vpn \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**Etape 3 : Redistribuer les configurations clients**

Generer et envoyer les fichiers de configuration WireGuard a chaque administrateur.

**Procedure de restauration du tunnel Borg cloud (backup01 <-> VPS)**

**Etape 1 : Recuperer la configuration WireGuard depuis backup01 (Borg configs)**
```bash
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract /var/backups/borg/configs::nova-configs-<DATE> \
  etc/wireguard/
```

**Etape 2 : Redeployer la config sur le nouveau backup01**
```bash
sudo cp /tmp/wg0.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

**Etape 3 : Verifier la connectivite vers le VPS**
```bash
sudo ping -c 3 10.30.0.1
sudo ssh -i /root/.ssh/id_ed25519_borg-cloud borguser@10.30.0.1 echo OK
```

**RTO :** 30 minutes (reprovisioning + validation).
**RPO :** N/A pour le VPN road-warrior (pas de donnees). Pour le tunnel Borg cloud : la config est dans le depot Borg configs (RPO 24h).

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
WireGuard utilise une cryptographie moderne (Curve25519, ChaCha20-Poly1305, BLAKE2s) reconnue comme robuste. Les cles privees sont stockees exclusivement en mode 600 root. La rotation des cles est recommandee annuellement. Chaque client road-warrior dispose d'une paire de cles unique, permettant la revocation individuelle.

**Art. 21.2.c -- Gestion des incidents :**
Les connexions WireGuard (handshakes) sont visibles via `wg show` et dans journald. Ces evenements sont collectes par Wazuh agent sur la VM serveur. En cas d'incident (cle compromise), la revocation est immediate via `wg set peer remove`.

**Art. 21.2.e -- Continuite d'activite :**
La configuration WireGuard est versionee dans Git (via Ansible) et sauvegardee dans Borg (configs). Le tunnel Borg cloud (backup01 <-> VPS) assure la continuite de la sauvegarde hors site, composante critique du plan de continuite.

**Art. 21.2.i -- Chaine d'approvisionnement :**
Le VPS Hetzner heberge le depot Borg cloud. La cle SSH Borg (`id_ed25519_borg-cloud`) donne acces append-only uniquement : le VPS ne peut pas lire les archives (chiffrement repokey cote backup01), et backup01 ne peut pas supprimer d'archives (mode append-only). Ce design limite l'impact d'une compromission de backup01.

### Inventaire des cles WireGuard

Maintenir un inventaire securise des cles :

| Peer | Usage | Pubkey (empreinte) | Expires |
|------|-------|-------------------|---------|
| matthieu-mac | Admin road-warrior | sha256:XXXX | 2027-01 |
| backup01-wg0 | Tunnel Borg cloud | sha256:YYYY | 2027-01 |

Stocker l'inventaire dans le vault Ansible et dans un gestionnaire de mots de passe hors ligne.

## 10. References

### Internes au projet

- `roles/vpn/defaults/main.yml` -- variables du role
- `roles/vpn/templates/wg0.conf.j2` -- template WireGuard
- `group_vars/vpn_servers/vars.yml` -- peers et configuration
- `docs/runbook-wireguard-vps.md` -- details du tunnel VPS Hetzner
- `docs/runbook-borg-cloud.md` -- backup cloud via WireGuard
- Runbook backup : `docs/runbooks/runbook-backup.md`
- Terraform OPNsense : `terraform/environments/opnsense/` (IPsec Lyon-MRS)

### Documentation upstream

- WireGuard documentation officielle : https://www.wireguard.com/
- WireGuard quickstart : https://www.wireguard.com/quickstart/
- wg-quick man page : https://man7.org/linux/man-pages/man8/wg-quick.8.html
- Borg documentation : https://borgbackup.readthedocs.io/
- NIS2 Directive : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32022L2555
