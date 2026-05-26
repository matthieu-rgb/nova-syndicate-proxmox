# Agent : Network Mapper

## Mission

Agent read-only qui scanne l'infrastructure Nova Syndicate et genere :
1. Un inventaire JSON machine-readable (LIVRABLE PRINCIPAL) - source de verite
   consommee par les agents pentest-light, rules-auditor et report-writer.
2. Un diagramme draw.io XML (draft best-effort) - point de depart a polir
   manuellement dans draw.io desktop. Ce n'est PAS un livrable final.

L'agent NE MODIFIE JAMAIS l'infrastructure. Toutes les commandes sont read-only.

## Inputs

- Acces SSH a la flotte Nova via awx01 (cle awx-runner deja deployee)
- Skill drawio-nova : ../conventions/drawio-nova-skill.md (charte + templates XML)
- Topologie reference (cf skill)

## Outputs

- ../outputs/network-inventory.json (inventaire structure - LIVRABLE PRINCIPAL)
- ../outputs/network-map.drawio (XML draw.io - draft best-effort, non livrable jury,
  a polir dans draw.io desktop)
- ../outputs/network-mapper-execution.log (log d'execution)

## Tools necessaires (deja installes sur awx01)

- nmap (TCP scan, version detection)
- ssh + nft (read live FW rules)
- jq, yq (parsing)
- ip, ss (network state)

## Procedure

### Phase A : Discovery

1. Depuis awx01, scan TCP rapide des hosts Nova connus :
   - 172.16.1.2 (web01), 172.16.1.3 (mail01), 172.16.1.4 (vpn-gw01)
   - 192.168.15.2 (bastion01)
   - 192.168.20.10..13 (dc01, fs01, db01, app01)
   - 192.168.50.2 (backup01)
   - 192.168.60.2 (awx01)
   - 192.168.99.1 (FW-INT-LYON), 192.168.40.1 (FW-EXT-MRS si accessible)

   nmap -sT -p- --min-rate 1000 -oG /tmp/nmap-scan.gnmap <hosts>

2. Pour chaque host UP, version detection sur les ports ouverts :
   nmap -sV -sC -p <ports_open> -oN /tmp/nmap-versions-<host>.txt <host>

3. Pour chaque host SSH accessible (5 VMs avec cle awx-runner), recolter :
   - Hostname (hostname)
   - Distrib (lsb_release -a)
   - Services systemd actifs (systemctl list-units --type=service --state=active)
   - Interfaces reseau (ip -j addr show)
   - Routes (ip -j route show)
   - nft ruleset compact (nft list ruleset | head -200)

4. Sur dc01 specifiquement, recolter aussi :
   - Domain : samba-tool domain info
   - Users count : samba-tool user list | wc -l
   - Groups : samba-tool group list

### Phase B : Synthese structuree

Genere ../outputs/network-inventory.json avec ce schema :

```json
{
  "generated_at": "ISO 8601 timestamp",
  "scanner_host": "awx01",
  "sites": {
    "lyon": {
      "zones": {
        "dmz": {
          "cidr": "172.16.1.0/29",
          "hosts": [
            {
              "name": "web01",
              "ip": "172.16.1.2",
              "role": "nginx public",
              "services": ["nginx"],
              "open_ports": [80, 443]
            }
          ]
        },
        "servers": {}
      }
    },
    "marseille": {}
  },
  "firewalls": [
    {
      "name": "FW-EXT-LYON",
      "type": "OPNsense 25.1",
      "interfaces": ["wan", "lan", "dmz"]
    }
  ],
  "tunnels": {
    "ipsec_site_to_site": { "endpoints": ["FW-EXT-LYON", "FW-EXT-MRS"], "tunnels_count": 4 },
    "wireguard_road_warriors": { "endpoint": "vpn-gw01", "peers_count_planned": 20, "peers_count_actual": 1 },
    "tailscale": { "endpoint": "Hyperviseur Nova", "purpose": "mgmt break-glass" }
  }
}
```

### Phase C : Generation du diagramme draw.io

Genere ../outputs/network-map.drawio en suivant STRICTEMENT le skill
conventions/drawio-nova-skill.md :

1. Lis le skill drawio-nova-skill.md (path relatif : ../conventions/drawio-nova-skill.md)
2. Cree un fichier XML draw.io valide avec :
   - Structure mxfile + mxGraphModel + root (templates dans le skill)
   - Layout A4 paysage (1654x1169)
   - Swim lanes par zone avec les bonnes couleurs (cf charte skill)
   - VMs/hosts positionnees dans leur zone respective
   - Firewalls (rouge fonce #F08080) entre les zones
   - Liens VLAN avec labels
   - Tunnels IPsec (pointilles bleus), WireGuard (pointilles verts),
     Tailscale (pointilles gris)
   - Clouds externes (WAN-LYON, WAN-MRS, Tailscale, Road warriors)
3. Respecter les regles d'or :
   - ZERO reference virtualisation (pas de "Proxmox", "VMID", "lab", "simulator")
   - 2 WAN distincts
   - Standard keyboard chars uniquement
   - IPs jamais isolees (toujours dans le label d'une VM/firewall)

### Phase D : Log d'execution

Ecris ../outputs/network-mapper-execution.log avec :
- Timestamp debut/fin
- Hosts scanned (UP/DOWN)
- Erreurs eventuelles (host injoignable, etc.)
- Statistiques (X hosts scanned, Y ports detected, Z services identified)

## Garde-fous

- TOUS les commandes sont read-only. Aucun nft -f, aucun ssh -t, aucun ansible-playbook
  (sans --check).
- Si un scan met plus de 5 min sur un host : skip, log warning, continue.
- Si SSH echoue sur un host : log warning, continue.
- L'agent ne modifie JAMAIS de fichier hors /tmp et ../outputs/.
- Le drawio est un draft, pas un livrable final : le polish visuel se fait
  manuellement dans draw.io desktop, le JSON reste la source de verite.
