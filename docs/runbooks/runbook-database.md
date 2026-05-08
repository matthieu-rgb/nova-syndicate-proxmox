# Runbook -- Base de donnees (DB1 / MariaDB)

## Perimetre

DB1 (192.168.20.12), MariaDB 10.11.x. Bases : nova_logistique, nova_rh, nova_audit.

## Comptes applicatifs

| Compte | Droits | Base |
|--------|--------|------|
| app_logistique_rw | SELECT, INSERT, UPDATE, DELETE | nova_logistique |
| app_hr_ro | SELECT | nova_rh |
| backup_user | SELECT, RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT, SHOW VIEW, EVENT, TRIGGER, BINLOG MONITOR | *.* |

## Operations courantes

### Connexion locale

```bash
ssh debian@192.168.20.12
sudo mysql -u root
```

### Verifier les bases

```sql
SHOW DATABASES;
```

### Verifier les comptes

```sql
SELECT user, host FROM mysql.user;
SHOW GRANTS FOR 'app_logistique_rw'@'%';
```

### Lancer un dump manuel

```bash
sudo /opt/nova-backup/backup-db.sh
# Resultat dans /var/backups/db-dumps/ sur DB1
# rsync vers BACKUP01:/var/backups/from-db1 automatique (cron 02h00)
```

### Verifier le dernier dump

```bash
ls -lht /var/backups/db-dumps/
# Sur BACKUP01 :
ssh debian@192.168.50.2 "ls -lht /var/backups/from-db1/"
```

### Creer un nouveau compte

```sql
CREATE USER 'nouveau'@'%' IDENTIFIED BY '<password>';
GRANT SELECT ON nova_logistique.* TO 'nouveau'@'%';
FLUSH PRIVILEGES;
```

## Diagnostic

### MariaDB ne demarre pas

```bash
sudo systemctl status mariadb
sudo journalctl -u mariadb -n 50
sudo mysqlcheck --all-databases -u root
```

### Connexion backup_user echoue

```bash
# Tester depuis DB1 :
mysql -u backup_user -p -e "SHOW DATABASES;"
# Verifier fail2ban sur BACKUP01 :
ssh debian@192.168.50.2 "sudo fail2ban-client status sshd"
# Debannir si necessaire :
sudo fail2ban-client set sshd unbanip 192.168.20.12
```

### Rsync dump vers BACKUP01 echoue

```bash
# Verifier cle SSH root DB1 -> BACKUP01
sudo ssh -i /root/.ssh/id_backup debian@192.168.50.2 "echo OK"
# Cle autorisee dans /home/debian/.ssh/authorized_keys sur BACKUP01
```

## Backup

- Script : /opt/nova-backup/backup-db.sh (sur DB1)
- Cron : 02h00 chaque nuit
- Destination locale : /var/backups/db-dumps/
- Destination BACKUP01 : /var/backups/from-db1/ (rsync)
- Borg : /var/backups/borg/databases/ sur BACKUP01 (cron 04h00)
- Playbook Ansible : playbooks/database.yml
