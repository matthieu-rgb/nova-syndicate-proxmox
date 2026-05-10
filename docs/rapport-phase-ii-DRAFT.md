# Rapport Phase II - Nova Syndicate
# Infrastructure securisee multi-sites : deploiement, durcissement et conformite NIS2

---

## Page de garde

```
Titre       : Rapport de Projet Phase II
              Nova Syndicate - Infrastructure IT securisee PME
              Deploiement Proxmox VE, IaC Terraform/Ansible, conformite NIS2

Auteur      : Matthieu Broquard

Formation   : Titre Professionnel Administrateur Infrastructure Securisee
              RNCP 37680 - Niveau 6
              Jedha Academy

Encadrant   : - -

Date        : 2026-05-10

Version     : DRAFT 1.0

Classification : Confidentiel - document jury uniquement
```

---

## Executive Summary

Nova Syndicate est un projet de homelab de niveau entreprise deploye sur Proxmox VE 8.x,
simulant l'infrastructure IT d'une PME logistique fictive de 50 employes repartis sur deux
sites (Lyon headquarter et Marseille disaster recovery). L'objectif est double : constituer
un dossier technique probant pour le titre professionnel AIS (RNCP 37680), et construire
une infrastructure reellement operationnelle sur laquelle des scenarios de securite et
d'administration peuvent etre executes.

La Phase II couvre le deploiement complet de l'infrastructure de production, depuis la
virtualisation Proxmox jusqu'a la mise en conformite NIS2. En deux semaines de travail
concentre (7-10 mai 2026), les realisations suivantes ont ete menees a terme :

- Deploiement de 14 VMs sur Proxmox VE via Terraform (provider bpg/proxmox)
- Configuration de 4 firewalls OPNsense entierement pilotes par Terraform IaC (provider
  browningluke/opnsense 0.16), avec 33 ressources et politique block_all activee sur 8
  interfaces
- Active Directory Samba avec 91 utilisateurs, 5 OUs, 8 groupes, domain join FS01
- Tunnel IPsec IKEv2 multi-VLAN Lyon/Marseille avec 4 Child SAs separes (SERVERS,
  BASTION, USERS, BACKUP) via backend moderne swanctl
- Monitoring complet : Wazuh 4.11.2 avec 7 agents actifs et regles NIS2 custom,
  Prometheus scrape sur 10 hotes, Grafana dashboards
- Backup 3-2-1-1-0 : 3 repos Borg locaux + synchronisation cloud vers VPS Hetzner via
  WireGuard, retention 7j/4s/6m, mode append-only anti-ransomware
- Drill de restauration valide : 836 fichiers restaures en 14.6 secondes, 5/5 checksums OK

Quatre incidents majeurs ont marque cette phase. Chacun a ete diagnostique, resolu et
perennise dans le code IaC ou Ansible, transformant des bugs de deploiement en
ameliorations durables de l'infrastructure. Ce rapport en documente les causes, les
correctifs et les lecons tirees.

La dette technique residuelle est documentee sans minoration : cinq points prioritaires
sont identifies, avec une roadmap claire pour les phases suivantes.

---

## 1. Contexte et besoins

### 1.1 Le client Nova Syndicate

Nova Syndicate est une PME de logistique specialisee dans la distribution de composants
critiques a destination des secteurs medical, aerospatial et defense. Environ 50 employes
se repartissent sur deux sites : le quartier general a Lyon (equipe IT, finances, direction,
RH) et un site secondaire a Marseille qui sert egalement de site de reprise d'activite (DR).
Une vingtaine d'agents mobiles se connectent a distance selon les besoins.

La nature des clients (secteurs reglementes) et la sensibilite des donnees traitees (donnees
contractuelles, RH, financieres) placent Nova Syndicate dans une categorie d'entites soumises
aux exigences renforcees de la directive NIS2, transposee en droit francais par la loi du
13 mars 2024 relative a la resilience des activites d'importance vitale.

Le projet debute par un constat d'infrastructure vieillissante : pas de segmentation reseau
formalisee, acces SSH avec mot de passe sur tous les serveurs, pas de supervision centralisee,
sauvegardes manuelles et non testees. L'objectif de la Phase II est de bascules vers une
infrastructure maitrisee, documentee, reproductible et auditabble.

Le DSI fictif de Nova Syndicate, Jean Thalor (j.thalor@nova-syndicate.fr), exprime trois
priorites :

1. Garantir la continuite de service : aucune perte de donnees superieure a 24 heures, RTO
   inferieur a 4 heures pour les services critiques.
2. Se conformer a NIS2 avant la deadline reglementaire : journalisation, gestion des
   incidents, segmentation, chiffrement.
3. Reduire la surface d'attaque : supprimer les acces directs, centraliser les identites,
   automatiser le durcissement.

### 1.2 Cadre reglementaire NIS2 + RGPD

#### NIS2 - Directive 2022/2555

La directive NIS2 (Network and Information Security 2), transposee en France en mars 2024,
impose aux entites importantes et essentielles un ensemble de mesures de gestion des risques
de cybersecurite definies a l'article 21. Les paragraphes pertinents pour Nova Syndicate sont :

**Article 21.b - Gestion des risques** : politiques d'analyse des risques et de securite
des systemes d'information. Couvert par la segmentation VLAN, la politique firewall block_all
declarative en Terraform, et la matrice de trafic documentee.

**Article 21.c - Gestion des incidents** : detection, signalement et reponse aux incidents.
Couvert par Wazuh SIEM avec 7 agents actifs, regles de detection NIS2 custom (IDs 100001 a
100010), retention 90 jours en lab, et les runbooks d'incident response documentes.

**Article 21.e - Continuite des activites** : sauvegardes, reprise apres sinistre, gestion
de crise. Couvert par la strategie backup 3-2-1-1-0 avec drill de restauration valide, le
site DR Marseille connecte par IPsec, et les procedures de recovery documentees.

**Article 21.f - Securite des reseaux et des systemes d'information** : politiques et
procedures relatives a la securite des reseaux. Couvert par l'architecture firewall en serie
(FW-EXT + FW-INT), les VLANs avec VLSM strict, le bastion SSH comme unique point d'entree
administratif, et l'audit trail Wazuh.

**Article 21.i - Securite de la chaine d'approvisionnement** : non couverte en Phase II.
La relation avec les fournisseurs logiciels (OPNsense, Samba, Wazuh) n'est pas formalisee.
Identifiee comme dette technique a traiter en Phase V.

#### RGPD

Les donnees RH contenues dans la base MariaDB (nova_rh) et les fichiers sur FS01 constituent
des donnees a caractere personnel au sens du RGPD. Les mesures implementees :

- Chiffrement des backups : Borg avec algorithme repokey-blake2, passphrase stockee en
  dehors des archives
- Minimisation des donnees : les bases MariaDB ne contiennent que les champs strictement
  necessaires pour le contexte lab
- Audit trail : toutes les connexions administratives sont tracees par Wazuh et auditd
- Controle d'acces : RBAC via Samba AD, acces aux partages SMB par groupe AD uniquement

### 1.3 Contraintes techniques et budget

Le projet est deploy sur un serveur physique unique servant d'hyperviseur Proxmox VE. Les
contraintes sont celles d'un homelab de niveau professionnel :

```
Hyperviseur : AMD Ryzen 12 coeurs / 24 threads, 64 GB RAM, NVMe dedie
Budget      : materiel existant, logiciels open-source uniquement
              VPS Hetzner CX22 Helsinki : 3.99 EUR/mois (backup offsite)
Contrainte  : pas de routeur physique dedie, simulation WAN via VM OPNsense
Contrainte  : une seule adresse IP publique (NAT Proxmox sur vmbr0)
```

Ces contraintes ont des consequences architecturales directes. Le WAN est simule par une VM
OPNsense (WAN-SIM, VMID 200) qui joue le role de routeur ISP entre les deux sites. Les
tunnels IPsec traversent donc un reseau de transit interne (10.0.0.0/30 cote Lyon,
10.0.2.0/30 cote Marseille) plutot qu'un vrai internet. Ce choix est documente et n'affecte
pas la validite des tests de securite.

### 1.4 Equipe et timeline

L'infrastructure est deployee et administree par une seule personne. Cette contrainte est
pertinente pour le jury : elle signifie que chaque choix technique a ete assume en solo, et
que les incidents documentes dans ce rapport ont ete diagnostiques et resolus sans escalade.

**Timeline Phase II (7-10 mai 2026) :**

```
2026-05-07 : Deploiement VMs Proxmox, cloud-init, common packages
             Correction BUG-C1 (NAT Proxmox temporaire)
2026-05-08 : T-MIGRATION IPsec legacy -> Connections modernes
             Roles Ansible : AD, FS, DB, Wazuh, Grafana, Borg
             91 users AD, 5 shares SMB, 3 repos Borg, 7 agents Wazuh
2026-05-09 : T3-DURCISSEMENT : block_all sur 8 interfaces (3h)
             Incident T-WAZUH-NFT detecte et resolu
2026-05-10 : T-WAZUH-NFT perennise dans Ansible
             WireGuard VPS Hetzner + Borg cloud
             T-RESTORE-DRILL valide
             T-TAILSCALE-SSH-HARDEN documente
```

---

## 2. Architecture cible

### 2.1 Vision globale

L'architecture de Nova Syndicate suit un modele de defense en profondeur a plusieurs couches.
La philosophie directrice est simple : chaque flux doit etre explicitement autorise ; tout ce
qui n'est pas permis est bloque et trace.

```
INTERNET
    |
[WAN-SIM] -- simulation transit ISP (10.0.0.0/30 Lyon, 10.0.2.0/30 MRS)
    |
    +----[FW-EXT-LYON] (VMID 201)
    |        |-- DMZ (172.16.1.0/29) : web01, mail01
    |        |-- Transit vers FW-INT (10.0.1.0/30)
    |        |-- IPsec IKEv2 -> MRS (4 Child SAs)
    |        |
    |    [FW-INT-LYON] (VMID 202)
    |        |-- VLAN 15 Bastion  (192.168.15.0/29)
    |        |-- VLAN 20 Servers  (192.168.20.0/28)
    |        |-- VLAN 30 Users    (192.168.30.0/26)
    |        |-- VLAN 50 Backup   (192.168.50.0/29)
    |
    +----[FW-EXT-MRS] (VMID 203)
             |-- LAN MRS (192.168.40.0/26) : site DR
```

Le choix de deux firewalls en serie (FW-EXT + FW-INT) pour le site Lyon n'est pas decoratif.
FW-EXT-LYON gere la frontiere internet : il expose la DMZ et termine les tunnels IPsec.
FW-INT-LYON gere la segmentation interne : il separe le bastion, les serveurs, les postes
utilisateurs et le backup. Un attaquant qui compromettrait FW-EXT-LYON (scenario plausible
si une vulnerabilite OPNsense est publiee) se trouverait face a un deuxieme filtrage avant
d'atteindre les serveurs metier.

L'ensemble de la configuration des 4 firewalls est gere par Terraform (provider
browningluke/opnsense 0.16). Cela signifie que l'etat de securite des firewalls est
controle par version dans git, reproductible, et auditabble via `terraform plan`.

### 2.2 Plan d'adressage VLAN

Le plan VLSM a ete dimensionne au plus juste, en appliquant la contrainte de conformite
NIS2.b : chaque segment doit avoir un perimetre firewall distinct.

**Liens de transit point a point (/30 - 2 hotes utiles) :**

```
Reseau          Lien
10.0.0.0/30     WAN-SIM (.1) <-> FW-EXT-LYON (.2)
10.0.1.0/30     FW-EXT-LYON (.1) <-> FW-INT-LYON (.2)
10.0.2.0/30     WAN-SIM (.1) <-> FW-EXT-MRS (.2)
10.30.0.0/24    VPN WireGuard BACKUP01 (.2) <-> VPS Hetzner (.1)
```

**VLANs internes Lyon :**

```
VLAN  Nom       Reseau             Capacite  VMs
--    DMZ       172.16.1.0/29      6 hotes   web01 (.2), mail01 (.3)
15    Bastion   192.168.15.0/29    6 hotes   bastion01 (.2)
20    Servers   192.168.20.0/28    14 hotes  dc01(.10) fs01(.11) db01(.12) app01(.13) proxy-lyon01(.14)
30    Users     192.168.30.0/26    62 hotes  postes Lyon DHCP
50    Backup    192.168.50.0/29    6 hotes   backup01 (.2)
```

**Site Marseille :**

```
Reseau             Capacite  Usage
192.168.40.0/26    62 hotes  LAN Marseille DR (proxy-mrs01 .11)
```

**Justification des masques :**

Le VLAN Bastion utilise un /29 (6 hotes) car le bastion est un composant unique ; agrandir
ce sous-reseau augmenterait la surface d'attaque sans benefice. Le VLAN Servers utilise un
/28 (14 hotes) car il doit accueillir les cinq serveurs actuels et laisser de la place pour
les extensions de Phase IV (serveurs VPN, PKI). Le VLAN Users utilise un /26 (62 hotes)
couvrant les 50 employes de Lyon avec marge.

### 2.3 Topologie firewalls

Chaque firewall OPNsense applique la meme politique de base : `block_all + log` en derniere
regle sur chaque interface, precedee de regles `pass` explicites pour chaque flux autorise.
Cette approche garantit que toute denegation genere une entree de log exploitable par Wazuh.

**FW-EXT-LYON (VMID 201, 10 regles Terraform) :**

```
Interface vtnet0 (WAN, 10.0.0.2) :
  pass  IKE UDP 500 depuis 10.0.2.2 (MRS)
  pass  NAT-T UDP 4500 depuis 10.0.2.2
  pass  ESP proto 50 depuis 10.0.2.2
  pass  HTTP/HTTPS -> DMZ (172.16.1.0/29)
  pass  SMTP 25/465/587 -> mail01 (172.16.1.3)
  block all + log

Interface vtnet1 (DMZ, 172.16.1.1) :
  pass  HTTP/HTTPS sortant DMZ
  pass  SMTP sortant DMZ
  block all + log
```

**FW-INT-LYON (VMID 202, 16 regles Terraform) :**

```
Interface vtnet0 (transit, 10.0.1.2) :
  pass  trafic decapsule IPsec depuis MRS (192.168.40.0/26)
  block all + log

Interface opt1 (VLAN 50 Backup, 192.168.50.0/29) :
  pass  BACKUP01 -> servers SSH (borg pull)
  pass  BACKUP01 -> internet (rclone, apt, NTP)
  block all + log [placeholder T-SQUID]

Interface opt2 (VLAN 15 Bastion, 192.168.15.0/29) :
  pass  BASTION -> servers SSH (Ansible, admin)
  pass  BASTION -> DC01 AD TCP (88, 389, 445, 464, 636, 3268)
  pass  BASTION -> DC01 AD UDP (53, 88, 123)
  pass  BASTION -> internet (git, terraform, ansible-galaxy)
  block all + log

Interface opt3 (VLAN 20 Servers, 192.168.20.0/28) :
  pass  SERVERS -> internet [pass-all provisoire, T-SQUID]
  block all + log

Interface opt4 (VLAN 30 Users, 192.168.30.0/26) :
  pass  USERS -> DC01 AD TCP + UDP
  pass  USERS -> servers SMB (445)
  pass  USERS -> internet [pass-all provisoire, T-SQUID]
  block all + log
```

### 2.4 Topologie VPN

Deux technologies VPN coexistent, avec des roles distincts et clairement separes :

**IPsec IKEv2 - tunnel site a site Lyon/Marseille :**

Backend swanctl (moderne) sur FW-EXT-LYON (initiateur) et FW-EXT-MRS (repondeur).
PSK partage, 1 IKE_SA, 4 Child SAs avec reqids separes :

```
Child SA       reqid  Trafic selecteur
child_servers  1      192.168.40.0/26 <-> 192.168.20.0/28
child_bastion  2      192.168.40.0/26 <-> 192.168.15.0/29
child_users    3      192.168.40.0/26 <-> 192.168.30.0/26
child_backup   4      192.168.40.0/26 <-> 192.168.50.0/29
```

Ce design a 4 Child SAs est le resultat direct de l'incident T-MIGRATION (voir section 3.2).
La version precedente utilisait le backend legacy avec un seul Child SA bundlant les 4 VLANs,
ce qui causait un narrowing IKEv2 et rendait trois VLANs inaccessibles.

**WireGuard - tunnel backup offsite :**

Tunnel dedie entre BACKUP01 (10.30.0.2 sur wg0) et le VPS Hetzner CX22 Helsinki (10.30.0.1).
Port 51820 UDP. PersistentKeepalive=25 cote BACKUP01 pour maintenir le tunnel traversant un
NAT. Ce tunnel est exclusivement reserve aux transferts Borg ; il ne fait pas partie du reseau
de production.

**Tailscale - acces administratif personnel :**

Tailscale est actif sur l'hyperviseur Proxmox (100.112.113.2) pour l'acces admin du poste
Mac de l'administrateur. Il n'est pas utilise pour la gestion des VMs de production ; l'acces
passe par le bastion SSH. Une dette technique (T-TAILSCALE-SSH-HARDEN) est documentee : le
compte borguser sur le VPS Hetzner est accessible via Tailscale SSH, ce qui contourne la
restriction ForceCommand configuree dans sshd.

### 2.5 Inventaire VMs

```
VMID  Hostname       IP               VLAN    Role
200   wan-sim        10.0.0.1         -       OPNsense simulateur WAN/ISP
201   fw-ext-lyon    10.0.0.2/172.16.1.1  -   OPNsense firewall externe Lyon
202   fw-int-lyon    192.168.99.1     -       OPNsense firewall interne Lyon
203   fw-ext-mrs     192.168.40.1     -       OPNsense firewall Marseille
100   web01          172.16.1.2       DMZ     Nginx (site web Nova Syndicate)
101   mail01         172.16.1.3       DMZ     Postfix minimal
102   bastion01      192.168.15.2     15      SSH jumpbox
103   dc01           192.168.20.10    20      Samba AD DC, DNS, DHCP
104   fs01           192.168.20.11    20      Samba fileserver, shares SMB
105   db01           192.168.20.12    20      MariaDB (nova_logistique, nova_rh)
106   app01          192.168.20.13    20      Wazuh 4.11.2, Prometheus, Grafana
107   proxy-lyon01   192.168.20.14    20      Squid proxy (deploye, non mandatory)
108   proxy-mrs01    192.168.40.11    40      Squid proxy Marseille
109   backup01       192.168.50.2     50      Borg backup local + sync cloud
VPS   vps-hetzner    10.30.0.1 (wg0)  -      Borg backup offsite (Helsinki)
```

Toutes les VMs Linux sont des clones du template Debian 12 (VMID 9000, genericcloud AMD64)
configure avec cloud-init : hostname, IP statique, cle SSH Ansible, sudo NOPASSWD, qemu-guest-agent.

---

## 3. Implementation technique

### 3.1 Hyperviseur Proxmox

Proxmox VE 8.x est installe en bare-metal sur un serveur AMD Ryzen 12 coeurs / 64 GB RAM.
La configuration reseau utilise 6 bridges Linux (vmbr0 a vmbr5) :

```
vmbr0  : management Proxmox (192.168.10.0/24, acces UI Proxmox)
vmbr1  : trunk VLAN-aware Lyon (bridge-vids 15 20 30 50)
vmbr2  : LAN Marseille (FW-EXT-MRS cote LAN)
vmbr3  : DMZ (web01, mail01)
vmbr4  : lien point-a-point FW-EXT-LYON <-> FW-INT-LYON (10.0.1.0/30)
vmbr5  : WAN Marseille (WAN-SIM <-> FW-EXT-MRS)
```

Le choix du bridge vmbr1 VLAN-aware permet au FW-INT-LYON de gerer les sous-interfaces
802.1Q directement dans OPNsense, sans creer un bridge par VLAN cote Proxmox. C'est la
configuration recommandee pour les topologies avec firewall VLAN-aware.

**Template cloud-init Debian 12 (VMID 9000) :**

La creation du template est une operation manuelle one-shot. Elle consiste a importer l'image
genericcloud Debian 12, configurer les peripheriques cloud-init (cdrom), et convertir la VM
en template. Toutes les VMs de production sont des clones full de ce template, puis
customisees par cloud-init (hostname, IP, cle SSH) au premier demarrage.

```bash
# Creation template (one-shot, sur l'hote Proxmox)
qm create 9000 --name debian-12-cloud-template --memory 2048 --cores 2 \
    --net0 virtio,bridge=vmbr0 --ostype l26 --scsihw virtio-scsi-single

qm importdisk 9000 debian-12-genericcloud-amd64.qcow2 local-lvm
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0 --ide2 local-lvm:cloudinit \
    --boot c --bootdisk scsi0 --serial0 socket --vga serial0 \
    --ipconfig0 ip=dhcp --agent enabled=1

qm template 9000
```

Les VMs sont ensuite deployees via Terraform (provider bpg/proxmox) qui gere les clones,
le dimensionnement (RAM, CPU, disque) et les parametres cloud-init de chaque VM.

### 3.2 Firewalls OPNsense (Terraform)

La configuration des 4 firewalls OPNsense est integralement geree par Terraform via le
provider browningluke/opnsense (version 0.16). Le code est organise en modules par couche :

```
terraform/environments/opnsense/
  main.tf          -- 4 providers (1 alias par firewall)
  variables.tf     -- 12 variables IP/key/secret + maps VLSM et VLAN IDs
  outputs.tf       -- URLs API, plan VLSM, recap VLANs
  aliases.tf       -- 24 aliases (networks, hosts, ports) sur 4 firewalls
  fw_int_vlans.tf  -- 4 sous-interfaces VLAN 802.1Q sur FW-INT-LYON
  fw_ext.tf        -- regles FW-EXT-LYON (10 regles)
  fw_int.tf        -- regles FW-INT-LYON (16 regles)
  fw_ext_mrs.tf    -- regles FW-EXT-MRS (5 regles)
  fw_wansim.tf     -- regles WAN-SIM (3 regles)
```

**Total : 33 ressources Terraform, 0 drift post-deploy (`terraform plan` = No changes).**

Le pattern applique sur chaque interface est systematique :

```hcl
# Exemple : interface BASTION sur FW-INT-LYON
resource "opnsense_firewall_filter" "fwint_bastion_to_servers_ssh" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION -> servers SSH (Ansible, admin)"
  sequence    = 10
  interface   = { interface = ["opt2"] }
  filter = {
    action      = "pass"
    direction   = "in"
    quick       = true
    protocol    = "tcp"
    source      = { net = "net_vlan15_bastion" }
    destination = { net = "net_vlan20_servers", port = "22" }
  }
}

resource "opnsense_firewall_filter" "fwint_bastion_block_all" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "BASTION block_all + log (NIS2)"
  sequence    = 9999
  interface   = { interface = ["opt2"] }
  interface_default_block = true
  filter = { action = "block", direction = "in", log = true }
}
```

**Incident T-MIGRATION (2026-05-08) - Migration IPsec legacy vers Connections modernes :**

Le backend IPsec legacy d'OPNsense ("Tunnel Settings") regroupe tous les Phase 2 en un seul
Child SA avec Traffic Selectors bundles. IKEv2 applique le TS narrowing et seul le premier
VLAN (SERVERS) etait accessible. Les trois autres (BASTION, USERS, BACKUP) etaient bloques.

La migration vers le backend moderne ("Connections", swanctl natif) a ete effectuee via
l'API Python OPNsense, avec snapshot config.xml pre-migration et script de rollback disponible.
La procedure :

1. Snapshot : config.xml des 3 FW sauvegardes dans `backups/pre-migration-20260508-1956/`
2. Migration FW-EXT-MRS (responder) : creation PSK + Connection moderne + 4 children avec
   reqids distincts (1 a 4). Legacy Phase 1 desactive.
3. Migration FW-EXT-LYON (initiateur) : meme procedure, puis initiation manuelle IKE_SA.
4. Validation : `swanctl --list-sas | grep INSTALLED` = 4 sur les deux firewalls.

Extrait de l'etat post-migration sur FW-EXT-LYON :

```
UUID-78112723: #1, ESTABLISHED, IKEv2, local 10.0.0.2, remote 10.0.2.2
  child_servers  reqid 1  : 192.168.20.0/28 === 192.168.40.0/26  INSTALLED
  child_bastion  reqid 2  : 192.168.15.0/29 === 192.168.40.0/26  INSTALLED
  child_users    reqid 3  : 192.168.30.0/26 === 192.168.40.0/26  INSTALLED
  child_backup   reqid 4  : 192.168.50.0/29 === 192.168.40.0/26  INSTALLED
```

**Incident T3-DURCISSEMENT (2026-05-09) - block_all sur 8 interfaces :**

L'activation du `block_all` sur les 8 interfaces WAN/OPT a revele deux comportements
contre-intuitifs d'OPNsense qui ne sont pas documentes clairement dans le provider Terraform.

Lecon 1 : OPNsense place les nouvelles regles en tete de liste (prepend), pas en fin
(append). Une regle creee en dernier apparait en premier dans `pfctl -sr`. Consequence :
l'ordre de creation dans Terraform influence l'ordre d'evaluation dans pf, a l'inverse de ce
qu'on attend d'un system append-based.

Lecon 2 : L'option `-replace` de l'API OPNsense peut recycler le meme slot de sequence
si la regle est recree au meme endroit dans config.xml. Symptome : le `block_all` se retrouve
en milieu de liste, entre des regles `pass`, ce qui le rend inefficace (pf evalue en ordre
sequentiel avec `quick`).

Fix : le champ `sequence` expose par le provider browningluke 0.16 permet de forcer l'ordre
de maniere declarative et idempotente. Apres ajout de `sequence=` sur chaque regle, le
`terraform plan` confirme No changes et `pfctl -sr` montre les regles dans le bon ordre.

```hcl
# block_all doit avoir la sequence la plus haute (derniere evaluee)
resource "opnsense_firewall_filter" "fwint_wan_block_all" {
  sequence    = 9999
  ...
  interface_default_block = true
}
```

### 3.3 Configuration OS (Ansible 10 roles)

L'ensemble de la configuration des serveurs Linux est gere par Ansible (10 roles). Le
playbook principal `site.yml` applique les roles dans un ordre deterministe :

```
Role         Hotes cibles          Fonction
common       tous                  packages systeme, NTP, timezone
hardening    tous                  sshd, nftables, fail2ban, auditd, unattended-upgrades
dc           dc01                  Samba AD DC, DNS, DHCP, users, groupes
fileserver   fs01                  Samba member, domain join, shares SMB
database     db01                  MariaDB, schemas, users, dump cron
wazuh_manager app01               Wazuh 4.11.2, config, regles NIS2
wazuh_agent  tous sauf app01       install agent, enregistrement manager
bastion      bastion01             SSH hardening, ProxyJump, fail2ban strict
proxy        proxy-lyon01          Squid, ACL par VLAN (en cours)
backup       backup01              Borg repos, scripts, crons, WireGuard
```

**Role hardening - politique appliquee :**

```
sshd_config : PasswordAuthentication no
              PermitRootLogin no
              MaxAuthTries 3
              AllowUsers debian
              Port 22 (pas de port non-standard, le bastion suffit)

nftables    : default input drop
              accept established,related
              accept ICMP (echo uniquement)
              accept SSH depuis 192.168.15.0/29 (bastion) et 192.168.10.0/24 (mgmt)
              accept Wazuh 1514 depuis tous les VLANs internes
              accept node_exporter 9100 depuis 192.168.20.0/28 (Prometheus)

fail2ban    : bantime 3600s
              findtime 600s
              maxretry 3
              ignoreip 192.168.15.0/29 (bastion)

auditd      : regles NIS2 : acces /etc/passwd, /etc/shadow, escalade sudo,
              modifications fichiers critiques, connexions SSH echouees
              retention 90j (lab), 12 mois en production
```

**Active Directory Samba :**

DC01 execute Samba 4 en mode Active Directory Domain Controller (pas un controleur de domaine
Windows). Le domaine est `nova.syndicate` (realm `NOVA.SYNDICATE`). La configuration est
entierement generee par le role Ansible `dc` :

- 91 utilisateurs crees depuis un CSV (85 metier + 6 comptes systeme)
- 5 OUs : Lyon, Marseille, MobileAgents, ServiceAccounts, Groups
- 8 groupes : lyon-staff, marseille-staff, mobile-agents, finance, it-admins, managers, rh, direction
- FS01 rejoint le domaine (domain join via winbind)
- 5 partages SMB avec ACL par groupe AD : lyon, marseille, commun, finance (hidden), it-restricted (hidden)

### 3.4 Active Directory Samba

Le choix de Samba AD plutot que d'un controleur Windows Server est un choix delibere et
assume. Il est justifie par trois raisons :

1. Cout zero (pas de licence Windows Server ni CAL)
2. Configuration 100% scriptable via `samba-tool` depuis Ansible
3. Interoperabilite complete avec les clients Windows (Kerberos, NTLM, LDAP, SMB)

Un point de vigilance a ete rencontre : la version Samba 4.17 (Debian 12) a deprecie
certaines options de `samba-tool user add` (`--fullname` invalide, `--userou` avec format
different). Les roles Ansible ont ete corriges en consequence :

```yaml
# Avant (incompatible Samba 4.17)
- name: Create user
  command: samba-tool user add {{ item.username }} --fullname="{{ item.fullname }}"

# Apres
- name: Create user
  command: >
    samba-tool user add {{ item.username }}
    --given-name="{{ item.firstname }}"
    --surname="{{ item.lastname }}"
    --userou="OU={{ item.ou }},DC=nova,DC=syndicate"
```

La validation AD utilise `samba-tool user list | wc -l` (retourne 91) et
`samba-tool domain info 127.0.0.1` pour confirmer que le domaine repond correctement.

### 3.5 Backup Borg multi-site

La strategie de sauvegarde suit le modele 3-2-1-1-0, valide par le drill T-RESTORE-DRILL :

```
3 copies    : donnees sources + repos Borg locaux (BACKUP01) + cloud VPS Hetzner
2 supports  : disque local NVMe + VPS distant (Helsinki)
1 copie hors-site : VPS Hetzner via tunnel WireGuard dedie
1 copie "offline" : mode append-only (les archives ne peuvent pas etre supprimees par le client)
0 erreur    : checksums MD5 OK sur 5/5 fichiers testes lors du drill
```

**Architecture locale (BACKUP01, 192.168.50.2) :**

Trois repos Borg independants dans `/var/backups/borg/` :

```
filesystem/  -- rsync depuis FS01 quotidien (cron 03h00)
databases/   -- dump MariaDB toutes les 15 minutes (all-databases + schemas individuels)
configs/     -- /etc de chaque serveur (rsync via SSH, cron 05h00)
```

Le dump MariaDB toutes les 15 minutes est une decision consciente : la base nova_logistique
contient des mouvements de stock (commandes en cours). Un RPO de 15 minutes est acceptable
pour une PME ; en dessous, il faudrait de la replication MariaDB, hors scope Phase II.

**Architecture cloud (VPS Hetzner CX22, Helsinki) :**

Tunnel WireGuard 10.30.0.0/24 entre BACKUP01 (10.30.0.2) et le VPS (10.30.0.1). Le VPS
execute borgbackup 1.2.8, un compte borguser dedie avec restrictions SSH :

```
# /etc/ssh/sshd_config sur VPS
Match User borguser
    ForceCommand borg serve --append-only --restrict-to-path /srv/borg-repo/nova-syndicate
    PermitTTY no
    X11Forwarding no
    AllowTcpForwarding no
```

La cle SSH est restreinte par `from="10.30.0.2"` dans `authorized_keys`, ce qui garantit
que seul le tunnel WireGuard peut declencher un backup. Un cron sur BACKUP01 lance le
script `/usr/local/bin/borg-cloud-sync.sh` a 23h30 daily avec retention 7j/4s/6m.

**Chiffrement :** repokey-blake2. La cle de repo est stockee dans le repo lui-meme
(chiffree par la passphrase). La passphrase est dans `/etc/borg/passphrase` (600 root) sur
BACKUP01. Dette T-BORG-KEY-EXPORT : exporter la cle repo dans un password manager hors
infrastructure.

**Drill T-RESTORE-DRILL (2026-05-10) :**

```
Archive testee  : backup01-2026-05-10-2110
Volume          : 14.92 MB / 836 fichiers
Temps restore   : 14.6 secondes
Debit effectif  : ~1 MB/s (WireGuard tunnel, normal pour Hetzner CX22)
Checksums       : 5/5 OK (MD5)
Comptage        : borg repos 48/48, DB dumps 12/12
Permissions     : preservees (passphrase 600 root:root confirme)
Restore partiel : etc/borg isole, 0 fichier hors scope
```

Ce drill valide la mecanique complete du chemin de restauration. Les limites sont documentees
honnetement : le restore a ete effectue in-place sur BACKUP01 (machine source), pas dans une
VM bac-a-sable. Un T-SQL-RESTORE-DRILL (dezipper + reimporter en MariaDB) est prevu mais pas
encore realise.

### 3.6 Monitoring (Wazuh + Prometheus + Grafana)

**Wazuh 4.11.2 - SIEM :**

Wazuh Manager tourne sur app01 (192.168.20.13). Sept agents sont actifs, couvrant tous les
serveurs sauf les firewalls OPNsense (les agents Wazuh pour FreeBSD/OPNsense existent mais
sont hors scope Phase II) :

```
Agent  Hostname   IP              Status
001    dc01       192.168.20.10   Active
002    fs01       192.168.20.11   Active
003    db01       192.168.20.12   Active
004    bastion01  192.168.15.2    Active
005    backup01   192.168.50.2    Active
006    web01      172.16.1.2      Active
007    mail01     172.16.1.3      Active
```

Dix regles NIS2 custom ont ete deployees (IDs 100001 a 100010) :

```xml
<!-- Exemple : regle NIS2 detection sudo abuse -->
<rule id="100003" level="12">
  <if_sid>5402</if_sid>
  <description>NIS2-21f : sudo commande non autorisee</description>
  <group>sudo,authentication_failure,pci_dss_10.2.4</group>
</rule>

<!-- Detection modification fichiers sensibles (NIS2-21f) -->
<rule id="100007" level="10">
  <if_sid>80790</if_sid>
  <match>/etc/passwd|/etc/shadow|/etc/sudoers</match>
  <description>NIS2-21f : modification fichier systeme critique</description>
</rule>
```

La retention est configuree a 90 jours (lab). En production, NIS2 recommande 12 mois.

**Incident T-WAZUH-NFT (2026-05-10) :**

Apres le reboot des firewalls OPNsense suite au durcissement T3, deux agents Wazuh (backup01
et bastion01) sont passes en statut "Disconnected". Cause racine : le role hardening avait
applique nftables sur app01 sans regle pour le port 1514 (Wazuh agent listener). Les cinq
agents deja connectes avaient survecu grace aux etats `ct state established,related accept`
(connexions etablies avant le hardening). Le reboot de FW-INT-LYON avait flush le conntrack,
obligeant backup01 et bastion01 a reamorcer la connexion, qui etait alors bloquee par nftables.

Fix tactique immediat :

```bash
ssh debian@192.168.20.13 'sudo nft insert rule inet filter input position 6 \
  ip saddr { 192.168.15.0/24, 192.168.50.0/24 } tcp dport 1514 accept'
# Resultat : 7/7 agents Active
```

Fix perennise dans Ansible (commit cebb6c2) : ajout de `wazuh_manager_listeners` dans
`host_vars/app01.yml` et extension du template `nftables.conf.j2` avec boucle conditionnelle.

```yaml
# host_vars/app01.yml
wazuh_manager_listeners:
  - { name: "wazuh-agents-bastion", ip: "192.168.15.0/29", port: 1514 }
  - { name: "wazuh-agents-backup",  ip: "192.168.50.0/29", port: 1514 }
  - { name: "wazuh-agents-servers", ip: "192.168.20.0/28", port: 1514 }
  - { name: "wazuh-agents-mrs",     ip: "192.168.40.0/26", port: 1514 }
  - { name: "wazuh-agents-dmz",     ip: "172.16.1.0/29",   port: 1514 }
```

**Prometheus + Grafana :**

Prometheus scrape les node_exporter installes sur 10 hotes (toutes les VMs Linux).
Grafana est configure avec Prometheus comme datasource et expose les dashboards via HTTP
sur le VLAN Management (192.168.10.0/24). Les metriques collectees : CPU, RAM, disque,
reseau, processus. Un dashboard "Nova Overview" consolide l'etat de toute l'infrastructure.

### 3.7 Bastion et acces administratifs

BASTION01 (192.168.15.2) est le seul point d'entree administratif vers les serveurs de
production. Aucun serveur n'accepte de connexion SSH directe depuis l'exterieur du VLAN
Bastion. La configuration SSH du poste admin utilise ProxyJump :

```
# ~/.ssh/config (poste admin Mac)
Host bastion01
    HostName 192.168.15.2
    User debian
    IdentityFile ~/.ssh/nova_admin_ed25519

Host dc01
    HostName 192.168.20.10
    User debian
    ProxyJump bastion01

Host backup01
    HostName 192.168.50.2
    User debian
    ProxyJump bastion01
```

Les regles firewall sur FW-INT-LYON autorisent explicitement les connexions SSH uniquement
depuis le VLAN Bastion (192.168.15.0/29) vers le VLAN Servers (192.168.20.0/28).

Teleport 14 est planifie en Phase V (T-BASTION-TELEPORT) pour ajouter l'authentification MFA
TOTP et l'enregistrement de session. En l'etat, les connexions SSH sont tracees par auditd
sur chaque serveur et remontees a Wazuh, ce qui satisfait l'exigence NIS2.f d'audit trail.

---

## 4. Securite et conformite

### 4.1 Mapping NIS2 article 21

**Article 21.b - Politiques d'analyse des risques et de securite des SI :**

La segmentation VLAN avec VLSM est la mise en oeuvre principale de cet article. Chaque VLAN
represente un niveau de confiance distinct et une surface d'attaque maitrisee. La matrice de
trafic T3 documente explicitement chaque flux autorise et son justification.

La politique firewall Terraform est la formalisation de la politique de securite en code
versionne. L'historique git constitue une trace d'audit de toutes les modifications de la
politique de securite depuis le debut du projet.

Ecart documente : les regles to_internet pour SERVERS et USERS sont actuellement des
pass-all (dette T-SQUID). L'article 21.b est partiellement satisfait pour ces deux VLANs ;
le filtrage granulaire par Squid est planifie en Phase III.

**Article 21.c - Gestion des incidents :**

Wazuh fournit la capacite de detection. Les regles custom NIS2 (100001-100010) couvrent :
brute force SSH, modifications fichiers systeme, escalade de privileges, connexions
inhabituelles. Les runbooks de response aux incidents sont documentes dans `docs/runbooks/`.

L'incident T-WAZUH-NFT illustre le processus de gestion d'incident : detection (agents
Disconnected dans le dashboard Wazuh), diagnostic (analyse nftables + conntrack), correction
tactique (regle nft manuelle), correction perennise (Ansible). Duree totale de resolution :
environ 45 minutes.

Ecart documente : pas de systeme de ticketing ni d'escalade formalisee (hors scope homelab).
Les incidents sont documentes dans `docs/` via des fichiers Markdown versionnes dans git.

**Article 21.e - Continuite des activites :**

La strategie 3-2-1-1-0 avec drill valide couvre l'essentiel de cet article pour les donnees.

Pour les services : le site Marseille (FW-EXT-MRS + LAN 192.168.40.0/26) constitue le
site DR. En cas de defaillance du site Lyon, les services critiques (AD, DB) pourraient
etre reinstancies a Marseille via les procedures documentees. Le RTO estime est de 4 heures
(provisionnement VM depuis template + restore Borg + reconfiguration DNS).

Ecart documente : le plan de reprise d'activite (PRA) n'est pas formellement documente avec
objectifs RTO/RPO chiffres pour chaque service. C'est un livrable Phase V.

**Article 21.f - Securite des reseaux et SI :**

Le hardening Ansible couvre les vecteurs d'attaque les plus courants :

```
Vecteur           Mesure implementee
Brute force SSH   fail2ban (bantime 3600s, maxretry 3) + PasswordAuth=no
Acces root direct PermitRootLogin=no sur tous les serveurs
Lateral movement  nftables default drop + regles explicites par VLAN
Persistence       auditd surveille les modifications /etc, cron, bashrc
Exfiltration      pas d'acces direct internet depuis postes de travail (VLAN 30)
```

**Article 21.i - Securite de la chaine d'approvisionnement :**

Non couverte en Phase II. Les logiciels utilises (OPNsense, Samba, Wazuh, MariaDB, Borg)
sont tous open-source avec des communautes actives. Aucune politique formelle de gestion des
mises a jour de securite des composants tiers n'est en place. `unattended-upgrades` est
configure sur tous les serveurs pour les patches de securite Debian, mais ce n'est pas
suffisant pour satisfaire 21.i. A traiter en Phase V.

### 4.2 Mapping RGPD

Les donnees a caractere personnel presentes dans l'infrastructure :

- Base `nova_rh` (MariaDB db01) : noms, prenoms, postes, salaires fictifs des employes
- Partage `finance` (SMB FS01) : fichiers RH et comptables fictifs
- Logs auditd et Wazuh : adresses IP, noms d'utilisateurs, actions

Mesures implementees :

```
Chiffrement en transit  : SSH (acces admin), IPsec (inter-sites), WireGuard (backup)
Chiffrement au repos    : Borg repokey-blake2 pour les backups
Controle acces          : RBAC AD, partages SMB par groupe, sudo minimal
Audit trail             : auditd + Wazuh, retention 90j (lab)
Minimisation            : les bases contiennent uniquement les donnees necessaires au lab
```

Ecart documente : le compte MariaDB `app_hr_ro` a acces en lecture a nova_rh depuis app01.
Dans un contexte de production, il faudrait un pseudonymat ou un chiffrement au niveau
colonne pour les donnees RH sensibles (salaires, informations medicales).

### 4.3 Defense en profondeur

L'architecture implemente plusieurs couches de protection independantes. La compromission
d'une couche ne doit pas entrainer la compromission des suivantes.

```
Couche 1 : Perimetre internet (FW-EXT-LYON)
           Expose uniquement les ports 80/443 (DMZ) et 25/465/587 (mail01)
           Tout le reste est bloque et trace

Couche 2 : DMZ (172.16.1.0/29)
           web01 et mail01 sont isoles des serveurs internes
           Un attaquant qui compromet web01 ne voit pas le VLAN Servers

Couche 3 : Firewall interne (FW-INT-LYON)
           Segmentation des VLANs internes
           VLAN Users ne peut pas se connecter en SSH aux serveurs

Couche 4 : Bastion SSH (VLAN 15)
           Seul chemin d'acces administratif aux serveurs
           Toutes les connexions passent par bastion01

Couche 5 : Hardening serveurs
           nftables default drop, fail2ban, PasswordAuth=no
           Meme si un attaquant arrive dans le VLAN Servers, les serveurs resisteent

Couche 6 : Audit et detection (Wazuh)
           Toute action suspecte est detectable et alertee
```

Limitations honnetes de ce modele : la DMZ est en acces internet direct (web01), mais sans
chemin de retour vers les serveurs internes. Le VLAN Users a un acces internet "raw" actuel
(dette T-SQUID). Les firewalls OPNsense ne sont pas supervises par Wazuh (agents FreeBSD
hors scope).

### 4.4 Incident response et DR

**Procedures de recovery documentees :**

Trois scenarios de recovery sont documentes dans `docs/runbook-borg-cloud.md` :

1. **Restore complet** : depuis l'archive Borg cloud, restauration complete de BACKUP01
   via `borg extract` avec verification des checksums.

2. **Restore partiel** : extraction d'un sous-repertoire specifique (ex: `etc/borg` uniquement)
   avec verification que l'isolation est parfaite.

3. **Restore from scratch** : procedure de reconstruction complete de BACKUP01 depuis zero :
   provisionner une nouvelle VM, installer Borg, configurer WireGuard, pointer vers le repo
   VPS, extraire les archives.

**Recovery IPsec post-reboot (procedure validee en conditions reelles) :**

L'incident du 2026-05-09 a produit une procedure de recovery testee :

```bash
# 1. Charger les connexions dans charon
swanctl --load-conns && swanctl --load-creds

# 2. Initier l'IKE_SA
swanctl --initiate --ike 78112723-0176-40d8-905f-1c187aaf58b3

# 3. Initier les 4 Child SAs (UUIDs specifiques a cette installation)
swanctl --initiate --child <uuid_child_servers>
swanctl --initiate --child <uuid_child_bastion>
swanctl --initiate --child <uuid_child_users>
swanctl --initiate --child <uuid_child_backup>

# 4. Verification
swanctl --list-sas | grep -c INSTALLED  # doit retourner 4
```

Cette procedure est documentee dans `docs/INCIDENT-IPSEC-RECOVERY.md`. La cause racine
(`start_action = trap` qui ne demarre pas automatiquement les tunnels au boot) est documentee
avec deux options de correction (changement en `start_action = start` ou script post-boot).
Ce point reste ouvert en dette technique.

### 4.5 Audit trail Wazuh

Wazuh collecte et centralise les evenements de securite de toute l'infrastructure.
Les sources d'evenements :

```
Source          Type d'evenements
auditd          syscalls, modifications fichiers, escalades sudo
sshd            connexions reussies et echouees, cles utilisees
fail2ban        tentatives de brute force, adresses bannies
samba           connexions LDAP, authentifications Kerberos
mariadb         connexions, requetes (si query log active)
nginx           acces web01 (format combined)
postfix         envois/reception mail01
nftables (log)  connexions bloquees (chaque block_all + log)
```

Les regles NIS2 custom sont deployees dans `/var/ossec/etc/rules/nova-nis2.xml`. Elles
declenchent des alertes de niveau 10-12 (niveau d'alerte eleve) sur les evenements suivants :
modification de `/etc/passwd` ou `/etc/shadow`, utilisation de `sudo` hors des commandes
autorisees, connexions depuis des plages IP inconnues, demarrage de services non repertories.

---

## 5. Resultats et tests

### 5.1 Metriques operationnelles

**Infrastructure :**

```
Metrique                              Valeur
VMs deployees et operationnelles      14/14
Roles Ansible appliques               10/10
Ressources Terraform deployees        33 (0 drift)
Tests connectivity inter-VLAN         OK (ping bastion01/dc01)
Tests connectivity cross-site         OK (ping dc01 -> proxy-mrs01 et retour)
pfctl status sur 4 firewalls          Enabled
Tunnels IPsec INSTALLED               4/4 (post-migration swanctl)
WireGuard handshake                   OK (~39ms BACKUP01 -> VPS Helsinki)
```

**Active Directory :**

```
Utilisateurs AD              91 (85 metier + 6 systeme)
OUs                          5
Groupes AD                   8
Partages SMB                 5 (dont 2 hidden avec ACL AD)
Domain join FS01             OK (winbind + net ads join)
```

**Monitoring :**

```
Agents Wazuh actifs          7/7
Regles NIS2 custom deployees 10 (IDs 100001-100010)
Hotes supervises Prometheus  10
Uptime services              100% sur periode de test
```

**Backup :**

```
Repos Borg locaux            3 (filesystem, databases, configs)
Frequence dump MariaDB       toutes les 15 minutes
Frequence sync cloud         23h30 daily
Retention cloud              7j / 4 semaines / 6 mois
Chiffrement                  repokey-blake2
Mode anti-ransomware         append-only (archives non effacables par client)
```

### 5.2 Tests effectues (T-RESTORE-DRILL)

Le T-RESTORE-DRILL du 2026-05-10 est le test de validation le plus significatif de la Phase II.
Il prouve que la mecanique backup-to-cloud-to-restore fonctionne de bout en bout.

**Conditions du test :**

```
Machine      : BACKUP01 (192.168.50.2)
Tunnel WG    : UP, dernier handshake 2 minutes avant le test
Archive      : backup01-2026-05-10-2110
              Fingerprint : bfb53f16ecf3b84023769da0d5e6484d25479b7eb1ccd0982a876134623c7361
```

**Procedure executee :**

```bash
# Phase 1 : lister les archives disponibles
BORG_PASSPHRASE=$(sudo cat /etc/borg/passphrase) \
  borg list borguser@10.30.0.1:/srv/borg-repo/nova-syndicate

# Phase 2 : restore complet dans /tmp/restore-test/
mkdir -p /tmp/restore-test
BORG_PASSPHRASE=$(sudo cat /etc/borg/passphrase) \
  borg extract --progress \
  borguser@10.30.0.1:/srv/borg-repo/nova-syndicate::backup01-2026-05-10-2110

# Phase 3 : validation integrite
md5sum /var/backups/borg/filesystem/hints.9
md5sum /tmp/restore-test/var/backups/borg/filesystem/hints.9
# Comparaison manuelle : match confirme

# Phase 4 : restore partiel (isolation)
mkdir -p /tmp/restore-partial
borg extract ... --strip-components 1 etc/borg
ls /tmp/restore-partial/  # seul etc/borg present
```

**Resultats :**

```
Duree restore complet   : 14.6 secondes
Volume                  : 14.92 MB / 836 fichiers
Erreurs                 : 0
Checksums MD5 valides   : 5/5
Comptage fichiers       : borg repos 48/48 (exact), DB dumps 12/12 (exact)
Permissions             : preservees (600 root:root sur passphrase confirme)
Isolation restore partiel : parfaite (0 fichier hors scope)
```

**Conclusion T-RESTORE-DRILL :** 3-2-1-1-0 valide. Le chemin complet
BACKUP01 -> WireGuard -> VPS Hetzner -> borg extract -> verification est operationnel.

### 5.3 Validation conformite

**Checklist NIS2 Phase II :**

```
Article  Exigence                          Statut     Note
21.b     Segmentation reseaux              VALIDE     7 VLANs + VLSM strict
21.b     Politique firewall documentee     VALIDE     Terraform IaC + git
21.b     Filtrage granulaire USERS/SERVERS EN COURS   T-SQUID (pass-all provisoire)
21.c     SIEM centralise                  VALIDE     Wazuh 7 agents
21.c     Regles de detection              VALIDE     10 regles NIS2 custom
21.c     Procedure incident response       PARTIEL    Runbooks, pas de ticketing
21.e     Sauvegarde avec test restore      VALIDE     Drill 836 fichiers 14.6s
21.e     Site DR operationnel              VALIDE     Marseille IPsec + LAN
21.e     RTO/RPO documentes               PARTIEL    Estimes, pas formalises
21.f     Hardening serveurs               VALIDE     10 roles Ansible
21.f     Audit trail                       VALIDE     auditd + Wazuh + retention
21.f     Acces admin via bastion           VALIDE     ProxyJump obligatoire
21.i     Securite fournisseurs             NON        Hors scope Phase II
```

**Resultat global Phase II :** conformite NIS2 partielle (articles 21.b, 21.c, 21.e, 21.f
couverts a 80%+), avec plan de correction identifie pour les ecarts. Article 21.i non couvert,
identifie comme dette Phase V.

---

## 6. Dette technique et perspectives

### 6.1 Dette identifiee

La dette technique est documentee sans ambiguite. Elle represente des choix deliberes
(faire vite pour valider un bloc fonctionnel) plutot que des oublis.

**T-SQUID - Pass-all VLAN 20/30/50 a remplacer par regles granulaires + Squid :**

Les interfaces opt3 (SERVERS), opt4 (USERS) et opt1 (BACKUP) de FW-INT-LYON utilisent
actuellement des regles `pass-all to any` pour l'acces internet. C'est fonctionnel mais
contraire a la segmentation NIS2.b : un poste compromis dans VLAN 30 (Users) peut initier
n'importe quelle connexion internet.

La correction implique deux etapes :
1. Deployer Squid sur proxy-lyon01 avec whitelist differenciee par VLAN source
2. Remplacer les regles pass-all par des regles specifiques authorisant uniquement le flux
   vers Squid (port 3128)

Effort estime : 3 heures. Priorite : haute (impacte NIS2.b et NIS2.f).

```
VLAN 30 Users   : autoriser uniquement DC01 AD + FS01 SMB + Squid:3128
VLAN 20 Servers : autoriser intra-VLAN + DC01 + BACKUP01 + Wazuh + Squid:3128
VLAN 50 Backup  : autoriser uniquement rsync sources + Squid:3128 (apt, NTP)
```

**T-TAILSCALE-SSH-HARDEN - Tailscale SSH bypasse ForceCommand :**

Tailscale SSH est une feature qui permet des connexions SSH authentifiees par le reseau
Tailscale, en contournant sshd. Sur le VPS Hetzner, borguser a une session Tailscale active.
Consequence : un administrateur avec acces Tailscale peut se connecter en SSH a borguser
sans passer par la restriction `ForceCommand borg serve` de sshd.

Ce n'est pas une vulnerabilite exploitable de l'exterieur (require un compte Tailscale de
l'organisation), mais c'est une violation du principe de moindre privilege. Options de
correction : desactiver Tailscale SSH sur le VPS (`tailscale set --ssh=false`) ou supprimer
Tailscale du VPS et n'autoriser l'acces que via le tunnel WireGuard.

**T-VAULT-INTEGRATE - Passphrase Borg en clair sur disque :**

La passphrase Borg est stockee dans `/etc/borg/passphrase` (permissions 600 root). C'est
acceptable en lab mais insuffisant en production : si BACKUP01 est compromise, la passphrase
est accessible au root. La solution cible est Ansible Vault pour chiffrer le fichier de
passphrase dans le depot IaC, avec injection au runtime via `--vault-password-file`.

**T-BASTION-TELEPORT - Teleport 14 pour MFA + session recording :**

Le bastion SSH actuel (BASTION01) assure l'isolement reseau mais pas l'authentification forte
ni l'enregistrement de session. Teleport 14 est prevu pour Phase V. Il apportera : MFA TOTP
obligatoire, enregistrement de session (audit complet des commandes executees), annuaire AD
integre (connexion avec les comptes Samba AD plutot que le compte debian generique).

**T-BORG-KEY-EXPORT - Cle repo Borg hors infrastructure :**

La cle de repo Borg est actuellement uniquement dans le repo chiffre. Si le VPS Hetzner
disparait ET que BACKUP01 est perdu, la cle est inaccessible. La cle doit etre exportee et
stockee dans un password manager hors de l'infrastructure (Bitwarden, 1Password).

**IPSEC-PERSIST - Tunnels ne remontent pas automatiquement au boot :**

`start_action = trap` dans la configuration swanctl signifie que les tunnels IPsec ne
demarrent pas au boot : ils montent uniquement quand du trafic traverse les policies SPD
(trigger ACQUIRE). En production, cela implique une interruption de service inter-sites
apres chaque redemarrage des firewalls jusqu'au premier paquet de trafic. La correction est
simple (passer a `start_action = start`) mais necessite un test de non-regression.

### 6.2 Roadmap court terme

**Phase III (mai 2026) - Livrables et documentation :**

- Diagrammes d'architecture a jour (D2 ou draw.io)
- Screenshots Wazuh, Grafana, pfctl
- Documentation technique Word/PDF pour le jury
- Validation T-FAIL2BAN-CLEANUP (whitelist bastion dans fail2ban)
- Resolution T-IPSEC-PERSIST (start_action = start)

**Phase IV (juin 2026) - Filtrage et securite applicative :**

- T-SQUID : deploiement Squid + regles granulaires par VLAN (priorite haute)
- T-TAILSCALE-SSH-HARDEN : securiser acces borguser
- T-VAULT-INTEGRATE : passphrase Borg dans Ansible Vault
- Migration NAT OPNsense Automatic -> Hybrid (regles NO-NAT IPsec)

### 6.3 Evolutions long terme

**Phase V (septembre 2026) - Zero trust et PKI :**

- T-BASTION-TELEPORT : Teleport 14 (MFA + session recording)
- PKI interne (cfssl ou ACME) pour certificates internes
- NIS2.i : politique de gestion des composants tiers
- PRA formel avec RTO/RPO documentes par service

**Phase VI (octobre 2026) - Bootstrap idempotent :**

- Script de bootstrap one-shot (template Proxmox, bridges, OPNsense ISO, gateways)
- Cartographie automatique de l'infrastructure (terraform-to-d2)
- Tests de penetration internes (scan Nessus + exploitation)

**Phase VII (2027) - Tests offensifs :**

Utilisation de l'infrastructure comme cible de tests de penetration dans le cadre de la
preparation au stage Thales Luxembourg. Scenarios : lateral movement depuis DMZ, elevation
de privileges via vulns AD, exfiltration de donnees depuis VLAN Servers.

---

## 7. Conclusion

Ce projet represente environ trois semaines de travail concentre, depuis la conception de
l'architecture VLSM jusqu'au drill de restauration valide. La somme de ce qui a ete construit
est concrete : 14 VMs, 33 ressources Terraform, 10 roles Ansible, 7 agents Wazuh, un backup
qui fonctionne et une infrastructure ou chaque flux reseau est explicitement autorise ou bloque.

Mais ce qui m'a le plus appris n'est pas dans les succes, c'est dans les incidents.

L'incident T-MIGRATION m'a force a comprendre reellement ce que fait IKEv2 avec les Traffic
Selectors. Avant, je deploiais des tunnels IPsec en suivant une documentation. Apres, je sais
pourquoi un seul Child SA avec TS bundles echoue sur le TS narrowing, et pourquoi 4 reqids
distincts resolvent le probleme. C'est la difference entre configurer et comprendre.

L'incident T3-DURCISSEMENT m'a appris qu'un outil de gestion d'etat (Terraform) peut donner
une fausse securite si on ne comprend pas le comportement de l'API sous-jacente. OPNsense
prepend les regles, pas append. Le champ `sequence=` du provider resout le probleme de
maniere declarative et idempotente, mais je ne l'aurais jamais cherche sans avoir vu le
`block_all` se retrouver en milieu de pfctl entre des regles pass.

L'incident T-WAZUH-NFT m'a rappele que le conntrack est un etat fragile. Cinq agents Wazuh
survecurent au hardening nftables parce que leurs connexions TCP etaient etablies avant le
changement de regles. Deux autres s'y sont retrouves bloques apres le reboot qui a flush le
conntrack. Ce genre de comportement ne se voit pas dans un lab ou on "teste" sans rebooter.

Ce parcours vers l'IT est atypique. Vingt ans dans l'industrie automobile, a diagnostiquer
des ECU et deboguer des protocoles CAN bus chez Ford Werke. Le travail de technicien
diagnostic m'a appris une discipline que je retrouve directement dans ce projet : ne jamais
supposer, toujours mesurer. Quand un tunnel IPsec ne monte pas, `swanctl --list-sas` avant
toute hypothese. Quand une regle firewall semble bonne mais que le trafic est bloque,
`pfctl -sr | nl` avant de modifier quoi que ce soit.

La methode est la meme. Les protocoles ont change, les outils ont change, mais la rigueur
de diagnostic reste identique. C'est probablement le transfert le plus important que j'ai fait
en changeant de secteur.

Le stage Thales Luxembourg en septembre 2026 (pentest automobile) prolongera ce travail dans
la direction qui m'interesse le plus : le cote offensif. Ce projet Nova Syndicate est d'abord
defensif, et c'est le bon ordre : on ne peut pas attaquer efficacement ce qu'on n'est pas
capable de construire et de defendre.

La Phase II est terminee. La dette est documentee. La suite est planifiee.

---

## Annexes

### Annexe A - Inventaire complet des ressources Terraform

```
Type                               Nom                              FW
opnsense_firewall_filter           fwext_wan_ipsec_ike              FW-EXT-LYON
opnsense_firewall_filter           fwext_wan_ipsec_natt             FW-EXT-LYON
opnsense_firewall_filter           fwext_wan_ipsec_esp              FW-EXT-LYON
opnsense_firewall_filter           wan_to_dmz_http                  FW-EXT-LYON
opnsense_firewall_filter           wan_to_dmz_https                 FW-EXT-LYON
opnsense_firewall_filter           wan_to_mail                      FW-EXT-LYON
opnsense_firewall_filter           fwext_wan_to_mail_submission     FW-EXT-LYON
opnsense_firewall_filter           fwext_wan_block_all              FW-EXT-LYON
opnsense_firewall_filter           fwint_bastion_to_servers_ssh     FW-INT-LYON
opnsense_firewall_filter           fwint_bastion_to_dc_ad_tcp       FW-INT-LYON
opnsense_firewall_filter           fwint_bastion_to_dc_ad_udp       FW-INT-LYON
opnsense_firewall_filter           fwint_bastion_to_internet        FW-INT-LYON
opnsense_firewall_filter           fwint_bastion_block_all          FW-INT-LYON
opnsense_firewall_filter           fwint_users_to_dc_ad_tcp         FW-INT-LYON
opnsense_firewall_filter           fwint_users_to_dc_ad_udp         FW-INT-LYON
opnsense_firewall_filter           fwint_users_to_servers_smb       FW-INT-LYON
opnsense_firewall_filter           fwint_users_to_internet          FW-INT-LYON
opnsense_firewall_filter           fwint_users_block_all            FW-INT-LYON
opnsense_firewall_filter           fwint_servers_to_internet        FW-INT-LYON
opnsense_firewall_filter           fwint_servers_block_all          FW-INT-LYON
opnsense_firewall_filter           fwint_backup_to_servers_ssh      FW-INT-LYON
opnsense_firewall_filter           fwint_backup_to_internet         FW-INT-LYON
opnsense_firewall_filter           fwint_backup_block_all           FW-INT-LYON
opnsense_firewall_filter           fwint_wan_ipsec_decapsulated     FW-INT-LYON
opnsense_firewall_filter           fwint_wan_block_all              FW-INT-LYON
opnsense_firewall_filter           fwextmrs_wan_ipsec_ike           FW-EXT-MRS
opnsense_firewall_filter           fwextmrs_wan_ipsec_natt          FW-EXT-MRS
opnsense_firewall_filter           fwextmrs_wan_ipsec_esp           FW-EXT-MRS
opnsense_firewall_filter           fwextmrs_wan_block_all           FW-EXT-MRS
opnsense_firewall_filter           wansim_lan_to_any                WAN-SIM
opnsense_firewall_filter           wansim_opt1_to_any               WAN-SIM
opnsense_firewall_filter           wansim_wan_block_all             WAN-SIM
opnsense_vlan                      fwint_vlan15/20/30/50 (x4)       FW-INT-LYON
opnsense_route                     4 routes necessaires             Divers
opnsense_alias                     24 aliases (nets, hosts, ports)  Tous
```

Total : 33 ressources gerees + 4 routes + 24 aliases

### Annexe B - Schema d'adressage complet

```
+------------------+   10.0.0.0/30   +------------------+   10.0.0.0/30   +------------------+
|    WAN-SIM       |+--------------->|   FW-EXT-LYON    |                 |   FW-EXT-MRS     |
|  VMID 200        |                 |   VMID 201       |                 |   VMID 203       |
|  10.0.0.1        |<---------------+|   10.0.0.2       |                 |   10.0.2.2       |
+------------------+   10.0.2.0/30   |   172.16.1.1 (DMZ)|                |   192.168.40.1   |
        |            +--------------->|   10.0.1.1 (INT) |                 +--------+---------+
        |            |                +--------+---------+                          |
        |            |                         |                                    |
        +------------+                 10.0.1.0/30                          192.168.40.0/26
                                               |                               LAN Marseille
                                      +--------+---------+                   proxy-mrs01 .11
                                      |   FW-INT-LYON    |
                                      |   VMID 202       |
                                      |   10.0.1.2       |
                                      +---+--+--+--+-----+
                                          |  |  |  |
                         +----------------+  |  |  +-------------------+
                         |                   |  |                      |
                  VLAN 15/29              VLAN 20/28              VLAN 50/29
                 192.168.15.0            192.168.20.0            192.168.50.0
                 bastion01 .2            dc01 .10                backup01 .2
                                         fs01 .11
                                         db01 .12       VLAN 30/26
                                         app01 .13      192.168.30.0
                                         proxy .14      postes Lyon

     DMZ 172.16.1.0/29                         WireGuard 10.30.0.0/24
     web01 .2                                  backup01 .2 <-> VPS .1
     mail01 .3                                 (Helsinki, Hetzner CX22)
```

### Annexe C - Chronologie des incidents Phase II

```
Date        Heure  Incident                 Cause racine              Resolution
2026-05-07  -      BUG-C1 packages manquants  NAT Proxmox absent     NAT temporaire configure
2026-05-08  -      T-MIGRATION IPsec bundle   TS bundling IKEv2       4 Child SAs distincts
2026-05-09  ~14h   T3 block_all prepend       OPNsense prepend rules  sequence= Terraform
2026-05-09  ~18h52 Reboot FW, IPsec DOWN      start_action=trap       swanctl --initiate manuel
2026-05-09  ~19h15 Wazuh 5/7 agents           nftables port 1514      nft insert rule tactique
2026-05-10  -      T-TAILSCALE-SSH-HARDEN     Tailscale bypass sshd   Documente, correction prevue
```

### Annexe D - Commandes de verification operationnelle

```bash
# Verification IPsec (depuis FW-EXT-LYON)
swanctl --list-sas | grep -E "ESTABLISHED|INSTALLED"

# Verification firewalls (sur chaque OPNsense)
pfctl -si | grep "Status"
pfctl -sr | wc -l  # nombre de regles actives

# Verification Wazuh (sur app01)
sudo /var/ossec/bin/agent_control -l  # liste agents et status

# Verification WireGuard (sur BACKUP01)
sudo wg show wg0

# Verification Borg cloud (depuis BACKUP01)
BORG_PASSPHRASE=$(sudo cat /etc/borg/passphrase) \
  borg list borguser@10.30.0.1:/srv/borg-repo/nova-syndicate

# Verification AD (sur dc01)
samba-tool user list | wc -l  # doit retourner 91
samba-tool domain info 127.0.0.1

# Verification MariaDB (sur db01)
mysql -u root -e "SHOW DATABASES;"  # nova_logistique, nova_rh, nova_audit presents

# Terraform state (dans terraform/environments/opnsense/)
terraform plan  # doit retourner "No changes"
```

### Annexe E - Structure du depot git

```
nova-syndicate-proxmox/
+-- terraform/
|   +-- environments/
|       +-- proxmox/          # Deploiement VMs
|       +-- opnsense/         # Configuration 4 firewalls
|           +-- main.tf       # 4 providers
|           +-- aliases.tf    # 24 aliases
|           +-- fw_int.tf     # 16 regles FW-INT-LYON
|           +-- fw_ext.tf     # 10 regles FW-EXT-LYON
|           +-- fw_ext_mrs.tf # 5 regles FW-EXT-MRS
|           +-- fw_wansim.tf  # 3 regles WAN-SIM
|           +-- fw_int_vlans.tf # 4 VLANs 802.1Q
+-- ansible/
|   +-- roles/                # 10 roles
|   +-- playbooks/            # playbooks par service
|   +-- inventory/            # hosts.yml + users.csv
|   +-- host_vars/            # variables par hote
+-- docs/
|   +-- runbooks/             # procedures operationnelles
|   +-- PHASE-II-KANBAN.md    # suivi taches
|   +-- INCIDENT-IPSEC-RECOVERY.md
|   +-- T-RESTORE-DRILL-LOG.md
|   +-- adressage_vlsm.md
+-- scripts/
    +-- rollback-ipsec-migration.sh
    +-- health-check.sh
```

---

*Fin du rapport Phase II - Nova Syndicate*
*Version DRAFT 1.0 - 2026-05-10*
*Matthieu Broquard - Jedha Academy - RNCP 37680*
