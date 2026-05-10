# Runbook : backup (Borg Backup + sync cloud)

## 1. Perimetre

Le role `backup` configure backup01 (192.168.50.2, VLAN BACKUP 192.168.50.0/29) en tant que serveur de sauvegarde centralise du parc Nova Syndicate. Il s'appuie sur BorgBackup (repokey-blake2) pour trois depots independants : `configs` (configurations systeme et AD), `databases` (dumps MariaDB), `filesystem` (donnees de partage fs01).

backup01 recoit les donnees des VMs via deux mecanismes distincts : rsync depuis fs01 (donnees de partage) et transfert des dumps MariaDB depuis db01. Borg cree ensuite des archives chiffrees avec compression zstd. Un second niveau de protection (sync cloud) est assure par un tunnel WireGuard vers un VPS Hetzner, avec synchronisation quotidienne a 23h30 via le script `borg-cloud-sync.sh`. L'architecture de sauvegarde complete est : VM source -> rsync/dump -> backup01 local (Borg) -> WireGuard -> VPS Hetzner (Borg append-only).

Ce runbook couvre le deploiement du role `backup`, les operations Borg courantes, et la procedure de restauration depuis les deux niveaux (local et cloud). Pour les details du tunnel WireGuard VPS, voir `docs/runbook-borg-cloud.md` et `docs/runbook-wireguard-vps.md`.

**Note :** Le role Ansible `backup` configure backup01 lui-meme. Les scripts de sauvegarde sur les autres VMs (mariadb-backup.sh sur db01, fs-backup.sh sur fs01) sont deployes par leurs roles respectifs. La synchronisation cloud WireGuard + VPS a ete deployee manuellement (hors role Ansible).

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `backup`.
- Les roles `database` et `fileserver` doivent etre deployes et operationnels (pour que les scripts de sauvegarde source fonctionnent).
- Le tunnel WireGuard vers le VPS Hetzner doit etre actif pour la sync cloud.

### Reseau

- backup01 : IP statique 192.168.50.2/29, gateway 192.168.50.1 (OPNsense VLAN 50).
- Acces SSH entrant depuis bastion01 (192.168.15.2) pour l'administration.
- Acces SSH entrant depuis db01 (192.168.20.12) et fs01 (192.168.20.11) pour rsync.
- Interface WireGuard wg0 : 10.30.0.2/24, pointe vers VPS Hetzner (10.30.0.1).
- Port UDP 51820 sortant pour WireGuard.

### Packages

`borgbackup`, `rsync`, `wireguard-tools` (pour le tunnel cloud)

### Structure des depots Borg sur backup01

```
/var/backups/borg/
  configs/      -- configurations systeme + AD backup
  databases/    -- dumps MariaDB
  filesystem/   -- donnees SMB de fs01
```

### Acces

- SSH via bastion : `ssh -J debian@192.168.15.2 debian@192.168.50.2`

## 3. Installation

### Verification pre-deploiement

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Verifier que backup01 est accessible
ansible backup -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian

# Verifier l'espace disponible sur backup01
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "df -h /var/backups/"
```

### Dry-run

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l backup \
  --tags backup \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l backup \
  --tags backup \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Initialisation des depots Borg (premiere fois uniquement)

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

# Initialiser les trois depots avec chiffrement repokey-blake2
export BORG_PASSPHRASE=$(sudo cat /etc/borg/passphrase)

sudo borg init --encryption=repokey-blake2 \
  /var/backups/borg/configs

sudo borg init --encryption=repokey-blake2 \
  /var/backups/borg/databases

sudo borg init --encryption=repokey-blake2 \
  /var/backups/borg/filesystem

# Exporter et stocker les cles Borg hors backup01
sudo borg key export /var/backups/borg/configs \
  /tmp/borg-key-configs.txt
# Stocker /tmp/borg-key-configs.txt dans un coffre-fort hors ligne
```

## 4. Configuration

### Passphrase Borg

```
/etc/borg/passphrase   -- mode 600, proprietaire root
```

La passphrase est generee aleatoirement et stockee dans le vault Ansible : `vault_borg_passphrase`.

### Crons sur backup01

```
# Sauvegarde filesystem (rsync de from-fs01 + borg)
0 3 * * *   root   /usr/local/bin/backup-filesystem.sh

# Sauvegarde databases (rsync des dumps + borg)
30 2 * * *  root   /usr/local/bin/backup-databases.sh

# Sauvegarde configs (samba AD backup + etc)
0 4 * * *   root   /usr/local/bin/backup-configs.sh

# Sync cloud WireGuard vers VPS Hetzner
30 23 * * * root   /usr/local/bin/borg-cloud-sync.sh
```

### Politique de retention Borg

```
--keep-daily 7
--keep-weekly 4
--keep-monthly 6
```

### Tunnel WireGuard (sync cloud)

```
Interface wg0 : 10.30.0.2/24
Peer (VPS) : endpoint <VPS_IP>:51820
AllowedIPs : 10.30.0.0/24
```

Cle privee WireGuard dans `/etc/wireguard/wg0.conf` (mode 600, root).
Depot Borg remote : `borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/`
Mode append-only sur le VPS : les archives ne peuvent pas etre supprimees par backup01 (protection anti-ransomware).

## 5. Validation post-deploiement

### Verifier les depots Borg

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg list /var/backups/borg/databases"

ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg list /var/backups/borg/filesystem"
```

### Verifier le tunnel WireGuard

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo wg show | grep -E 'interface|latest handshake|transfer'"
```

Le champ `latest handshake` ne doit pas etre superieur a 3 minutes si le tunnel est actif.

### Verifier les crons actifs

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo crontab -l | grep -v '^#'"
```

### Tester un backup manuel

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo /usr/local/bin/backup-databases.sh && \
   sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg list /var/backups/borg/databases | tail -3"
```

### Verifier la sync cloud

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo tail -30 /var/log/borg-cloud-sync.log"
```

## 6. Operations courantes

### Lancer une archive Borg manuelle

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg create \
  --compression zstd \
  --stats \
  /var/backups/borg/databases::nova-db-manual-$(date +%Y%m%d-%H%M) \
  /var/backups/from-db01/
```

### Lister les archives d'un depot

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg list /var/backups/borg/filesystem"
```

### Verifier l'integrite d'un depot

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg check --progress /var/backups/borg/databases"
```

### Lancer la sync cloud manuellement

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo /usr/local/bin/borg-cloud-sync.sh"
```

### Appliquer la retention (pruning)

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg prune \
   --keep-daily 7 \
   --keep-weekly 4 \
   --keep-monthly 6 \
   --stats \
   /var/backups/borg/databases"
```

### Verifier l'espace utilise par les depots

```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo du -sh /var/backups/borg/* && df -h /var/backups/"
```

### Recevoir un dump depuis db01 manuellement

```bash
# Sur backup01 : attendre le rsync depuis db01
# Ou depuis db01, forcer le transfert :
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo rsync -avz /var/backups/mariadb/ \
   debian@192.168.50.2:/var/backups/from-db01/"
```

## 7. Troubleshooting

### Incident 1 : Borg retourne "Repository does not exist"

**Symptome :** `borg list /var/backups/borg/databases` retourne `Repository /var/backups/borg/databases does not exist`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo ls -la /var/backups/borg/"
```

**Fix :** Si le repertoire est vide ou absent, le depot doit etre reinitialise. Recuperer d'abord les donnees depuis le depot cloud (VPS Hetzner) si disponible, puis reinitialiser et restaurer les archives via `borg transfer`. Voir la procedure DR section 8.

### Incident 2 : Le tunnel WireGuard est down, sync cloud echoue

**Symptome :** `wg show` ne montre aucun `latest handshake` recent. Les logs `borg-cloud-sync.log` montrent des erreurs de connexion SSH vers 10.30.0.1.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo wg show wg0 && \
   sudo systemctl status wg-quick@wg0"
```

**Fix :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo systemctl restart wg-quick@wg0 && \
   sudo wg show | grep 'latest handshake'"

# Tester la connectivite vers le VPS
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo ping -c 3 10.30.0.1"
```

Si le VPS est injoignable, verifier l'etat du VPS Hetzner via l'interface web Hetzner Cloud.

### Incident 3 : Passphrase Borg incorrecte ou perdue

**Symptome :** `borg list` retourne `passphrase supplied in BORG_PASSPHRASE is incorrect`.

**Diagnostic :**
```bash
# Verifier la passphrase dans le fichier
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo cat /etc/borg/passphrase | wc -c"
# Doit etre non vide
```

**Fix :** La passphrase est dans le vault Ansible (`vault_borg_passphrase`). Extraire et recrire le fichier :
```bash
ansible-vault view group_vars/backup/vault.yml | grep vault_borg_passphrase
# Corriger /etc/borg/passphrase sur backup01
```

Si la passphrase est definitivement perdue ET qu'aucune cle Borg exportee n'est disponible hors ligne, le depot est irrecuperable. Reinitialiser un nouveau depot et relancer les sauvegardes.

### Incident 4 : Espace disque plein sur backup01

**Symptome :** `df -h /var/backups/` montre 100% d'utilisation. Les nouvelles archives Borg echouent.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo du -sh /var/backups/borg/* && \
   sudo du -sh /var/backups/from-*"
```

**Fix :**
```bash
# Appliquer un pruning agressif sur le depot databases
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg prune --keep-daily 2 --keep-weekly 1 --stats \
   /var/backups/borg/databases"

# Compacter le depot (liberer l'espace effectivement)
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg compact /var/backups/borg/databases"

# Long terme : etendre le disque backup01 via Proxmox
```

### Incident 5 : rsync depuis fs01 echoue (cle SSH absente)

**Symptome :** Le script `backup-filesystem.sh` retourne `Permission denied (publickey)` lors du rsync depuis fs01.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo ssh -v -i /root/.ssh/id_ed25519_fs01 \
   debian@192.168.20.11 'echo OK' 2>&1 | grep -E 'identity|auth'"
```

**Fix :** La cle SSH root de backup01 vers fs01 doit etre deployee :
```bash
# Sur backup01, generer une cle si absente
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_fs01 -N ""

# Autoriser la cle sur fs01
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "echo 'ssh-ed25519 AAAA...<cle_pub_backup01>...' \
   >> /root/.ssh/authorized_keys"
```

### Incident 6 : Archive Borg corrompue (checksum error)

**Symptome :** `borg check /var/backups/borg/filesystem` retourne des erreurs de checksum.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   borg check --progress --verify-data \
   /var/backups/borg/filesystem 2>&1 | grep -E 'ERROR|WARNING'"
```

**Fix :** Si seules quelques archives sont corrompues, les supprimer et relancer une nouvelle archive :
```bash
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg delete /var/backups/borg/filesystem::nova-fs-<DATE_CORROMPUE>
```

Les archives non corrompues restent exploitables pour la restauration.

## 8. Disaster Recovery

### Contexte DR

backup01 est le niveau 1 de protection. En cas de perte complete de backup01, le niveau 2 (VPS Hetzner, mode append-only) est le seul recours pour les donnees. RTO cible : 3 heures. RPO : 24 heures (sauvegardes nocturnes).

### Procedure de restauration niveau 1 (backup01 accessible)

**Restaurer les donnees MariaDB depuis Borg local :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

# Extraire le dump le plus recent du depot databases
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg list /var/backups/borg/databases | tail -5

sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract \
  /var/backups/borg/databases::nova-db-<DATE> \
  var/backups/from-db01/

# Transferer vers db01 pour restauration
rsync -avz /var/backups/from-db01/*.sql.gz \
  debian@192.168.20.12:/tmp/
```

**Restaurer les fichiers de partage depuis Borg local :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract \
  /var/backups/borg/filesystem::nova-fs-<DATE> \
  srv/shares/

rsync -avz /srv/shares/ debian@192.168.20.11:/srv/shares/
```

### Procedure de restauration niveau 2 (depuis le VPS Hetzner)

**Etape 1 : Verifier que le tunnel WireGuard est actif sur backup01**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo wg show && sudo ping -c 2 10.30.0.1"
```

**Etape 2 : Lister les archives disponibles sur le VPS**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   BORG_RSH='ssh -i /root/.ssh/id_ed25519_borg-cloud' \
   borg list borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/"
```

**Etape 3 : Extraire les donnees depuis le VPS**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "sudo BORG_PASSPHRASE=\$(cat /etc/borg/passphrase) \
   BORG_RSH='ssh -i /root/.ssh/id_ed25519_borg-cloud' \
   borg extract \
   borguser@10.30.0.1:/srv/borg-repo/nova-syndicate/::nova-<TYPE>-<DATE> \
   var/backups/"
```

**Etape 4 : Reprovisioner backup01 et reinitialiser les depots**
```bash
# Deployer le role backup sur la nouvelle VM
ansible-playbook -i inventory/hosts.yml site.yml \
  -l backup \
  --tags common,hardening,backup \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass

# Reinitialiser les depots Borg locaux
# Transferer les donnees recuperees du VPS dans les nouveaux depots
```

**RTO :** 3 heures (provisioning + deploiement + restoration depuis cloud).
**RPO :** 24 heures (sync cloud quotidienne a 23h30).

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
Chiffrement Borg repokey-blake2 : les archives sont chiffrees localement avant tout transfert. La passphrase est stockee dans le vault Ansible et dans `/etc/borg/passphrase` (mode 600). Le mode append-only sur le VPS protege contre les ransomwares qui atteindraient backup01.

**Art. 21.2.e -- Continuite d'activite (particulierement pertinent) :**
Double sauvegarde (local + cloud) avec retention 7j/4s/6m garantit la disponibilite des donnees apres incident. Le RPO 24h et le RTO 3h sont documentes et testes lors des exercices DR. L'isolation du VLAN BACKUP (192.168.50.0/29) limite la surface d'attaque sur backup01.

**Art. 21.2.f -- Audit :**
Les logs des scripts de sauvegarde (`/var/log/borg-cloud-sync.log`, journald) sont collectes par Wazuh agent sur backup01. Les operations Borg (create, prune, check) sont tracees.

**Art. 21.2.i -- Chaine d'approvisionnement :**
La cle SSH `id_ed25519_borg-cloud` sur backup01 donne acces au VPS Hetzner. Elle est root-only (mode 600) et ne doit jamais etre copiee sur d'autres machines.

### Cles Borg a stocker hors ligne

Les cles exportees des depots Borg (`borg key export`) doivent etre stockees dans un media physique hors site (cle USB chiffree, gestionnaire de mots de passe offline). Sans ces cles, le chiffrement repokey est irrecuperable.

## 10. References

### Internes au projet

- `roles/backup/defaults/main.yml` -- variables du role
- `docs/runbook-borg-cloud.md` -- details de la sync cloud VPS
- `docs/runbook-wireguard-vps.md` -- tunnel WireGuard VPS Hetzner
- Runbook database : `docs/runbooks/runbook-database.md`
- Runbook fileserver : `docs/runbooks/runbook-fileserver.md`
- Runbook DC : `docs/runbooks/runbook-dc.md`

### Documentation upstream

- BorgBackup documentation : https://borgbackup.readthedocs.io/en/stable/
- Borg key export/import : https://borgbackup.readthedocs.io/en/stable/usage/key.html
- WireGuard documentation : https://www.wireguard.com/quickstart/
- Hetzner Cloud API : https://docs.hetzner.cloud/
