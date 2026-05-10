# Runbook Borg Cloud Backup

## Architecture

```
BACKUP01 (10.30.0.2 via wg0)
  --> SSH borguser@10.30.0.1:22 (WireGuard uniquement)
  --> /srv/borg-repo/nova-syndicate/ sur VPS
```

Encryption : repokey-blake2
Passphrase : /etc/borg/passphrase (600 root) sur BACKUP01
Cle SSH : /root/.ssh/id_ed25519_borg-cloud (root sur BACKUP01)
Mode : append-only (les archives ne peuvent pas etre supprimees par le client)

## Prerequis

WireGuard tunnel UP sur BACKUP01 :
```bash
sudo wg show | grep "latest handshake"
```

## Backup quotidien automatique

Cron actif sur BACKUP01 : `/etc/cron.d/borg-cloud-backup`
Schedule : **23h30 daily**
Script : `/usr/local/bin/borg-cloud-sync.sh`

Sources : `/var/backups/borg`, `/var/backups/from-db1`, `/etc`
Retention : 7 jours / 4 semaines / 6 mois
Compression : zstd

Lire les logs :
```bash
sudo tail -50 /var/log/borg-cloud-sync.log
# ou via syslog
sudo journalctl -t borg-cloud-sync --since today
```

Tester manuellement (dry-run, aucune modification) :
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2
sudo /usr/local/bin/borg-cloud-sync.sh --dry-run
```

Lancer un backup immediat :
```bash
sudo /usr/local/bin/borg-cloud-sync.sh
```

Changer la retention (editer le script) :
```bash
sudo nano /usr/local/bin/borg-cloud-sync.sh
# Modifier les valeurs --keep-daily / --keep-weekly / --keep-monthly
# dans la section "Pruning"
```

Desactiver temporairement le cron :
```bash
sudo rm /etc/cron.d/borg-cloud-backup
sudo systemctl restart cron
# Reinstaller : recréer le fichier depuis T-CLOUD-BACKUP-DEPLOY-LOG.md
```

## Backup manuel

```bash
# Sur BACKUP01 (en root)
sudo bash
export BORG_PASSPHRASE=$(cat /etc/borg/passphrase)
export BORG_RSH="ssh -i /root/.ssh/id_ed25519_borg-cloud"
REPO="borguser@10.30.0.1:/srv/borg-repo/nova-syndicate"
DATE=$(date +%Y-%m-%d-%H%M)

# Backup /srv/borgdata (exemple, adapter au besoin)
borg create --stats --compression zstd \
    ${REPO}::backup-${DATE} \
    /srv/borgdata \
    --exclude-caches

# Ou backup /etc de BACKUP01
borg create --stats --compression zstd \
    ${REPO}::backup01-etc-${DATE} \
    /etc
```

## Lister les archives

```bash
sudo bash
export BORG_PASSPHRASE=$(cat /etc/borg/passphrase)
export BORG_RSH="ssh -i /root/.ssh/id_ed25519_borg-cloud"
borg list borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/
```

## Tester un restore

```bash
sudo bash
export BORG_PASSPHRASE=$(cat /etc/borg/passphrase)
export BORG_RSH="ssh -i /root/.ssh/id_ed25519_borg-cloud"
REPO="borguser@10.30.0.1:/srv/borg-repo/nova-syndicate"

# Lister les fichiers d'une archive
borg list ${REPO}::NOM_ARCHIVE

# Extraire un fichier dans /tmp/borg-restore/
mkdir -p /tmp/borg-restore
cd /tmp/borg-restore
borg extract ${REPO}::NOM_ARCHIVE etc/hostname

# Verifier le contenu
ls /tmp/borg-restore/
```

## Verifier l'integrite du repo

```bash
sudo bash
export BORG_PASSPHRASE=$(cat /etc/borg/passphrase)
export BORG_RSH="ssh -i /root/.ssh/id_ed25519_borg-cloud"
borg check borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/
```

## Prune (si quota depasse)

Append-only mode = les clients NE PEUVENT PAS supprimer d'archives.
Pour pruner, se connecter en root sur le VPS et utiliser borg directement :

```bash
# Sur VPS Hetzner en root
export BORG_PASSPHRASE="<passphrase>"
borg prune --list --keep-daily=7 --keep-weekly=4 --keep-monthly=3 \
    /srv/borg-repo/nova-syndicate/

# Apres prune, compacter pour liberer l'espace disque
borg compact /srv/borg-repo/nova-syndicate/
```

## Exporter la cle Borg (a faire une fois, sauvegarder hors repo)

```bash
# Sur BACKUP01
sudo bash
export BORG_PASSPHRASE=$(cat /etc/borg/passphrase)
export BORG_RSH="ssh -i /root/.ssh/id_ed25519_borg-cloud"
borg key export borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/ /tmp/borg-key-export.txt
cat /tmp/borg-key-export.txt
# -> stocker dans password manager avec la passphrase
rm /tmp/borg-key-export.txt
```

## Changer la passphrase

```bash
# Sur BACKUP01
sudo bash
export BORG_PASSPHRASE=$(cat /etc/borg/passphrase)
export BORG_RSH="ssh -i /root/.ssh/id_ed25519_borg-cloud"
borg key change-passphrase borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/
# Saisir ancienne passphrase, puis nouvelle x2
# Mettre a jour /etc/borg/passphrase avec la nouvelle
```

## Monitoring quota

Script cron sur VPS : `/usr/local/bin/borg-disk-monitor.sh` (23h00 daily)
Alerte dans syslog si usage > 15 GB :
```bash
grep borg-monitor /var/log/syslog
```

## DR -- Si tunnel WireGuard down

```bash
# Relancer wg0 sur BACKUP01
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
    "sudo systemctl restart wg-quick@wg0 && sudo wg show"

# Verifier handshake VPS
ssh root@100.94.199.97 "wg show | grep handshake"
```

## DR -- Si VPS inaccessible

Acces via console Hetzner Cloud (navigateur).
Repo Borg toujours dans /srv/borg-repo/nova-syndicate/ sur /dev/sda1.
La cle repokey est dans le repo -- elle survit a un rebuild du VPS
si /srv/ est preserve (ou depuis backup).

## Dette technique

- T-TAILSCALE-SSH-HARDEN : borguser accessible via Tailscale SSH daemon
  (bypasse ForceCommand sshd). Fix : exclure borguser des ACL Tailscale.
- T-VAULT-INTEGRATE : migrer /etc/borg/passphrase vers Ansible vault.
- T-BORG-KEY-EXPORT : exporter la cle repo et stocker hors systeme.
