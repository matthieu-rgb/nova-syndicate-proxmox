# ADR-0002 : Plan d'adressage VLAN avec VLSM

## Status
Accepted

## Date
2026-05-10

## Contexte

Le projet Nova Syndicate requiert une segmentation reseau en plusieurs zones de securite distinctes. Chaque zone correspond a un profil de trafic, un niveau de confiance et un nombre d'hotes previsible different. La conception du plan d'adressage precede toute configuration Terraform ou Ansible et conditionne l'ensemble de la matrice de flux firewall.

Les contraintes initiales du plan d'adressage :

- **Nombre de zones** : 6 VLANs minimaux identifies -- MGMT (administration), BASTION (acces entrant), SERVERS (serveurs internes), USERS (postes clients), DMZ Marseille (zone demi-militarisee site DR), BACKUP (trafic sauvegarde).
- **Espace d'adressage prive** : utilisation obligatoire de prefixes RFC 1918. L'espace 10.0.0.0/8 est retenu pour toute l'infrastructure afin de ne pas fragmenter l'espace de routage inter-site.
- **Realisme enterprise** : le choix des tailles de sous-reseaux doit refleter les besoins reels de chaque zone, pas un decoupage arbitraire en /24 uniformes.
- **Liaison inter-firewalls** : le segment transit entre FW-EXT-LYON et FW-INT-LYON doit etre minimal (2 hotes utiles suffisent).
- **Routage inter-site Lyon-Marseille** : les prefixes des sites ne doivent pas se chevaucher. L'espace Lyon est 10.0.0.0/16, l'espace Marseille est 10.1.0.0/16 (DR).
- **Prefixes IPsec** : chaque VLAN bridged via IPsec entre Lyon et Marseille necessite des plages non-overlapping pour les child SAs.

Le document de reference produit pendant la phase de conception est `docs/adressage_vlsm.md`.

## Decision

Adoption d'un plan VLSM (Variable Length Subnet Masking) avec des prefixes calibres par zone :

| VLAN | Nom | Prefixe | Masque | Hotes utiles | Justification taille |
|------|-----|---------|--------|--------------|----------------------|
| 10 | MGMT | 10.0.10.0/24 | /24 | 254 | Administration : outils de monitoring, agents Wazuh, acces Ansible, besoin d'espace pour evolution |
| 15 | BASTION | 10.0.15.0/29 | /29 | 6 | Un seul hote (bastion01) + adresses gateway. Taille minimale justifiee. |
| 20 | SERVERS | 10.0.20.0/28 | /28 | 14 | dc01, fs01, db01, app01 = 4 serveurs actuels, marge pour 10 serveurs futurs |
| 30 | USERS | 10.0.30.0/26 | /26 | 62 | VLAN clients : VMs de test, postes simules, besoin de place |
| 40 | DMZ-MRS | 10.1.40.0/28 | /28 | 14 | Zone DMZ site Marseille, symetrie avec SERVERS Lyon |
| 50 | BACKUP | 10.0.50.0/29 | /29 | 6 | backup01 uniquement + VPS Hetzner endpoint WireGuard |
| Transit | FW-EXT <-> FW-INT | 10.0.1.0/30 | /30 | 2 | Liaison point-a-point entre les deux firewalls |

La logique de choix des prefixes obeit aux regles suivantes :

1. **Le prefixe le plus court (MGMT /24)** est reserve a la zone de management car elle heberge des outils evolutifs (Wazuh agents, Prometheus exporters, Ansible controller) dont le nombre peut croitre.
2. **Les prefixes /29 (6 hotes)** sont utilises pour les zones a hote unique ou quasi-unique (BASTION, BACKUP). Cela reduit le blast radius en cas de compromission : la portee du segment est minimale.
3. **Le prefixe /28 (14 hotes)** pour SERVERS offre une marge raisonnable (4 serveurs deployes, 10 en reserve) sans gaspiller l'espace d'adressage.
4. **Le prefixe /26 (62 hotes)** pour USERS anticipe l'ajout de VMs clients pour les scenarii de tests (Active Directory, GPO, postes Windows).
5. **Le /30 de transit** est le pattern classique pour les liaisons point-a-point entre routeurs/firewalls : 2 adresses utiles, pas de broadcast superflu.

Les child SAs IPsec IKEv2 sont definies par paire de prefixes Lyon <-> Marseille pour chaque VLAN bridge, ce qui necessite que les plages soient non-chevauchantes entre sites (10.0.x.x pour Lyon, 10.1.x.x pour Marseille).

## Alternatives considerees

### Subnets /24 uniformes pour tous les VLANs

**Pour** :
- Simplicite extreme : chaque VLAN = un /24, facile a memoriser.
- Marge maximale pour l'expansion sans readdressing.
- Pas d'erreur de calcul de masque.

**Contre** :
- Gaspillage flagrant pour BASTION (1 hote reel dans un /24 = 253 adresses inutilisees).
- Ne reflecte pas la realite enterprise : les architectes reseau calibrent les subnets selon les besoins reels, pas par facilite.
- Reduire la taille des prefixes est une mesure de securite en soi : une ARP scan sur un /29 couvre 6 adresses, sur un /24 elle couvre 254. L'enumeration de la zone est plus rapide dans un sous-reseau plat.
- Incoherent avec l'objectif pedagogique de valider la maitrise du VLSM (requis dans le referentiel AIS).

### Microsegmentation en /30 pour tous les VLANs

**Pour** :
- Segmentation maximale : chaque lien = 2 hotes. Blast radius minimal absolu.
- Patterne utilise dans certaines architectures zero-trust extremes.

**Contre** :
- Impraticable pour USERS et MGMT qui ont besoin de multiple hotes dans le meme broadcast domain.
- Multiplication des sous-reseaux, de la configuration de routage et des regles firewall sans benefice proportionnel.
- Chaque ajout de VM dans SERVERS necessite un nouveau sous-reseau et une nouvelle route, rendant la maintenance excessive.
- Ne correspond pas au pattern enterprise standard pour les VLANs serveur.

### Adressage par classe (Class B, Class C)

**Pour** :
- Historiquement coherent avec les anciens designs reseau.
- Facile a comprendre pour des administrateurs formes avant l'ere CIDR.

**Contre** :
- L'adressage par classe est obsolete depuis RFC 1519 (CIDR, 1993). Son utilisation dans un projet 2026 serait une regression technique.
- Les classes ne correspondent pas aux besoins fonctionnels : une "Class C" pour BASTION (254 hotes) est surdimensionnee, une "Class C" pour USERS peut etre insuffisante si on simule plusieurs dizaines de postes.
- Ne satisfait pas les criteres d'evaluation du titre professionnel AIS.

## Consequences

**Positives :**
- La matrice de flux firewall est precisement delimitee par les prefixes. Les regles OPNsense referent des alias Terraform (`alias_mgmt_subnet`, `alias_servers_subnet`, etc.) definis depuis les variables Terraform, garantissant la coherence entre IaC et configuration firewall reelle.
- La lisibilite de la table de routage est amelioree : chaque prefixe designe sans ambiguite une zone fonctionnelle.
- La validation des child SAs IPsec est simplifiee : les prefixes locaux/distants sont clairement non-chevauchants.
- Le plan d'adressage est documente dans `docs/adressage_vlsm.md` et sert de reference unique, evitant les divergences entre Terraform, Ansible et la documentation.

**Negatives et risques residuels :**
- **Readdressing douloureux** : si SERVERS /28 atteint la limite de 14 hotes, un readdressing ou l'ajout d'un deuxieme subnet SERVERS implique des modifications dans Terraform, Ansible, les regles firewall et la config IPsec simultanement. Cout eleve.
- **Erreurs de masque** : la diversite des prefixes (/24, /28, /29, /26, /30) augmente le risque d'erreur de saisie dans les configurations. Mitigation : variables Terraform centralisees dans `variables.tf`, source unique de verite.
- **Documentation necessaire** : un /29 n'est pas intuitif pour un lecteur non familier avec le VLSM. La documentation `adressage_vlsm.md` est obligatoire pour que le plan reste comprehensible.
- **MGMT /24 disproportionne** : le choix d'un /24 pour MGMT alors que les autres zones sont optimisees cree une inconsistance visuelle. Justification retenue : MGMT est la zone la plus susceptible d'evoluer (ajout d'outils de monitoring, nouveaux agents).

## References

- Document de reference VLSM : `docs/adressage_vlsm.md`
- RFC 1519 - CIDR : https://www.rfc-editor.org/rfc/rfc1519
- Variables Terraform subnets : `terraform/environments/opnsense/variables.tf`
- Configuration IPsec child SAs : `terraform/environments/opnsense/ipsec.tf`
- ADR-0003 (architecture dual firewall) : `docs/adr/ADR-0003-architecture-dual-firewall.md`
- ADR-0005 (IPsec IKEv2) : `docs/adr/ADR-0005-ipsec-ikev2-site-to-site.md`
