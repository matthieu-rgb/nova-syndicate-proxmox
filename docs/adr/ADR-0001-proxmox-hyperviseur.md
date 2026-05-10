# ADR-0001 : Choix de Proxmox VE comme hyperviseur principal

## Status
Accepted

## Date
2026-05-10

## Contexte

Le projet Nova Syndicate Phase II necessite un environnement de virtualisation capable d'heberger 14 VMs sur un seul serveur physique. Les contraintes sont les suivantes :

- **Materiel unique** : un seul serveur physique disponible pour le lab. Pas de cluster haute disponibilite envisageable dans ce contexte formation.
- **Objectif pedagogique** : la formation AIS (titre RNCP 37680 niveau 6) exige un environnement representatif d'une infrastructure d'entreprise reelle, avec segmentation reseau, firewalls, Active Directory, SIEM et plan de reprise.
- **IaC obligatoire** : toutes les ressources doivent etre provisionables via Terraform et Ansible pour satisfaire les exigences de reproductibilite et de documentation du portfolio.
- **Gestion de cycles de vie** : snapshots avant operations risquees, templates pour re-deploy rapide, consoles VM sans dependance SSH.
- **Couts** : budget formation, pas de licences commerciales.

La contrainte la plus structurante est l'existence d'un provider Terraform mature pour l'hyperviseur. Sans API REST stable et un provider Terraform documente, l'approche IaC est compromise.

L'architecture cible comprend : FW-EXT-LYON, FW-INT-LYON (OPNsense), dc01 (Active Directory), fs01 (Samba), db01 (MariaDB), app01 (Wazuh/Prometheus/Grafana), bastion01, backup01, et les equivalents Marseille pour le site DR.

## Decision

Adoption de **Proxmox VE 8.x** (licence AGPL, open source) comme hyperviseur principal.

Justifications techniques detaillees :

**1. Provider Terraform bpg/proxmox**
Le provider `bpg/proxmox` (anciennement `Telmate/proxmox`) est activement maintenu, couvre la gestion des VMs (`proxmox_virtual_environment_vm`), des templates cloud-init, des reseaux (`proxmox_virtual_environment_network`), des datastores et du pool de ressources. La version 0.x est stable en production. Aucun equivalent aussi mur n'existe pour KVM nu ou pour les alternatives open source examinees.

**2. API REST native**
Proxmox VE expose une API REST comprehensive (`/api2/json`) sans surcouche. Chaque operation UI est accessible via API. Cela permet d'instrumenter le lab avec des scripts de validation post-deploy et des checks Ansible via le module `community.general.proxmox`.

**3. Gestion des snapshots et templates**
Les snapshots QEMU avec sauvegarde de l'etat RAM sont natifs. Les templates cloud-init permettent de cloner une VM et de l'initialiser avec cloud-config en moins de 60 secondes. Cette capacite est critique pour le workflow : modifier un playbook Ansible, re-deploy la VM depuis le template, re-tester.

**4. VLANs et Linux bridges**
Proxmox supporte les Linux bridges avec VLAN awareness et les bonds. La configuration des interfaces reseau des VMs (virtio, E1000) est exposee via l'API et gerable via Terraform. La segmentation en 6 VLANs (MGMT/10, BASTION/15, SERVERS/20, USERS/30, DMZ/40, BACKUP/50) est implementable nativement sans surcharge logicielle.

**5. Acces console KVM**
La console `noVNC` et `SPICE` permettent d'acceder aux VMs meme quand le reseau est rompu (configuration incorrecte d'OPNsense, panne de routing). C'est indispensable dans un lab ou les erreurs de firewall sont frequentes.

**6. Pas de cout de licence**
Proxmox VE Community Edition est gratuit. L'abonnement support n'est pas necessaire pour un lab. La restriction est uniquement l'alerte a la connexion (`No valid subscription`), sans impact fonctionnel.

## Alternatives considerees

### KVM nu avec libvirt/virt-manager

**Pour** : controle total, pas de surcouche, performance maximale theorique, interface libvirt standard.

**Contre** :
- Absence de provider Terraform mature pour libvirt sur macOS (le provider `dmacvicar/libvirt` requiert que Terraform tourne sur l'hote KVM lui-meme ou via un socket libvirt expose, ce qui complexifie l'architecture IaC).
- Pas d'interface web centrale pour la gestion des VMs sans SSH.
- Gestion des templates laborieuse (qemu-img, virt-install, cloud-localds manuels).
- Pas de gestion native des snapshots avec etat RAM via UI.
- Cout en temps d'administration eleve sans gain fonctionnel pour l'objectif.

### VMware ESXi (free tier)

**Pour** : standard de l'industrie, ecosystem outils tres riche (PowerCLI, Terraform vsphere), bon support cloud-init via VMware tools ou open-vm-tools.

**Contre** :
- VMware ESXi free tier a ete retire par Broadcom en 2024. Les licences payantes (vSphere Foundation) commencent a plusieurs milliers d'euros.
- La version gratuite residuelle (hypervisor standalone) ne dispose pas d'API vCenter, rendant l'IaC Terraform impossible sans vCenter.
- Pas adapte a un budget lab/formation.
- L'acquisition par Broadcom cree une incertitude sur la perennite du produit dans les environnements SMB.

### GNS3

**Pour** : tres bien adapte aux labs reseau (Cisco IOS, OSPF, BGP, multi-vendor), partage de topologies `.gns3project`, integration avec Wireshark.

**Contre** :
- GNS3 est un simulateur reseau, pas un hyperviseur generaliste. Il peut heberger des VMs (via QEMU integre), mais la gestion de VMs Linux completes (Active Directory, Samba, MariaDB) est laborieuse et non prevue comme cas d'usage principal.
- Pas de provider Terraform. L'IaC sur GNS3 n'est pas un pattern etabli.
- Performance degradee pour les charges de travail non-reseau.
- L'auteur du projet avait un historique GNS3 (sessions precedentes) qui a revele ses limites pour les workloads server.
- Pas de snapshots QEMU natifs via l'interface GNS3.

### VirtualBox

**Pour** : cross-platform, gratuit, interface simple.

**Contre** :
- Pas d'API REST. Le provider Terraform `terra-farm/virtualbox` est abandonne et non maintenu.
- Performance reseau inferieure (adaptateurs NAT/bridged sans VLAN aware).
- Pas adapte a des charges de production-like (pas de virtio optimise par defaut, surcouche importante).
- Gestion des snapshots limitee et non scriptable proprement.

## Consequences

**Positives :**
- Provisionnement des 14 VMs entierement via Terraform (`bpg/proxmox`), permettant un `terraform destroy && terraform apply` pour reset complet du lab.
- Interface web Proxmox comme panneau de controle unifie : monitoring ressources, console VM, gestion snapshots.
- Cloud-init integration pour injection de cles SSH et configuration reseau au premier boot sans acces console.
- Base documentaire riche : la communaute Proxmox est large, les runbooks sont disponibles.

**Negatives et risques residuels :**
- Proxmox ne simule pas les equipements reseau constructeur (Cisco, Juniper). Pour les labs de routing avance, GNS3 reste pertinent en complement. Nova Syndicate se limite volontairement a OPNsense/Linux.
- Le provider `bpg/proxmox` evolue rapidement ; des breaking changes entre versions mineures ont ete observes (voir CHANGELOG). Epinglage strict de la version dans `versions.tf` necessaire.
- Proxmox VE est un produit allemand (Proxmox Server Solutions GmbH, Vienne). La roadmap est influencee par les besoins enterprise europeens, pas forcement aligne avec les patterns cloud-native.
- Un seul noeud physique = pas de HA. Une panne materielle arrete tout le lab. Acceptable pour un contexte formation, inacceptable en production.
- La console noVNC necessite l'ouverture du port 8006 depuis le poste de travail. Gere via Tailscale pour eviter l'exposition directe.

## References

- Documentation Proxmox VE 8 : https://pve.proxmox.com/pve-docs/
- Provider Terraform bpg/proxmox : https://registry.terraform.io/providers/bpg/proxmox/latest/docs
- Fichier Terraform principal : `terraform/environments/proxmox/main.tf`
- Fichier versions.tf : `terraform/environments/proxmox/versions.tf`
- Cloud-init configuration : `ansible/roles/common/templates/cloud-init/`
