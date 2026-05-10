# ADR-0014 : Bastion jumpbox avec Teleport planifie pour MFA et enregistrement de session

## Status
Accepted

## Date
2026-05-10

## Contexte

NIS2 Article 21 impose des mesures de controle des acces et d'audit des operations administratives. Dans Nova Syndicate, les acces SSH aux VMs internes constituent le principal vecteur d'administration. Sans point d'entree unique et controle, les risques sont :

- **Acces direct non trace** : si chaque administrateur peut se connecter directement a n'importe quelle VM via SSH, les connexions ne sont pas centralisees et l'audit est incomplet.
- **Surface d'attaque distribuee** : chaque VM avec SSH expose est une cible potentielle si une cle SSH est compromise.
- **Pas d'enforcement de MFA** : les cles SSH seules n'offrent pas la double authentification requise pour les acces privilegies.
- **Absence d'enregistrement de session** : en cas d'incident, il est impossible de reconstituer precisement ce qu'un administrateur a fait sur une VM si les sessions ne sont pas enregistrees.

La solution doit satisfaire deux etapes :

**Etape 1 (deploye)** : bastion01 comme point d'entree unique (ProxyJump SSH). Toutes les connexions aux VMs internes transitent par bastion01. Cela centralise le vecteur d'acces sans ajouter de complexite operationnelle majeure.

**Etape 2 (planifie, tache T-BASTION-TELEPORT)** : deploiement de Teleport 14 sur bastion01 pour ajouter MFA, enregistrement de sessions, et acces base sur des roles (RBAC).

Les deux etapes sont liees : la topologie ProxyJump mise en place a l'etape 1 est la fondation sur laquelle Teleport s'inserera a l'etape 2.

## Decision

**Etape 1 (implementee) : bastion01 comme ProxyJump obligatoire**

bastion01 est une VM dediee (VLAN BASTION, 10.0.15.x/29) dont le role est uniquement d'etre le point d'entree SSH vers toutes les VMs internes.

Configuration cote client SSH (`~/.ssh/config` sur le Mac M4 Pro) :
```
Host bastion01
  HostName 10.0.15.2
  User admin
  IdentityFile ~/.ssh/nova_syndicate_ed25519
  ProxyCommand ssh -W %h:%p proxmox-tailscale  # Acces via Tailscale si hors reseau

Host dc01
  HostName 10.0.20.2
  User admin
  ProxyJump bastion01

Host fs01
  HostName 10.0.20.3
  User admin
  ProxyJump bastion01
# ... idem pour toutes les VMs internes
```

Les regles OPNsense (FW-INT-LYON) interdisent les connexions SSH directes vers les VMs internes depuis n'importe quel VLAN autre que BASTION. Seul bastion01 (VLAN BASTION, 10.0.15.0/29) est autorise a initier des connexions SSH vers SERVERS.

Le runbook `docs/runbooks/runbook-bastion-internet.md` documente les procedures d'acces.

**Etape 2 (planifiee, T-BASTION-TELEPORT) : Teleport 14**

Teleport sera deploye sur bastion01 (mode single-node avec backend local). Les fonctionnalites visees :
- MFA TOTP obligatoire pour toutes les connexions SSH.
- Enregistrement complet des sessions (chaque commande tapee, chaque sortie affichee).
- RBAC : roles `admin` (acces tout), `readonly` (acces bastion01 seulement), etc.
- Audit log centralise (JSON, searchable dans le dashboard Teleport).

**Justification du ProxyJump vs alternatives plus complexes aujourd'hui :**

La tache T-BASTION-TELEPORT est dans le backlog mais pas encore completee. Le deploiement de Teleport 14 sur une VM existante en cours d'utilisation presente un risque : une mauvaise configuration peut couper tous les acces SSH aux VMs internes. Ce risque est acceptable dans un contexte de lab planifie avec une fenetre de maintenance, mais pas dans le calendrier immediat du projet Phase II.

La decision d'implementer d'abord le bastion SSH simple (etape 1) puis Teleport (etape 2) suit le principe de "incremental improvement" : l'etape 1 ameliore deja la posture de securite significativement (acces centralise, regle firewall inter-VLAN), et l'etape 2 pourra etre ajoutee sans refonte architecturale.

## Alternatives considerees

### Teleport deploye immediatement (sans etape intermediaire)

**Pour** :
- Une seule migration au lieu de deux.
- Pas de configuration SSH temporaire a maintenir.
- MFA et enregistrement de session disponibles des le debut du projet.

**Contre** :
- Le deploiement de Teleport 14 (meme en mode single-node) requiert une planification soigneuse : generation de certificats, configuration du proxy SSH, integration avec les agents sur chaque VM. Une erreur coupe tous les acces.
- La complexite de Teleport est significative : il n'est pas raisonnable de deployer Teleport en parallele du deploiement de l'ensemble de l'infrastructure (firewalls, AD, Wazuh, backup). La charge cognitive est trop elevee.
- Le planning de formation AIS impose un calendrier. L'etape 1 (bastion SSH) peut etre livree rapidement, l'etape 2 (Teleport) est dans le backlog avec une date cible post-soutenance.

### CyberArk Privileged Access Manager

**Pour** :
- Standard PAM de l'industrie dans les grands comptes.
- Fonctionnalites tres avancees : vault de credentials, session isolation, threat analytics.
- Valeur portfolio elevee si c'est l'outil cible de Thales Luxembourg.

**Contre** :
- CyberArk PAM est une solution enterprise onereuse (plusieurs milliers d'euros de licence annuelle).
- Infrastructure complexe : CyberArk necessite un Digital Vault, un PVWA, un PSM, un CPM -- quatre composants minimum, chacun avec ses propres requirements serveur.
- Inrealisable dans un lab avec les ressources disponibles.
- Teleport open source offre 80% des fonctionnalites de CyberArk pour 0 EUR de licence.

### VPN pour l'administration (acces via WireGuard road-warrior)

**Pour** :
- Si l'administrateur est connecte au VPN, il a acces directement aux VMs internes sans bastion.
- Simpler : pas de VM bastion a maintenir.

**Contre** :
- Un VPN donne acces a un segment reseau entier, pas a des systemes specifiques. Si la cle VPN est compromise, l'acces est large.
- Pas de point d'entree unique : les connexions SSH viennent du VLAN VPN, pas d'un bastion identifie. L'audit est moins precis.
- Pas de mecanisme d'enregistrement de session natif.
- NIS2 requiert des controles d'acces granulaires : un VPN seul ne suffit pas.
- L'approche VPN + bastion est plus robuste que VPN seul : le bastion centralise l'acces apres que le VPN a authentifie le client au niveau reseau.

### Pas de bastion, acces direct depuis MGMT VLAN

**Pour** :
- Simplicite maximale : les administrateurs se connectent directement aux VMs depuis le VLAN MGMT.
- Pas de VM supplementaire a maintenir.

**Contre** :
- Pas de point d'entree unique : chaque VM est une cible potentielle directe depuis le VLAN MGMT.
- Si le VLAN MGMT est compromis (ex : poste d'administration infecte), l'attaquant peut pivoter vers toutes les VMs.
- NIS2 requiert un controle des acces : l'absence de bastion rend difficile l'application de politiques d'acces differenciees par VM.
- Pas d'enregistrement de session possible sans agent supplementaire sur chaque VM.
- La valeur portfolio d'une architecture sans bastion est nulle pour le stage Thales Luxembourg.

## Consequences

**Positives (etape 1 implementee) :**
- Toutes les connexions SSH aux VMs internes transitent par bastion01. L'audit des connexions se reduit a l'audit des logs sshd de bastion01 et des regles firewall FW-INT.
- La regle firewall OPNsense (deny SSH depuis non-BASTION) reduit la surface d'attaque : une compromission d'une VM dans SERVERS n'ouvre pas d'acces SSH direct vers les autres VMs (seul bastion01 peut initier des connexions SSH inter-VMs).
- La configuration ProxyJump est transparente pour l'administrateur : `ssh dc01` via le `.ssh/config` etablit automatiquement la connexion via bastion01.

**Negatives et risques residuels (etape 1) :**
- **bastion01 = single point of failure** : si bastion01 est inaccessible (panne VM, mauvaise configuration réseau), tous les acces SSH aux VMs internes sont bloques. La console Proxmox (noVNC) reste disponible comme fallback, mais est moins pratique.
- **Pas de MFA en etape 1** : les connexions SSH via bastion01 utilisent uniquement les cles ED25519. NIS2 recommande l'authentification multifacteur pour les acces privilegies. Cette lacune est une dette documentee, couverte par T-BASTION-TELEPORT.
- **Pas d'enregistrement de session en etape 1** : les commandes executees sur les VMs internes via bastion01 ne sont pas enregistrees. Un incident sans enregistrement de session est plus difficile a investiguer.
- **T-BASTION-TELEPORT est dans le backlog** : le deploiement de Teleport reste une tache future. Si la soutenance AIS a lieu avant que Teleport soit deploye, l'enregistrement de session et le MFA sont absents du portfolio. Ce point doit etre documente comme "prevu mais non implementé" avec un plan clair.
- **Expansion de perimetre** : bastion01 est une VM dans le VLAN BASTION. Si bastion01 est compromise, l'attaquant a acces a toutes les VMs internes (via les cles SSH presentes sur bastion01 ou via les sessions ouvertes). Le hardening de bastion01 est critique.

**Dette techniques identifiees :**
- T-BASTION-TELEPORT : deploiement Teleport 14 (MFA + session recording)
- Rotation des cles SSH bastion01 : les cles authorisees sur bastion01 doivent etre auditees regulierement
- Audit log bastion : integration des logs SSH bastion01 dans Wazuh (partiellement implementee)

## References

- Teleport documentation : https://goteleport.com/docs/
- SSH ProxyJump documentation : https://man.openbsd.org/ssh_config#ProxyJump
- Runbook bastion : `docs/runbooks/runbook-bastion-internet.md`
- NIS2 Article 21 controle des acces : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX%3A32022L2555
- ADR-0007 (Tailscale admin) : `docs/adr/ADR-0007-tailscale-admin-perso.md`
- ADR-0013 (Wazuh SIEM) : `docs/adr/ADR-0013-wazuh-siem-nis2.md`
- Task T-BASTION-TELEPORT : `docs/PHASE-II-KANBAN.md`
