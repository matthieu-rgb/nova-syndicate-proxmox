# ADR-0011 : Ansible pour la configuration OS (IaC niveau 2)

## Status
Accepted

## Date
2026-05-10

## Contexte

L'infrastructure Nova Syndicate comprend 10 VMs Linux (plus 2 VMs OPNsense gerees par Terraform). Chacune de ces VMs necessite une configuration initiale et une maintenance continue : utilisateurs, paquets, services, regles firewall locales (nftables), hardening sshd, etc.

La configuration manuelle (connexion SSH VM par VM) est inacceptable pour plusieurs raisons :

- **Reproductibilite** : si une VM est detruite et recree depuis un template (suite a un test destructif ou a un `terraform destroy && terraform apply`), sa configuration ne doit pas necessiter d'intervention manuelle.
- **Coherence** : des configurations divergentes entre VMs du meme type (ex : deux configurations sshd differentes sur dc01 et fs01) creent des failles de securite par omission.
- **Auditabilite** : la configuration de chaque VM doit etre versionnable dans Git. Un changement de politique (ajout d'une regle fail2ban, modification d'un parametre sysctl) doit etre tracable.
- **Contexte formation** : Ansible est un outil central du referentiel AIS et une competence attendue par les recruteurs dans les environnements enterprise (Thales Luxembourg, secteur defense).

Le niveau IaC du projet est structure en deux couches :
- **Niveau 1 (Terraform)** : provisionnement des VMs sur Proxmox (creation, disque, CPU, RAM, reseau) et configuration OPNsense (regles firewall, tunnels VPN).
- **Niveau 2 (Ansible)** : configuration interne des VMs (OS, paquets, services, hardening).

Cette separation des responsabilites correspond au pattern "immutable infrastructure" : Terraform definit ce qui existe, Ansible configure ce qui s'y passe.

## Decision

Adoption d'**Ansible** (version community >= 9.x, core >= 2.17) comme outil de configuration OS.

**Architecture des playbooks :**

```
ansible/
  inventory/
    hosts.yml             -- Inventaire YAML avec groupes (all, servers, backup, bastion, etc.)
    group_vars/
      all.yml             -- Variables globales
      servers.yml         -- Variables specifiques au groupe servers
      backup.yml          -- Variables specifiques (secrets Borg dans vault.yml)
    host_vars/
      dc01.yml            -- Variables specifiques a dc01
      ...
  roles/
    common/               -- Base commune a toutes les VMs (paquets, utilisateurs, SSH keys)
    hardening/            -- Hardening securite (sshd, nftables, fail2ban, auditd, sysctl)
    dc01/                 -- Specifique Active Directory (samba-ad-dc)
    fs01/                 -- Specifique Samba shares
    db01/                 -- Specifique MariaDB
    app01/                -- Specifique Wazuh manager + Prometheus + Grafana
    bastion/              -- Specifique bastion SSH jumpbox
    borg_client/          -- Client Borg backup
    borg_server/          -- Serveur Borg (sur VPS Hetzner)
    wireguard_server/     -- WireGuard server (sur VPS Hetzner)
    wazuh_agent/          -- Agent Wazuh (installe sur toutes les VMs surveillees)
  site.yml                -- Playbook principal
  vault.yml               -- Secrets Ansible Vault
```

**Justifications techniques :**

**1. Idempotence native**
Les modules Ansible sont idempotents par conception : `apt`, `template`, `service`, `user`, `file`, etc. verifient l'etat avant d'agir. Un `ansible-playbook site.yml` sur une VM deja configuree n'applique des changements que si l'etat diverge de la definition. Cela permet de detecter la derive de configuration (configuration drift) et de la corriger sans risque.

**2. Pas de daemon agent**
Ansible fonctionne en mode push, sans agent sur les VMs gerees. La connexion est SSH. Cela reduit la surface d'attaque (pas de daemon supplementaire avec des ports ouverts) et simplifie la mise en place initiale (les VMs n'ont besoin que de SSH et Python3 preinstalle, fourni par cloud-init).

**3. Ansible Vault pour les secrets**
Les mots de passe et cles sensibles (passphrase Borg, mots de passe MariaDB, cles WireGuard) sont chiffres avec AES-256 dans des fichiers `vault.yml`. Ces fichiers peuvent etre commites dans Git en toute securite. Seul le mot de passe du vault (conserve hors Git) est necessaire pour les dechiffrer.

**4. Hierarchie group_vars/host_vars**
La hierarchie de variables permet d'exprimer des configurations generiques au niveau du groupe et des surcharges specifiques au niveau de l'hote. Par exemple, la politique de retention des logs Wazuh est definie dans `group_vars/all.yml` mais le serveur Wazuh (app01) a des parametres supplementaires dans `host_vars/app01.yml`.

**5. Modules community pour les usages specifiques**
- `community.general.proxmox` : interaction avec l'API Proxmox pour les operations post-deploy
- `community.mysql` : gestion des bases de donnees et utilisateurs MariaDB
- `community.samba` : configuration Samba (avec limites, la majeure partie est geree par templates)
- `ansible.builtin.template` : generation de fichiers de configuration depuis des templates Jinja2

## Alternatives considerees

### Puppet (agent-based)

**Pour** :
- Tres utilise en entreprise pour la gestion de parc a grande echelle (> 100 noeuds).
- Puppet DSL est expressif pour les configurations complexes.
- Mode pull : les agents se synchronisent periodiquement sans intervention centrale.
- Catalogue Puppet applique en continu = correction automatique de la derive.

**Contre** :
- Necessite un Puppet Master (ou Puppet Enterprise) : infrastructure supplementaire a maintenir. Pour 10 VMs, c'est disproportionne.
- Courbe d'apprentissage elevee (Puppet DSL, modules Puppet, Hiera).
- Puppet n'est pas dans le referentiel AIS et moins present dans les offres d'emploi SMB en France que Ansible.
- Mode agent = daemon supplementaire sur chaque VM = surface d'attaque.
- La configuration initiale d'un master Puppet pour un lab de 10 VMs prend plus de temps que l'ecriture des playbooks Ansible equivalents.

### Salt (SaltStack)

**Pour** :
- Architecture master/minion avec communication bidirectionnelle (event-driven).
- Salt peut etre utilise en mode agentless (salt-ssh) similaire a Ansible.
- Performance superieure a Ansible pour les grands parcs (communication asynchrone via ZeroMQ).
- Jinja2 pour les templates (identique a Ansible).

**Contre** :
- Complexite de l'architecture Salt : master, minion, pillar, grains, reactor. Concept plus difficile a apprehender que les playbooks Ansible.
- Le mode salt-ssh (agentless) est moins performant que le mode master/minion et perd l'avantage de l'architecture Salt.
- Moins utilise en France que Ansible, competence moins valorisee dans les offres d'emploi cibles.
- Pour 10 VMs, l'overhead de Salt (daemon master, communication ZeroMQ) n'est pas justifie.

### Chef (agent-based)

**Pour** :
- Ruby DSL expressif pour les configurations complexes.
- Chef InSpec pour les verifications de conformite (tests d'infrastracture).

**Contre** :
- Ruby DSL = courbe d'apprentissage importante pour un profil non-developpeur.
- Architecture similaire a Puppet (Chef Server, Chef Workstation, Chef Agent) = infrastructure supplementaire.
- Chef a ete racheite par Progress Software en 2020. L'activite de la communaute open source a diminue.
- Tres peu utilise dans les environnements SMB et formation francais.

### Scripts shell manuels

**Pour** :
- Pas de dependance externe.
- Comprehensible par n'importe quel administrateur Linux.
- Pas de courbe d'apprentissage DSL.

**Contre** :
- Pas d'idempotence native : un script shell qui installe un paquet echoue silencieusement ou re-execute des operations si le paquet est deja installe, selon la gestion des erreurs.
- Pas de gestion des secrets (les mots de passe sont soit en clair dans les scripts, soit passes en variables d'environnement sans chiffrement persistent).
- Pas de versionnement structure des changements (diff d'un script shell est moins lisible qu'un diff d'un playbook YAML).
- Maintenance difficile a l'echelle : un changement de politique sshd necessite de modifier N scripts sur N VMs.
- Incoherent avec l'objectif IaC du projet et avec les criteres du portfolio.

### Cloud-init uniquement (pas d'outil de gestion post-deploy)

**Pour** :
- Cloud-init est deja utilise pour l'initialisation initiale des VMs (cle SSH, hostname, user).
- Une configuration cloud-config etendue pourrait couvrir l'installation des paquets et la creation des fichiers de configuration.

**Contre** :
- Cloud-init est execute une seule fois au premier boot. Il ne gere pas la derive de configuration (drift) : si un fichier est modifie manuellement apres le boot initial, cloud-init ne le detecte pas ni ne le corrige.
- Les modifications de configuration post-deploy (ajout d'une regle fail2ban, mise a jour d'une politique sshd) ne peuvent pas etre appliquees via cloud-init sans redemarrage de la VM.
- Cloud-init ne gere pas les secrets de facon robuste (les donnees user-data sont lisibles en clair sur le systeme apres le boot).

## Consequences

**Positives :**
- La configuration de chaque VM est entierement dans Git (`ansible/`). Un `git diff` montre exactement ce qui a change entre deux configurations.
- La reconstruction d'une VM depuis zero (destroy + terraform apply + ansible-playbook) est realisable en quelques minutes, ce qui simplifie les tests destructifs et les reinits apres une operation de lab ratee.
- L'idempotence permet d'executer `ansible-playbook site.yml` a tout moment pour detecter et corriger la derive de configuration.
- Les secrets sont chiffres dans Ansible Vault, versionnables et partageables (avec le mot de passe du vault separe).
- La structure modulaire (roles) permet de reutiliser les roles dans d'autres projets (portfolio).

**Negatives et risques residuels :**
- **Mode push = connectivite SSH requise** : Ansible necessite une connexion SSH a chaque VM pour executer les playbooks. Si le reseau est coupe (mauvaise config firewall), Ansible ne peut pas corriger la situation lui-meme. Necessite l'acces hors-bande via Tailscale ou console Proxmox.
- **Pas de correction automatique de la derive** : contrairement a Puppet ou Salt en mode pull, Ansible ne corrige pas automatiquement la derive de configuration. Un cron qui execute le playbook periodiquement peut pallier ce manque, mais n'est pas mis en place dans Nova Syndicate Phase II.
- **Versions Ansible** : les modules Ansible evoluent. Un playbook ecrit pour Ansible core 2.15 peut avoir des deprecations sur core 2.17+. Maintenance necessaire.
- **Python3 requis sur les VMs gerees** : Ansible necessite Python3 sur les hotes cibles. C'est standard sur Ubuntu 22.04 mais doit etre verifie sur d'autres distributions.
- **Secrets vault** : le mot de passe du vault Ansible est le secret critique. Sa perte rend tous les fichiers `vault.yml` inaccessibles. Conservation hors Git dans un gestionnaire de mots de passe externe (Bitwarden ou equivalent).

## References

- Documentation Ansible : https://docs.ansible.com/
- Collection community.general : https://docs.ansible.com/ansible/latest/collections/community/general/
- Ansible Vault : https://docs.ansible.com/ansible/latest/vault_guide/
- Structure des playbooks Nova Syndicate : `ansible/`
- Inventaire hosts : `ansible/inventory/hosts.yml`
- ADR-0015 (hardening custom role) : `docs/adr/ADR-0015-hardening-custom-role.md`
