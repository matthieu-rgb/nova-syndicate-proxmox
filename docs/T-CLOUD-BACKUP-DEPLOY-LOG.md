# T-CLOUD-BACKUP-DEPLOY -- Log de deploiement
# Date : 2026-05-10

## Objectif

Deployer le script de backup cloud production sur BACKUP01, avec cron quotidien
23h30 et retention 7d/4w/6m. Prerequis : T-CLOUD-BACKUP-PREP termine (tunnel WG UP,
repo Borg initialise sur VPS).

## Architecture deployee

```
BACKUP01 (192.168.50.2)
  /usr/local/bin/borg-cloud-sync.sh   (script production, 750 root:root)
  /etc/cron.d/borg-cloud-backup       (cron 23h30 daily, 644 root:root)
  /var/log/borg-cloud-sync.log        (logs applicatifs)
  /etc/borg/passphrase                (existant, 600 root)
```

## Sources sauvegardees

| Chemin | Contenu | Taille approx. |
|--------|---------|----------------|
| /var/backups/borg | Archives Borg locales | 6.4 MB |
| /var/backups/from-db1 | Dumps SQL DB1 | 6.1 MB |
| /etc | Configs BACKUP01 (inclut /etc/borg) | 5.6 MB |

Total : ~18 MB. Compresse zstd -> ~13 MB. Deduplication active.

## Exclusions

```
/var/backups/dpkg.*
/var/backups/alternatives.tar.*
/var/log
/var/cache
/var/tmp
```

## Retention configuree

```
--keep-daily 7
--keep-weekly 4
--keep-monthly 6
```

## Cron schedule

```
30 23 * * *   root   /usr/local/bin/borg-cloud-sync.sh
```

Execution apres les backups Borg locaux (supposes termines avant 23h30).

## Fonctionnalites du script

- Mode `--dry-run` : test sans ecriture (prune skippee)
- Lock file `/var/run/borg-cloud-sync.lock` : pas d'execution parallele
- Trap EXIT/INT/TERM : nettoyage lock garanti
- Test connectivite repo avant create
- Logging double : syslog (logger) + /var/log/borg-cloud-sync.log
- Prune + compact integres (liberation espace apres chaque backup)

## Etat du repo apres deploiement

Archives presentes apres le premier backup production :
```
test-2026-05-10-1740     Sun, 2026-05-10 17:40:30   (archive de test)
backup01-2026-05-10-2110 Sun, 2026-05-10 21:10:44   (premier backup prod)
```

Stats repo :
- Original : 14.92 MB / Compresse : 13.32 MB / Deduplique : 13.38 MB
- 802 chunks uniques / 832 total

## Procedure d'execution manuelle

```bash
# Dry-run (test sans modification)
ssh -J debian@192.168.15.2 debian@192.168.50.2
sudo /usr/local/bin/borg-cloud-sync.sh --dry-run

# Backup reel
sudo /usr/local/bin/borg-cloud-sync.sh

# Suivre les logs en temps reel
sudo tail -f /var/log/borg-cloud-sync.log
```

## Procedure de rollback

Pour desactiver le cron sans supprimer le script :
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2
sudo rm /etc/cron.d/borg-cloud-backup
sudo systemctl restart cron
```

Pour rollback complet :
```bash
sudo rm /etc/cron.d/borg-cloud-backup
sudo rm /usr/local/bin/borg-cloud-sync.sh
sudo systemctl restart cron
```

Note : les archives deja poussees sur le VPS restent. Pour les supprimer,
se connecter en root sur le VPS et utiliser `borg delete`.

## Prochaine etape

T-RESTORE-DRILL : valider la procedure de restore depuis le VPS.
