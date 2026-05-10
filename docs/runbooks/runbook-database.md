# Runbook : database (MariaDB)

## 1. Perimetre

Le role `database` provisionne et gere le serveur de bases de donnees MariaDB sur db01 (192.168.20.12, VLAN SERVERS). Il couvre l'installation de MariaDB, la configuration serveur optimisee pour le parc Nova Syndicate, la securisation initiale (suppression des comptes anonymes et de la base test, mot de passe root), la creation des bases de donnees et comptes applicatifs (`nova_logistique`, `nova_rh`), l'activation du plugin d'audit serveur (`server_audit`), et la mise en place des sauvegardes automatiques via un script `mariadb-backup.sh` avec cron.

db01 est la source unique de donnees relationnelles du projet. Les applications logistique et RH hebergees sur app01 (192.168.20.13) se connectent a db01 via TCP 3306 en utilisant des comptes applicatifs a privileges minimaux. Le plugin server_audit genere des logs d'acces conformes NIS2 Art. 21.f. La replication binlog (ROW) est activee pour permettre des restaurations point-in-time.

Le serveur MariaDB ecoute uniquement sur l'IP interne 192.168.20.12 (pas de `0.0.0.0`). L'acces est restreint par nftables a l'accept de TCP 3306 depuis les reseaux internes autorises. Aucune interface d'administration web n'est deployee sur db01. Toutes les operations d'administration se font en CLI via SSH ProxyJump depuis bastion01.

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `database`.
- Le role `wazuh_agent` doit etre deploye sur db01 pour la collecte des logs d'audit MariaDB.

### Reseau

- db01 : IP statique 192.168.20.12/28, gateway 192.168.20.1.
- Port 3306 ouvert par nftables (via `hardening_extra_nft_rules: ["tcp dport 3306 accept"]`).
- db01 doit avoir acces a backup01 (192.168.50.2) pour le transfert des dumps.

### Packages

`mariadb-server`, `mariadb-client`, `python3-mysqldb`

### Acces

- SSH via bastion : `ssh -J debian@192.168.15.2 debian@192.168.20.12`

## 3. Installation

### Verification pre-deploiement

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Verifier que db01 est accessible
ansible databases -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian

# Verifier que MariaDB n'est pas deja installe (idempotent sinon)
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "dpkg -l mariadb-server 2>&1 | grep -E '^ii|no packages'"
```

### Dry-run

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l databases \
  --tags database \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement complet

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l databases \
  --tags database \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement cible (reconfigurer uniquement)

```bash
# Reappliquer uniquement la configuration MariaDB (50-nova-server.cnf)
ansible-playbook -i inventory/hosts.yml site.yml \
  -l databases \
  --tags database,config \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes

1. Installation MariaDB + packages
2. Deploiement `/etc/mysql/mariadb.conf.d/50-nova-server.cnf.j2`
3. Securisation : root password, suppression comptes anonymes, suppression base test
4. Creation bases `nova_logistique` et `nova_rh` + comptes applicatifs
5. Creation compte `backup_nova` avec privileges LOCK TABLES, SELECT
6. Activation plugin `server_audit`
7. Creation repertoire dump + script `mariadb-backup.sh`
8. Cron toutes les 15 minutes

## 4. Configuration

### Variables principales (group_vars/databases/vars.yml)

```yaml
mariadb_bind_address: "192.168.20.12"
mariadb_port: 3306
mariadb_max_connections: 150
mariadb_innodb_buffer: "256M"
mariadb_log_bin: true
mariadb_binlog_format: "ROW"
mariadb_expire_logs_days: 7
mariadb_audit_enable: true
mariadb_audit_events: "CONNECT,QUERY_DDL,QUERY_DML_NO_SELECT"
db_dump_schedule: "*/15 * * * *"
db_dump_path: "/var/backups/mariadb"
nova_databases:
  - name: nova_logistique
    user: app_logistique
  - name: nova_rh
    user: app_rh
hardening_extra_nft_rules:
  - "tcp dport 3306 accept"
```

### Variables Vault (group_vars/databases/vault.yml)

```yaml
vault_mariadb_root_password: "..."
vault_app_logistique_password: "..."
vault_app_rh_password: "..."
vault_backup_nova_password: "..."
```

### Fichier de configuration (50-nova-server.cnf)

```ini
[mysqld]
bind-address            = 192.168.20.12
port                    = 3306
max_connections         = 150
innodb_buffer_pool_size = 256M
log_bin                 = /var/log/mysql/mysql-bin.log
binlog_format           = ROW
expire_logs_days        = 7
server_audit_logging    = ON
server_audit_events     = CONNECT,QUERY_DDL,QUERY_DML_NO_SELECT
server_audit_file_path  = /var/log/mysql/server_audit.log
```

## 5. Validation post-deploiement

### Verifier que MariaDB ecoute sur la bonne IP

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo ss -tlnp | grep 3306"
```

Resultat attendu : `0.0.0.0:3306` ne doit PAS apparaitre. Seul `192.168.20.12:3306`.

### Verifier les bases de donnees

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e 'SHOW DATABASES;'"
```

Resultat attendu : `nova_logistique` et `nova_rh` presentes. `test` absente.

### Verifier les comptes applicatifs

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \"SELECT user, host FROM mysql.user WHERE user LIKE 'app_%';\""
```

### Verifier le plugin server_audit

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \"SHOW PLUGINS;\" | grep -i audit"

# Verifier que les logs d'audit sont ecrits
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo tail -5 /var/log/mysql/server_audit.log"
```

### Verifier le cron de sauvegarde

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo crontab -l | grep mariadb-backup && \
   ls -lh /var/backups/mariadb/ | head -5"
```

### Tester la connexion applicative

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "mysql -u app_logistique -p'${VAULT_APP_LOGISTIQUE_PASS}' \
   -h 192.168.20.12 nova_logistique -e 'SHOW TABLES;'"
```

## 6. Operations courantes

### Creer une nouvelle base de donnees

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \
   \"CREATE DATABASE nova_audit CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\""
```

Puis ajouter l'entree dans `nova_databases` dans `group_vars/databases/vars.yml` et rejouer le role pour creer le compte utilisateur associe.

### Redemarrer MariaDB

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo systemctl restart mariadb && \
   sudo systemctl is-active mariadb"
```

### Lancer un dump manuel

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo /usr/local/bin/mariadb-backup.sh"

# Verifier le resultat
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "ls -lh /var/backups/mariadb/ | tail -5"
```

### Consulter les logs d'audit (server_audit)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo grep 'CONNECT' /var/log/mysql/server_audit.log | tail -20"

# Voir les DDL recents (CREATE, DROP, ALTER)
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo grep 'QUERY_DDL' /var/log/mysql/server_audit.log | tail -10"
```

### Verifier l'etat du binlog

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e 'SHOW MASTER STATUS;'"
```

### Reinitialiser un mot de passe applicatif

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \
   \"ALTER USER 'app_logistique'@'%' IDENTIFIED BY 'NouveauMotDePasse';\""

# Mettre a jour vault_app_logistique_password dans le vault Ansible
```

### Verifier les connexions actives

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e 'SHOW PROCESSLIST;'"
```

## 7. Troubleshooting

### Incident 1 : MariaDB refuse de demarrer

**Symptome :** `systemctl start mariadb` echoue. `systemctl status mariadb` affiche `failed`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo journalctl -u mariadb -n 50 --no-pager"

# Tester la syntaxe de la config
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysqld --user=mysql --help --verbose 2>&1 | grep -E 'ERROR|error' | head -10"
```

**Fix :** La cause la plus frequente est une erreur de syntaxe dans `50-nova-server.cnf`. Verifier la config via `mysql --print-defaults`. Si l'innodb tablespace est corrompu, tenter :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql_upgrade --user=root -p"
```

### Incident 2 : Connexion refusee depuis app01 (192.168.20.13)

**Symptome :** L'application sur app01 retourne `ERROR 1045 (28000): Access denied for user 'app_logistique'@'192.168.20.13'`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \
   \"SELECT user, host FROM mysql.user WHERE user='app_logistique';\""

# Verifier le pare-feu
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo nft list ruleset | grep 3306"
```

**Fix :** Si le compte `app_logistique` est defini avec `host='localhost'` uniquement, corriger en ajoutant le host `%` ou `192.168.20.%` :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \
   \"GRANT ALL ON nova_logistique.* TO 'app_logistique'@'192.168.20.%' \
   IDENTIFIED BY '<PASS>'; FLUSH PRIVILEGES;\""
```

### Incident 3 : Espace disque plein sur /var/backups/mariadb

**Symptome :** Le cron de backup echoue avec `No space left on device`. Les dumps s'accumulent.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "df -h /var/backups/ && \
   ls -lht /var/backups/mariadb/ | head -20"
```

**Fix :**
```bash
# Supprimer les dumps de plus de 2 jours
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo find /var/backups/mariadb/ -name '*.sql.gz' -mtime +2 -delete"

# Modifier le script mariadb-backup.sh pour limiter la retention
# Ajouter en fin de script : find /var/backups/mariadb/ -mtime +1 -delete
```

### Incident 4 : Logs d'audit server_audit vides ou plugin desactive

**Symptome :** `SHOW PLUGINS` ne montre pas `SERVER_AUDIT` comme `ACTIVE`. Les logs `/var/log/mysql/server_audit.log` sont absents ou vides.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \"SHOW VARIABLES LIKE 'server_audit%';\""
```

**Fix :**
```bash
# Activer le plugin en runtime
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \
   \"INSTALL SONAME 'server_audit'; \
   SET GLOBAL server_audit_logging = ON; \
   SET GLOBAL server_audit_events = 'CONNECT,QUERY_DDL,QUERY_DML_NO_SELECT';\""

# S'assurer que le plugin est charge au demarrage (dans 50-nova-server.cnf)
# plugin_load_add = server_audit
```

### Incident 5 : Replication binlog saturee (binlog trop volumineux)

**Symptome :** Le disque /var/log/mysql/ est plein de fichiers `mysql-bin.XXXXXX`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo du -sh /var/log/mysql/ && \
   sudo mysql -e 'SHOW BINARY LOGS;'"
```

**Fix :**
```bash
# Purger les binlogs anterieurs a une date
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e 'PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 3 DAY);'"

# Verifier que expire_logs_days = 7 est bien configure
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e \"SHOW VARIABLES LIKE 'expire_logs_days';\""
```

### Incident 6 : Mot de passe root MariaDB perdu

**Symptome :** Impossible de se connecter avec `mysql -u root`.

**Fix (reinitialisation en mode safe) :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12

sudo systemctl stop mariadb
sudo mysqld_safe --skip-grant-tables --skip-networking &
sudo mysql -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '<NOUVEAU_PASS>';"
sudo kill $(cat /var/run/mysqld/mysqld.pid)
sudo systemctl start mariadb

# Mettre a jour vault_mariadb_root_password dans le vault Ansible
```

## 8. Disaster Recovery

### Contexte DR

db01 heberge les donnees metier critiques (nova_logistique, nova_rh). Sa perte impacte les operations. RTO cible : 2 heures. RPO : 15 minutes (dump toutes les 15 min + binlog).

### Procedure de restauration

**Etape 1 : Provisionner une nouvelle VM db01**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/
terraform apply -target=proxmox_vm_qemu.db01
```

**Etape 2 : Deployer common, hardening, puis database**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  -l databases \
  --tags common,hardening,database \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**Etape 3 : Recuperer le dump le plus recent depuis backup01**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

# Lister les archives Borg contenant les dumps MariaDB
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg list /var/backups/borg/databases

# Extraire le dump le plus recent
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract /var/backups/borg/databases::nova-db-<DATE> \
  var/backups/mariadb/

# Copier vers db01
scp -J debian@192.168.15.2 \
  /var/backups/mariadb/nova_logistique_<TIMESTAMP>.sql.gz \
  debian@192.168.20.12:/tmp/
scp -J debian@192.168.15.2 \
  /var/backups/mariadb/nova_rh_<TIMESTAMP>.sql.gz \
  debian@192.168.20.12:/tmp/
```

**Etape 4 : Restaurer les bases de donnees**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12

sudo gunzip -c /tmp/nova_logistique_<TIMESTAMP>.sql.gz | \
  sudo mysql -u root nova_logistique

sudo gunzip -c /tmp/nova_rh_<TIMESTAMP>.sql.gz | \
  sudo mysql -u root nova_rh
```

**Etape 5 : Appliquer les binlogs depuis le dernier dump (PITR)**

Si des binlogs sont disponibles (sauvegardes avec les dumps) :
```bash
# Extraire les binlogs depuis le dernier dump
sudo mysqlbinlog /var/log/mysql/mysql-bin.* | \
  sudo mysql -u root
```

**Etape 6 : Valider la restoration**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo mysql -e 'SELECT COUNT(*) FROM nova_logistique.commandes LIMIT 1;'"
```

**RTO :** 2 heures (provisioning VM + deploiement + restauration dump + PITR).
**RPO :** 15 minutes (dump cron toutes les 15 minutes).

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
MariaDB ecoute uniquement sur 192.168.20.12 (pas de `0.0.0.0`). Les comptes applicatifs ont des privileges minimaux (SELECT, INSERT, UPDATE, DELETE sur leur base uniquement, pas de GRANT, pas de FILE). Le compte root n'est accessible qu'en local (`root@localhost`). Chiffrement des passwords en vault Ansible.

**Art. 21.2.c -- Gestion des incidents :**
Le plugin `server_audit` enregistre tous les CONNECT, les DDL (CREATE/DROP/ALTER tables) et les DML hors SELECT. Ces logs sont collectes par Wazuh agent sur db01 et centralises sur app01 (192.168.20.13). Alertes configurees sur les DROP TABLE et les connexions hors heures ouvrables.

**Art. 21.2.e -- Continuite d'activite :**
Dumps toutes les 15 minutes + binlog ROW pour PITR. RPO 15 min garanti. Dumps transferes vers backup01 via Borg chiffre repokey-blake2, puis sync cloud VPS Hetzner.

**Art. 21.2.f -- Audit :**
Les logs `server_audit` et les binlogs constituent le trail d'audit des operations sur les donnees. Conservation 90 jours dans Wazuh. Les modifications de schema (DDL) sont traçables jusqu'a l'utilisateur et l'horodatage. Conforme a l'article sur l'auditabilite des traitements de donnees (RGPD Art. 30 connexe).

### RGPD

La base `nova_rh` contient potentiellement des donnees a caractere personnel (salaries). Mesures :
- Acces restreint au compte `app_rh` uniquement (pas d'acces direct pour les developpeurs).
- Chiffrement du transit : forcer SSL sur la connexion app01 -> db01 si non fait.
- Retention limitee : inclure `nova_rh` dans la politique de purge des donnees.

## 10. References

### Internes au projet

- `roles/database/defaults/main.yml` -- variables du role
- `roles/database/templates/50-nova-server.cnf.j2` -- config MariaDB
- `group_vars/databases/vars.yml` -- variables du groupe
- Runbook backup : `docs/runbooks/runbook-backup.md`
- Runbook Wazuh : `docs/runbooks/runbook-wazuh.md`

### Documentation upstream

- MariaDB Knowledge Base : https://mariadb.com/kb/en/
- MariaDB server_audit plugin : https://mariadb.com/kb/en/mariadb-audit-plugin/
- MariaDB binlog : https://mariadb.com/kb/en/binary-log/
- Borg Backup : https://borgbackup.readthedocs.io/
