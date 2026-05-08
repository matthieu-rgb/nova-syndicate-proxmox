# Runbook -- Monitoring (Prometheus + Grafana)

## Perimetre

APP1 (192.168.20.13). Prometheus port 9090, Grafana port 3000. node_exporter (9100) sur 10 hotes.

## Acces

- Grafana : http://192.168.20.13:3000 (admin / vault_grafana_admin_password)
- Prometheus : http://192.168.20.13:9090

## Hotes supervises (node_exporter)

dc01, fs01, db01, app01, bastion01, backup01, proxy-lyon01, proxy_mrs01, web01, mail01.

## Operations courantes

### Verifier les services

```bash
ssh debian@192.168.20.13
sudo systemctl status prometheus grafana-server
```

### Verifier les targets Prometheus

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"instance"'
```

### Ajouter un target node_exporter

Editer /etc/prometheus/prometheus.yml, ajouter l'IP:9100 dans le job `node`, puis :

```bash
sudo systemctl reload prometheus  # ou restart si reload non supporte
```

### Acceder au mot de passe Grafana

```bash
# Sur le poste Ansible :
ansible-vault view inventory/group_vars/all/vault.yml --vault-password-file ~/.ansible/nova_vault_pass | grep grafana
```

### Reinitialiser le mot de passe Grafana (API)

```bash
curl -X PUT -H "Content-Type: application/json" \
  -d '{"oldPassword":"<ancien>","newPassword":"<nouveau>","confirmNew":"<nouveau>"}' \
  http://admin:<ancien>@localhost:3000/api/user/password
```

### Importer un dashboard (TODO matin)

- Dashboard Node Exporter Full : ID 1860
- Dashboard MariaDB : ID 13338
- Via Grafana UI : Dashboards > Import > ID > Load

## Diagnostic

### Grafana ne demarre pas

```bash
sudo journalctl -u grafana-server -n 50
sudo grafana-cli admin reset-admin-password <nouveau>  # reset emergency
```

### Prometheus ne scrape pas un host

```bash
# Verifier node_exporter sur le host :
ssh debian@<host> "sudo systemctl status prometheus-node-exporter"
curl http://<host_ip>:9100/metrics | head -5
# Verifier firewall VLAN : node_exporter doit etre joignable depuis APP1 (192.168.20.13)
```

### Datasource Prometheus manquante dans Grafana

```bash
# Recree via API :
curl -X POST http://admin:<pass>@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{"name":"Prometheus","type":"prometheus","url":"http://localhost:9090","access":"proxy","isDefault":true}'
```

## Fichiers importants

- Config Prometheus : /etc/prometheus/prometheus.yml
- Config Grafana : /etc/grafana/grafana.ini
- Data Prometheus : /var/lib/prometheus/
- Data Grafana : /var/lib/grafana/
- Playbook Ansible : playbooks/monitoring.yml
