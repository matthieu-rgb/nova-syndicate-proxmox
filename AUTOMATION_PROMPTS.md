# AUTOMATION_PIPELINE_PROMPTS.md

## Strategie de sessions automation pipeline -- economie de tokens

Ce fichier contient les prompts a copier-coller dans automation pipeline,
session par session. Chaque session est ciblee, courte, et verifiable.

**Principe** : 1 session = 1 objectif clair = 1 commit propre.

---

## Setup initial (a faire une fois Proxmox installe)

### Prerequis cote utilisateur

- Proxmox VE 9.x installe et accessible via https://IP-PROXMOX:8006
- API token Proxmox cree (voir PROXMOX_ARCHITECTURE.md section 7)
- Template Debian 12 cloud-init cree (VMID 9000)
- Bridges vmbr0, vmbr1, vmbr2, vmbr3, vmbr4, vmbr5 configures
- Cle SSH ed25519 pour Ansible existante (~/.ssh/nova_ansible_ed25519)

### Lancement automation pipeline

```bash
cd ~/Documents/Nova-syndicate-Code/nova-syndicate-proxmox
automation
```

---

## Session 1 -- Squelette Terraform Proxmox + 1 VM de test

### Objectif

Creer la structure terraform/environments/proxmox/, configurer le
provider, et deployer UNE VM de test (DC01) avec cloud-init pour
valider le pipeline.

### Prompt a copier

```
Lis MIGRATION_CONTEXT.md, PROXMOX_ARCHITECTURE.md et STATUS.md.

Objectif de cette session : creer le squelette Terraform Proxmox et
deployer DC01 comme VM de test.

Concretement :

1. Creer terraform/environments/proxmox/ avec :
   - main.tf      (provider bpg/proxmox configuration)
   - variables.tf (api token, hote Proxmox, ssh keys publiques)
   - terraform.tfvars.example (template avec valeurs factices)
   - vms.tf       (juste DC01 pour cette session)
   - cloud-init/  (dossier pour les user-data)
   - cloud-init/dc01-user-data.yml

2. Utiliser le provider bpg/proxmox (plus moderne que telmate)
   Documentation : https://registry.terraform.io/providers/bpg/proxmox

3. La VM DC01 doit cloner le template VMID 9000 et avoir :
   - Hostname : dc01
   - IP statique 192.168.20.10/28
   - Gateway 192.168.20.1
   - DNS 1.1.1.1 (DC01 sera son propre DNS apres Ansible)
   - Bridge vmbr1 avec tag VLAN 20
   - 2 GB RAM, 2 cores, 32 GB disque

4. Mettre a jour le .gitignore pour exclure :
   terraform/environments/proxmox/terraform.tfvars
   terraform/environments/proxmox/.terraform/
   terraform/environments/proxmox/*.tfstate*

5. Creer un README.md dans terraform/environments/proxmox/ qui explique :
   - Comment generer l'API token Proxmox
   - Comment copier terraform.tfvars.example vers terraform.tfvars
   - Comment lancer terraform init / plan / apply
   - Que faire si le clone du template echoue

6. Mettre a jour STATUS.md avec ce qui a ete fait.

7. Commiter avec :
   feat(proxmox): squelette Terraform + VM DC01 de test

Ne touche PAS aux roles Ansible ni au Terraform OPNsense existant.
```

### Validation

A la fin de la session, l'utilisateur lance manuellement :

```bash
cd terraform/environments/proxmox/
cp terraform.tfvars.example terraform.tfvars
# Editer terraform.tfvars avec les vraies valeurs
terraform init
terraform plan
terraform apply
```

Si DC01 apparait dans l'UI Proxmox et que `ssh ansible@192.168.20.10`
fonctionne, la session est valide.

---

## Session 2 -- Toutes les autres VMs Linux

### Objectif

Etendre le module Terraform pour declarer les 9 autres VMs Linux
en suivant le pattern de DC01.

### Prompt a copier

```
Lis MIGRATION_CONTEXT.md, PROXMOX_ARCHITECTURE.md et STATUS.md.

Objectif : ajouter les 9 autres VMs Linux dans Terraform Proxmox
en suivant exactement le pattern de DC01 (deja deploye).

VMs a ajouter (specs dans PROXMOX_ARCHITECTURE.md section 4) :
- WEB01     (DMZ vmbr3 sans tag)
- MAIL01    (DMZ vmbr3 sans tag)
- BASTION01 (vmbr1 tag 15)
- FS01      (vmbr1 tag 20)
- DB01      (vmbr1 tag 20)
- APP01     (vmbr1 tag 20, plus de ressources : 4 GB RAM 4 cores)
- PROXY-LYON01 (vmbr1 tag 20)
- PROXY-MRS01  (vmbr2 sans tag)
- BACKUP01  (vmbr1 tag 50, gros disque 200 GB)

Refactoring attendu :
- Extraire la logique dans un module reutilisable :
  terraform/modules/proxmox-vm/
  variables.tf : hostname, vmid, ip, gateway, vlan_tag, bridge,
                 ram, cpu, disk, dns
  main.tf      : resource bpg/proxmox-vm avec cloud-init
- Reecrire vms.tf pour utiliser ce module

Pour chaque VM :
- Cloud-init user-data dans cloud-init/<hostname>-user-data.yml
- Ajouter qemu-guest-agent dans le user-data

Mettre a jour STATUS.md.

Commit :
feat(proxmox): module reutilisable + 9 VMs Linux

Ne touche PAS aux roles Ansible.
```

### Validation

```bash
terraform plan
# Doit afficher 9 VMs a creer
terraform apply
# Verifier dans Proxmox UI : 10 VMs au total visibles
# ssh ansible@<chaque-ip> doit fonctionner
```

---

## Session 3 -- Firewalls OPNsense

### Objectif

Deployer les 4 VMs OPNsense (WAN-SIMULATOR + 3 firewalls) via Terraform.

Note : la configuration des firewalls (regles, NAT, VPN) sera faite
dans la session 4 via le Terraform OPNsense existant.

### Prompt a copier

```
Lis MIGRATION_CONTEXT.md, PROXMOX_ARCHITECTURE.md et STATUS.md.

Objectif : deployer les 4 VMs OPNsense via Terraform Proxmox.

Particularite : OPNsense ne supporte pas le clonage cloud-init Debian,
donc il faut une approche differente :

1. Telecharger l'ISO OPNsense 25.1 sur l'hote Proxmox manuellement
   (ou via Terraform avec resource proxmox_download_file)

2. Creer un module proxmox-opnsense dans terraform/modules/proxmox-opnsense/
   qui declare une VM avec :
   - ISO OPNsense en CD-ROM
   - Disque vide 16 GB
   - Plusieurs interfaces reseau selon les specs
   - Note : la configuration initiale (assigner les interfaces,
     mot de passe root, etc.) reste manuelle au premier boot

3. Declarer dans vms.tf :
   - WAN-SIMULATOR (3 interfaces : vmbr0, vmbr0, vmbr5)
   - FW-EXT-LYON01 (3 interfaces : vmbr0, vmbr3, vmbr4)
   - FW-INT-LYON01 (2 interfaces : vmbr4, vmbr1)
     Note : sur vmbr1 il faudra creer les sub-interfaces VLAN
     manuellement dans OPNsense apres install
   - FW-EXT-MRS01  (2 interfaces : vmbr5, vmbr2)

4. Documenter dans terraform/environments/proxmox/README.md la procedure
   manuelle de premier boot OPNsense :
   - Assigner les interfaces (em0, em1, em2)
   - Definir l'IP de management
   - Activer l'API REST + creer api_key/api_secret
   - Sauvegarder ces credentials pour Terraform OPNsense

5. Mettre a jour STATUS.md.

6. Commit :
feat(proxmox): module OPNsense + 4 firewalls
```

### Validation manuelle

```
1. Pour chaque OPNsense, demarrer la VM, faire l'install initiale
2. Configurer les IPs de management
3. Activer l'API et creer les keys
4. Sauvegarder les keys dans terraform/environments/lyon/terraform.tfvars
   (qui existe deja, mettre a jour les IPs)
```

---

## Session 4 -- Adapter le Terraform OPNsense aux nouvelles IPs

### Objectif

Le Terraform OPNsense existant fonctionne, mais les IPs de management
des firewalls ont change. Mettre a jour les variables et tester.

### Prompt a copier

```
Lis MIGRATION_CONTEXT.md, PROXMOX_ARCHITECTURE.md et STATUS.md.

Objectif : adapter le Terraform OPNsense existant aux nouvelles IPs
des firewalls deployes en session 3.

Etapes :

1. Lire terraform/environments/lyon/main.tf, variables.tf et tfvars.example

2. Verifier que les variables fw_ext_ip, fw_int_ip pointent vers
   les bonnes IPs de management (a definir avec l'utilisateur)

3. Si le tfvars.example ne contient que Lyon, l'etendre pour inclure
   FW-EXT-MRS aussi (creer un terraform/environments/marseille/ ou
   ajouter dans lyon/, a discuter)

4. Tester terraform plan -- pas terraform apply, juste valider que
   le code fonctionne et detecte les changements

5. Ne pas modifier la logique des regles/NAT/VPN (c'est deja fait)

6. Mettre a jour STATUS.md

7. Commit :
fix(opnsense-tf): adapte les IPs management pour Proxmox

Note : ne pas lancer terraform apply tant que l'utilisateur n'a pas
confirme que les firewalls sont prets.
```

---

## Session 5 -- Ansible : adapter et lancer

### Objectif

Lancer le playbook Ansible existant sur les nouvelles VMs Proxmox.

### Prompt a copier

```
Lis MIGRATION_CONTEXT.md, PROXMOX_ARCHITECTURE.md et STATUS.md.

Objectif : faire tourner le playbook Ansible site.yml sur les VMs
Proxmox deployees en sessions 1-2.

Etapes :

1. Verifier que les corrections d'incoherences signalees dans
   MIGRATION_CONTEXT.md section 6 sont faites :
   - nova_ip_bastion01 : 192.168.15.2 (pas 15.10)
   - nova_ip_backup01  : 192.168.50.2 (pas 50.10)
   Si pas faites, les faire et commiter :
   fix(inventory): harmonise IPs bastion01 et backup01 sur la verite

2. Creer un script scripts/test-ansible-connectivity.sh qui fait :
   ansible all -i inventory/hosts.yml -m ping
   Pour valider que toutes les VMs sont joignables.

3. Documenter dans le README.md la sequence complete de deploiement :
   ```
   # 1. Generer le template Debian cloud-init (manuel)
   # 2. Configurer les bridges Proxmox (manuel, /etc/network/interfaces)
   # 3. Generer l'API token Proxmox
   # 4. cd terraform/environments/proxmox/
   # 5. terraform init && terraform apply
   # 6. Configuration manuelle des OPNsense (1ere boot)
   # 7. cd ../lyon/
   # 8. terraform init && terraform apply
   # 9. cd ~/Documents/Nova-syndicate-Code/nova-syndicate-proxmox
   # 10. ansible-playbook site.yml --vault-password-file .vault_pass
   ```

4. NE PAS lancer ansible-playbook pendant cette session, c'est
   l'utilisateur qui le fera apres validation.

5. Mettre a jour STATUS.md.

6. Commit :
docs: procedure complete deploiement Proxmox bare-metal
```

---

## Session 6+ -- Roles Ansible manquants (web, mail, backup)

A faire selon le besoin. Prompt type :

```
Lis MIGRATION_CONTEXT.md, PROXMOX_ARCHITECTURE.md et STATUS.md.

Objectif : creer le role Ansible "web" pour deployer Nginx sur WEB01
en zone DMZ.

Le role doit :
- Installer Nginx
- Configurer un site HTTPS minimal (cert auto-signe pour le lab)
- Hardening de base (headers HTTP, no version disclosure)
- Activer l'agent Wazuh sur WEB01

Suivre le pattern des autres roles (defaults, handlers, tasks, templates).

Mettre a jour site.yml pour ajouter une etape "ETAPE 11 -- Web server".

Commit :
feat(role-web): role Nginx pour WEB01 DMZ
```

---

## Conseils d'utilisation efficace de automation pipeline

### Economie de tokens

- Une session = un objectif precis (pas "deploie tout d'un coup")
- Toujours commencer par "Lis MIGRATION_CONTEXT.md, STATUS.md"
- Toujours finir par "Mets a jour STATUS.md"
- Si une session devient trop longue, l'arreter et reprendre dans
  une nouvelle conversation

### Verification

A la fin de chaque session, l'utilisateur fait :

```bash
git status                  # voir les fichiers modifies
git diff                    # verifier les changements
git log --oneline | head -3 # voir les commits crees
```

### Si ca tourne mal

```bash
# Annuler les modifications non commitees
git checkout .

# Annuler le dernier commit (en gardant les fichiers)
git reset --soft HEAD~1

# Annuler completement le dernier commit
git reset --hard HEAD~1
```

### Pas de panique

Le repo est sur GitHub, tout est sauvegarde. Une session automation pipeline
ratee n'est pas un drame, on revient en arriere et on retente avec
un prompt plus precis.

---

Fin du AUTOMATION_PIPELINE_PROMPTS.md
