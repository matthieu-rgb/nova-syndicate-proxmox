# ADR-0010 : VPS Hetzner Helsinki pour le stockage hors-site

## Status
Accepted

## Date
2026-05-10

## Contexte

La strategie de sauvegarde 3-2-1-1-0 (ADR-0009) exige une copie hors-site geographiquement distincte du site principal (Lyon). Cette copie hors-site sert de dernier recours en cas de sinistre affectant l'infrastructure principale : incendie, inondation, vol du materiel, defaillance catastrophique du disque principal.

Les criteres de selection du fournisseur de stockage hors-site :

- **Cout** : le budget formation est contraint. Le cout mensuel doit etre minimal (objectif < 10 EUR/mois).
- **Capacite** : les archives Borg des 4 noeuds sauvegardes (dc01, fs01, db01, app01) avec deduplication et compression sont estimees a 5-15 GB selon la frequence et la duree de retention. Un disque de 40 GB est suffisant.
- **Localisation UE** : le RGPD (Reglement UE 2016/679) s'applique aux donnees personnelles traitees dans l'AD (comptes utilisateurs, groupes). Le stockage hors de l'UE implique des conditions supplementaires (adequation, clauses contractuelles types). Un hebergeur UE simplifie la conformite.
- **Connectivite** : le VPS doit accepter les connexions WireGuard (UDP/51820) et SSH (pour l'administration). L'IP publique doit etre fixe (pas de NAT externe).
- **Fiabilite** : l'uptime du VPS impacte directement la disponibilite des sauvegardes hors-site. Un SLA > 99.5% est acceptable.

Le VPS n'est pas un serveur applicatif critique : il heberge uniquement le daemon Borg en mode serveur, WireGuard et le monitoring minimal (Borg check). Un CX22 (2 vCPU, 4 GB RAM) est largement surdimensionne pour ce role mais est la configuration de base de Hetzner disponible au moment de l'inscription.

## Decision

Adoption d'un **VPS Hetzner Cloud CX22**, datacenter **Helsinki (Finlande, EU)**.

**Specifications retenues :**
- Instance : CX22 (2 vCPU AMD EPYC, 4 GB RAM, 40 GB SSD NVMe)
- OS : Ubuntu 22.04 LTS
- Bande passante : 20 TB inclus/mois
- Cout : ~5.32 EUR HT/mois (tarif 2026 Hetzner Cloud)
- Region : hel1 (Helsinki, Finlande)

**Justification du choix Helsinki vs Frankfurt (FSN1) ou Nuremberg (NBG1) :**

Helsinki est retenu pour sa distance geographique maximale par rapport au site principal (Saint-Avold/Lyon). En cas de sinistre regional affectant l'Europe de l'Ouest (scenarios extremes : panne de datacenter regional, catastrophe naturelle), la distance physique entre Lyon et Helsinki (~2000 km) renforce l'independance des copies. Frankfurt et Nuremberg sont a 400-600 km de Lyon, dans la meme zone regionale de risque potentielle.

**Justification Hetzner vs alternatives :**

Hetzner est l'un des rares hebergeurs cloud a offrir des VPS entierement situes dans l'UE avec la transparence sur la localisation des donnees requise par le RGPD. L'entreprise est allemande (Hetzner Online GmbH), soumise exclusivement au droit europeen, sans entite americaine. Le CLOUD Act americain ne s'applique pas.

Le rapport qualite/prix Hetzner est reconnu dans le secteur : un CX22 a 5 EUR/mois offre une performance similaire a une instance EC2 t3.small (~17 USD/mois chez AWS, sans le stockage supplementaire). Pour un usage uniquement sauvegarde, cette difference de cout est determinante.

**Configuration du VPS :**

La configuration du VPS est geree par le role Ansible `wireguard_server` et le role `borg_server`. Les taches deployees :
- Installation de `borgbackup` (>= 1.2)
- Installation de `wireguard-tools`
- Configuration du fichier `wg0.conf` via template Jinja2
- Ajout de la cle SSH de backup01 dans `~borg/.ssh/authorized_keys` avec `command="borg serve --append-only ..."` et l'option `restrict`
- Configuration de fail2ban sur le port SSH (22)
- Mise a jour automatique des paquets de securite (unattended-upgrades)

Le VPS est administrable uniquement via SSH (clef ED25519, root desactive, utilisateur `admin` avec `sudo`).

## Alternatives considerees

### OVHcloud (Roubaix, France)

**Pour** :
- Hebergeur europeen, donnees en France, conformite RGPD native.
- Gamme VPS Start a partir de ~4 EUR/mois (1 vCPU, 2 GB RAM, 20 GB SSD).
- Presente dans les appels d'offres publics francais (Cloud de confiance).

**Contre** :
- OVHcloud a subi un incendie majeur dans son datacenter SBG2 (Strasbourg) en mars 2021, detruisant plusieurs milliers de serveurs sans backup automatise. Cet incident a revele des lacunes dans la resilience des infrastructures OVHcloud pour certains clients.
- Les datacenters OVHcloud disponibles pour les VPS economiques sont Roubaix et Gravelines (France) ou Beauharnois (Canada). La localisation en France est pertinente du point de vue RGPD mais moins differenciante geographiquement pour le site Lyon.
- L'API OVHcloud pour les VPS est moins mature que l'API Hetzner pour l'automatisation Terraform. La gestion IaC du VPS est plus complexe.
- Meme gamme de prix apres comparaison equivalente (configuration proche de CX22).

### AWS S3 Glacier Instant Retrieval

**Pour** :
- Stockage objet immuable via S3 Object Lock (mode COMPLIANCE).
- Duree de retention configurable via les politiques S3.
- SLA 99.99% de disponibilite.
- Pas de serveur a gerer.

**Contre** :
- AWS est une societe americaine soumise au CLOUD Act. Les donnees dans S3 peuvent etre requises par les autorites americaines meme si stockees dans une region EU. Ce risque est theorique pour un lab de formation mais doit etre documente.
- Cout en egress (sortie de donnees) : 0.09 USD/GB pour la restauration depuis S3 Standard, moins depuis Glacier mais avec un delai de 1-5 minutes. Pour un sinistre ou une restauration d'urgence est necessaire, les frais d'egress peuvent etre significatifs.
- La complexite de la configuration S3 avec Object Lock, les politiques de lifecycle et les roles IAM est disproportionnee pour un lab de formation.
- La valeur pedagogique de S3 pour le titre AIS est moindre que la gestion d'un VPS Linux avec WireGuard et Borg.

### Backblaze B2

**Pour** :
- Stockage objet le moins cher du marche : 0.006 USD/GB/mois.
- Backblaze B2 Object Lock disponible (immuabilite WORM).
- Compatible avec l'ecosysteme restic et duplicati (S3-compatible API).

**Contre** :
- Backblaze est une societe americaine (San Mateo, Californie). Meme problematique CLOUD Act qu'AWS.
- Les datacenters Backblaze B2 sont principalement aux Etats-Unis. Backblaze propose maintenant des endpoints en Europe (Frankfurt, via Cloudflare), mais la souverainete des donnees reste questionnable.
- L'API S3-compatible de B2 ne supporte pas toutes les fonctionnalites S3 (certaines operations manquent). Des incompatibilites avec les clients S3 ont ete rapportees.
- Pas de VPS : uniquement stockage objet. Le scenario de tunnel WireGuard + Borg server ne s'applique pas. Il faudrait utiliser restic avec backend B2, ce qui change l'outil de sauvegarde (restic vs Borg, voir ADR-0008).

### Serveur domestique dedie (NAS a domicile)

**Pour** :
- Controle total des donnees, pas de fournisseur tiers.
- Cout marginal si le materiel existe deja.
- Acces rapide en cas de restauration.

**Contre** :
- Un NAS "a domicile" n'est pas une solution "hors-site" au sens strict si l'auteur habite sur le meme site que l'infrastructure principale (ce qui est le cas : Mac M4 Pro et serveur Proxmox a Saint-Avold).
- Dependance a la connexion Internet domestique (ADSL/VDSL asymetrique, bande passante montante limitee).
- Pas de SLA, pas de redondance d'alimentation, pas de systeme de climatisation.
- Risques physiques (incendie, vol) affectent les deux copies simultanement si le NAS est au meme endroit.

## Consequences

**Positives :**
- Le VPS Hetzner offre une independance totale de l'infrastructure principale : une defaillance complete du serveur Proxmox n'affecte pas les archives sur le VPS.
- La conformite RGPD est simplifiee : hebergeur allemand, datacenters en UE, aucun transfert hors-UE.
- La distance geographique (Lyon <-> Helsinki, ~2000 km) satisfait le critere "hors-site" de la strategie 3-2-1-1-0.
- Le cout est inferieur a 6 EUR/mois, compatible avec un budget formation.
- Le VPS est entierement gere par Ansible, reconstruisable en quelques minutes si necessaire (`ansible-playbook -l vps_hetzner site.yml`).

**Negatives et risques residuels :**
- **Dependance a un tiers** : une defaillance de Hetzner (coupure de datacenter, defaillance de l'instance) interrompt les sauvegardes hors-site. Hetzner a un historique fiable mais n'est pas immune aux incidents.
- **40 GB de disque** : la capacite du CX22 est de 40 GB. Si les archives Borg grossissent (augmentation du volume de donnees, ajout de noeuds sauvegardes), le disque peut se remplir. La supervision de l'utilisation du disque est necessaire (alerte a implementer via le monitoring Prometheus/Grafana ou simple script cron).
- **Pas de haute disponibilite du VPS** : le VPS est une instance unique. Une defaillance materielle chez Hetzner peut rendre le VPS indisponible temporairement. Hetzner propose la migration live des instances, mais pas la HA automatique pour les VPS Cloud.
- **Administration hors bande limitee** : si le VPS est inaccessible via SSH et WireGuard, Hetzner propose une console VNC via l'interface Cloud (Hetzner Cloud Console). Cela necessite un acces au compte Hetzner, dont les credentials sont dans le gestionnaire de mots de passe personnel.
- **Cout en cas d'egress massive** : les 20 TB inclus de bande passante sont largement suffisants pour les sauvegardes (quelques GB par mois). Mais en cas de restauration complete depuis le VPS (scenario DR), le transfert de 15-20 GB n'implique aucun surcoat dans ce cas.

## References

- Hetzner Cloud documentation : https://docs.hetzner.com/cloud/
- Hetzner Cloud pricing : https://www.hetzner.com/cloud/
- RGPD Article 46 (transferts hors UE) : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX%3A32016R0679
- Role Ansible VPS : `ansible/roles/wireguard_server/` et `ansible/roles/borg_server/`
- Log deploiement VPS : `docs/T-WG-SERVER-VPS-BACKUP-LOG.md`
- Runbook VPS WireGuard : `docs/runbooks/runbook-wireguard-vps.md`
- ADR-0008 (Borg) : `docs/adr/ADR-0008-borg-repokey-append-only.md`
- ADR-0009 (strategie 3-2-1-1-0) : `docs/adr/ADR-0009-strategie-backup-3-2-1-1-0.md`
