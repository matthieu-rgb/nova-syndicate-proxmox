# Runbook : hardening

## 1. Perimetre

Le role `hardening` applique le durcissement systeme a l'ensemble des VMs Nova Syndicate, apres le role `common`. Il est le garant de la posture de securite operationnelle du parc : configuration avancee de sshd, pare-feu nftables par VM, fail2ban pour la protection brute-force, auditd pour la traçabilite des evenements kernel, et unattended-upgrades pour les correctifs de securite automatiques.

Ce role est deliberement separe de `common` pour permettre de redeployer les regles pare-feu ou la configuration fail2ban de facon isolee, sans risquer de rejouer les packages ou la config NTP. Les regles nftables sont generees a partir de templates Jinja2 avec des variables par groupe, ce qui permet d'ouvrir uniquement les ports requis par le service metier de chaque VM.

Les machines ciblees sont identiques a celles du role `common` : dc01 (192.168.20.10), fs01 (192.168.20.11), db01 (192.168.20.12), app01 (192.168.20.13), bastion01 (192.168.15.2), backup01 (192.168.50.2), proxy-lyon01 (192.168.20.14), web01 (172.16.1.2), mail01 (172.16.1.3). Chaque VM dispose d'une configuration nftables adaptee a son role via `hardening_extra_nft_rules`.

## 2. Prerequis

### Dependances de roles

- Le role `common` doit etre execute avant `hardening` (packages de base, configuration SSH initiale).
- `hardening` doit etre execute avant tous les roles metier (`dc`, `fileserver`, `database`, etc.).

### Acces reseau

- SSH accessible depuis le bastion 192.168.15.2 avant deploiement.
- Attention critique : si nftables est mal configure, la VM peut devenir inaccessible par SSH. Toujours avoir un acces console Proxmox disponible avant d'appliquer ce role.
- Les reseaux autorises pour SSH sont configures via `hardening_allowed_ssh_nets`.

### Packages

- `nftables` doit etre installable depuis les miroirs apt.
- `fail2ban` depend de `python3` (installe par `common`).
- `auditd` est un package standard Debian.

### Verifications pre-deploiement

```bash
# Verifier l'acces console Proxmox disponible (securite)
# Verifier que common est deja deploye
ansible all -i inventory/hosts.yml -m command \
  -a "systemctl is-active chrony" \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

## 3. Installation

### Dry-run obligatoire avant tout deploiement

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  --tags hardening \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

Inspecter soigneusement le diff des regles nftables avant de valider.

### Deploiement sur tout le parc

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags hardening \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement cible (recommande pour les premiers deploiements)

```bash
# Sur dc01 uniquement
ansible-playbook -i inventory/hosts.yml site.yml \
  -l dc01 \
  --tags hardening \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass

# Sur le groupe databases
ansible-playbook -i inventory/hosts.yml site.yml \
  -l databases \
  --tags hardening \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes

1. `tasks/ssh.yml` -- sshd_config durci
2. `tasks/firewall.yml` -- regles nftables deployees
3. `tasks/fail2ban.yml` -- installation + configuration fail2ban
4. `tasks/auditd.yml` -- auditd avec regles CIS/NIS2
5. `tasks/updates.yml` -- unattended-upgrades configure
6. `tasks/sysctl.yml` -- sysctl complementaires de securite

## 4. Configuration

### Variables par defaut (defaults/main.yml)

```yaml
hardening_extra_nft_rules: []
hardening_allowed_ssh_nets:
  - "192.168.10.0/24"
  - "192.168.15.0/24"
  - "192.168.18.0/24"
  - "192.168.20.0/28"
hardening_auditd_log_size: 100
hardening_auditd_num_logs: 12
monitoring_scrapers: []
```

### Surcharge par groupe

**domain_controllers (dc01) -- group_vars/domain_controllers/vars.yml :**
```yaml
hardening_extra_nft_rules:
  - "tcp dport { 53, 88, 135, 139, 389, 445, 464, 636, 3268, 3269 } accept"
  - "udp dport { 53, 67, 68, 88, 123, 137, 138, 389, 464 } accept"
```

**databases (db01) -- group_vars/databases/vars.yml :**
```yaml
hardening_extra_nft_rules:
  - "tcp dport 3306 accept"
```

**bastions (bastion01) -- group_vars/bastions/vars.yml :**
```yaml
hardening_extra_nft_rules:
  - "tcp dport 443 accept"
  - "tcp dport 3023 accept"
  - "tcp dport 3024 accept"
  - "tcp dport 3025 accept"
```

**fileservers (fs01) -- group_vars/fileservers/vars.yml :**
```yaml
hardening_extra_nft_rules:
  - "tcp dport 445 accept"
  - "udp dport { 137, 138 } accept"
  - "tcp dport 139 accept"
```

### fail2ban

Configuration deployee via template :
```ini
[DEFAULT]
maxretry = 5
bantime  = 3600
findtime = 600
ignoreip = 127.0.0.1/8 192.168.15.0/29

[sshd]
enabled = true
port    = 22
logpath = %(sshd_log)s
```

### auditd

Taille maximale des logs : `hardening_auditd_log_size` MB par fichier, `hardening_auditd_num_logs` fichiers en rotation.
Regles auditd deployees : surveillance des appels syscall sensibles (execve, open, chmod, chown), modifications /etc/passwd, /etc/sudoers, /etc/ssh/sshd_config.

## 5. Validation post-deploiement

### Verifier nftables actif

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo nft list ruleset | head -40"
```

### Verifier que les ports attendus sont ouverts

```bash
# Sur db01 : seul 3306 doit etre ouvert en plus de SSH
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo nft list ruleset | grep -E 'dport|accept'"

# Tester depuis la machine de controle via bastion (SSH tunnel)
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "ss -tlnp | grep -E '3306|22'"
```

### Verifier fail2ban

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo fail2ban-client status sshd"
```

Resultat attendu : `Currently banned: 0` (en fonctionnement normal), jail sshd active.

### Verifier auditd

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo systemctl is-active auditd && sudo auditctl -l | head -10"
```

### Verifier unattended-upgrades

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo unattended-upgrades --dry-run -d 2>&1 | tail -5"
```

### Test de rejet SSH depuis un reseau non autorise

Depuis une machine hors des reseaux `hardening_allowed_ssh_nets`, tenter une connexion SSH. Elle doit etre rejetee sans message (DROP, pas REJECT) par nftables.

## 6. Operations courantes

### Recharger nftables apres modification des regles

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l db01 \
  --tags hardening,firewall \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian

# En manuel si necessaire
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo systemctl reload nftables"
```

### Debloquer une IP bannie par fail2ban

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo fail2ban-client set sshd unbanip 192.168.30.55"
```

### Consulter les bans actifs

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo fail2ban-client status sshd | grep 'Banned IP'"
```

### Forcer une mise a jour de securite immediate

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo unattended-upgrades -v"
```

### Consulter les logs auditd

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo ausearch -ts today -m USER_AUTH | tail -20"

# Rechercher les executions sudo recentes
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo ausearch -ts today -m EXECVE -k privileged | tail -30"
```

### Ajouter une regle nftables temporaire (debug)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo nft add rule inet filter input tcp dport 8080 accept"
# Attention : regle non persistante, sera ecrasee au prochain deploiement Ansible
```

## 7. Troubleshooting

### Incident 1 : VM inaccessible par SSH apres deploiement nftables

**Symptome :** Connexion SSH refusee ou timeout apres le deploiement du role hardening.

**Diagnostic :**
```bash
# Tenter via bastion
ssh -J debian@192.168.15.2 debian@192.168.20.12
# Si echec, ouvrir la console Proxmox de la VM
```

**Fix :**
Via console Proxmox :
```bash
# Lister les regles nftables actives
sudo nft list ruleset

# Vider les regles temporairement (DANGEREUX, ne pas faire en prod sans supervision)
sudo nft flush ruleset

# Ou ajouter une regle d'urgence autorisant SSH depuis tout le reseau interne
sudo nft add rule inet filter input tcp dport 22 accept

# Puis corriger la variable hardening_allowed_ssh_nets et rejouer
```

Verifier que `hardening_allowed_ssh_nets` inclut bien le reseau depuis lequel Ansible tourne.

### Incident 2 : fail2ban banne l'utilisateur debian Ansible

**Symptome :** Les plays Ansible echouent avec `UNREACHABLE` apres des echecs d'authentification precedents. fail2ban a banne l'IP de la machine de controle.

**Diagnostic :**
```bash
# Via console Proxmox sur la VM concernee
sudo fail2ban-client status sshd | grep "Banned IP"
# Verifier que l'IP Ansible est listee
```

**Fix :**
```bash
# Debloquer l'IP (ex. 192.168.10.5 = machine Ansible)
sudo fail2ban-client set sshd unbanip 192.168.10.5
```

Prevention : s'assurer que `ignoreip` dans fail2ban inclut le reseau de la machine de controle. Ajouter `192.168.10.0/24` a la liste si necessaire et rejouer `--tags hardening,fail2ban`.

### Incident 3 : auditd sature le disque

**Symptome :** Espace disque plein sur une VM (`df -h` montre /var a 100%). Les logs auditd dans `/var/log/audit/` occupent tout l'espace.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo du -sh /var/log/audit/ && ls -lh /var/log/audit/"
```

**Fix :**
```bash
# Forcer la rotation immediate
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo service auditd rotate"

# Supprimer les archives les plus anciennes si necessaire
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo ls -lt /var/log/audit/ | tail -5"
# Supprimer les 3 plus anciens audit.log.X

# Reduire hardening_auditd_log_size ou hardening_auditd_num_logs puis rejouer
```

### Incident 4 : Regles nftables non chargees au demarrage

**Symptome :** Apres un reboot, `nft list ruleset` retourne un jeu de regles vide ou le jeu de regles par defaut.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo systemctl status nftables && cat /etc/nftables.conf | head -20"
```

**Fix :**
```bash
# Verifier que le service nftables est enabled
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo systemctl enable nftables && sudo systemctl start nftables"

# Rejouer le role pour s'assurer que le fichier /etc/nftables.conf est correct
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fs01 --tags hardening,firewall \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

### Incident 5 : unattended-upgrades casse un service apres mise a jour automatique

**Symptome :** Un service (ex. mariadb, samba) ne demarre plus apres une mise a jour nocturne non supervisee.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo journalctl -u mariadb --since '2 hours ago' | tail -30"

# Identifier le package mis a jour
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "grep 'Packages that were auto-upgraded' /var/log/unattended-upgrades/unattended-upgrades.log | tail -5"
```

**Fix :**
```bash
# Downgrade du package si necessaire
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo apt-get install mariadb-server=<version_precedente>"

# Mettre le package en hold pour eviter la re-mise-a-jour
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sudo apt-mark hold mariadb-server"
```

Signaler le probleme upstream et planifier un créneau de mise a jour manuelle supervise.

### Incident 6 : fail2ban ne banne pas malgre des tentatives visibles dans les logs

**Symptome :** `journalctl -u sshd` montre des dizaines d'echecs d'authentification mais fail2ban ne banne pas l'IP source.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo fail2ban-client status sshd && \
   sudo grep 'ban' /var/log/fail2ban.log | tail -10"

# Verifier que le logpath correspond bien aux logs sshd
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo fail2ban-client get sshd logpath"
```

**Fix :** Sur Debian Bookworm, les logs sshd vont dans journald. Verifier que la jail sshd utilise `backend = systemd` dans la config fail2ban. Rejouer le role pour appliquer le template corrige.

## 8. Disaster Recovery

### Contexte DR

Le role `hardening` gere des configurations systeme (pare-feu, auditd, fail2ban). Sa perte entraine une exposition des VMs (pas de pare-feu actif). La priorite DR est de restaurer rapidement les regles nftables.

### Procedure de restauration

**Etape 1 : Evaluer l'etat du pare-feu sur les VMs affectees**
```bash
ansible all -i inventory/hosts.yml -m command \
  -a "sudo nft list ruleset | wc -l" \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```
Un resultat de 0 ou 2 lignes indique que nftables est vide.

**Etape 2 : Appliquer en urgence une regle restrictive minimale via console Proxmox**

Pour chaque VM exposee sans pare-feu :
```bash
sudo nft add table inet filter
sudo nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
sudo nft add rule inet filter input iif lo accept
sudo nft add rule inet filter input ct state established,related accept
sudo nft add rule inet filter input ip saddr 192.168.10.0/24 tcp dport 22 accept
sudo nft add rule inet filter input ip saddr 192.168.15.0/29 tcp dport 22 accept
```

**Etape 3 : Reprovisioner le role hardening complet**
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags hardening \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

**Etape 4 : Valider chaque VM avec les tests de la section 5**

**Etape 5 : Verifier les logs auditd pour identifier toute activite suspecte pendant la fenetre d'exposition**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo ausearch -ts <heure_incident> -m USER_LOGIN | grep 'res=success'"
```

**RTO :** 20 minutes pour restaurer les regles pare-feu sur tout le parc.
**RPO :** N/A -- configuration as-code dans Git, aucune donnee de config stockee localement.

## 9. Securite et conformite

### NIS2 Article 21 -- Mapping detaille

**Art. 21.2.b -- Politiques de securite des systemes d'information et gestion des risques :**
nftables avec politique DROP par defaut applique le principe du moindre privilege reseau. Seuls les flux necessaires sont explicitement autorises. La configuration est versionee dans Git (traçabilite des changements de politique).

**Art. 21.2.c -- Gestion des incidents :**
fail2ban fournit une reponse automatique aux tentatives de force brute (banissement automatique). auditd assure la collecte des evenements de securite requis pour l'investigation post-incident (DFIR).

**Art. 21.2.e -- Continuite d'activite :**
unattended-upgrades garantit l'application des correctifs de securite critiques sans intervention manuelle, reduisant la fenetre d'exposition aux CVE. La politique nftables `ESTABLISHED,RELATED` assure la continuite des connexions en cours.

**Art. 21.2.f -- Securite dans l'acquisition et le developpement :**
Les regles auditd surveillent les modifications des fichiers de configuration sensibles (/etc/passwd, /etc/sudoers, /etc/ssh/sshd_config), creant un trail d'audit requis pour la conformite.

**Art. 21.2.i -- Gestion des vulnerabilites :**
unattended-upgrades avec log dans `/var/log/unattended-upgrades/` fournit l'historique des patchs appliques, requis pour les audits de vulnerabilite.

### Controles RGPD

Les logs auditd peuvent contenir des informations sur les activites des utilisateurs. La retention est limitee a `hardening_auditd_num_logs * hardening_auditd_log_size` = 1,2 GB par VM (12 * 100 MB). Les logs sont stockes localement et envoyes vers Wazuh (app01) pour centralisation. Acces restreint au groupe `adm` et `root`.

## 10. References

### Internes au projet

- `roles/hardening/defaults/main.yml` -- valeurs par defaut
- `roles/hardening/tasks/firewall.yml` -- template nftables
- `roles/hardening/tasks/fail2ban.yml` -- configuration fail2ban
- `group_vars/domain_controllers/vars.yml` -- regles nftables DC
- `group_vars/databases/vars.yml` -- regles nftables DB
- `group_vars/bastions/vars.yml` -- regles nftables bastion
- Runbook common : `docs/runbooks/runbook-common.md`
- Runbook Wazuh : `docs/runbooks/runbook-wazuh.md`

### Documentation upstream

- nftables wiki : https://wiki.nftables.org/
- fail2ban documentation : https://www.fail2ban.org/wiki/index.php/MANUAL_0_8
- auditd man page : https://linux.die.net/man/8/auditd
- CIS Debian Benchmark : https://www.cisecurity.org/benchmark/debian_linux
- NIS2 Directive : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32022L2555
