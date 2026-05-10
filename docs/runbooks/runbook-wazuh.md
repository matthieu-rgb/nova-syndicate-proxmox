# Runbook : wazuh (Manager + Agents)

## 1. Perimetre

Le role `wazuh_manager` deploie Wazuh 4.11.2 sur app01 (192.168.20.13, VLAN SERVERS), qui fait office de SIEM central pour tout le parc Nova Syndicate. Le manager collecte les evenements de securite de tous les agents, applique les regles de detection (dont les regles NIS2 custom `nova_nis2_rules.xml`), et expose une API REST sur le port 55000. Le dashboard Wazuh (Kibana/OpenSearch) est installe separement sur app01 (hors perimetre de ce role).

Le role `wazuh_agent` deploie l'agent Wazuh 4.11.2 sur toutes les autres VMs : dc01 (192.168.20.10), fs01 (192.168.20.11), db01 (192.168.20.12), bastion01 (192.168.15.2), backup01 (192.168.50.2), proxy-lyon01 (192.168.20.14), web01 (172.16.1.2) et mail01 (172.16.1.3). Les agents s'enregistrent aupres du manager via le port 1515 (authd) et transmettent leurs evenements sur le port 1514 (remoted).

app01 est egalement la machine qui heberge Prometheus et Grafana (monitoring metrique), mais ces composants sont geres par des roles distincts. Ce runbook couvre exclusivement le deploiement et l'operation de Wazuh manager et agents. La retention des alertes est fixee a 90 jours (`wazuh_alerts_retention_days: 90`), repondant a l'exigence NIS2 Art. 21.f sur la traçabilite.

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `wazuh_manager` et `wazuh_agent`.
- `wazuh_manager` doit etre deploye sur app01 avant `wazuh_agent` sur les autres VMs (les agents ont besoin que le manager soit operationnel pour s'enregistrer).

### Reseau

- app01 (192.168.20.13) doit avoir les ports suivants accessibles :
  - TCP 1514 : reception evenements agents (remoted)
  - TCP 1515 : enregistrement agents (authd)
  - TCP 55000 : API Wazuh
- Les agents doivent pouvoir joindre 192.168.20.13 sur TCP 1514 et 1515 depuis leurs VLANs respectifs.
- Le pare-feu OPNsense doit autoriser les flux inter-VLAN correspondants (VLAN 15, 50 -> VLAN 20 sur 1514/1515).

### Packages

- Manager : depots GPG Wazuh officiels, paquet `wazuh-manager` version 4.11.2
- Agent : depots GPG Wazuh officiels, paquet `wazuh-agent` version 4.11.2

### Acces

- Manager SSH : `ssh -J debian@192.168.15.2 debian@192.168.20.13`
- Agent SSH (exemple db01) : `ssh -J debian@192.168.15.2 debian@192.168.20.12`

## 3. Installation

### Deploiement du manager (app01)

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Dry-run
ansible-playbook -i inventory/hosts.yml site.yml \
  -l app01 \
  --tags wazuh_manager \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass

# Deploiement
ansible-playbook -i inventory/hosts.yml site.yml \
  -l app01 \
  --tags wazuh_manager \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement des agents (toutes les autres VMs)

```bash
# Dry-run agents
ansible-playbook -i inventory/hosts.yml site.yml \
  -l all,!app01 \
  --tags wazuh_agent \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass

# Deploiement agents
ansible-playbook -i inventory/hosts.yml site.yml \
  -l all,!app01 \
  --tags wazuh_agent \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement d'un agent sur une nouvelle VM

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l <nouvelle_vm> \
  --tags wazuh_agent \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes (manager)

1. `tasks/install.yml` -- depot GPG, apt, wazuh-manager 4.11.2
2. `tasks/config.yml` -- ossec.conf template (remoted, authd, alerts)
3. `tasks/rules.yml` -- deploiement nova_nis2_rules.xml
4. `tasks/service.yml` -- enable + start wazuh-manager

### Ordre des tasks internes (agent)

1. Installation GPG + depot + wazuh-agent 4.11.2
2. Configuration IP manager : 192.168.20.13
3. Enregistrement via agent-auth sur port 1515
4. Enable + start wazuh-agent

## 4. Configuration

### Variables wazuh_manager (defaults/main.yml)

```yaml
wazuh_manager_version: "4.11.2"
wazuh_manager_port_remoted: 1514
wazuh_manager_port_authd: 1515
wazuh_manager_port_api: 55000
wazuh_api_user: "wazuh"
wazuh_install_dir: /var/ossec
wazuh_nis2_rules_filename: "nova_nis2_rules.xml"
wazuh_alerts_retention_days: 90
wazuh_use_reload_for_rules: true
```

### Variables wazuh_agent (defaults/main.yml)

```yaml
wazuh_manager_ip: "192.168.20.13"
wazuh_manager_port: 1514
```

### Fichier ossec.conf (extrait cle)

```xml
<ossec_config>
  <global>
    <logall>no</logall>
    <logall_json>no</logall_json>
    <alerts_log>yes</alerts_log>
    <jsonout_output>yes</jsonout_output>
  </global>
  <remote>
    <connection>secure</connection>
    <port>1514</port>
    <protocol>tcp</protocol>
  </remote>
  <auth>
    <disabled>no</disabled>
    <port>1515</port>
    <use_source_ip>no</use_source_ip>
    <purge>yes</purge>
  </auth>
</ossec_config>
```

### Regles NIS2 custom (nova_nis2_rules.xml)

Regles deployees dans `/var/ossec/etc/rules/nova_nis2_rules.xml` couvrant :
- Alertes sur les connexions root (niveau 10)
- Alertes sur les modifications /etc/passwd, /etc/sudoers (niveau 12)
- Alertes sur les DROP TABLE MariaDB (niveau 11)
- Alertes sur les fails d'authentification repetitifs AD (niveau 10)
- Alertes sur les changements de regles nftables (niveau 9)

## 5. Validation post-deploiement

### Verifier le manager actif

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/wazuh-control status"
```

Resultat attendu : tous les processus `ossec-analysisd`, `ossec-remoted`, `ossec-authd`, `wazuh-modulesd` a l'etat `running`.

### Verifier les ports en ecoute

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo ss -tlnp | grep -E '1514|1515|55000'"
```

### Verifier les agents connectes

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/agent_control -l"
```

Tous les agents (dc01, fs01, db01, bastion01, backup01, proxy-lyon01, web01, mail01) doivent etre a l'etat `Active`.

### Tester l'API Wazuh

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "curl -s -u wazuh:<API_PASS> \
   'https://localhost:55000/agents?status=active' -k | \
   python3 -m json.tool | grep 'name'"
```

### Verifier les alertes recentes

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo tail -20 /var/ossec/logs/alerts/alerts.log"
```

### Verifier les regles NIS2

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/wazuh-logtest" 
# Injecter un log test pour valider les regles NIS2 custom
```

## 6. Operations courantes

### Redemarrer le manager

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo systemctl restart wazuh-manager && \
   sudo /var/ossec/bin/wazuh-control status"
```

### Recharger les regles sans redemarrage

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/wazuh-control reload"
```

### Ajouter/modifier les regles NIS2

1. Modifier le template `roles/wazuh_manager/templates/nova_nis2_rules.xml.j2`
2. Rejouer le role :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l app01 \
  --tags wazuh_manager,rules \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

Le handler `Reload wazuh-manager` (`wazuh-control reload`) s'executera automatiquement.

### Verifier l'etat d'un agent specifique

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/agent_control -i <AGENT_ID>"
```

### Redemarrer un agent sur une VM

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo systemctl restart wazuh-agent && \
   sudo systemctl is-active wazuh-agent"
```

### Consulter les logs du manager

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo tail -50 /var/ossec/logs/ossec.log | grep -E 'ERROR|WARN'"
```

### Rotation manuelle des alertes

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo find /var/ossec/logs/alerts/ -name '*.log' -mtime +90 -delete"
```

## 7. Troubleshooting

### Incident 1 : Agent affiche le statut "Disconnected" dans la liste

**Symptome :** `agent_control -l` montre un ou plusieurs agents en `Disconnected`.

**Diagnostic :**
```bash
# Verifier l'etat du service wazuh-agent sur la VM concernee (ex. db01)
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo systemctl status wazuh-agent && \
   sudo tail -20 /var/ossec/logs/ossec.log"

# Verifier la connectivite reseau vers le manager
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo nc -zv 192.168.20.13 1514 && \
   sudo nc -zv 192.168.20.13 1515"
```

**Fix :**
```bash
# Redemarrer l'agent
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo systemctl restart wazuh-agent"

# Si le probleme persiste, re-enregistrer l'agent
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo /var/ossec/bin/agent-auth -m 192.168.20.13 -p 1515"
```

### Incident 2 : Le manager ne demarre pas apres modification des regles

**Symptome :** `wazuh-control status` montre `ossec-analysisd` a `stopped`. Le log indique une erreur XML.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/ossec-logtest -t 2>&1 | tail -20"
```

**Fix :** Identifier la ligne incriminee dans `nova_nis2_rules.xml`. Valider le XML avant de le deployer :
```bash
xmllint --noout /var/ossec/etc/rules/nova_nis2_rules.xml
```

Corriger le template Ansible et rejouer avec `--tags wazuh_manager,rules`.

### Incident 3 : L'API Wazuh retourne 401 Unauthorized

**Symptome :** `curl -u wazuh:<PASS> https://localhost:55000/` retourne `{"error":6,"message":"Invalid credentials"}`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo cat /var/ossec/api/configuration/api.yaml | grep -E 'user|pass'"
```

**Fix :** Reinitialiser le mot de passe de l'utilisateur API :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/wazuh-passwords-tool -u wazuh -p '<NOUVEAU_PASS>'"
```

Mettre a jour la variable vault correspondante dans le vault Ansible.

### Incident 4 : Aucune alerte generee malgre des evenements suspects

**Symptome :** Des echecs SSH sont visibles dans les logs systeme mais aucune alerte Wazuh n'est generee.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo /var/ossec/bin/wazuh-logtest"
# Injecter manuellement un log SSH failed : 
# sshd: Failed password for invalid user admin from 10.0.0.1 port 22 ssh2
```

**Fix :** Si wazuh-logtest ne decode pas le log, le decoder correspondant est manquant ou mal configure. Verifier les decoders actifs et les regles de niveau correspondant. Verifier que l'agent collecte bien les logs sshd (`/var/log/auth.log`).

### Incident 5 : Espace disque plein sur app01 (logs Wazuh)

**Symptome :** `df -h /var/ossec/` montre 100% d'utilisation. Le manager peut cesser d'ecrire des alertes.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo du -sh /var/ossec/logs/ && \
   sudo ls -lht /var/ossec/logs/alerts/ | head -10"
```

**Fix :**
```bash
# Supprimer les alertes de plus de 90 jours
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo find /var/ossec/logs/ -name '*.log.gz' -mtime +90 -delete && \
   sudo find /var/ossec/logs/alerts/ -name '*.json.gz' -mtime +90 -delete"
```

Verifier que la retention automatique (`wazuh_alerts_retention_days: 90`) est bien configuree dans ossec.conf.

### Incident 6 : Agent non enregistre apres deploiement (key error)

**Symptome :** `systemctl status wazuh-agent` affiche `ERROR: Unable to connect to server. Disconnecting.`

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo cat /var/ossec/etc/client.keys"
# Si vide ou absent, l'agent n'est pas enregistre
```

**Fix :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo /var/ossec/bin/agent-auth \
   -m 192.168.20.13 \
   -p 1515 \
   -A fs01"

sudo systemctl restart wazuh-agent
```

## 8. Disaster Recovery

### Contexte DR

La perte du manager Wazuh entraine une perte de visibilite sur le parc (pas d'alertes, pas de SIEM). Les agents continuent de fonctionner localement et bufferisent leurs evenements jusqu'a reconnexion. RTO cible : 2 heures. RPO : les evenements bufferises sur les agents (jusqu'a 1h en general).

### Procedure de restauration du manager (app01)

**Etape 1 : Provisionner une nouvelle VM app01 si necessaire**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/
terraform apply -target=proxmox_vm_qemu.app01
```

**Etape 2 : Deployer common, hardening, puis wazuh_manager**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  -l app01 \
  --tags common,hardening,wazuh_manager \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**Etape 3 : Restaurer les cles agents depuis backup01**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg list /var/backups/borg/configs

sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract /var/backups/borg/configs::nova-configs-<DATE> \
  var/ossec/etc/

scp -J debian@192.168.15.2 \
  /var/ossec/etc/client.keys \
  debian@192.168.20.13:/var/ossec/etc/
```

**Etape 4 : Redemarrer le manager et verifier les agents**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo systemctl restart wazuh-manager && \
   sudo /var/ossec/bin/agent_control -l"
```

**Etape 5 : Si les cles sont perdues, re-enregistrer tous les agents**

Rejouer le role `wazuh_agent` sur toutes les VMs :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l all,!app01 \
  --tags wazuh_agent \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**RTO :** 2 heures (provisioning + deploiement + validation agents).
**RPO :** Evenements bufferises sur agents (environ 1h), alertes historiques recuperees depuis Borg.

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
Wazuh constitue le systeme de detection d'intrusion (IDS) du parc. La centralisation des logs sur app01 permet la correlation d'evenements multi-VM, necessaire pour detecter les attaques laterales (pass-the-hash, reconnaissance AD via LDAP). Les regles NIS2 custom (`nova_nis2_rules.xml`) couvrent les vecteurs d'attaque specifiques au perimetre Nova Syndicate.

**Art. 21.2.c -- Gestion des incidents :**
La retention de 90 jours des alertes (`wazuh_alerts_retention_days: 90`) satisfait a l'obligation de conservation des preuves necessaires a l'analyse post-incident. L'API Wazuh (port 55000) permet l'integration avec des outils d'orchestration d'incidents (TheHive, dans l'infrastructure Matthieu sur 192.168.100.49).

**Art. 21.2.e -- Continuite d'activite :**
La sauvegarde des cles agents (client.keys) et de la configuration ossec.conf via Borg assure la restauration rapide du SIEM sans perte de couverture de monitoring.

**Art. 21.2.f -- Audit et traçabilite (particulierement pertinent) :**
C'est la mesure centrale de ce role. Wazuh collecte et centralise les evenements d'audit de tout le parc (connexions, sudo, modifications fichiers sensibles, activite AD, activite MariaDB via server_audit). Les alertes de niveau >= 7 doivent etre revues quotidiennement. La traçabilite des actions privilegiees (root, sudo) est garantie par la combinaison auditd (sur chaque VM) + Wazuh agent.

### Comptes et secrets

- L'utilisateur API `wazuh` a un mot de passe dans le vault Ansible.
- L'acces au dashboard Wazuh doit etre restreint au VLAN Management (192.168.10.0/24).
- Les cles d'enregistrement des agents (client.keys) doivent etre sauvegardees dans Borg.

## 10. References

### Internes au projet

- `roles/wazuh_manager/defaults/main.yml` -- variables manager
- `roles/wazuh_agent/defaults/main.yml` -- variables agent
- `roles/wazuh_manager/templates/nova_nis2_rules.xml.j2` -- regles NIS2 custom
- `roles/wazuh_manager/templates/ossec.conf.j2` -- config manager
- Runbook hardening : `docs/runbooks/runbook-hardening.md`
- Runbook backup : `docs/runbooks/runbook-backup.md`

### Documentation upstream

- Wazuh documentation 4.11 : https://documentation.wazuh.com/current/
- Wazuh agent deployment : https://documentation.wazuh.com/current/installation-guide/wazuh-agent/
- Wazuh rules syntax : https://documentation.wazuh.com/current/user-manual/ruleset/rules-syntax.html
- NIS2 Directive Art. 21 : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32022L2555
