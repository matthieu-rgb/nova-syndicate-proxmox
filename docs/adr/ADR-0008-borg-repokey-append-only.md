# ADR-0008 : BorgBackup avec chiffrement repokey-blake2 et mode append-only

## Status
Accepted

## Date
2026-05-10

## Contexte

Nova Syndicate requiert une solution de sauvegarde pour les donnees critiques : Active Directory (dc01), partages Samba (fs01), base de donnees MariaDB (db01), configuration Wazuh (app01). La solution doit satisfaire plusieurs criteres qui ne sont pas independants :

**Chiffrement** : les archives de sauvegarde contiennent des donnees sensibles (hashes NTLM de l'AD, donnees de la base de donnees, logs SIEM). Le chiffrement au repos est obligatoire, a la fois pour la copie locale et pour la copie distante (VPS Hetzner). Le chiffrement doit etre cote client : les donnees doivent etre chiffrees avant d'etre transmises vers le VPS, de sorte que le fournisseur (Hetzner) n'ait jamais acces au plaintext.

**Immutabilite contre le ransomware** : un scenario de ransomware sur `backup01` (le noeud qui initie les sauvegardes) ne doit pas permettre la destruction des archives sur le serveur de depot distant. Le client ne doit pas avoir la capacite de supprimer les archives sur le serveur, seulement d'en ecrire de nouvelles.

**Deduplication** : les sauvegardes quotidiennes de fichiers similaires (DC01 SYSVOL, Samba shares avec peu de modifications) doivent etre efficaces en espace disque. La deduplication est preferable a la compression seule.

**Compression** : les archives de logs (Wazuh) et les fichiers de base de donnees sont compressibles. La compression reduit le volume de donnees transferees vers le VPS, donc les couts (VPS facture selon le trafic sortant chez certains hebergeurs) et les temps de transfert.

**Contexte NIS2** : l'Article 21 de la directive NIS2 exige des mesures de securite proportionnees pour la continuite des activites, incluant la protection des sauvegardes contre les attaques. Le mode append-only satisfait partiellement cette exigence en rendant les archives resistantes a la suppression par un acteur mal intentionne ayant compromis le client de sauvegarde.

## Decision

Adoption de **BorgBackup** (version 1.2+) avec les parametres suivants :

**Mode de chiffrement : `repokey-blake2`**

Le mode `repokey-blake2` signifie :
- `repokey` : la cle de chiffrement est stockee dans le depot (dans la structure de metadonnees de l'archive Borg), chiffree par la passphrase. Cela permet d'acceder au depot avec la passphrase seule, sans fichier de cle externe.
- `blake2` : utilisation de BLAKE2b (BLAKE2b-256) comme fonction de hachage pour la verification d'integrite des chunks, en remplacement de SHA-256 (utilise dans le mode `repokey` simple). BLAKE2b est significativement plus rapide que SHA-256 sur les architectures modernes sans instruction SHA-NI, et equivalent en securite.

La cle de chiffrement symetrique elle-meme utilise AES-256-CTR pour le chiffrement des chunks, avec HMAC-SHA256 pour l'integrite (dans les versions Borg <= 1.2). Borg 2.0 utilise AES-256-OCB ou BLAKE2b-based MAC.

La passphrase est stockee dans Ansible Vault (`ansible/group_vars/backup/vault.yml`) et injectee via la variable d'environnement `BORG_PASSPHRASE` dans les scripts systemd (droits 600).

**Mode append-only sur le serveur Borg**

Le mode append-only est configure sur le serveur (VPS Hetzner) dans le fichier `authorized_keys` du compte `borg` :

```
command="borg serve --append-only --restrict-to-path /var/backup/nova-syndicate",restrict ssh-rsa AAAA...
```

L'option `--append-only` interdit au client d'executer les operations de suppression (`borg delete`, `borg prune`) sur le depot. Le client peut uniquement creer de nouvelles archives (`borg create`) et lire les archives existantes (`borg extract`, `borg list`). La suppression des anciennes archives (pruning) doit etre executee en se connectant directement sur le VPS avec un compte distinct (protection par mot de passe fort, pas de cle SSH depuis backup01).

**Compression : zstd**

La compression `zstd` (Zstandard, niveau 3 par defaut dans les scripts) offre un bon ratio compression/CPU. Les benchmarks Borg montrent que `zstd,3` est superieur a `lz4` (vitesse comparable, meilleur ratio) et superieur a `zlib,6` (meme ratio, plus rapide). Pour les logs Wazuh et les fichiers de configuration, le ratio de compression typique est de 3:1 a 5:1.

**Structure des depots Borg** :

```
/var/backup/nova-syndicate/
  dc01/       -- Active Directory (SYSVOL, ntds.dit, cles de registre)
  fs01/       -- Partages Samba (/srv/samba/shares/)
  db01/       -- Dumps MariaDB (mysqldump)
  app01/      -- Configuration Wazuh (/var/ossec/etc/, /var/ossec/rules/)
```

Chaque noeud a son propre depot pour permettre un acces granulaire et une restauration independante.

## Alternatives considerees

### Restic

**Pour** :
- Restic est ecrit en Go, multiplateforme, client unique sans daemon serveur.
- Supporte nativement de nombreux backends : local, SFTP, S3, B2, Azure, Google Cloud, etc. Sans WireGuard, Restic peut ecrire directement sur S3 ou Backblaze B2.
- La gestion des cles est via un fichier de mot de passe, similaire a Borg.
- Restic 0.16+ supporte le mode "cold storage" (pack files) qui reduit le nombre d'IOPS sur les backends objet.

**Contre** :
- Restic ne supporte pas le mode append-only via SSH. La protection contre la suppression par un client compromis necessite une solution au niveau du backend (ex : Backblaze B2 Object Lock, S3 Object Lock). Cela implique un cout supplementaire et une dependance a un service cloud specifique.
- La deduplication de Restic est par contenu (content-defined chunking), similaire a Borg, mais Borg est generalement considere plus performant pour les gros volumes de fichiers sur filesystem POSIX.
- Restic ne stocke pas la cle dans le depot (pas de mode `repokey`). La cle (mot de passe) est separee du depot, ce qui peut creer des problemes de recuperation si le fichier de configuration est perdu.
- Dans le contexte de Nova Syndicate ou le depot est sur un VPS accessible via WireGuard, le mode append-only SSH de Borg est la solution la plus elegante sans cout supplementaire.

### Duplicati

**Pour** :
- Interface web pour la gestion des sauvegardes.
- Supporte de nombreux backends cloud.
- Chiffrement AES-256.

**Contre** :
- Duplicati a une reputation mitigee en termes de fiabilite (corruptions de bases de donnees SQLite, problemes de reprises apres interruption).
- Pas de mode append-only natif.
- Interface web = surface d'attaque supplementaire.
- Deduplication moins efficace que Borg sur les grands ensembles de fichiers.
- Pas d'outil de verification d'integrite aussi robuste que `borg check`.

### rsync seul (sans chiffrement ni deduplication)

**Pour** :
- Extreme simplicite : un seul binaire, disponible sur toutes les distributions Linux.
- Performance excellente pour la synchronisation incrementale de fichiers.
- Facile a scripter et a monitorer.

**Contre** :
- Pas de chiffrement natif (sauf si combine avec SSH, qui chiffre le transport mais pas les donnees au repos sur le serveur).
- Sur le serveur de destination, les fichiers sont en clair. Hetzner (ou tout attaquant ayant acces au VPS) peut lire les sauvegardes.
- Pas de deduplication : chaque sauvegarde est une copie complete ou incrementale des fichiers modifies, sans gestion intelligente des blocs.
- Pas de mode append-only : `rsync --delete` supprime les fichiers sur la destination. Un ransomware sur le client peut effacer les sauvegardes.
- Pas de verification d'integrite des archives.

### Bacula / Bareos

**Pour** :
- Solutions enterprise utilisees en production.
- Gestion centralisee de multiples clients et serveurs.
- Support des bandes magnetiques.

**Contre** :
- Architecture complexe : Director, Storage Daemon, File Daemon -- trois composants a configurer et maintenir.
- Surdimensionne pour un lab de 7 VMs.
- Courbe d'apprentissage elevee sans apport direct pour le portfolio securite (Bacula/Bareos sont des outils de production, pas des sujets d'examen AIS).
- Pas de mode append-only natif equivalent.

## Consequences

**Positives :**
- Le chiffrement `repokey-blake2` garantit que les donnees sur le VPS Hetzner sont inaccessibles sans la passphrase, meme en cas d'acces physique ou logique au serveur par Hetzner ou un attaquant.
- Le mode append-only sur le serveur limite le rayon d'action d'un ransomware qui compromet `backup01` : il ne peut pas effacer les archives existantes, seulement en creer de nouvelles (potentiellement chiffrees avec sa propre cle, mais les archives legitimes restent intactes).
- `borg check` permet de verifier l'integrite cryptographique des archives sans les extraire. Cette capacite est utilisee dans le drill de restauration (T-RESTORE-DRILL).
- La deduplication de Borg (content-defined chunking avec SHA-256/BLAKE2) reduit significativement l'espace occupe pour les sauvegardes quotidiennes de machines similaires.
- La compression `zstd` reduit le volume transfere via WireGuard vers le VPS, important pour les sauvegardes de logs volumineux.

**Negatives et risques residuels :**
- **La passphrase est le secret critique** : si la passphrase Borg est perdue, les archives sont definitvement inaccessibles. La passphrase est dans Ansible Vault, dont le mot de passe de vault doit etre conserve separement et en securite (gestionnaire de mots de passe externe). Perte du vault password = perte des archives.
- **Mode append-only = pruning manuel** : la suppression des archives trop anciennes doit etre effectuee manuellement en se connectant au VPS avec un compte administrateur distinct (pas de cle SSH depuis backup01). Si le pruning n'est pas effectue regulierement, le disque du VPS (40 GB pour CX22) peut se saturer.
- **Pas de chiffrement des metadonnees dans les modes repokey** : Borg chiffre les chunks de donnees, mais certaines metadonnees (taille des archives, timestamps, noms des fichiers dans les modes anciens) peuvent etre partiellement lisibles sur le serveur. Borg 2.0 adresse ce point. Version 1.2 retenue pour stabilite.
- **Performance borg check** : la verification d'integrite complete d'un depot volumineux (`borg check --verify-data`) est CPU et I/O intensive. Sur le VPS CX22 (2 vCPU), une verification complete prend du temps et doit etre planifiee hors des heures de sauvegarde.

## References

- Documentation BorgBackup : https://borgbackup.readthedocs.io/
- BorgBackup modes de chiffrement : https://borgbackup.readthedocs.io/en/stable/usage/init.html
- Mode append-only documentation : https://borgbackup.readthedocs.io/en/stable/usage/serve.html
- Scripts de sauvegarde : `ansible/roles/borg_client/templates/`
- Log deploiement backup cloud : `docs/T-CLOUD-BACKUP-DEPLOY-LOG.md`
- Log drill restauration : `docs/T-RESTORE-DRILL-LOG.md`
- ADR-0009 (strategie 3-2-1-1-0) : `docs/adr/ADR-0009-strategie-backup-3-2-1-1-0.md`
- ADR-0010 (VPS Hetzner) : `docs/adr/ADR-0010-vps-hetzner-hors-site.md`
