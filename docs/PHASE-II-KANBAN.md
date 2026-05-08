# Phase II -- KANBAN Nova Syndicate OPNsense IaC
# Date : 2026-05-08

## Taches

### [x] T-MIGRATION -- IPsec legacy -> Connections moderne

Migration complete sur FW-EXT-LYON (initiator) et FW-EXT-MRS (responder).
4 Child SAs separes avec reqids distincts. Backend moderne natif.
Legacy Phase1/Phase2 supprimes. Scripts fix_ipsec_children supprimes.
Ref : docs/SESSION-LOG.md Phases 1-3.

### [x] T2 -- Internet BASTION -- CLOSED 2026-05-08

Diagnostic Phase 1 a revele que fwint_bastion_to_internet (enabled=true)
etait deja en place depuis Phase II IaC. BASTION01 (192.168.15.2)
atteignait internet sans modification :
- curl https://github.com -> HTTP/2 200
- DNS : 140.82.121.3 github.com (Unbound FW-INT-LYON)
- Route : default via 192.168.15.1 (vlan02 FW-INT-LYON)

Note : SERVERS/USERS/BACKUP ont aussi un acces internet "raw" via
leurs regles to_internet respectives (besoins legaux : apt, NTP, rclone B2).
Le filtrage granulaire par VLAN est reporte en T-SQUID.
Ref : docs/runbook-bastion-internet.md

### [ ] T3 -- Durcissement block_all (dette technique)

Remplacer les 8 block_all=false par regles pass explicites :
- FW-INT-LYON WAN : pass IPsec return (192.168.40.0/26 -> VLANs)
- FW-EXT-LYON WAN : complement aux regles IKE/ESP existantes
- FW-EXT-MRS WAN : complement aux regles IKE/ESP existantes
- WAN-SIM WAN : pass trafic inter-FW legitime

Approche : Terraform IMPORT-ONLY. Importer les regles existantes,
verifier plan = No changes, puis durcir incrementalement.

---

## Dette technique restante

### [x] DT-1 -- 9 routes Terraform-orphan dans OPNsense -- CLOSED 2026-05-08

9 routes importees dans le state Terraform (terraform import x9).
terraform plan = "No changes" confirme.
Audit: 5 routes PARASITES identifiees, 4 NECESSAIRES conservees.
Routes parasites a supprimer lors de T3-DURCISSEMENT :
- wansim_to_lyon_internal_subnets
- wansim_to_mrs_lan
- wansim_to_lyon_transit
- fwext_to_mrs_lan
- fwextmrs_to_lyon
Ref : docs/SESSION-LOG.md section "T-IMPORT" + runbook section "Audit des routes statiques"

### DT-2 -- 8 block_all=false sur interfaces WAN/OPT

Etat actuel : block_all desactivees (debug) pour maintenir les tunnels UP.
Fichiers : fw_ext.tf, fw_ext_mrs.tf, fw_int.tf, fw_wansim.tf.
Cf. T3 ci-dessus pour le plan de durcissement.

### DT-3 -- IKE SA orphelin con1 (legacy)

SA #2 (con1) encore etablie sur FW-EXT-LYON (~82800s de lifetime restante).
Children 26-29 installes mais aucun trafic entrant. Expiration naturelle.
Aucune action requise, surveiller via swanctl --list-sas.

### DT-4 -- Terraform : aucun state IPsec/Connections

Les connexions IPsec modernes (UUIDs 78112723/cbe685dd) ne sont pas
gerees par Terraform. Migration faite manuellement via API Python.
A documenter ou ignorer (hors scope browningluke/opnsense v0.16).

---

## Nouvelles taches

### [ ] T-SQUID -- Proxy forward Squid avec whitelist par VLAN

Objectif : remplacer l'acces internet "raw" (to any) par filtrage
applicatif via proxy Squid, avec politique differenciee par VLAN.

Strategie cible :

| VLAN | Politique Squid | Whitelist / Categories |
|------|-----------------|------------------------|
| BASTION 15.0/29 | Bypass Squid OU whitelist large | github.com, registry.terraform.io, deb.debian.org, pypi.org, hub.docker.com, registry-1.docker.io, galaxy.ansible.com |
| SERVERS 20.0/28 | Whitelist stricte | deb.debian.org, security.debian.org, pool.ntp.org, registry-1.docker.io, github.com, packages.microsoft.com |
| USERS 30.0/26 | Categories Squid | work + news, blacklist streaming/social/gambling |
| BACKUP 50.0/29 | Whitelist tres stricte | api.backblazeb2.com, f001.backblazeb2.com..f100.backblazeb2.com |

Prerequis :
- Deployer Squid sur une VM dediee (SERVERS VLAN ou DMZ)
- Configurer le transparent proxy ou proxy explicite sur FW-INT-LYON
- Basculer les regles *_to_internet de "to any" vers "to squid_ip port 3128"
- Maintenir les no-NAT IPsec existants

Sequence recommandee :
1. Deployer Squid sur proxy-lyon01 (192.168.20.x -- deja dans alias host_proxy_lyon01)
2. Configurer ACLs par VLAN source
3. Tester en mode explicite (HTTP_PROXY) avant de basculer en transparent
4. Modifier FW-INT-LYON : rediriger port 80/443 des VLANs vers Squid (sauf BASTION)
5. Supprimer les regles to_internet "raw" une fois Squid valide
