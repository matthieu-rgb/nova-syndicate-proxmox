# ADR-0003 : Architecture dual firewall avec zone de transit DMZ

## Status
Accepted

## Date
2026-05-10

## Contexte

La conception de la couche firewall de Nova Syndicate requiert un positionnement clair des appliances de securite par rapport aux zones reseau. Le premier constat est qu'un firewall unique, meme bien configure, presente des limites structurelles importantes dans une architecture orientee "defense en profondeur".

Les exigences identifies lors de la phase de conception :

- **Segmentation inter-zones** : le trafic entre la WAN (internet), la DMZ, les serveurs internes et le VLAN utilisateurs ne doit pas transiter par le meme plan de forwarding. Une compromission du firewall expose-t-il toutes les zones simultanement ?
- **Inspection differentielle** : les politiques de securite applicables au trafic WAN->DMZ different des politiques LAN->SERVERS. Un seul firewall peut gerer les deux, mais au prix d'une ruleset complexe et difficile a auditer.
- **Resilience aux erreurs de configuration** : une regle incorrecte sur un firewall unique peut ouvrir un acces direct WAN->SERVERS. L'architecture dual-firewall cree une deuxieme couche de validation.
- **Alignement avec les architectures d'entreprise documentees** : les references ANSSI (guide de definition d'une architecture de securite des SI, PA-022) et les architectures CIS Controls recommandent explicitement la separation des zones de confiance via des equipements distincts.
- **Contexte formation AIS** : l'examinateur de la soutenance attend une architecture qui demontre la comprehension des zones de securite, pas juste un firewall qui "marche".

L'infrastructure physique est hebergee sur Proxmox VE. Les firewalls sont des VMs OPNsense. Le cout de deploiement de deux firewalls virtuels versus un seul est marginal (ressources CPU/RAM, 2 vCPUs et 2 GB RAM par instance OPNsense).

## Decision

Adoption d'une **architecture dual firewall** avec segment de transit entre les deux appliances :

```
[WAN/Internet]
      |
  [FW-EXT-LYON]  -- interface WAN (DHCP public ou bridged)
      |            -- interface TRANSIT 10.0.1.1/30
  [10.0.1.0/30]  -- segment transit isolee
      |
  [FW-INT-LYON]  -- interface TRANSIT 10.0.1.2/30
      |            -- interface MGMT (10.0.10.0/24)
      |            -- interface BASTION (10.0.15.0/29)
      |            -- interface SERVERS (10.0.20.0/28)
      |            -- interface USERS (10.0.30.0/26)
      |            -- interface BACKUP (10.0.50.0/29)
```

**FW-EXT-LYON** a pour responsabilite exclusive :
- Terminer la connexion WAN
- Bloquer le trafic entrant non sollicite par defaut (deny all inbound)
- Autoriser uniquement les flux explicitement necessaires vers la DMZ et le bastion
- Gerer les tunnels IPsec IKEv2 vers le site Marseille (les tunnels se terminent sur FW-EXT)
- Filtrage anti-spoofing (uRPF)

**FW-INT-LYON** a pour responsabilite exclusive :
- Router le trafic entre les VLANs internes (MGMT, SERVERS, USERS, BACKUP)
- Appliquer les politiques inter-VLAN (USERS ne peut pas acceder directement a SERVERS sans passer par le bastion)
- Gerer les routes vers le segment de transit pour le trafic sortant

Le segment de transit **10.0.1.0/30** n'est accessible que depuis les deux firewalls. Aucune VM n'a une interface sur ce segment. Sa seule fonction est de transporter le trafic entre FW-EXT et FW-INT.

La justification principale de l'architecture duale est la **defense en profondeur** : un attaquant qui compromet FW-EXT (par exemple via une vulnerabilite de l'interface WAN d'OPNsense) se retrouve sur le segment de transit 10.0.1.0/30, pas sur le VLAN SERVERS. Il doit encore franchir FW-INT avec ses propres politiques.

## Alternatives considerees

### Firewall unique avec zones multiples (single-firewall multi-VLAN)

**Pour** :
- Simplicite operationnelle : une seule appliance a maintenir, une seule ruleset a auditer.
- Moindre consommation de ressources (une VM OPNsense au lieu de deux).
- Coherence : toutes les politiques au meme endroit, pas de split de configuration.
- Pattern courant dans les petites structures (PME, TPE).

**Contre** :
- Violation du principe de defense en profondeur : si la VM OPNsense est compromise (via une CVE non patchee sur l'interface web, par exemple), l'attaquant accede immediatement a tous les VLANs depuis la meme machine.
- Une erreur de configuration dans une regle (permit any any entre deux zones) est immediatement applicable a toutes les zones sans garde-fou.
- Moins representatif des architectures enterprise que l'on trouve dans les environnements que le diplome vise (Thales Luxembourg, contexte industriel).
- La matrice de flux inter-zone devient rapidement complexe dans un seul jeu de regles, augmentant le risque d'erreur humaine.

### pfSense + Suricata en mode IDS inline

**Pour** :
- pfSense est tres documente, communaute large.
- Suricata en mode IPS inline permettrait la detection et le blocage de patterns connus en plus du filtrage stateful.
- Un seul produit a maintenir.

**Contre** :
- Cette alternative a ete ecartee en meme temps que pfSense comme appliance principale (voir ADR-0004). Les raisons d'ecarter pfSense s'appliquent ici aussi.
- Un IPS inline sur le seul firewall cree un point de defaillance unique : si Suricata crashe ou genere des faux positifs massifs, la connexion reseau est interrompue.
- La maintenance de signatures Suricata dans un contexte lab est chronophage sans apport pedagogique direct sur l'architecture.

### Architecture three-tier avec DMZ intermediaire

**Pour** :
- Pattern classique des datacenters : [Internet] -> [FW externe] -> [DMZ] -> [FW interne] -> [LAN].
- Isolation optimale : les serveurs publics (web, mail) sont dans la DMZ, jamais en contact direct avec le LAN.

**Contre** :
- Nova Syndicate n'heberge pas de serveurs publics dans la DMZ Lyon. La DMZ est sur le site Marseille (zone DR/test). Une three-tier DMZ sur Lyon serait un artifice sans contenu fonctionnel.
- Trois firewalls virtuels consommeraient 6 vCPUs et 6 GB RAM sur un seul noeud Proxmox, au detriment des VMs applicatives.
- La complexite de maintenance (3 rulesets, 3 segments de transit) n'est pas justifiee par le nombre de services exposes.

### NGFWs virtuels (FortiGate-VM, Palo Alto VM-Series trial)

**Pour** :
- Fonctionnalites enterprise : DPI SSL, User-ID, App-ID, threat prevention.
- Valeur pedagogique elevee pour le portfolio (FortiGate est un standard de l'industrie).

**Contre** :
- FortiGate-VM trial limite : 1 vCPU, 2 GB RAM, pas d'API REST complete en mode eval.
- Palo Alto VM-Series necessite une licence (cout prohibitif).
- Ces solutions ne sont pas provisionables via Terraform dans un contexte lab sans environnement vCenter ou API specifique.
- L'objectif de l'IaC avec le provider `browningluke/opnsense` impose OPNsense. Deux firewalls differents (OPNsense + FortiGate) creeraient une heterogeneite non justifiee.

## Consequences

**Positives :**
- La defense en profondeur est implementee structurellement, pas seulement par configuration de regles.
- La separation des responsabilites entre FW-EXT (perimetre) et FW-INT (inter-VLAN) facilite l'audit des rulesets : chaque firewall a un domaine clair.
- Le segment de transit 10.0.1.0/30 est une zone inherente de l'architecture, visible dans Terraform et dans la documentation, ce qui facilite la comprehension lors de la soutenance.
- En cas de mise a jour majeure d'OPNsense, les deux appliances peuvent etre mises a jour sequentiellement avec un impact reduit (bascule du trafic sur FW-EXT pendant la mise a jour de FW-INT, par exemple).

**Negatives et risques residuels :**
- **Deux rulesets a maintenir** : toute nouvelle relation de flux doit potentiellement etre autorisee sur les deux firewalls. Risque d'incoherence si l'un des deux n'est pas mis a jour.
- **Trafic interne passe par deux sauts de routage** : USERS -> SERVERS implique FW-INT. SERVERS -> WAN implique FW-INT puis FW-EXT. Latence ajoutee (negligeable en pratique sur un LAN virtuel, quelques microsecondes).
- **Complexite operationnelle** : un technicien qui intervient sur le lab doit comprendre que le trafic traverse deux firewalls. Le troubleshooting reseau (tcpdump sur quel firewall ?) est plus complexe.
- **Point de defaillance du segment de transit** : si le segment 10.0.1.0/30 est mal configure (mauvaise IP, bridge manquant dans Proxmox), tout le trafic WAN est coupe. Ce scenario s'est produit pendant la phase de deploiement et est documente dans `docs/INCIDENT-IPSEC-RECOVERY.md`.
- Le cout en ressources Proxmox est double pour les firewalls, laissant moins de RAM disponible pour les VMs applicatives.

## References

- ANSSI - Guide d'architecture de securite des SI (PA-022) : https://www.ssi.gouv.fr/guide/architecture-de-securite/
- Configuration Terraform FW-EXT : `terraform/environments/opnsense/main.tf`
- Configuration Terraform FW-INT : `terraform/environments/opnsense/main.tf`
- Segment de transit : variable `transit_network` dans `variables.tf`
- Runbook incident segmentation : `docs/INCIDENT-IPSEC-RECOVERY.md`
- ADR-0004 (choix OPNsense) : `docs/adr/ADR-0004-opnsense-vs-pfsense.md`
- ADR-0002 (plan d'adressage) : `docs/adr/ADR-0002-plan-adressage-vlan.md`
