# ADR-0004 : Choix d'OPNsense comme appliance firewall

## Status
Accepted

## Date
2026-05-10

## Contexte

Le choix de l'appliance firewall/routeur est une decision fondatrice du projet Nova Syndicate. Il conditionne directement la faisabilite de l'approche IaC (Terraform), la qualite de l'API disponible et la maintenabilite a long terme. Deux contraintes majeures orientent cette decision :

**Contrainte IaC** : la configuration firewall doit etre entierement gerée par Terraform. Cela implique qu'un provider Terraform stable, documente et activement maintenu doit exister pour l'appliance choisie. Sans cette capacite, l'objectif "infrastructure reproductible via code" ne peut pas etre atteint pour la couche reseau.

**Contrainte pedagogique** : la formation AIS et le portfolio destine au stage Thales Luxembourg valorisent les technologies utilisees en contexte entreprise ou en croissance sur le marche. Les technologies marginales ou en declin ne sont pas pertinentes.

**Contexte technique** : les firewalls sont virtualises sur Proxmox VE (VMs OPNsense). L'hyperviseur est un serveur physique unique. Le cycle de vie des regles firewall (creation, modification, audit, rollback) doit etre tracable via Git.

Les fonctionnalites requises pour Nova Syndicate :
- Routage inter-VLAN (6 VLANs)
- IPsec IKEv2 multi-child-SA pour liaison Lyon-Marseille
- WireGuard pour tunnel backup cloud
- Gestion des aliases (alias_mgmt_subnet, alias_servers, etc.) via Terraform
- DHCP par VLAN
- Monitoring (interface graphique + API)

## Decision

Adoption d'**OPNsense** (version communaute, base FreeBSD 13.x, paquets HardenedBSD).

Justifications :

**1. Provider Terraform browningluke/opnsense v0.16**
C'est le critere determinant. Le provider `browningluke/opnsense` couvre en v0.16 :
- `opnsense_firewall_rule` : regles de filtrage avec source/destination/interface/protocole/logging
- `opnsense_firewall_alias` : aliases (hosts, networks, ports) references dans les regles
- `opnsense_route_static` : routes statiques
- `opnsense_ipsec_*` : tunnels IPsec (phase 1, phase 2/child SAs, propositions crypto)
- `opnsense_wireguard_*` : serveur WireGuard, peers
- `opnsense_dhcp_*` : pools DHCP par interface
- `opnsense_unbound_*` : DNS resolver Unbound

Ce niveau de couverture permet de gerer l'integralite de la configuration reseau via Terraform, sans recours a l'interface web ou a des scripts ad hoc. pfSense CE ne dispose pas d'equivalent (voir section Alternatives).

**2. API REST native et stable**
OPNsense expose une API REST accessible sur le port 443 (HTTPS) via des plugins modulaires. Chaque module (Firewall, IPsec, Interfaces, WireGuard) est un endpoint independant. L'API est documentee et versionnee. Le provider Terraform browningluke/opnsense repose exclusivement sur cette API.

**3. Developpement actif et transparent**
OPNsense est developpe par Deciso B.V. (Pays-Bas). Les releases sont bi-annuelles (janvier et juillet) avec un cycle predictible. Le changelog est detaille. Les CVE sont traites rapidement et documentees. L'heritage HardenedBSD (ASLR, SafeStack, PIE par defaut) ajoute une couche de mitigation au niveau OS.

**4. UI moderne et separee de la logique metier**
L'interface web OPNsense est construite en PHP avec un backend Python distinct. Cette separation facilite l'utilisation de l'API sans que l'interface web ne soit un goulot d'etranglement. Contrairement a pfSense CE dont l'interface est directement couplee a la generation de configuration, OPNsense conserve une coherence entre UI et API.

**5. Communaute et documentation**
La documentation officielle OPNsense est de bonne qualite pour les fonctionnalites utilisees dans ce projet (IPsec strongSwan, WireGuard kernel). Les forums Deciso et la communaute GitHub sont actifs.

## Alternatives considerees

### pfSense CE (Community Edition)

**Pour** :
- Base installee tres large (historiquement la reference open source pour les firewalls BSD).
- Tres bien documente, nombreux tutoriels, communaute abondante.
- Meme base technique qu'OPNsense (FreeBSD, pf firewall engine).

**Contre** :
- Pas de provider Terraform officiel ou communautaire equivalent a `browningluke/opnsense`. Le projet `marshallford/pfprovider` est en alpha, non maintenu, et ne couvre que les alias et les regles basiques. IPsec et WireGuard ne sont pas couverts. Cette lacune rend impossible l'IaC complete de la couche firewall, ce qui est la contrainte eliminatoire principale.
- Deciso (editeur d'OPNsense) a fork pfSense en 2015 precisement a cause de desaccords sur le modele open source. Depuis, pfSense CE a ete moins prioritaire que pfSense Plus (version commerciale) pour Netgate. Les fonctionnalites avancees sont de plus en plus reservees a pfSense Plus.
- L'interface pfSense est ancienn et directement couplee a la generation de config (PHP genere directement les fichiers de config). Cela limite la robustesse de l'API.
- pfSense Plus (version payante) pourrait offrir une meilleure API, mais implique un cout incompatible avec le budget lab.

### pfSense Plus

**Pour** :
- Maintenance active par Netgate.
- Fonctionnalites enterprise (HA, CARP, API etendue).

**Contre** :
- Payant. Netgate a mis fin a la licence gratuite pour usage "non-Netgate hardware" en 2022. L'utilisation sur VM Proxmox necessite une licence payante.
- Meme problematique que pfSense CE concernant l'absence de provider Terraform Terraform communautaire.

### VyOS (basé Linux/Debian)

**Pour** :
- Syntaxe de configuration proche de Juniper JunOS (valeur pedagogique pour les architectes reseau).
- API REST disponible dans VyOS 1.4+.
- Provider Terraform `wesmarcum/vyos` existe (coverage limitee).

**Contre** :
- La version LTS de VyOS est en rolling release payante pour les binaires pre-compiles. La compilation depuis les sources est possible mais chronophage et source d'instabilite en lab.
- Le provider Terraform `wesmarcum/vyos` couvre principalement les interfaces, routes et BGP. Il ne couvre pas nativement IPsec IKEv2 multi-child-SA ni WireGuard au niveau de detail requis.
- La courbe d'apprentissage de VyOS (syntaxe `set`, `commit`, `save`) est differente d'OPNsense et ajoute de la charge cognitive sans avantage net pour l'objectif du projet.
- VyOS est un routeur/firewall oriente CLI, moins adapte a la gestion via interface web dans un contexte formation ou la visibilite est importante pour la presentation.

### Mikrotik RouterOS (CHR - Cloud Hosted Router)

**Pour** :
- License CHR gratuite jusqu'a 1 Mbps (version free, utilisable en lab).
- Fonctionnalites tres riches : OSPF, BGP, MPLS, VPN multiples.
- API REST disponible (Mikrotik REST API depuis RouterOS 7).
- Provider Terraform `terraform-routeros/routeros` existe.

**Contre** :
- RouterOS 7 API REST est recente et le provider Terraform `terraform-routeros/routeros` ne couvre pas toutes les fonctionnalites avancees de facon stable.
- CHR free limite a 1 Mbps : impraticable pour les tests de performance et les transferts de sauvegarde Borg (qui peuvent depasser 100 Mbps en local).
- Mikrotik est moins present dans les architectures enterprise europeennes que dans les telcos et les MSPs d'Europe de l'Est. Valeur portfolio moins immediate pour le stage Thales.
- La licence payante CHR (P1 = 45 USD/an) est disproportionnee pour un lab de formation.

## Consequences

**Positives :**
- L'integralite de la configuration firewall est dans Git (`terraform/environments/opnsense/`). Chaque changement de regle est tracable, revertable, et reviewable.
- Le provider `browningluke/opnsense` genere un plan Terraform avant toute application, permettant de valider les changements avant leur deploiement en production.
- La coherence entre la configuration IaC et la configuration reelle est garantie par `terraform plan` : toute derive est detectable.
- OPNsense est utilise dans des contextes enterprise reels (Deciso propose du support commercial), ce qui renforce la valeur du portfolio.

**Negatives et risques residuels :**
- **Provider en version 0.x** : le provider `browningluke/opnsense` v0.16 est en phase de developpement actif. Des breaking changes entre versions mineures ont ete rencontres (notamment sur les resource types IPsec entre v0.14 et v0.16). L'epinglage de version dans `versions.tf` est obligatoire.
- **Dependance a un provider communautaire** : contrairement aux providers Hashicorp officiels (AWS, Azure, GCP), `browningluke/opnsense` est maintenu par un developpeur individuel. En cas d'abandon du projet, le maintien de l'IaC necessitera un fork.
- **Updates OPNsense peuvent casser l'API** : bien que l'API OPNsense soit relativement stable, des mises a jour majeures (passage de OPNsense 24.x a 25.x) peuvent modifier des endpoints. Necessite de tester les upgrades sur un snapshot avant application.
- **Courbe d'apprentissage API OPNsense** : le debugging des erreurs Terraform necessiten la comprehension des endpoints API OPNsense. Les messages d'erreur du provider sont parfois peu informatifs, necessitant un recours au curl direct sur l'API pour le troubleshooting.
- Le choix OPNsense verrouille sur la couche FreeBSD/HardenedBSD pour les firewalls. Les competences acquises sont partiellement transferables vers pfSense mais peu vers les firewalls Linux (nftables, iptables).

## References

- Provider Terraform browningluke/opnsense : https://registry.terraform.io/providers/browningluke/opnsense/latest/docs
- OPNsense API documentation : https://docs.opnsense.org/development/api.html
- OPNsense vs pfSense comparison (2024) : https://opnsense.org/opnsense-vs-pfsense/
- Fichiers Terraform OPNsense : `terraform/environments/opnsense/`
- ADR-0003 (dual firewall) : `docs/adr/ADR-0003-architecture-dual-firewall.md`
- ADR-0005 (IPsec IKEv2) : `docs/adr/ADR-0005-ipsec-ikev2-site-to-site.md`
- ADR-0012 (Terraform provider) : `docs/adr/ADR-0012-terraform-opnsense-browningluke.md`
