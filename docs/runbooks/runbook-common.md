# Runbook : common

## 1. Perimetre

Le role `common` constitue la fondation appliquee a toutes les machines virtuelles du projet Nova Syndicate. Il est execute en premier dans chaque play, avant tout autre role specialise. Son perimetre couvre la configuration minimale requise pour qu'une VM soit consideree "managed" : packages de base installes et packages dangereux supprimes, utilisateur de service Ansible present, configuration SSH durcie, NTP synchronise via chrony, et parametres kernel (sysctl) alignes avec les exigences de securite du projet.

Les machines ciblees sont l'ensemble du parc : dc01 (192.168.20.10), fs01 (192.168.20.11), db01 (192.168.20.12), app01 (192.168.20.13), bastion01 (192.168.15.2), backup01 (192.168.50.2), proxy-lyon01 (192.168.20.14), web01 (172.16.1.2) et mail01 (172.16.1.3). Le role est idempotent et peut etre rejoue a tout moment sans effet de bord.

Le role `common` n'ouvre aucun port reseau specifique et ne configure aucun service metier. Il pose uniquement les fondations : il est distinct du role `hardening` qui, lui, configure nftables, fail2ban et auditd. La separation deliberee permet de rejouer `common` seul (ex. ajout d'un package) sans risquer de modifier les regles pare-feu.

## 2. Prerequis

### Dependances de roles

- Aucun autre role Ansible n'est requis avant `common`.
- `common` doit etre execute avant `hardening`, `dc`, `fileserver`, `database`, `wazuh_manager`, `wazuh_agent`, `bastion`, `proxy` et `vpn`.

### Acces reseau

- Acces SSH (port 22) depuis la machine de controle Ansible via le bastion 192.168.15.2.
- Acces HTTPS sortant depuis chaque VM vers les miroirs Debian (apt) -- peut passer par le proxy Squid sur 192.168.20.14:3128 si configure.
- Port NTP UDP/123 sortant vers fr.pool.ntp.org (ou DNS resolving via 192.168.20.10).

### Machine de controle

- Ansible >= 2.14
- Fichier inventaire : `inventory/hosts.yml`
- Cle SSH Ansible : `~/.ssh/nova_ansible_ed25519`
- Vault Ansible accessible via `--ask-vault-pass` ou fichier `.vault_password`

### Packages requis sur la machine de controle

```bash
pip install ansible-lint
ansible --version   # doit afficher >= 2.14
```

## 3. Installation

### Verification pre-deploiement

Tester la connectivite SSH vers toutes les VMs via le bastion :

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible all -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

Verifier la syntaxe du role sans executer :

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags common \
  --syntax-check
```

### Dry-run (check mode)

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags common \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

### Deploiement complet

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags common \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement cible sur une VM specifique

```bash
# Sur dc01 uniquement
ansible-playbook -i inventory/hosts.yml site.yml \
  -l dc01 \
  --tags common \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass

# Sur le groupe servers
ansible-playbook -i inventory/hosts.yml site.yml \
  -l servers \
  --tags common \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes

1. `tasks/packages.yml` -- installation/suppression packages
2. `tasks/users.yml` -- utilisateur debian + sudo
3. `tasks/network.yml` -- configuration /etc/hosts minimal
4. `tasks/ntp.yml` -- chrony avec fr.pool.ntp.org
5. `tasks/sysctl.yml` -- parametres kernel

## 4. Configuration

### Variables principales (defaults/main.yml)

```yaml
common_extra_packages: []
common_remove_packages:
  - telnet
  - ftp
  - rsh-client
  - rpcbind
common_sysctl:
  net.ipv4.ip_forward: 0
  net.ipv4.conf.all.rp_filter: 1
  net.ipv4.tcp_syncookies: 1
  kernel.dmesg_restrict: 1
```

### Variables globales (group_vars/all/vars.yml)

```yaml
nova_domain: nova-syndicate.local
nova_dns_primary: 192.168.20.10
nova_ntp_server: fr.pool.ntp.org
ssh_port: 22
ssh_permit_root: "no"
ssh_password_auth: "no"
ssh_max_auth_tries: 3
ssh_idle_timeout: 600
```

### Surcharge par groupe

Pour ajouter des packages specifiques a un groupe (ex. outils de debug sur le bastion) :

```yaml
# group_vars/bastions/vars.yml
common_extra_packages:
  - tcpdump
  - net-tools
  - strace
```

Pour autoriser un parametre sysctl different sur le routeur/proxy :

```yaml
# group_vars/proxies/vars.yml
common_sysctl:
  net.ipv4.ip_forward: 1        # proxy-lyon01 a besoin du forwarding
  net.ipv4.conf.all.rp_filter: 1
  net.ipv4.tcp_syncookies: 1
  kernel.dmesg_restrict: 1
```

### Secrets Vault

Aucune variable sensible n'est stockee dans le role `common` directement. Les mots de passe eventuels (ex. `vault_debian_password` pour l'utilisateur debian) sont dans `group_vars/all/vault.yml`.

## 5. Validation post-deploiement

### Verification NTP

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "chronyc tracking | grep -E 'Reference|Stratum|Offset'"
```

Resultat attendu : Reference Source = fr.pool.ntp.org ou une IP NTP, Stratum <= 3.

### Verification sysctl

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sysctl net.ipv4.ip_forward net.ipv4.tcp_syncookies kernel.dmesg_restrict"
```

Resultat attendu :
```
net.ipv4.ip_forward = 0
net.ipv4.tcp_syncookies = 1
kernel.dmesg_restrict = 1
```

### Verification packages supprimes

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "dpkg -l telnet ftp rsh-client rpcbind 2>&1 | grep -E '^ii|no packages'"
```

Aucun package de la liste `common_remove_packages` ne doit apparaitre avec le statut `ii`.

### Verification SSH

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sshd -T | grep -E 'permitrootlogin|passwordauthentication|maxauthtries|clientaliveinterval'"
```

Resultat attendu :
```
permitrootlogin no
passwordauthentication no
maxauthtries 3
clientaliveinterval 600
```

### Verification chrony en service

```bash
ansible all -i inventory/hosts.yml -m command \
  -a "systemctl is-active chrony" \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

Toutes les VMs doivent repondre `active`.

## 6. Operations courantes

### Ajouter un package sur toutes les VMs

Modifier `common_extra_packages` dans `group_vars/all/vars.yml` ou dans le fichier de groupe concerne, puis rejouer :

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags common,packages \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

### Mettre a jour les sysctl sur une VM

Modifier la valeur dans le fichier de vars approprie et rejouer avec le tag sysctl :

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l db01 \
  --tags common,sysctl \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

### Redemarrer chrony (apres changement de source NTP)

Handler Ansible gere le redemarrage automatique. En manuel si necessaire :

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl restart chrony && chronyc sources -v"
```

### Redemarrer sshd (apres changement de config SSH)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl restart sshd && systemctl is-active sshd"
```

Note : ne redemarrer sshd que depuis une session deja ouverte ou via une tache Ansible pour eviter de se couper la connexion.

### Verifier la synchronisation NTP de tout le parc

```bash
ansible all -i inventory/hosts.yml -m command \
  -a "chronyc tracking | grep 'System time'" \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

## 7. Troubleshooting

### Incident 1 : Echec de la connexion SSH Ansible vers une VM

**Symptome :** `ansible all -m ping` retourne `UNREACHABLE` pour une ou plusieurs VMs.

**Diagnostic :**
```bash
# Tester manuellement via ProxyJump
ssh -v -J debian@192.168.15.2 debian@192.168.20.12 \
  -i ~/.ssh/nova_ansible_ed25519

# Verifier que bastion01 est accessible
ssh -v debian@192.168.15.2 -i ~/.ssh/nova_ansible_ed25519
```

**Fix :**
- Si bastion inaccessible : verifier que l'interface reseau VLAN 15 est UP sur OPNsense FW-INT-LYON (192.168.20.1).
- Si VM interne inaccessible : verifier l'etat de la VM dans Proxmox (VLAN 20, ip addr sur la VM via console Proxmox).
- Si cle rejetee : redeployer la cle avec `ssh-copy-id -i ~/.ssh/nova_ansible_ed25519.pub -J debian@192.168.15.2 debian@192.168.20.12`.

### Incident 2 : NTP non synchronise, offset eleve

**Symptome :** `chronyc tracking` affiche `Stratum: 0` ou un offset superieur a 1 seconde.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "chronyc sources -v && chronyc tracking"

# Verifier resolution DNS du serveur NTP
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "dig fr.pool.ntp.org +short"
```

**Fix :**
```bash
# Forcer une synchronisation immediate
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo chronyc makestep && chronyc tracking"

# Si DNS en panne, utiliser IP directe dans /etc/chrony/chrony.conf
# Remplacer fr.pool.ntp.org par 162.159.200.123 (Cloudflare NTP) temporairement
```

### Incident 3 : Package "telnet" toujours present apres deploiement

**Symptome :** `dpkg -l telnet` retourne `ii  telnet` sur une VM.

**Diagnostic :**
```bash
# Verifier si le package est en hold
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "apt-mark showhold | grep telnet"

# Verifier si une dependance tire le package
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "apt-rdepends --reverse telnet | head -20"
```

**Fix :**
```bash
# Lever le hold si present
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "sudo apt-mark unhold telnet && sudo apt-get purge -y telnet"

# Puis rejouer le role
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fs01 --tags common,packages \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

### Incident 4 : sysctl net.ipv4.ip_forward = 1 apres deploiement sur une VM non-proxy

**Symptome :** Le forwarding IP est actif sur une VM qui ne devrait pas l'avoir (ex. db01).

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "sysctl net.ipv4.ip_forward && cat /etc/sysctl.d/99-nova-common.conf"
```

**Fix :** Verifier que `group_vars/databases/vars.yml` ne surcharge pas `common_sysctl` incorrectement. Corriger la valeur dans le fichier de vars, puis :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l db01 --tags common,sysctl \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

### Incident 5 : Drift NTP entre VMs superieur a 100 ms

**Symptome :** Les timestamps des logs Wazuh (app01) ne correspondent pas aux timestamps des agents. Alertes de correlation temporelle.

**Diagnostic :**
```bash
# Comparer les offsets sur plusieurs VMs
for host in 192.168.20.10 192.168.20.11 192.168.20.12 192.168.20.13; do
  echo "=== $host ===" && ssh -J debian@192.168.15.2 debian@$host \
    "chronyc tracking | grep 'System time'"
done
```

**Fix :** Si dc01 est la source NTP interne, verifier que les autres VMs pointent bien vers fr.pool.ntp.org et non vers une source divergente. Corriger `nova_ntp_server` si necessaire et rejouer le role `common` avec `--tags ntp`.

### Incident 6 : Ansible retourne "sudo: no tty present" ou "sudo password required"

**Symptome :** Les tasks avec `become: true` echouent avec une erreur sudo.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.13 \
  "sudo -l | grep NOPASSWD"
```

**Fix :** Verifier que le fichier `/etc/sudoers.d/debian` existe sur la VM cible avec `debian ALL=(ALL) NOPASSWD:ALL`. Si absent, se connecter en root via la console Proxmox et recreer le fichier, ou utiliser `--ask-become-pass` temporairement.

## 8. Disaster Recovery

### Contexte DR

Le role `common` ne gere aucune donnee persistante. Sa perte n'entraine pas de perte de donnees. La procedure DR consiste a reprovisioner les configurations perdues.

### Procedure de restauration

**Etape 1 : Identifier les VMs affectees**
```bash
ansible all -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

**Etape 2 : Acces console Proxmox si SSH indisponible**

Se connecter a l'interface web Proxmox (VLAN 10 Management, 192.168.10.0/24), ouvrir la console de la VM concernee, verifier l'etat reseau avec `ip addr` et `systemctl status sshd`.

**Etape 3 : Recreer l'acces SSH minimum**

```bash
# Via console Proxmox : ajouter la cle publique Ansible
mkdir -p /home/debian/.ssh
echo "ssh-ed25519 AAAA...cle_publique_nova_ansible... ansible@nova" \
  >> /home/debian/.ssh/authorized_keys
chmod 700 /home/debian/.ssh
chmod 600 /home/debian/.ssh/authorized_keys
chown -R debian:debian /home/debian/.ssh
```

**Etape 4 : Reprovisioner le role common**

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l <vm_affectee> \
  --tags common \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

**Etape 5 : Valider la configuration**

Reprendre les tests de la section 5.

**RTO :** 15 minutes par VM (acces console + reprovisioning Ansible).
**RPO :** N/A -- aucune donnee, configuration as-code dans Git.

## 9. Securite et conformite

### NIS2 Article 21 -- Mesures de gestion des risques

**Art. 21.2.b -- Gestion des risques :**
Le role `common` applique la suppression des services non necessaires (`rpcbind`, `telnet`, `ftp`, `rsh-client`) conformement au principe de surface d'attaque minimale. Les sysctl `tcp_syncookies` et `rp_filter` mitigent respectivement les attaques SYN flood et le IP spoofing.

**Art. 21.2.e -- Continuite d'activite :**
La configuration NTP synchronisee sur l'ensemble du parc garantit la coherence temporelle des logs, prerequis pour la continuite des systemes de detection et de traçabilite.

**Art. 21.2.f -- Securite de la chaine d'approvisionnement (audit) :**
`kernel.dmesg_restrict = 1` empeche les utilisateurs non privilegies de lire les messages kernel, reduisant la surface de reconnaissance. La configuration SSH (`PasswordAuthentication no`, `PermitRootLogin no`, `MaxAuthTries 3`) limite les vecteurs d'acces non autorise.

### Points d'audit

- Verifier regulierement que les packages de la liste `common_remove_packages` ne sont pas reintroduits par des dependances tierces.
- S'assurer que la cle SSH Ansible (`~/.ssh/nova_ansible_ed25519`) est protegee avec une passphrase et renouvelee annuellement.
- Journaliser les executions Ansible (stdout + stderr) dans un repertoire archive (ex. `/var/log/ansible/`) pour traçabilite.

### RGPD

Le role `common` ne traite aucune donnee a caractere personnel directement. La configuration SSH sans mot de passe reduit le risque de compromission de comptes associes a des personnes physiques.

## 10. References

### Internes au projet

- `group_vars/all/vars.yml` -- variables globales Nova Syndicate
- `roles/common/defaults/main.yml` -- valeurs par defaut du role
- `roles/common/tasks/` -- packages.yml, users.yml, network.yml, ntp.yml, sysctl.yml
- `inventory/hosts.yml` -- inventaire complet
- Runbook hardening : `docs/runbooks/runbook-hardening.md`

### Documentation upstream

- Ansible Roles documentation : https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html
- Debian sysctl securite : https://www.debian.org/doc/manuals/securing-debian-manual/
- Chrony documentation : https://chrony-project.org/documentation.html
- NIS2 Article 21 texte officiel : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32022L2555
