# Runbook -- Sauvegarde (BorgBackup + rclone)

## Perimetre

BACKUP01 (192.168.50.2). BorgBackup repokey. Trois repos independants.

## Architecture

```
DB1 (/opt/nova-backup/backup-db.sh, cron 02h00)
  -> dump /var/backups/db-dumps/
  -> rsync -> BACKUP01:/var/backups/from-db1/

BACKUP01 crons :
  03h00 : backup-fs.sh   -- rsync FS1:/srv/samba/ -> borg/filesystem
  04h00 : backup-db-borg.sh -- borg/databases (depuis from-db1)
  05h00 : backup-configs.sh -- rsync /etc 5 hotes -> borg/configs
  06h00 : sync-cloud.sh  -- borg -> B2/Wasabi (DESACTIVE -- creds TODO)
```

## Repos Borg

| Repo | Chemin | Passphrase vault |
|------|--------|-----------------|
| filesystem | /var/backups/borg/filesystem | vault_borg_passphrase_filesystem |
| databases | /var/backups/borg/databases | vault_borg_passphrase_databases |
| configs | /var/backups/borg/configs | vault_borg_passphrase_configs |

## Operations courantes

### Lister les archives

```bash
ssh debian@192.168.50.2
export BORG_PASSPHRASE="<passphrase>"
sudo borg list /var/backups/borg/filesystem
sudo borg list /var/backups/borg/databases
sudo borg list /var/backups/borg/configs
```

Passphrases dans le vault :
```bash
ansible-vault view inventory/group_vars/all/vault.yml --vault-password-file ~/.ansible/nova_vault_pass | grep borg
```

### Restaurer un fichier depuis une archive

```bash
export BORG_PASSPHRASE="<passphrase>"
sudo borg extract /var/backups/borg/filesystem::<archive> <chemin/relatif>
```

### Lancer un backup manuel

```bash
ssh debian@192.168.50.2
sudo /opt/nova-backup/backup-fs.sh
sudo /opt/nova-backup/backup-db-borg.sh
sudo /opt/nova-backup/backup-configs.sh
```

### Verifier integrite d'un repo

```bash
export BORG_PASSPHRASE="<passphrase>"
sudo borg check --verbose /var/backups/borg/filesystem
```

### Activer la sync cloud (B2/Wasabi)

1. Completer /etc/rclone/rclone.conf avec les creds
2. Tester : `sudo rclone --config /etc/rclone/rclone.conf ls b2-nova:`
3. Activer le cron :

```bash
sudo crontab -e
# Remplacer : 0 6 * * * /opt/nova-backup/sync-cloud.sh >> /var/log/nova-sync-cloud.log 2>&1
```

Ou via Ansible : modifier rclone-setup.yml, passer `state: present` sur le cron.

## Diagnostic

### Archive corrompue

```bash
export BORG_PASSPHRASE="<passphrase>"
sudo borg check --repair /var/backups/borg/<repo>
```

### Espace disque BACKUP01

```bash
ssh debian@192.168.50.2 "df -h /var/backups"
sudo du -sh /var/backups/borg/*
```

### Rsync DB1 -> BACKUP01 echoue

```bash
# Verifier SSH depuis DB1 :
sudo ssh -i /root/.ssh/id_backup -o StrictHostKeyChecking=no debian@192.168.50.2 "echo OK"
# Verifier fail2ban sur BACKUP01 :
sudo fail2ban-client status sshd
```

## Retention

7 daily / 4 weekly / 12 monthly / 10 yearly (toutes les politiques).

## Fichiers importants

- Scripts : /opt/nova-backup/ (backup-fs.sh, backup-db-borg.sh, backup-configs.sh, sync-cloud.sh)
- Config rclone : /etc/rclone/rclone.conf
- Logs : /var/log/nova-backup-*.log, /var/log/nova-sync-cloud.log
- Playbooks Ansible : playbooks/borgbackup.yml, playbooks/rclone-setup.yml
