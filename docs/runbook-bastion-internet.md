# Runbook -- Accès internet BASTION01 et VLANs

## Etat actuel (2026-05-08)

### Architecture NAT

FW-INT-LYON assure le NAT outbound pour tous les VLANs internes
vers FW-EXT-LYON, qui effectue un second NAT vers le WAN.

```
VLAN (192.168.x.x)
    |
    vlan0x (FW-INT-LYON)
    NAT -> vtnet0 (10.0.1.2)
    |
    10.0.1.0/30 transit
    |
    vtnet2 (FW-EXT-LYON)
    NAT -> vtnet0 (WAN IP)
    |
    WAN -> Internet
```

FW-INT-LYON pfctl -sn (extrait pertinent) :
```
no nat on vtnet0 inet from 192.168.0.0/16 to 192.168.40.0/26   # no-NAT IPsec
no nat on vtnet0 inet from 192.168.15.0/29 to 192.168.40.0/26  # no-NAT IPsec
nat on vtnet0 inet from (vlan01:network) to any -> (vtnet0:0)   # BACKUP outbound
nat on vtnet0 inet from (vlan02:network) to any -> (vtnet0:0)   # BASTION outbound
nat on vtnet0 inet from (vlan03:network) to any -> (vtnet0:0)   # SERVERS outbound
nat on vtnet0 inet from (vlan04:network) to any -> (vtnet0:0)   # USERS outbound
```

### Regles filter actives par VLAN (fw_int.tf)

| VLAN | Interface | Ressource Terraform | Acces internet | Description |
|------|-----------|---------------------|----------------|-------------|
| BASTION 15.0/29 | opt2 (vlan02) | fwint_bastion_to_internet | OUI | host_bastion01 -> any |
| SERVERS 20.0/28 | opt3 (vlan03) | fwint_servers_to_internet | OUI | net_lyon_servers -> any |
| USERS 30.0/26 | opt4 (vlan04) | fwint_users_to_internet | OUI | net_lyon_users -> any |
| BACKUP 50.0/29 | opt1 (vlan01) | fwint_backup_to_internet | OUI | host_backup01 -> any |

Toutes ces regles sont `enabled = true` en Terraform. Les regles
`*_block_all` correspondantes sont `enabled = false` (dette T3).

### Tests de fonctionnement BASTION (2026-05-08)

Depuis BASTION01 (192.168.15.2) :
```
curl -sI https://github.com  -> HTTP/2 200  (PASS)
getent hosts github.com      -> 140.82.121.3 github.com (DNS OK)
ip route                     -> default via 192.168.15.1 (GW = FW-INT-LYON vlan02)
```

T2 valide : BASTION01 peut git clone, apt, terraform, ansible.

---

## Justification : acces "raw" conserve sur SERVERS/USERS/BACKUP

Les regles `to_internet` sur les 3 autres VLANs sont volontairement
conservees en attendant le deploiement de T-SQUID.

Les supprimer maintenant casserait :
- SERVERS : apt update/upgrade, NTP synchronisation, pull Docker Hub/registry
- USERS : navigation web (postes de travail)
- BACKUP : rclone vers Backblaze B2 (backups distants)

Le filtrage granulaire sera assure par un proxy Squid forward
(voir T-SQUID dans PHASE-II-KANBAN.md) avec whitelist par VLAN.

---

## Troubleshooting BASTION perd internet

### 1. Verifier la regle filter sur FW-INT-LYON

```sh
ssh opn-fw-int-lyon 'pfctl -sr | grep bastion'
# Doit afficher :
# pass in quick on vlan02 inet from <host_bastion01> to any ...
```

Si absent : terraform apply fw_int.tf (la regle fwint_bastion_to_internet
est en state).

### 2. Verifier le NAT outbound sur FW-INT-LYON

```sh
ssh opn-fw-int-lyon 'pfctl -sn | grep vlan02'
# Doit afficher :
# nat on vtnet0 inet from (vlan02:network) to any -> (vtnet0:0)
```

NAT gere par OPNsense Hybrid mode (Automatic + regles manuelles).

### 3. Verifier le NAT sur FW-EXT-LYON

```sh
ssh opn-fw-ext-lyon 'pfctl -sn | grep vtnet2'
# nat on vtnet0 inet from (vtnet2:network) to any -> (vtnet0:0)
```

Le trafic 10.0.1.2 (NATte par FW-INT) arrive sur vtnet2 de FW-EXT-LYON,
qui le re-NAT vers le WAN. Ce NAT est gere automatiquement.

### 4. Test de connectivite par etape

```sh
# Depuis BASTION01
ping -c 2 192.168.15.1        # gateway FW-INT-LYON vlan02
ping -c 2 10.0.1.1            # FW-EXT-LYON vtnet2 (opt1)
ping -c 2 10.0.0.1            # WAN-SIM
curl -sI --max-time 5 https://1.1.1.1  # internet sans DNS
curl -sI --max-time 5 https://github.com  # internet avec DNS
```

### 5. DNS

BASTION01 utilise le resolver par defaut configure par DHCP ou statique.
FW-INT-LYON expose Unbound sur 192.168.15.1 (interface vlan02).
Verifier :
```sh
# Depuis BASTION01
cat /etc/resolv.conf
# ou
resolvectl status
```

Si DNS en echec, verifier Unbound sur FW-INT-LYON :
```sh
ssh opn-fw-int-lyon 'curl -sk -u "API_KEY:API_SECRET" https://192.168.99.1/api/unbound/diagnostics/stats | python3 -m json.tool | head -20'
```

---

## Prochaine etape : T-SQUID

Voir PHASE-II-KANBAN.md section T-SQUID pour le plan de filtrage
par VLAN via proxy forward Squid.
