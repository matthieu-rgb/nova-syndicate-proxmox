# Runbook -- Demo WireGuard road-warrior Mac (Option 3 revue)

**Statut** : PLAN d'execution **non execute**. A valider avant action.
**Date** : 2026-06-03
**Ticket** : T-WG-DEMO-ROADWARRIOR.

## TL;DR -- ce que la RECO a appris

L'option 3 initiale ("DNAT sur FW-EXT-LYON via Terraform") **n'est pas faisable
en l'etat** : le provider Terraform `browningluke/opnsense` 0.16 ne supporte
pas la ressource `opnsense_firewall_nat` (cf STATUS Phase II §1).

**Le vrai pattern d'architecture (ADR-0017)** : le DNAT se fait **sur le host
Proxmox** (iptables), pas sur FW-EXT-LYON. Et il existe DEJA :

```
iptables -t nat -L PREROUTING -n -v :
  pkts bytes target  prot in     dst-port             redirect-to
     1   176 DNAT    udp  vmbr0  51820  ->  172.16.1.4:51820
```

Mais cette regle est **restreinte a `-i vmbr0`** (interface mgmt), donc le
trafic Mac via Tailscale (`tailscale0`) **n'est pas redirige**. Et l'IP
`172.16.1.5/29` sur vmbr3 (Proxmox DMZ side), pre-requis du policy routing
WG (ADR-0017), **n'a jamais ete posee** -- `iface vmbr3 inet manual`.

**Plan revu Option 3** :
1. Documenter les 2 dettes dans STATUS.md (route fantome + provider NAT).
2. Poser l'IP `172.16.1.5/29` sur vmbr3 Proxmox + persistance `/etc/network/interfaces`.
3. Elargir la regle DNAT iptables (retirer `-i vmbr0`, ou ajouter `-i tailscale0`)
   et persister via `iptables-save > /etc/iptables/rules.v4`.
4. Sur le Mac, monter wg-quick avec `Endpoint = 100.112.113.2:51820` (IP Tailscale Proxmox).
5. Test handshake + ping app01.
6. Captures jury.

---

## 1. Findings RECO (synthese)

### 1.1. La "route fantome" 172.16.1.5 expliquee

ADR-0016 + ADR-0017 prevoyaient que Proxmox host porte l'IP `172.16.1.5/29`
sur `vmbr3` (DMZ Lyon). Role joue :

```
                       Internet / WAN-SIM
                              |
                       FW-EXT-LYON (10.0.0.2 WAN, 172.16.1.1 DMZ)
                              |
                       vmbr3 = DMZ Lyon 172.16.1.0/29
                              |
                       Proxmox host : 172.16.1.5 (vmbr3)  <-- jamais posee
                              |
                       vpn-gw01 (172.16.1.4)
                              |
                       wg0 : 10.20.0.1/24
```

**Pourquoi cette IP** (ADR-0017) : asymetrie NAT WireGuard. Quand vpn-gw01
repond aux clients (sport=51820), si la reponse passe par FW-EXT-LYON, OPNsense
modifie le port source via auto-NAT (51820 -> 44169) et le client ne
reconnait pas la reponse. Solution : policy-based routing sur vpn-gw01 qui
re-route les replies via Proxmox `172.16.1.5` (qui voit le trafic entrant
original et applique le SNAT symetrique).

**Configuration runtime aujourd'hui** :
- `/etc/network/interfaces` Proxmox : `iface vmbr3 inet manual` (pas d'IPv4 assignee).
- `/etc/wireguard/wg0.conf` vpn-gw01 : `PostUp = ip route add 192.168.0.0/16 via 172.16.1.5 || true`.
- `vpn_gw_proxmox_dmz_ip: "172.16.1.5"` dans `roles/vpn_gateway/defaults/main.yml`.
- `ping 172.16.1.5` depuis FW-EXT-LYON : 100 % packet loss.

**Bug concret** : la PostUp `ip route add 192.168.0.0/16 via 172.16.1.5` ne
**fonctionne pas** -- la table de routage accepte la route (gateway pas
verifiee a l'ajout), mais tout trafic emis vers 192.168.x.x (sauf le subset
192.168.20.0/24 couvert par une autre PostUp via `172.16.1.1`) est
black-hole : pas de reponse ARP pour 172.16.1.5, pas de forwarding.

**Reference croisee** : ADR-0016 (architecture vpn-gw01), ADR-0017 (policy
routing fwmark 0x1 table 100).

### 1.2. Provider Terraform OPNsense -- pas de NAT

`grep -rE "opnsense_firewall_(nat|port_forward|source_nat)"
terraform/environments/opnsense/*.tf` -> 0 hit. Le provider
`registry.terraform.io/browningluke/opnsense` ne supporte pas ces ressources
en version 0.16 (cf STATUS Phase II §1).

**Consequence** : la regle DNAT 51820 ne peut pas etre codee en Terraform
cote OPNsense. **Alternative IaC** : la coder en role Ansible cible Proxmox
host (`hosts: proxmox`, `ansible_user=root`) qui depose
`/etc/iptables/rules.v4` + active `netfilter-persistent`. Cohere avec
T-IAC-BRIDGES-PROXMOX-HOST de l'audit IaC.

### 1.3. iptables Proxmox -- etat actuel

```
PREROUTING (NAT) :
  DNAT  udp -i vmbr0  dport 51820  ->  172.16.1.4:51820

POSTROUTING (NAT) :
  ts-postrouting (Tailscale standard)
  MASQUERADE all 192.168.15.0/29 -> 0.0.0.0/0   x2 (doublon suspect)
  MASQUERADE all 192.168.20.0/28 -> 0.0.0.0/0   x2 (doublon suspect)
  MASQUERADE all 192.168.50.0/29 -> 0.0.0.0/0   x2 (doublon suspect)
```

- `netfilter-persistent` enabled + `/etc/iptables/rules.v4` present (modifie 11 mai)
- **Doublon MASQUERADE** suspect (a investiguer hors scope WG, dette `T-IPTABLES-MASQUERADE-DUPLICATE`)
- **DNAT restreint a `-i vmbr0`** : trafic Tailscale (`-i tailscale0`) **non couvert**

### 1.4. Tailscale Proxmox

- Interface `tailscale0` : `100.112.113.2/32` IPv4 + IPv6 ULA
- Pas de subnet routes annoncees aujourd'hui
- `tailscale up --advertise-routes=...` non necessaire pour Option 3 revue
  (le Mac taperait directement Tailscale IP de Proxmox sur le port 51820)

---

## 2. Strategie revue

### 2.1. Pourquoi le NAT cote Proxmox et pas OPNsense

| Critere | OPNsense (FW-EXT-LYON) | Proxmox host (iptables) |
|---------|----------------------|--------------------------|
| Support Terraform | **non** (provider 0.16) | non (mais Ansible-on-host possible) |
| Conformite ADR-0017 | non conforme | **conforme** (design DNAT Box -> Proxmox) |
| Trafic Tailscale | impossible (FW-EXT-LYON ne voit pas Tailscale) | **OK** (Proxmox host porte tailscale0) |
| Persistance IaC | bloque par provider | Ansible-on-host (dette T-IAC-BRIDGES-PROXMOX-HOST) |

-> **Retenu** : DNAT cote Proxmox host, persistance via `netfilter-persistent` +
`/etc/iptables/rules.v4` (deja en place + enabled). Code-as-config dans un
futur role Ansible `proxmox_host_network` (dette ouverte).

### 2.2. Chemin reseau Mac -> vpn-gw01

```
Mac (10.x Tailscale IP)
  |
  | wg-quick up wg0, Endpoint=100.112.113.2:51820
  | (chiffrement UDP)
  v
Tailscale mesh (chiffrement WG natif Tailscale)
  v
Proxmox host (tailscale0 = 100.112.113.2)
  | DNAT iptables : udp dport 51820 (peu importe interface) -> 172.16.1.4:51820
  v
vmbr3 (DMZ)
  v
vpn-gw01 (172.16.1.4:51820) -- charon WG accepte le handshake
  | reponse src 172.16.1.4:51820
  | PostUp : ip rule fwmark 0x1 lookup 100, table 100: default via 172.16.1.5
  v
Proxmox host (172.16.1.5 = nouvelle IP a poser sur vmbr3)
  | SNAT conntrack inverse -> reponse vers Tailscale IP du Mac
  v
Tailscale mesh
  v
Mac
```

**Note design** : la demo est "vraie road-warrior" au sens fonctionnel : un
client externe (Mac via Tailscale) monte un tunnel WG vers le concentrateur
Nova et accede aux ressources internes. Le WAN simule (10.0.0.0/30, 10.0.2.0/30)
n'est pas traverse parce que (a) Mac n'a pas de route vers ces segments,
(b) WAN-SIM ne route pas inter-WAN (deja constate avec IPsec), (c) ADR-0017
prevoit explicitement le DNAT cote Proxmox.

Pour la slide jury : "le client se connecte via le mesh prive Tailscale qui
joue le role du WAN public ; le DNAT Proxmox redirige vers le concentrateur
WG ; vpn-gw01 traite le handshake et autorise l'acces selectif aux VLANs
Lyon via policy routing".

---

## 3. Prerequis a appliquer (avec validation utilisateur)

### Prerequis P1 -- IP 172.16.1.5/29 sur vmbr3 Proxmox

**Operation** : modification `/etc/network/interfaces` Proxmox.

```ini
# Avant
auto vmbr3
iface vmbr3 inet manual

# Apres
auto vmbr3
iface vmbr3 inet static
    address 172.16.1.5/29
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

**Application non destructive** :
```sh
ssh root@100.112.113.2 \
  'cp /etc/network/interfaces /etc/network/interfaces.bak-pre-wg-demo-20260603 && \
   ip addr add 172.16.1.5/29 dev vmbr3'
```
puis modifier `/etc/network/interfaces` pour la persistance (le runtime est
deja en place).

**Verification** :
```sh
ssh root@100.112.113.2 'ip -br a show vmbr3; ping -c 2 172.16.1.4'
# Attendu : vmbr3 UP + 172.16.1.5/29 + reponse ping de vpn-gw01
```

**Rollback** : `ip addr del 172.16.1.5/29 dev vmbr3` + restaurer le `.bak`
de `/etc/network/interfaces`.

### Prerequis P2 -- DNAT iptables elargi + persiste

**Operation** :
1. Backup : `cp /etc/iptables/rules.v4 /etc/iptables/rules.v4.bak-pre-wg-demo-20260603`.
2. Retirer la restriction d'interface sur la regle DNAT existante :
   ```sh
   # Supprimer la regle vmbr0-restricted, ajouter une regle sans -i
   iptables -t nat -D PREROUTING -i vmbr0 -p udp --dport 51820 -j DNAT --to 172.16.1.4:51820
   iptables -t nat -I PREROUTING 1 -p udp --dport 51820 -j DNAT --to 172.16.1.4:51820 \
            -m comment --comment "WG roadwarrior DNAT -- toute interface (T-WG-DEMO-ROADWARRIOR 2026-06-03)"
   ```
3. Persister :
   ```sh
   iptables-save > /etc/iptables/rules.v4
   netfilter-persistent reload
   ```

**Verification** :
```sh
iptables -t nat -L PREROUTING -n -v | grep 51820
# Attendu : DNAT sans 'in vmbr0', juste 'udp dpt:51820 to:172.16.1.4:51820'
```

**Rollback** : restaurer `/etc/iptables/rules.v4.bak-pre-wg-demo-20260603` +
`netfilter-persistent reload`.

### Prerequis P3 (verification utilisateur) -- cle privee matthieu-mac

Tu m'as dit "je verifie, je te dis". Lance :
```sh
grep -l "$(echo XTG8TL36x4fG2xyjp1jLZYjmvkvDfI/ZSbNMjY6MuUA= | base64 -d | xxd -p)" \
     ~/.config/wireguard/*.conf ~/Library/Application\ Support/WireGuard/*.conf 2>/dev/null
# Ou plus simple :
grep -lR "matthieu-mac\|10.20.0.10" ~/.config/wireguard/ ~/Library 2>/dev/null
```

Si la cle privee correspondant a la pub `XTG8TL36...` est trouvee, on l'utilise
directement. Sinon : voir Option 1bis du brief precedent (regenerer la paire,
mettre a jour le peer dans le role Ansible + replay sur vpn-gw01).

---

## 4. Demo road-warrior (apres P1+P2+P3 OK)

### 4.1. Config client Mac (`~/Library/Application\ Support/WireGuard/wg0.conf`)

```ini
[Interface]
PrivateKey = <ta cle privee matthieu-mac>
Address = 10.20.0.10/32
DNS = 10.20.0.1   # dnsmasq sur vpn-gw01 forwarde vers dc01

[Peer]
PublicKey = 9ExSPQD6PWsFChdoX3SDEkY8ZppRnvXmH78SKM0vvy4=   # server public key vpn-gw01
Endpoint = 100.112.113.2:51820   # Tailscale IP Proxmox (DNAT)
AllowedIPs = 10.20.0.0/24, 192.168.20.0/24
PersistentKeepalive = 25
```

Note `AllowedIPs` : on cible **uniquement** 10.20.0.0/24 (tunnel) + 192.168.20.0/24
(servers Lyon, route OK via 172.16.1.1). On EXCLUT 192.168.0.0/16 large car la
route fantome 172.16.1.5 est en train d'etre corrigee, mais on garde un perimetre
clean cote client.

### 4.2. Activation Mac

```sh
sudo wg-quick up ~/Library/Application\ Support/WireGuard/wg0.conf
# Ou via WireGuard.app : Add Tunnel + Activate
```

### 4.3. Validation handshake (cote serveur vpn-gw01)

```sh
ssh root@100.112.113.2 \
  'qm guest exec 110 --timeout 10 -- /bin/bash -c "sudo wg show wg0 latest-handshakes; sudo wg show wg0 transfer"'
```
**Attendu** : timestamp `< 60s` pour le peer `XTG8TL36...`, transfer > 0 bytes.

### 4.4. Test acces ressources internes (cote Mac)

```sh
ping -c 4 192.168.20.13              # app01 Wazuh
curl -k --max-time 5 https://192.168.20.13/   # nginx app01
curl -k --max-time 5 \
  --resolve authelia.nova-syndicate.local:443:192.168.20.13 \
  https://authelia.nova-syndicate.local/api/health
# Attendu : 200
```

### 4.5. Captures jury

```sh
# Capture 1 : config client Mac (avant connexion)
cat ~/Library/Application\ Support/WireGuard/wg0.conf | grep -v PrivateKey

# Capture 2 : handshake serveur (apres connexion)
ssh root@100.112.113.2 \
  'qm guest exec 110 --timeout 10 -- /bin/bash -c "sudo wg show wg0"'

# Capture 3 : ping + curl reponse depuis le Mac (preuve d'acces)
ping -c 4 192.168.20.13
curl ...

# Capture 4 : tcpdump cote vpn-gw01 montrant le decapsulage WG
ssh root@100.112.113.2 \
  'qm guest exec 110 --timeout 10 -- /bin/bash -c "sudo timeout 5 tcpdump -nn -i wg0 -c 10"'
```

---

## 5. Sequence d'execution proposee (ordonnee)

| # | Etape | Type | Point de non-retour |
|---|-------|------|---------------------|
| 1 | Verifier cle privee `matthieu-mac` (toi) | lecture | non |
| 2 | Commit STATUS.md (dettes + prerequis runbook) | git | non (commit isole) |
| 3 | RECO finale (revalider iptables + vmbr3) | lecture | non |
| 4 | Backup `/etc/network/interfaces` + `/etc/iptables/rules.v4` | shell sur Proxmox | non |
| 5 | `ip addr add 172.16.1.5/29 dev vmbr3` (runtime only) | shell | **OUI** (modif reseau host) |
| 6 | Modif `/etc/network/interfaces` (persistance vmbr3) | edition fichier | non (deja en runtime) |
| 7 | Validation : `ping 172.16.1.4` depuis Proxmox | lecture | non |
| 8 | Supprimer DNAT `-i vmbr0` + ajouter sans restriction | iptables | **OUI** (modif NAT) |
| 9 | `iptables-save > /etc/iptables/rules.v4` (persistance) | shell | non (idempotent) |
| 10 | Activer wg-quick sur le Mac | Mac | non (cote client uniquement) |
| 11 | Verifier handshake + ping app01 | lecture | non |
| 12 | Captures jury | lecture | non |
| 13 | Mise a jour STATUS.md (resultat) + commit + push | git | non |

**Points de non-retour explicites** :
- Etape 5 : ajout IP sur vmbr3. Risque faible (juste un nouvel IP sur bridge),
  mais si erreur de masque/IP -> Proxmox host pourrait perdre connectivite si
  routes confuses. Mitigation : Tailscale 100.x reste accessible meme si vmbr0
  est partiellement perturbe.
- Etape 8 : modif iptables NAT. Risque : si la nouvelle regle est mal ecrite,
  Tailscale pourrait casser (mais `iptables-restore` accepte ou rejette en bloc,
  pas de demi-modif). `iptables-save` apres permet retour rapide via backup.

Pas de snapshot Proxmox host (pas une VM). Backups fichiers suffisent.

---

## 6. Dettes ouvertes par cette RECO

Detailees dans STATUS.md (commit a part) :

| Ticket | Severite | Description |
|--------|----------|-------------|
| **T-VMBR3-DMZ-IP** | MEDIUM | IP 172.16.1.5/29 prevue par ADR-0017 jamais posee sur vmbr3 Proxmox. Fix applique dans ce runbook. |
| **T-TF-OPNSENSE-NAT-NO-SUPPORT** | LOW | Provider browningluke 0.16 ne supporte pas `opnsense_firewall_nat` -> port-forwards/DNAT non IaC cote OPNsense. Confirmation STATUS Phase II §1. |
| **T-IPTABLES-ANSIBLE-PROXMOX** | MEDIUM | Pas de role Ansible pour gerer les regles iptables sur Proxmox host (`/etc/iptables/rules.v4`). Aujourd'hui edition manuelle. A integrer dans T-IAC-BRIDGES-PROXMOX-HOST. |
| **T-IPTABLES-MASQUERADE-DUPLICATE** | LOW | Doublon MASQUERADE pour 192.168.15.0/29, 192.168.20.0/28, 192.168.50.0/29 dans POSTROUTING Proxmox. A investiguer + nettoyer. |
| **T-WG-WGCONF-CLIENT-VAULT** | LOW | Les configs client `matthieu-mac` + `vps-hetzner-test` referencees mais cles privees off-repo. Convention de stockage a definir (1Password, vault Ansible client, ...). |

---

## 7. Decisions / questions ouvertes pour validation

1. **Activation runtime + persistance dans la meme operation ?** Recommandation
   du runbook : runtime d'abord (etape 5), persistance fichier ensuite (etape 6).
   En cas de pepin, le runtime peut etre retire (`ip addr del`) sans toucher
   au fichier.

2. **Mac private key trouvee ou regeneration ?** Determine si on procede en
   Option 3 directe (cle existante) ou Option 3 + 1bis (regen + update peer).

3. **`AllowedIPs` cote client** : on garde `10.20.0.0/24, 192.168.20.0/24`
   (servers Lyon) ou on ajoute aussi 172.16.1.0/29 (DMZ) ? Pour la demo,
   192.168.20.0/24 suffit (app01 = visible). 172.16.1.0/29 n'apporte rien
   sauf si tu veux montrer l'acces a web01 ou pki01 (mais ils sont en
   VLAN 60, pas 172.16, hors scope).

4. **AppendCommit dette `T-WG-POSTROUTING-MASQUERADE-DUPLICATE`** : si tu veux
   que je clean les doublons MASQUERADE pendant qu'on est dans iptables.
   Recommandation : **non**, hors scope demo, prevoir une session dediee.

---

## 8. References

- [ADR-0016 vpn-concentrator-architecture](adr/ADR-0016-vpn-concentrator-architecture.md) -- vpn-gw01 en DMZ
- [ADR-0017 nat-asymmetry-policy-routing](adr/ADR-0017-nat-asymmetry-policy-routing.md) -- pourquoi 172.16.1.5
- [STATUS.md Phase II §1](../STATUS.md) -- NAT outbound Automatic + provider TF limit
- [runbook-wireguard-road-warriors.md](runbook-wireguard-road-warriors.md) -- procedure ops
- [T-WG-ROAD-WARRIORS-LOG.md](T-WG-ROAD-WARRIORS-LOG.md) + [T-WG-HANDSHAKE-DEBUG.md](T-WG-HANDSHAKE-DEBUG.md) -- historique debug
- `roles/vpn_gateway/defaults/main.yml` -- defaut `vpn_gw_proxmox_dmz_ip: "172.16.1.5"`
- `/etc/wireguard/wg0.conf` vpn-gw01 -- annote Ansible-managed
- `iptables -t nat -L PREROUTING -n -v` -- DNAT existant Proxmox host
