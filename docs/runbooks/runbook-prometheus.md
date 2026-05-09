# Runbook -- Prometheus + node_exporter scrape

## Perimetre

Prometheus sur APP1 (192.168.20.13:9090). Scrape node_exporter (port 9100) sur tous les hotes Nova Syndicate.

## Etat actuel (2026-05-09)

| Hote | IP | Statut scrape | nftables regle |
|------|-----|---------------|----------------|
| app01 | 192.168.20.13 | UP | iif lo accept (loopback) |
| dc01 | 192.168.20.10 | UP | ip saddr 192.168.20.13 tcp dport 9100 accept |
| fs01 | 192.168.20.11 | UP | idem |
| db01 | 192.168.20.12 | UP | idem |
| bastion01 | 192.168.15.2 | UP | idem |
| backup01 | 192.168.50.2 | UP | idem |

## Architecture Prometheus -> node_exporter

```
APP1 (192.168.20.13:9090)
    |-- scrape :9100 --> dc01    (192.168.20.10)
    |-- scrape :9100 --> fs01    (192.168.20.11)
    |-- scrape :9100 --> db01    (192.168.20.12)
    |-- scrape :9100 --> bastion01 (192.168.15.2)
    |-- scrape :9100 --> backup01 (192.168.50.2)
    `-- scrape :9100 --> app01   (localhost, via lo)
```

nftables sur chaque hote autorise uniquement APP1 (192.168.20.13/32) sur port 9100.
Pas de ouverture large -- source stricte.

## Variable Ansible -- monitoring_scrapers

Definie dans `inventory/group_vars/all/vars.yml` du repo nova-syndicate-ansible :

```yaml
monitoring_scrapers:
  - name: "prometheus-app01"
    ip:   "{{ nova_ip_app01 }}"   # 192.168.20.13
    port: 9100
```

Le role `hardening` injecte ces regles dans `/etc/nftables.conf` via le template `nftables.conf.j2`.

## Ajouter un nouveau scraper (ex: Wazuh future)

1. Ajouter l'entree dans `group_vars/all/vars.yml` :
   ```yaml
   monitoring_scrapers:
     - name: "prometheus-app01"
       ip:   "{{ nova_ip_app01 }}"
       port: 9100
     - name: "wazuh-manager"
       ip:   "{{ nova_ip_app01 }}"
       port: 1514
   ```

2. Relancer le playbook hardening sur les hotes cibles :
   ```bash
   cd nova-syndicate-ansible
   ansible-playbook -i inventory/hosts.yml site.yml --tags role:hardening --limit <hotes>
   ```

3. Verifier la regle :
   ```bash
   ssh debian@<hote> "sudo nft list ruleset | grep <port>"
   ```

## Ajouter un scraper specifique a un hote (host_vars override)

Pour un hote qui necessite un scraper supplementaire, surcharger dans `host_vars/<hote>.yml` :

```yaml
monitoring_scrapers:
  - name: "prometheus-app01"
    ip:   "192.168.20.13"
    port: 9100
  - name: "scraper-specifique"
    ip:   "192.168.10.5"
    port: 8080
```

Note : la surcharge de liste en Ansible remplace la liste entiere. Toujours inclure le scraper Prometheus de base.

## Operations courantes

### Verifier les targets Prometheus

```bash
ssh debian@192.168.20.13 'curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys,json
data=json.load(sys.stdin)
for t in data[\"data\"][\"activeTargets\"]:
    print(t[\"labels\"][\"instance\"], t[\"health\"])
"'
```

### Verifier une regle nftables sur un hote

```bash
ssh debian@<hote> "sudo nft list ruleset | grep 9100"
# Attendu : ip saddr 192.168.20.13 tcp dport 9100 accept
```

### Tester le scrape manuellement depuis APP1

```bash
ssh debian@192.168.20.13 "curl -sI --max-time 5 http://<hote_ip>:9100/metrics | head -2"
# Attendu : HTTP/1.1 200 OK
```

### Reappliquer les regles nftables (idempotent)

```bash
cd nova-syndicate-ansible
ansible-playbook -i inventory/hosts.yml site.yml --tags role:hardening --limit <hote>
```

## Note -- SSH allowlist nftables (2026-05-09)

Le deploiement du role hardening a revele que `hardening_allowed_ssh_nets` dans les defaults du role ne incluait pas le reseau Proxmox. Les defaults ont ete etendus dans `group_vars/all/vars.yml` :

```yaml
hardening_allowed_ssh_nets:
  - "192.168.10.0/24"   # VLAN management
  - "192.168.15.0/24"   # VLAN bastion (jumpbox)
  - "192.168.18.0/24"   # Proxmox vmbr0 (management Proxmox)
  - "192.168.20.0/28"   # VLAN servers (Proxmox utilise 192.168.20.5 via vmbr1.20 pour ProxyJump)
```

Sans ces 4 nets, Ansible perd la connexion SSH apres reload nftables car le ProxyJump
Proxmox -> VM utilise l'IP VLAN de Proxmox (192.168.20.5) pas l'IP management (192.168.18.50).

## TODO

- [ ] Finaliser import dashboards Grafana (voir runbook-grafana.md -- script pret sur APP1)
- [ ] Ajouter node_exporter sur proxy-mrs01, web01, mail01 (non enrolles)
- [ ] Configurer alertmanager Prometheus (aucune alerte active en l'etat)
- [ ] Wazuh datasource dans Grafana
