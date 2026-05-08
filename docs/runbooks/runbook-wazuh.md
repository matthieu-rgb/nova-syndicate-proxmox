# Runbook -- SIEM Wazuh

## Perimetre

Wazuh 4.11.2 sur APP1 (192.168.20.13). 6 agents enrolles : backup01, proxy-lyon01, dc01, fs01, db01, bastion01.

## Operations courantes

### Verifier le manager

```bash
ssh debian@192.168.20.13
sudo systemctl status wazuh-manager
sudo /var/ossec/bin/wazuh-control status
```

### Lister les agents actifs

```bash
sudo /var/ossec/bin/agent_control -l
```

### Verifier les regles custom

```bash
sudo cat /var/ossec/etc/rules/nova_custom_rules.xml
sudo /var/ossec/bin/wazuh-logtest  # tester une regle
```

### Regles custom deployes

| ID | Niveau | Description |
|----|--------|-------------|
| 100100 | 10 | Samba brute-force (>10 echecs 60s) |
| 100101 | 6 | Samba auth failure unique |
| 100200 | 6 | MariaDB access denied |
| 100300 | 10 | SSH brute-force |

### Recharger les regles sans redemarrer

```bash
sudo kill -HUP $(cat /var/ossec/var/run/wazuh-analysisd.pid)
```

### Enroller un nouvel agent

```bash
# Sur le manager (APP1) :
sudo /var/ossec/bin/manage_agents  # option A = ajouter

# Sur l'agent :
sudo /var/ossec/bin/manage_agents  # option I = importer la cle
sudo systemctl restart wazuh-agent
```

### Verifier les alertes recentes

```bash
sudo tail -f /var/ossec/logs/alerts/alerts.log
sudo grep "nova:" /var/ossec/logs/alerts/alerts.log | tail -20
```

## Diagnostic

### Agent deconnecte

```bash
# Sur l'agent :
sudo systemctl status wazuh-agent
sudo systemctl restart wazuh-agent
sudo tail -f /var/ossec/logs/ossec.log

# Sur le manager, verifier connexion :
sudo /var/ossec/bin/agent_control -s -i <agent_id>
```

### Manager ne demarre pas

```bash
sudo /var/ossec/bin/ossec-logtest  # valider config XML
sudo /var/ossec/bin/wazuh-control start
sudo journalctl -u wazuh-manager -n 100
```

### Regle ne se declenche pas

```bash
# Tester manuellement :
echo "<syslog_message>" | sudo /var/ossec/bin/wazuh-logtest
# Verifier que le fichier de regles est bien inclus dans ossec.conf
sudo grep "nova_custom_rules" /var/ossec/etc/ossec.conf
```

## Fichiers importants

- Config manager : /var/ossec/etc/ossec.conf
- Regles custom : /var/ossec/etc/rules/nova_custom_rules.xml
- Alerts : /var/ossec/logs/alerts/
- Logs manager : /var/ossec/logs/ossec.log
- Playbook Ansible : playbooks/wazuh-agents.yml
