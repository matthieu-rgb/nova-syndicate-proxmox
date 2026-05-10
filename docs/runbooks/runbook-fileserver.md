# Runbook : fileserver (Samba Fileserver AD Member)

## 1. Perimetre

Le role `fileserver` configure fs01 (192.168.20.11, VLAN SERVERS) en tant que serveur de fichiers Samba membre du domaine Active Directory `nova-syndicate.local`. Contrairement a dc01, fs01 n'est pas un controleur de domaine : il est membre du domaine et utilise Kerberos + Winbind pour deleguer l'authentification a dc01 (192.168.20.10). Les partages SMB sont accessibles aux utilisateurs authentifies AD.

Le role deploie : les packages Samba membre (samba, winbind, smbclient, acl, krb5-user), la configuration krb5.conf pointant vers le realm NOVA-SYNDICATE.LOCAL, la jonction au domaine via `net ads join`, la configuration smb.conf avec les partages definis dans `nova_shares`, la creation des repertoires de partage avec les permissions ACL POSIX, et l'activation des services smbd, nmbd, winbind.

Un script de sauvegarde rsync (`/usr/local/bin/fs-backup.sh`) est deploye et planifie en cron pour synchroniser les donnees vers backup01 (192.168.50.2) via le VLAN BACKUP. Ce script constitue le second niveau de sauvegarde (le premier etant Borg sur backup01). Les donnees utilisateurs sur fs01 ont une criticite elevee : leur perte impacte directement les operations metier.

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `fileserver`.
- Le role `dc` doit etre deploye et le domaine `nova-syndicate.local` operationnel avant la jonction de domaine.
- dc01 (192.168.20.10) doit etre accessible depuis fs01 sur les ports AD (TCP 88, 389, 445).

### Reseau

- fs01 : IP statique 192.168.20.11/28, gateway 192.168.20.1.
- DNS resolu par dc01 : 192.168.20.10 (requis pour la jonction AD via `net ads join`).
- Ports ouverts par nftables sur fs01 via `hardening_extra_nft_rules` :
  - TCP 445 (SMB)
  - TCP 139 (NetBIOS session)
  - UDP 137, 138 (NetBIOS name/datagram)
- Acces rsync vers backup01 (192.168.50.2) via VLAN BACKUP sur port SSH 22.

### Packages

`samba`, `smbclient`, `acl`, `rsync`, `winbind`, `krb5-user`

### Acces

- SSH via bastion : `ssh -J debian@192.168.15.2 debian@192.168.20.11`

## 3. Installation

### Verification pre-deploiement

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Verifier que dc01 repond en DNS et Kerberos
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "dig nova-syndicate.local @192.168.20.10 +short && \
   ping -c 2 192.168.20.10"

# Verifier que fs01 n'est pas deja joint au domaine
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo net ads info 2>&1 | head -5"
```

### Dry-run

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers \
  --tags fileserver \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement complet

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers \
  --tags fileserver \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement cible (rejouer smb.conf uniquement)

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers \
  --tags fileserver,config \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes

1. Installation des packages
2. Deploiement de krb5.conf
3. Jonction au domaine : `net ads join -U Administrator`
4. Deploiement smb.conf.j2
5. Creation des repertoires de partage + ACL POSIX
6. Activation smbd, nmbd, winbind
7. Deploiement fs-backup.sh + cron rsync

## 4. Configuration

### Variables principales (group_vars/fileservers/vars.yml)

```yaml
nova_shares:
  - name: "Logistique"
    path: "/srv/shares/logistique"
    valid_users: "@GRP_LOGISTIQUE"
    writable: true
  - name: "RH"
    path: "/srv/shares/rh"
    valid_users: "@GRP_RH"
    writable: true
  - name: "Commun"
    path: "/srv/shares/commun"
    valid_users: "@Domain Users"
    writable: false

fs_backup_schedule: "0 2 * * *"

hardening_extra_nft_rules:
  - "tcp dport 445 accept"
  - "udp dport { 137, 138 } accept"
  - "tcp dport 139 accept"
```

### Variables Vault (group_vars/fileservers/vault.yml)

```yaml
vault_domain_join_password: "..."    # Mot de passe Administrator AD pour la jonction
```

### smb.conf cle (template)

```ini
[global]
   workgroup = NOVA-SYNDICATE
   realm = NOVA-SYNDICATE.LOCAL
   security = ADS
   winbind use default domain = yes
   idmap config * : backend = tdb
   idmap config NOVA-SYNDICATE : backend = rid
   idmap config NOVA-SYNDICATE : range = 10000-20000

[Logistique]
   path = /srv/shares/logistique
   valid users = @GRP_LOGISTIQUE
   writable = yes
   create mask = 0660
   directory mask = 0770
```

## 5. Validation post-deploiement

### Verifier la jonction au domaine

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo net ads info"
```

Resultat attendu : LDAP server, server time, KDC server tous renseignes.

### Verifier Winbind

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo wbinfo -u | head -5 && sudo wbinfo -g | head -5"
```

Doit lister les utilisateurs et groupes AD.

### Verifier les services actifs

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo systemctl is-active smbd nmbd winbind"
```

### Tester l'acces a un partage

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo smbclient //192.168.20.11/Logistique \
   -U 'NOVA-SYNDICATE\jdupont%MotDePasse' \
   -c 'ls'"
```

### Verifier le script de sauvegarde rsync

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo cat /var/log/fs-backup.log | tail -10 && \
   crontab -l | grep fs-backup"
```

## 6. Operations courantes

### Ajouter un nouveau partage Samba

1. Ajouter l'entree dans `nova_shares` dans `group_vars/fileservers/vars.yml`.
2. Rejouer le role avec le tag config :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers \
  --tags fileserver,config \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

### Redemarrer les services Samba

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo systemctl restart smbd nmbd winbind"
```

### Lancer la sauvegarde rsync manuellement

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo /usr/local/bin/fs-backup.sh"

# Verifier le transfert sur backup01
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  "ls -lh /var/backups/from-fs01/ | head -10"
```

### Modifier les permissions d'un partage

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo setfacl -R -m g:GRP_LOGISTIQUE:rwx /srv/shares/logistique && \
   sudo setfacl -Rd -m g:GRP_LOGISTIQUE:rwx /srv/shares/logistique"
```

### Consulter les connexions SMB actives

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo smbstatus --shares"
```

### Verifier l'espace disque des partages

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "df -h /srv/shares/ && du -sh /srv/shares/*"
```

## 7. Troubleshooting

### Incident 1 : La jonction au domaine echoue (net ads join)

**Symptome :** La task `net ads join` retourne `Failed to join domain: failed to lookup DC info for domain 'nova-syndicate.local'`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "dig _kerberos._tcp.nova-syndicate.local SRV @192.168.20.10 && \
   dig _ldap._tcp.nova-syndicate.local SRV @192.168.20.10"

# Verifier que le DNS pointe vers dc01
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "cat /etc/resolv.conf"
```

**Fix :** Verifier que `/etc/resolv.conf` contient `nameserver 192.168.20.10`. Si non, corriger la configuration reseau sur fs01 et relancer la jonction :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers --tags fileserver,domain_join \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

### Incident 2 : Winbind ne resout pas les utilisateurs AD

**Symptome :** `wbinfo -u` retourne `Error looking up domain users` ou une liste vide.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo systemctl status winbind && \
   sudo wbinfo --ping-dc"
```

**Fix :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo systemctl restart winbind && \
   sudo net cache flush && \
   sudo wbinfo -u | head -5"
```

Si le probleme persiste, verifier que dc01 est accessible sur TCP 389 depuis fs01.

### Incident 3 : Acces SMB refuse malgre credentials corrects

**Symptome :** `smbclient //192.168.20.11/Logistique -U jdupont` retourne `NT_STATUS_ACCESS_DENIED`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo smbstatus --verbose && \
   sudo getfacl /srv/shares/logistique"

# Verifier que l'utilisateur est dans le bon groupe AD
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool group listmembers GRP_LOGISTIQUE"
```

**Fix :** Verifier les ACL POSIX sur le repertoire. Corriger avec `setfacl`. Verifier que le groupe AD correspond bien au groupe Samba dans smb.conf (`valid users`).

### Incident 4 : Le cron rsync echoue silencieusement

**Symptome :** Aucun log de sauvegarde recent. Les fichiers sur backup01 ne sont pas a jour.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo cat /var/log/fs-backup.log | tail -20"

# Tester la connectivite SSH vers backup01
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo ssh -i /root/.ssh/id_ed25519_backup \
   debian@192.168.50.2 'echo OK'"
```

**Fix :** Verifier que la cle SSH root vers backup01 est deployee. Si non :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_backup -N ''"
# Copier la cle publique vers backup01 et l'ajouter a authorized_keys
```

### Incident 5 : Partage Samba inaccessible depuis les clients VLAN USERS

**Symptome :** Depuis un poste du VLAN 30, `\\192.168.20.11\Logistique` est inaccessible.

**Diagnostic :**
```bash
# Verifier nftables sur fs01
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo nft list ruleset | grep -E '445|accept'"
```

**Fix :** Le routage inter-VLAN est gere par OPNsense FW-INT-LYON (192.168.20.1). Verifier les regles firewall permettant VLAN 30 -> VLAN 20 sur TCP 445. Si le probleme est nftables sur fs01, verifier que `hardening_extra_nft_rules` inclut bien `tcp dport 445 accept` et rejouer le role hardening.

### Incident 6 : Espace disque plein sur /srv/shares

**Symptome :** Les utilisateurs ne peuvent plus ecrire sur les partages. `df -h` montre /srv/shares a 100%.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo du -sh /srv/shares/* | sort -rh | head -10"
```

**Fix :** Identifier les gros fichiers et contacter les utilisateurs. En urgence, etendre le disque virtuel via Proxmox puis `resize2fs`. Pour le long terme, configurer des quotas Samba dans smb.conf (`disk quota = yes`).

## 8. Disaster Recovery

### Contexte DR

Les donnees sur fs01 (/srv/shares) sont sauvegardees quotidiennement via rsync vers backup01 et archivees via Borg. RTO cible : 4 heures. RPO : 24 heures.

### Procedure de restauration

**Etape 1 : Provisionner une nouvelle VM fs01 dans Proxmox**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/
terraform apply -target=proxmox_vm_qemu.fs01
```

**Etape 2 : Deployer common, hardening, puis fileserver**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers \
  --tags common,hardening,fileserver \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**Etape 3 : Restaurer les donnees depuis backup01**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

# Lister les archives Borg
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg list /var/backups/borg/filesystem

# Extraire les donnees de partage
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract /var/backups/borg/filesystem::nova-fs-<DATE> \
  srv/shares/
```

Ou utiliser le rsync disponible dans `/var/backups/from-fs01/` sur backup01 :
```bash
rsync -avz /var/backups/from-fs01/ \
  debian@192.168.20.11:/srv/shares/
```

**Etape 4 : Verifier les permissions ACL**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo getfacl /srv/shares/logistique && \
   sudo getfacl /srv/shares/rh"
```

Reappliquer les ACL si necessaire via le role Ansible (tag `fileserver,config`).

**Etape 5 : Valider l'acces SMB**

Reprendre les tests de la section 5.

**RTO :** 4 heures (provisioning VM + deploiement + restauration donnees + validation).
**RPO :** 24 heures (rsync nocturne + Borg quotidien).

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
L'authentification AD (Kerberos) remplace les mots de passe locaux Samba. Les partages ont des ACL POSIX strictes limitant l'acces aux groupes AD autorises. L'acces SMB est restreint aux reseaux internes (nftables).

**Art. 21.2.c -- Gestion des incidents :**
Les connexions SMB et les acces aux fichiers sont loggues par Samba (log level 2 minimum) et collectes par Wazuh agent sur fs01. Les alertes de masse de lecture/ecriture (potentiel ransomware) sont configurees dans les regles Wazuh NIS2 custom.

**Art. 21.2.e -- Continuite d'activite :**
Double sauvegarde : rsync nocturne vers backup01 + Borg chiffre. RPO 24h garanti. Les donnees de partage sont critiques pour la continuite operationnelle.

**Art. 21.2.f -- Audit :**
Les logs Samba (acces aux fichiers, authentifications) sont conserves 90 jours sur app01 via Wazuh. Les operations d'administration (jonction au domaine, modification smb.conf) sont traçables via auditd.

### Points d'audit

- Verifier regulierement que les groupes AD `valid users` dans smb.conf sont corrects (rotation d'effectifs).
- Controler les ACL des repertoires apres chaque modification manuelle (drift de configuration).
- S'assurer que les partages n'exposent pas de donnees hors perimetre.

## 10. References

### Internes au projet

- `roles/fileserver/defaults/main.yml` -- packages et variables
- `roles/fileserver/tasks/` -- tasks de jonction et configuration
- `group_vars/fileservers/vars.yml` -- configuration partages
- Runbook DC : `docs/runbooks/runbook-dc.md`
- Runbook backup : `docs/runbooks/runbook-backup.md`

### Documentation upstream

- Samba Wiki Domain Member : https://wiki.samba.org/index.php/Setting_up_Samba_as_a_Domain_Member
- Winbind configuration : https://wiki.samba.org/index.php/Configuring_Winbindd_on_a_Samba_AD_DC
- rsync man page : https://download.samba.org/pub/rsync/rsync.1
