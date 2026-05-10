# ADR-0005 : IPsec IKEv2 pour la liaison site-to-site Lyon-Marseille

## Status
Accepted

## Date
2026-05-10

## Contexte

Nova Syndicate est compose de deux sites logiques : Lyon (site principal, production) et Marseille (site DR/secondaire). La liaison entre les deux sites doit satisfaire les criteres suivants :

- **Chiffrement du trafic inter-site** : le trafic entre les VLANs Lyon et les VLANs Marseille doit etre protege en confidentialite et en integrite. Dans un environnement reel, les sites seraient relies via un reseau public (Internet ou MPLS mutualist). Dans le lab, les deux sites sont sur le meme hyperviseur Proxmox, mais l'architecture doit refleter la realite.
- **Multi-VLAN** : plusieurs VLANs Lyon doivent etre accessibles depuis Marseille (MGMT, SERVERS, BACKUP notamment). Une seule SA ne suffit pas si on veut un isolement cryptographique par zone.
- **Gestion IaC** : le tunnel doit etre provisionnable et configurable via Terraform (provider `browningluke/opnsense`).
- **Compatibilite interoperabilite** : IPsec IKEv2 est le standard de l'industrie pour les VPNs site-to-site enterprise. Utilise par les operateurs telecom, les fournisseurs cloud (AWS Site-to-Site VPN, Azure VPN Gateway), et les UTM enterprise (Palo Alto, Fortinet, Check Point).
- **Contexte NIS2** : la liaison inter-site transporte des donnees sensibles (replication AD, logs Wazuh, sauvegardes). Le chiffrement en transit est une exigence de l'Article 21 de la directive NIS2.

L'implementation OPNsense s'appuie sur **strongSwan** comme daemon IKE. IPsec IKEv2 est le mode recommande par strongSwan depuis la version 5.x (IKEv1 est maintenu pour compatibilite descendante uniquement).

## Decision

Adoption d'**IPsec IKEv2** avec **4 child SAs distinctes** (une par VLAN bridge) pour la liaison Lyon-Marseille.

**Architecture du tunnel :**

```
FW-EXT-LYON (10.0.1.1) <---[IKEv2 phase 1]---> FW-EXT-MRS (10.1.1.1)

Child SAs :
  SA-MGMT    : 10.0.10.0/24 <-> 10.1.10.0/24
  SA-SERVERS : 10.0.20.0/28 <-> 10.1.20.0/28
  SA-USERS   : 10.0.30.0/26 <-> 10.1.30.0/26
  SA-BACKUP  : 10.0.50.0/29 <-> 10.1.50.0/29
```

**Parametres cryptographiques phase 1 (IKE SA) :**
- Algorithme de chiffrement : AES-256-GCM (AEAD, pas de MAC separe)
- Algorithme d'integrite : SHA-512 (pour la derivation des cles, le HMAC est integre dans GCM)
- DH Group : 14 (MODP-2048 bits, acceptable) ou 19 (ECP-256) selon support OPNsense
- Duree de vie : 28800 secondes (8 heures, standard)
- Authentification : PSK (Pre-Shared Key)

**Parametres cryptographiques phase 2 (child SAs) :**
- Algorithme de chiffrement : AES-256-GCM
- PFS (Perfect Forward Secrecy) : active, DH Group 14
- Duree de vie : 3600 secondes (1 heure)

**Justification du choix PSK vs certificats :**
Dans un contexte lab, la gestion d'une PKI (CA, emission de certificats, renouvellement) ajoute une complexite significative sans apport pedagogique direct pour la partie VPN. La PSK est stockee dans Terraform via une variable sensible (`sensitive = true`) et dans le fichier `terraform.tfvars` exclu de Git (`.gitignore`). En production reelle, une PKI est obligatoire.

**Justification des 4 child SAs separees :**
Une child SA unique avec des selectors larges (0.0.0.0/0 <-> 0.0.0.0/0) regrouperait tout le trafic inter-site dans un seul tunnel chiffre. Le choix de 4 SAs separees est justifie par :
1. Isolation cryptographique par zone : si une SA est compromise (reuse de nonce, bug strongSwan), les autres zones ne sont pas impactees.
2. Controle granulaire du trafic autorise : chaque SA definit precisement quels prefixes peuvent communiquer.
3. Visibilite dans `ipsec statusall` : chaque VLAN est une SA identifiable, facilitant le troubleshooting.
4. Prerequis pour une future mise en place de QoS differentielle par zone.

## Alternatives considerees

### WireGuard pour la liaison site-to-site

**Pour** :
- Configuration plus simple que IPsec IKEv2 (fichiers courts, syntaxe epuree).
- Performance superieure : WireGuard fonctionne dans le kernel Linux, moindre overhead que strongSwan en userspace.
- Code base plus petite (~4000 lignes), donc surface d'attaque reduite.
- Gestion native des cles (Curve25519) sans PKI.

**Contre** :
- WireGuard n'est pas un standard de l'industrie pour les VPNs site-to-site enterprise. Les UTM enterprise (Palo Alto, Fortinet, Check Point, Cisco) utilisent tous IPsec IKEv2 pour les liaisons inter-sites.
- L'interoperabilite avec les equipements non-WireGuard (routeurs operateurs, AWS VPN, Azure VPN Gateway) est inexistante nativement. WireGuard ne peut pas negocier avec ces equipements.
- WireGuard ne supporte pas nativement les child SAs multiples avec des selectors de trafic precis. Un tunnel WireGuard transporte tout le trafic ou rien. Il faudrait multiplier les interfaces WireGuard pour obtenir l'equivalent des 4 child SAs.
- Dans le contexte formation AIS, demontrer la maitrise d'IPsec IKEv2 (standard de l'industrie) a plus de valeur que WireGuard pour la soutenance et le portfolio.

Note : WireGuard est utilise dans Nova Syndicate pour d'autres usages (tunnel backup cloud vers Hetzner, futur road-warrior) ou son profil de complexite simplifie et ses besoins (un seul pair, pas de multi-VLAN) sont adaptes. Voir ADR-0006.

### OpenVPN site-to-site

**Pour** :
- Tres documente, communaute large.
- TLS comme couche de transport, interoperabilite avec les clients logiciels OpenVPN.
- Supporte les configurations multi-site.

**Contre** :
- OpenVPN est oriente remote access (road-warrior) plus que site-to-site enterprise.
- Performance inferieure a IPsec IKEv2 : OpenVPN tourne en userspace et est single-threaded par defaut (mode tun). Le throughput se degrade sous charge.
- OpenVPN n'est pas supporte nativement par les equipements de connectivite cloud (AWS VPN, Azure VPN Gateway). La valeur portfolio d'une competence OpenVPN site-to-site est moindre que IPsec IKEv2.
- La configuration multi-VLAN avec OpenVPN (tap mode) est moins propre que les child SAs IPsec et necessite des bridges cotes serveur et client.
- Le provider `browningluke/opnsense` couvre IPsec de facon complete. La couverture OpenVPN est incomplete dans les versions actuelles.

### GRE over IPsec

**Pour** :
- Separation claire entre le transport (GRE) et la securisation (IPsec). GRE peut transporter des protocoles de routage dynamique (OSPF, BGP).
- Pattern courant dans les backbones d'operateurs.

**Contre** :
- Double encapsulation (GRE + IPsec) = overhead supplementaire.
- La configuration est plus complexe : deux couches a maintenir, deux points de defaillance potentiels.
- Dans Nova Syndicate, il n'y a pas de protocole de routage dynamique entre Lyon et Marseille. Le routage statique suffit. GRE n'apporte pas de valeur supplementaire.
- Pas couvert de facon stable par le provider Terraform OPNsense dans les versions utilisees.

### Simulation MPLS avec GNS3

**Pour** :
- Realiste pour simuler un lien WAN d'operateur.
- Valeur pedagogique pour les architectes reseau.

**Contre** :
- GNS3 a ete ecarte comme plateforme principale (ADR-0001). Integrer GNS3 comme composant MPLS alors que l'infrastructure principale est sur Proxmox/OPNsense introduit une dependance heterogene.
- MPLS n'est pas dans le perimetre du titre AIS ni du portfolio securite vise.
- La complexite d'administration (routeurs Cisco IOS virtuels, LDP, VRFs) est disproportionnee pour l'objectif.

## Consequences

**Positives :**
- La liaison Lyon-Marseille repond aux exigences de chiffrement en transit de NIS2 Article 21.
- La configuration IPsec est entierement dans Terraform (`terraform/environments/opnsense/ipsec.tf`), versionnee et reproductible.
- Les 4 child SAs donnent une visibilite fine sur quel VLAN est actif dans le tunnel (via `ipsec statusall` ou l'interface OPNsense).
- La competence IPsec IKEv2 est directement applicable dans les environnements enterprise et cloud (AWS Site-to-Site VPN utilise exactement la meme mecanique).
- PFS active garantit qu'une compromission de la cle de session courante ne compromet pas les sessions passees.

**Negatives et risques residuels :**
- **PSK en lab** : l'utilisation de PSK est une dette de securite acceptee pour le lab. En production, une PKI avec certificats et rotation automatique est obligatoire. Ce point est note comme dette dans la documentation.
- **Complexity de debugging** : IPsec IKEv2 avec 4 child SAs genere des logs volumineux dans strongSwan. Le troubleshooting d'un tunnel en echec necessite de comprendre les phases IKE, les proposals cryptographiques et les selectors de trafic. L'incident documente dans `docs/INCIDENT-IPSEC-RECOVERY.md` illustre cette complexite.
- **Rekey automatique** : la rekey des child SAs toutes les heures peut provoquer de breves interruptions du trafic inter-site si les deux pairs ne sont pas en accord sur les nouveaux parametres cryptographiques. Ce comportement a ete observe en lab.
- **AES-256-GCM overhead** : bien que negligeable sur des liens gigabit virtuels, la performance IPsec avec AES-256-GCM est moindre que WireGuard avec ChaCha20-Poly1305 sur des materiel sans AES-NI (ARM, CPU anciens). Pas d'impact sur les VMs Proxmox (CPU x86 avec AES-NI).
- Toute modification des parametres cryptographiques (ajout d'un VLAN, changement de DH group) necessite un `terraform apply` sur les deux firewalls et une recomposition du tunnel (downtime bref du lien inter-site).

## References

- RFC 7296 - Internet Key Exchange Protocol Version 2 (IKEv2) : https://www.rfc-editor.org/rfc/rfc7296
- strongSwan documentation : https://docs.strongswan.org/
- Provider OPNsense IPsec resources : https://registry.terraform.io/providers/browningluke/opnsense/latest/docs
- Fichier Terraform IPsec : `terraform/environments/opnsense/ipsec.tf`
- Runbook IPsec multi-VLAN : `docs/runbooks/runbook-ipsec-multi-vlan.md`
- Incident recovery log : `docs/INCIDENT-IPSEC-RECOVERY.md`
- ADR-0002 (plan adressage) : `docs/adr/ADR-0002-plan-adressage-vlan.md`
- ADR-0006 (WireGuard backup) : `docs/adr/ADR-0006-wireguard-backup-vpn.md`
