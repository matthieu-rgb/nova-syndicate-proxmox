# ADR-0015 : Role hardening Ansible custom plutot qu'outillage CIS automatise

## Status
Accepted

## Date
2026-05-10

## Contexte

La conformite aux benchmarks CIS (Center for Internet Security) est une exigence implicite de la formation AIS et une demonstration attendue de la posture de securite de l'infrastructure. NIS2 Article 21 impose des mesures techniques proportionnees, dont le durcissement des systemes d'exploitation est une composante standard.

Deux approches existent pour implementer le durcissement :

**Approche 1 - Outillage automatise CIS** : utiliser des outils qui scannent l'etat du systeme et appliquent automatiquement les recommandations CIS (OpenSCAP, Lynis, ansible-lockdown, Chef InSpec). Ces outils evaluent des centaines de controles CIS et peuvent les appliquer en lot.

**Approche 2 - Role Ansible custom** : implementer manuellement les controles pertinents dans un role Ansible, en selectionnant les controles applicables au contexte et en les adaptant aux besoins specifiques de l'infrastructure.

Les contraintes du choix :

- **Comprehensibilite** : le role hardening doit etre lisible par un administrateur junior. Des centaines de taches generees automatiquement par un scanner sont difficiles a comprendre et a maintenir.
- **Adaptabilite** : certains controles CIS sont incompatibles avec l'environnement de lab (ex : desactiver tous les compilers, ce qui empeche l'installation de paquets via pip ; contraindre les ACL fichiers, ce qui peut casser Samba AD).
- **Perennite** : le role doit etre maintenable apres la formation, dans un contexte professionnel.
- **Demonstrabilite** : lors de la soutenance, l'examinateur doit pouvoir comprendre ce que fait le hardening en lisant le code, pas seulement constater que "l'outil a appliqué 300 controles".
- **Scope defini** : les VMs Nova Syndicate ont des roles specifiques (DC, bastion, backup). Le hardening doit etre adapte a chaque role, pas uniformement applique a toutes les VMs.

## Decision

Adoption d'un **role Ansible `hardening` custom** avec les caracteristiques suivantes :

**Perimetre du role (taches communes a toutes les VMs) :**

| Composant | Actions implementees |
|-----------|---------------------|
| sshd_config | PermitRootLogin no, PasswordAuthentication no, MaxAuthTries 3, AllowTcpForwarding no (sauf bastion), X11Forwarding no, ClientAliveInterval 300, UsePAM yes |
| nftables | Politique par defaut DROP sur INPUT et FORWARD. Regles explicites pour SSH (BASTION -> * ou localhost), ICMP, Wazuh agent (1514), etc. Extension via `hardening_extra_nft_rules` par hote. |
| fail2ban | Jail SSH avec maxretry=5, bantime=3600, findtime=600. Mode action = nftables-multiport. |
| auditd | Regles d'audit pour les syscalls critiques : execve, open, unlink, chmod, chown, setuid. Audit des modifications de fichiers /etc/passwd, /etc/sudoers, /etc/ssh/. |
| sysctl | kernel.dmesg_restrict=1, kernel.kptr_restrict=2, net.ipv4.conf.all.rp_filter=1, net.ipv4.conf.all.accept_redirects=0, net.ipv4.tcp_syncookies=1, vm.swappiness=10. |
| unattended-upgrades | Installation et activation des mises a jour de securite automatiques (packagess security uniquement). |
| GRUB hardening | apparmor=1 security=apparmor dans les parametres kernel GRUB (uniquement sur VMs non-DC). |

**Extension par hote (hardening_extra_nft_rules) :**

Le role expose une variable `hardening_extra_nft_rules` (liste de chaines nftables) que chaque hote peut surcharger dans `host_vars/`. Par exemple, db01 ajoute une regle pour le port MariaDB (3306) accessible uniquement depuis SERVERS :

```yaml
# host_vars/db01.yml
hardening_extra_nft_rules:
  - "tcp dport 3306 ip saddr 10.0.20.0/28 accept"
```

Cette approche evite d'avoir un role monolithique avec des conditionnels complexes (`when: inventory_hostname == 'db01'`) et permet a chaque equipe de contribuer les regles specifiques a son role.

**Structure du role :**

```
ansible/roles/hardening/
  tasks/
    main.yml        -- Orchestration (include des sous-taches)
    sshd.yml        -- Configuration sshd_config
    nftables.yml    -- Regles nftables
    fail2ban.yml    -- Configuration fail2ban
    auditd.yml      -- Regles auditd
    sysctl.yml      -- Parametres kernel
    upgrades.yml    -- Unattended-upgrades
  templates/
    nftables.conf.j2    -- Template nftables avec hardening_extra_nft_rules
    sshd_config.j2      -- Template sshd_config
    auditd.rules.j2     -- Regles auditd
  defaults/
    main.yml        -- Valeurs par defaut (hardening_extra_nft_rules: [])
  handlers/
    main.yml        -- Handlers (restart sshd, reload nftables, restart fail2ban)
```

**Choix de nftables plutot qu'iptables :**

nftables est le successeur d'iptables dans le kernel Linux 3.13+. Ubuntu 22.04 utilise nftables par defaut. La syntaxe nftables est plus claire (regles atomiques vs chaines iptables separees) et les performances sont superieures grace au JIT compiler kernel. Le role utilise exclusivement nftables, pas de compatibilite iptables maintenue.

## Alternatives considerees

### OpenSCAP avec profil CIS Ubuntu 22.04

**Pour** :
- OpenSCAP est l'outil de reference pour l'evaluation de conformite CIS/STIG. Il produit des rapports HTML/XML detailles avec le statut de chaque controle.
- Le profil CIS Ubuntu 22.04 Level 1 couvre plus de 200 controles bases sur les recommendations CIS Benchmark.
- Integration Ansible via le role `ansible.posix.sap` ou le module `openscap`.
- La production d'un rapport SCAP est une preuve de conformite acceptee par les auditeurs.

**Contre** :
- L'application automatique des remedations OpenSCAP (`oscap xccdf eval --remediate`) sur un systeme en production peut avoir des effets de bord non previsibles. Certaines remediations cassent des services specifiques (ex : renforcement des permissions /tmp qui casse certaines applications).
- Les profils CIS contiennent des centaines de controles dont certains sont incompatibles avec Nova Syndicate : controles lie a l'installation d'un seul service par VM, restrictions sur les compilateurs (incompatible avec les roles qui compilent des paquets), restrictions PAM incompatibles avec Samba AD.
- Un rapport SCAP avec 80% de conformite et 20% d'exceptions non justifiees est moins pertinent pedagogiquement qu'un role custom dont on connait et justifie chaque parametre.
- La comprehensibilite pour la soutenance est moindre : un examinateur qui voit un rapport SCAP de 200 pages est moins convaincu que par la lecture d'un role Ansible de 100 lignes bien commente.

### Lynis (audit + hardening recommendations)

**Pour** :
- Lynis est un outil d'audit de securite system leger (shell script), tres facile a utiliser.
- Produit un score de hardening et des recommandations specifiques.
- Utilisable en complement du role hardening pour verifier son efficacite.

**Contre** :
- Lynis est un outil d'audit (lecture seule par defaut), pas d'application de configuration. Il genere des recommandations mais ne les applique pas.
- Lynis suggereit l'installation de rootkit scanners (rkhunter, chkrootkit), de modules AppArmor specifiques, et d'autres outils qui ne sont pas pertinents pour le scope de ce projet.
- Sans remediation automatique, Lynis necessite un cycle manuel : audit -> liste de recommandations -> implementation manuelle -> re-audit. Cela n'est pas IaC.
- Lynis peut etre utile comme validation (verifier que le role hardening produit le resultat attendu), mais ne remplace pas le role.

Note : Lynis est utilise dans Nova Syndicate comme outil de validation post-deploy du role hardening, pas comme outil d'application. Ce n'est pas une alternative mais un complement.

### ansible-lockdown (role CIS Ubuntu 22.04)

**Pour** :
- Role Ansible community qui implementes le CIS Ubuntu 22.04 benchmark Level 1 et Level 2.
- Bien maintenu, tests CI, couverture large.
- Pas besoin de redevelopper les controles CIS : le role les implemente deja.

**Contre** :
- ansible-lockdown applique tous les controles CIS (Level 1 = ~200 controles, Level 2 = ~300 controles). Sur les VMs Nova Syndicate avec des roles specifiques, de nombreux controles seront en conflit avec le fonctionnement normal :
  - CIS 1.1.1 : "Ensure mounting of cramfs filesystems is disabled" -- pas d'impact sur les VMs, mais genere du bruit.
  - CIS 1.6.1 : "Ensure AppArmor is installed" -- OK, mais les profils AppArmor pour Samba AD ne sont pas standards.
  - CIS 5.4.2 : "Ensure lockout for failed password attempts is configured" -- OK via fail2ban, mais ansible-lockdown le fait via PAM, ce qui peut conflituer.
- La taille du role (plusieurs centaines de taches) le rend difficile a comprendre et a adapter.
- Le role ansible-lockdown ne supporte pas nativement les extensions par hote (equivalent de `hardening_extra_nft_rules`).
- L'objectif pedagogique (comprendre chaque controle) est mieux atteint avec un role custom qu'avec un role opaque de 300 taches.

### Chef InSpec pour la validation de conformite

**Pour** :
- InSpec permet d'ecrire des tests de conformite executables (assertions sur l'etat du systeme).
- Profils InSpec CIS disponibles pour Ubuntu.
- L'approche "infrastructure as tests" complementerait l'approche "infrastructure as code" Ansible.

**Contre** :
- InSpec est un outil de validation, pas d'application. Il ne configure pas les systemes.
- Ruby DSL pour les profils InSpec = courbe d'apprentissage supplementaire.
- Ajouter un outil Ruby (InSpec) dans un environnement deja Python (Ansible) et Go (Teleport futur) fragmente l'environnement d'outils.
- La valeur portfolio de la maitrise d'InSpec est reelle mais hors perimetre du titre AIS.

## Consequences

**Positives :**
- Le role `hardening` est comprehensible et modifiable par n'importe quel administrateur Ansible. Chaque parametre est justifiable lors d'un audit ou d'une soutenance.
- L'extension via `hardening_extra_nft_rules` permet d'adapter les regles firewall locales a chaque VM sans modifier le role central.
- Le role est idempotent : re-executable sans effet de bord apres la configuration initiale.
- Les modifications du hardening (ajout d'une regle auditd, modification d'un parametre sysctl) sont tracables dans Git.
- La separation sshd/nftables/fail2ban/auditd/sysctl en fichiers de taches distincts facilite la maintenance : une modification des regles fail2ban n'implique pas de re-lire les 200 taches de ansible-lockdown.

**Negatives et risques residuels :**
- **Couverture partielle du CIS benchmark** : le role custom couvre les controles les plus importants, pas l'integralite du CIS Ubuntu 22.04. Une evaluation OpenSCAP du role produirait un score de conformite partiel (estimatif : 60-70% des controles Level 1). Ce score est acceptable pour un lab de formation mais insuffisant pour une entite NIS2 reelle.
- **Maintenance a la charge de l'auteur** : contrairement a ansible-lockdown (maintenu par une communaute), le role custom necessite une mise a jour manuelle quand le CIS benchmark Ubuntu est revise (tous les 1-2 ans) ou quand Ubuntu sort une nouvelle LTS.
- **Tests unitaires absents** : le role n'a pas de tests Molecule (framework de test de roles Ansible). Un changement peut introduire une regression non detectable sans test infrastructure.
- **Risque de drift entre VMs** : si `hardening_extra_nft_rules` est mal configure sur un hote, les regles nftables peuvent diverger sans alerte. Un audit periodique (`ansible --check` ou Lynis) est necessaire.
- **nftables remplace iptables** : si un outil tiers (ex : Docker, LXC) ajoute des regles iptables, les regles nftables du role peuvent etre contournees ou generer des conflits. Nova Syndicate n'utilise pas Docker sur les VMs cibles, mais ce risque existe si le perimetre evolue.

## References

- CIS Ubuntu 22.04 Benchmark : https://www.cisecurity.org/benchmark/ubuntu_linux
- OpenSCAP : https://www.open-scap.org/
- ansible-lockdown CIS Ubuntu : https://github.com/ansible-lockdown/UBUNTU22-CIS
- nftables documentation : https://wiki.nftables.org/
- Role hardening : `ansible/roles/hardening/`
- Variables host-level : `ansible/inventory/host_vars/`
- ADR-0011 (Ansible) : `docs/adr/ADR-0011-ansible-iac-config-os.md`
- ADR-0013 (Wazuh pour NIS2) : `docs/adr/ADR-0013-wazuh-siem-nis2.md`
