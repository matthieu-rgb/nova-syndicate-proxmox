# Runbook : bastion (SSH Jumpbox + Teleport planifie)

## 1. Perimetre

Le role `bastion` configure bastion01 (192.168.15.2, VLAN BASTION 192.168.15.0/29) en tant que point d'entree SSH unique vers tout le parc interne Nova Syndicate. bastion01 est la seule machine accessible directement depuis l'exterieur (ou depuis le VLAN Management Proxmox) : toutes les connexions vers les VMs internes (VLAN 20, VLAN 50) passent obligatoirement par ce jumpbox via SSH ProxyJump.

**Etat actuel deploye :** bastion01 utilise SSH standard avec ProxyJump (`ssh -J debian@192.168.15.2`). La cle SSH Ansible `~/.ssh/nova_ansible_ed25519` est deployee sur toutes les VMs. C'est l'etat operationnel reel.

**Etat planifie (non encore deploye) :** Le role `bastion` contient la logique de deploiement de Teleport 14 (cluster `nova-syndicate`, acces HTTPS sur bastion.nova-syndicate.local:443, enregistrement de sessions). Teleport remplacera le SSH plain a terme mais n'est pas en production actuellement. La section 3 couvre les deux scenarios.

Le VLAN BASTION (192.168.15.0/29) est isole : seul bastion01 (192.168.15.2) l'occupe. Le gateway VLAN 15 sur OPNsense FW-INT-LYON accepte les connexions SSH entrantes et les forwarde vers bastion01. Les regles nftables sur bastion01 ouvrent les ports SSH (22) et les futurs ports Teleport (443, 3023, 3024, 3025).

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `bastion`.
- Pour le deploiement Teleport (futur) : un certificat TLS valide pour `bastion.nova-syndicate.local` doit etre disponible.

### Reseau

- bastion01 : IP statique 192.168.15.2/29, gateway 192.168.15.1 (OPNsense VLAN 15).
- Acces SSH entrant : depuis le VLAN Management (192.168.10.0/24) et depuis l'exterieur (via OPNsense NAT).
- Ports ouverts par nftables via `hardening_extra_nft_rules` :
  - TCP 22 (SSH actuel)
  - TCP 443, 3023, 3024, 3025 (Teleport planifie)
- bastion01 doit pouvoir joindre tous les hotes internes sur TCP 22 (ProxyJump).

### Packages

- Etat actuel : aucun package supplementaire (SSH standard Debian).
- Etat planifie Teleport : `teleport` version 14, depuis les depots GPG officiels Gravitational.

### Variables Teleport (group_vars/bastions/vars.yml)

```yaml
teleport_version: "14"
teleport_cluster_name: "nova-syndicate"
teleport_public_addr: "bastion.nova-syndicate.local:443"
teleport_auth_type: "local"
teleport_session_record: "node"
teleport_cert_ttl: "8h"
teleport_max_sessions: 5
teleport_nodes:
  - dc01
  - fs01
  - db01
  - app01
```

## 3. Installation

### Scenario 1 : Deploiement SSH standard (etat actuel)

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Deployer le role bastion (SSH + hardening)
ansible-playbook -i inventory/hosts.yml site.yml \
  -l bastions \
  --tags common,hardening,bastion \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

Deployer la cle SSH Ansible sur toutes les VMs internes :
```bash
# La cle est deployee via le role common (tasks/users.yml)
ansible-playbook -i inventory/hosts.yml site.yml \
  --tags common,users \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Scenario 2 : Deploiement Teleport (planifie, pas encore en production)

```bash
# Dry-run Teleport
ansible-playbook -i inventory/hosts.yml site.yml \
  -l bastions \
  --tags bastion,teleport \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass

# Deploiement Teleport
ansible-playbook -i inventory/hosts.yml site.yml \
  -l bastions \
  --tags bastion,teleport \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes (role bastion)

1. Installation Teleport (GPG + apt)
2. Deploiement teleport.yaml.j2
3. Enable + start teleport service
4. (Handler : restart teleport si config change)

### Configuration SSH ProxyJump (client)

A configurer dans `~/.ssh/config` sur la machine de controle :

```
Host bastion01
  HostName 192.168.15.2
  User debian
  IdentityFile ~/.ssh/nova_ansible_ed25519

Host dc01
  HostName 192.168.20.10
  User debian
  IdentityFile ~/.ssh/nova_ansible_ed25519
  ProxyJump bastion01

Host fs01
  HostName 192.168.20.11
  User debian
  IdentityFile ~/.ssh/nova_ansible_ed25519
  ProxyJump bastion01

Host db01
  HostName 192.168.20.12
  User debian
  IdentityFile ~/.ssh/nova_ansible_ed25519
  ProxyJump bastion01

Host app01
  HostName 192.168.20.13
  User debian
  IdentityFile ~/.ssh/nova_ansible_ed25519
  ProxyJump bastion01

Host backup01
  HostName 192.168.50.2
  User debian
  IdentityFile ~/.ssh/nova_ansible_ed25519
  ProxyJump bastion01
```

## 4. Configuration

### Variables par defaut (defaults/main.yml)

```yaml
teleport_version: "14"
```

### Variables du groupe (group_vars/bastions/vars.yml)

```yaml
teleport_cluster_name: "nova-syndicate"
teleport_public_addr: "bastion.nova-syndicate.local:443"
teleport_auth_type: "local"
teleport_session_record: "node"
teleport_cert_ttl: "8h"
teleport_max_sessions: 5
hardening_extra_nft_rules:
  - "tcp dport 443 accept"
  - "tcp dport 3023 accept"
  - "tcp dport 3024 accept"
  - "tcp dport 3025 accept"
```

### teleport.yaml (template -- pour deploiement futur)

```yaml
teleport:
  nodename: bastion01
  data_dir: /var/lib/teleport
  log:
    output: stderr
    severity: INFO

auth_service:
  enabled: yes
  listen_addr: 0.0.0.0:3025
  cluster_name: nova-syndicate

ssh_service:
  enabled: yes
  listen_addr: 0.0.0.0:3022

proxy_service:
  enabled: yes
  listen_addr: 0.0.0.0:3023
  web_listen_addr: 0.0.0.0:443
  public_addr: bastion.nova-syndicate.local:443
```

### Etat actuel vs planifie

| Composant | Etat actuel | Etat planifie |
|-----------|-------------|---------------|
| SSH ProxyJump | Deploye, operationnel | Remplace par Teleport |
| Cle SSH nova_ansible_ed25519 | Deployee sur toutes les VMs | Inchangee pour Ansible |
| Teleport auth | Non deploye | Deploiement T-BASTION-TELEPORT |
| Session recording | Non active | Active dans Teleport |
| MFA | Non active | Planifiee avec Teleport |

## 5. Validation post-deploiement

### Verifier l'acces SSH via ProxyJump (etat actuel)

```bash
# Connexion directe au bastion
ssh debian@192.168.15.2 -i ~/.ssh/nova_ansible_ed25519 "hostname"

# ProxyJump vers dc01
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  -i ~/.ssh/nova_ansible_ed25519 "hostname"

# ProxyJump vers backup01
ssh -J debian@192.168.15.2 debian@192.168.50.2 \
  -i ~/.ssh/nova_ansible_ed25519 "hostname"
```

### Verifier les regles nftables sur bastion01

```bash
ssh debian@192.168.15.2 -i ~/.ssh/nova_ansible_ed25519 \
  "sudo nft list ruleset | grep -E 'accept|drop'"
```

### Verifier que SSH est durci

```bash
ssh debian@192.168.15.2 -i ~/.ssh/nova_ansible_ed25519 \
  "sshd -T | grep -E 'permitrootlogin|passwordauthentication|maxauthtries'"
```

### Verifier l'acces Ansible a tout le parc via bastion

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible all -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

Toutes les VMs doivent repondre `pong`.

### Test de rejet SSH par mot de passe

```bash
# Doit echouer
ssh -o PasswordAuthentication=yes debian@192.168.15.2
```

## 6. Operations courantes

### Se connecter a une VM interne via le bastion

```bash
# Syntaxe ProxyJump directe
ssh -J debian@192.168.15.2 debian@192.168.20.12

# Via ~/.ssh/config (si configure)
ssh db01
```

### Redemarrer sshd sur bastion01

```bash
# ATTENTION : ne jamais couper la connexion SSH active
# Ouvrir une 2e session avant de redemarrer
ssh debian@192.168.15.2 "sudo systemctl restart sshd && systemctl is-active sshd"
```

### Ajouter une cle SSH d'un nouvel administrateur

```bash
ssh -J debian@192.168.15.2 debian@192.168.15.2 \
  "echo 'ssh-ed25519 AAAA...nouvelle_cle... nouvel_admin' \
   >> ~/.ssh/authorized_keys"

# Propager la cle sur toutes les VMs si necessaire via Ansible
ansible all -i inventory/hosts.yml -m authorized_key \
  -a "user=debian key='ssh-ed25519 AAAA...'" \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian \
  --become
```

### Consulter les logs d'acces SSH

```bash
ssh debian@192.168.15.2 \
  "sudo journalctl -u sshd --since '24 hours ago' | \
   grep -E 'Accepted|Failed' | tail -20"
```

### Verifier fail2ban sur bastion01

```bash
ssh debian@192.168.15.2 \
  "sudo fail2ban-client status sshd | grep -E 'Currently banned|Banned IP'"
```

## 7. Troubleshooting

### Incident 1 : Bastion inaccessible (timeout SSH depuis la machine de controle)

**Symptome :** `ssh debian@192.168.15.2` timeout. Aucune reponse.

**Diagnostic :**
```bash
# Tester la connectivite reseau
ping 192.168.15.2

# Verifier l'etat de la VM dans Proxmox (console web)
# VLAN 15 UP sur OPNsense ?
```

**Fix :**
- Ouvrir la console Proxmox de bastion01. Verifier `systemctl status sshd` et `ip addr`.
- Si sshd est tombe : `sudo systemctl start sshd`.
- Si l'IP est incorrecte ou absente : verifier la config reseau `/etc/network/interfaces`.
- Si OPNsense a perdu la route VLAN 15 : se connecter a l'interface OPNsense et verifier l'interface du VLAN 15.

### Incident 2 : ProxyJump echoue (connexion au bastion OK, rebond KO)

**Symptome :** `ssh -J debian@192.168.15.2 debian@192.168.20.12` echoue avec `Connection refused` ou `Host unreachable`.

**Diagnostic :**
```bash
# Tester depuis bastion01 directement
ssh debian@192.168.15.2 \
  "ssh -o BatchMode=yes debian@192.168.20.12 hostname 2>&1"

# Verifier le routage entre VLAN 15 et VLAN 20 sur OPNsense
ssh debian@192.168.15.2 \
  "ip route && ping -c 2 192.168.20.12"
```

**Fix :** Le probleme est le plus souvent une regle pare-feu OPNsense bloquant VLAN 15 -> VLAN 20 sur TCP 22. Verifier et corriger les regles inter-VLAN dans OPNsense.

### Incident 3 : fail2ban banne l'IP de la machine de controle

**Symptome :** Impossible de se connecter au bastion. fail2ban a banni l'IP source suite a des echecs d'authentification.

**Diagnostic :**
```bash
# Via console Proxmox sur bastion01
sudo fail2ban-client status sshd | grep "Banned IP"
```

**Fix :**
```bash
# Debloquer l'IP (ex. 192.168.10.5)
sudo fail2ban-client set sshd unbanip 192.168.10.5
```

Prevention : s'assurer que la machine de controle est dans `ignoreip` fail2ban. Verifier `group_vars/bastions/vars.yml` et rejouer le role.

### Incident 4 : Cle SSH invalide ou refusee sur une VM interne

**Symptome :** `ssh -J debian@192.168.15.2 debian@192.168.20.11` retourne `Permission denied (publickey)`.

**Diagnostic :**
```bash
# Avec verbosity SSH
ssh -v -J debian@192.168.15.2 debian@192.168.20.11 \
  -i ~/.ssh/nova_ansible_ed25519 2>&1 | grep -E 'identity|auth'
```

**Fix :**
```bash
# Redeployer la cle sur la VM concernee
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fs01 \
  --tags common,users \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian

# Ou manuellement via console Proxmox : ajouter la cle dans authorized_keys
```

### Incident 5 : Teleport ne demarre pas (pour quand il sera deploye)

**Symptome :** `systemctl status teleport` affiche `failed`. Logs indiquent une erreur de certificat ou de configuration.

**Diagnostic :**
```bash
ssh debian@192.168.15.2 \
  "sudo journalctl -u teleport -n 50 --no-pager"

# Tester la config Teleport
ssh debian@192.168.15.2 \
  "sudo teleport configure --verify"
```

**Fix :**
- Verifier que le certificat TLS pour `bastion.nova-syndicate.local` est valide et lisible par le service Teleport.
- Verifier que les ports 443, 3023, 3024, 3025 ne sont pas deja utilises : `sudo ss -tlnp`.
- Corriger le template `teleport.yaml.j2` et rejouer le role.

### Incident 6 : SSH root permis accidentellement sur bastion01

**Symptome :** `sshd -T | grep permitrootlogin` retourne `permitrootlogin yes`.

**Diagnostic :**
```bash
ssh debian@192.168.15.2 \
  "sudo grep PermitRootLogin /etc/ssh/sshd_config"
```

**Fix :** Corriger la configuration et redemarrer sshd :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l bastions \
  --tags common,hardening,ssh \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

## 8. Disaster Recovery

### Contexte DR

La perte de bastion01 bloque tout acces SSH aux VMs internes depuis la machine de controle. Les VMs continuent de fonctionner. L'acces via console Proxmox reste disponible. RTO cible : 30 minutes. RPO : N/A (pas de donnees persistantes).

### Procedure de restauration

**Etape 1 : Utiliser la console Proxmox pour les operations urgentes**

Ouvrir la console web Proxmox (VLAN 10 Management) pour chaque VM necessitant une intervention immediate. C'est l'acces de contournement pendant la restauration du bastion.

**Etape 2 : Provisionner une nouvelle VM bastion01**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/
terraform apply -target=proxmox_vm_qemu.bastion01
```

La nouvelle VM doit recevoir l'IP 192.168.15.2.

**Etape 3 : Deployer les roles**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Acces direct via le VLAN Management pendant le bootstrapping
ansible-playbook -i inventory/hosts.yml site.yml \
  -l bastions \
  --tags common,hardening,bastion \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass \
  -e "ansible_ssh_common_args=''"
```

Note : sans ProxyJump disponible, utiliser `ansible_ssh_common_args=''` et s'assurer que bastion01 est joignable directement depuis la machine de controle (routage VLAN 10 -> VLAN 15).

**Etape 4 : Verifier le ProxyJump**

Reprendre les tests de la section 5.

**Etape 5 : Verifier l'acces Ansible a tout le parc**
```bash
ansible all -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

**RTO :** 30 minutes (provisioning VM + deploiement + validation).
**RPO :** N/A -- aucune donnee persistante, configuration as-code.

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
Le bastion est le point d'entree unique vers le parc interne. La segmentation VLAN (VLAN 15 isole) limite la surface d'attaque. SSH ProxyJump avec cle ed25519 uniquement (pas de mot de passe). fail2ban sur SSH.

**Art. 21.2.c -- Gestion des incidents :**
Les logs SSH du bastion (`/var/log/auth.log` + journald) sont collectes par Wazuh agent. Toutes les connexions entrantes et sortantes sont visibles. En cas d'incident, les logs du bastion permettent de reconstituer la timeline des acces. Teleport (planifie) ajoutera l'enregistrement de sessions (`teleport_session_record: node`).

**Art. 21.2.e -- Continuite d'activite :**
L'acces console Proxmox est le mecanisme de continuité en cas de perte du bastion. Documenter et tester regulierement l'acces console hors bastion.

**Art. 21.2.f -- Audit :**
Chaque connexion SSH est tracee dans les logs sshd avec l'IP source, l'utilisateur, et le timestamp. Ces logs sont forwrades vers Wazuh (app01). Avec Teleport (futur), les sessions seront integralement enregistrees et rejouables.

**Art. 21.2.i -- Chaine d'approvisionnement :**
La cle SSH Ansible est la cle d'administration universelle du parc. Elle doit etre : generee uniquement sur des machines de confiance, protegee par une passphrase, renouvelee annuellement, revoquee immediatement en cas de compromission.

### Procedures de gestion des cles

- Rotation de la cle SSH Ansible : generer une nouvelle cle, mettre a jour `group_vars/all/vars.yml`, deployer avec le role `common`.
- En cas de compromission : supprimer immediatement la cle des `authorized_keys` de toutes les VMs via console Proxmox, generer une nouvelle cle et redeployer.

## 10. References

### Internes au projet

- `roles/bastion/defaults/main.yml` -- version Teleport
- `roles/bastion/templates/teleport.yaml.j2` -- configuration Teleport
- `group_vars/bastions/vars.yml` -- variables du groupe
- `~/.ssh/config` -- configuration ProxyJump client
- Runbook hardening : `docs/runbooks/runbook-hardening.md`
- Runbook Wazuh : `docs/runbooks/runbook-wazuh.md`

### Documentation upstream

- OpenSSH ProxyJump : https://man.openbsd.org/ssh_config.5#ProxyJump
- Teleport documentation v14 : https://goteleport.com/docs/
- Teleport SSH access : https://goteleport.com/docs/server-access/getting-started/
- NIS2 Directive : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32022L2555
