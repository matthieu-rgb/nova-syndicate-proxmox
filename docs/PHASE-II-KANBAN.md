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

### [ ] T3 -- Durcissement firewall block_all + regles pass explicites

Scope : remettre block_all=true sur les 8 interfaces avec regles pass
specifiques pour le trafic legitime AVANT de fermer.

Interfaces concernees (8 block_all actuellement false) :
- FW-INT-LYON : vtnet0 (WAN/transit) + opt1/opt2/opt3/opt4 (VLANs)
- FW-EXT-LYON : vtnet0 (WAN)
- FW-EXT-MRS : vtnet0 (WAN)
- WAN-SIM : vtnet0 (WAN)

Trafic a autoriser explicitement avant de fermer :
- IPsec : UDP 500, 4500 + ESP entre 10.0.0.2 (LYON) et 10.0.2.2 (MRS)
- Transit FW-INT <-> FW-EXT sur 10.0.1.0/30
- IKE management interfaces OPNsense (SSH, HTTPS admin)
- DNS/NTP sortants depuis VLANs internes
- Replies IPsec decapsules (192.168.40.0/26 -> VLANs Lyon et inverse)
- BASTION -> internet (fwint_bastion_to_internet deja OK)
- SERVERS/USERS/BACKUP -> internet (conserve pour apt/NTP/web/rclone,
  durcissement final en T-SQUID via proxy filtrant)

Risques critiques :
- Casser les 4 tunnels IPsec si oubli d'une regle pass ESP/IKE
- Se couper l'acces SSH management depuis le Mac si regle WAN trop stricte

Approche (une interface a la fois) :
1. Importer les regles existantes (IMPORT-ONLY) -> plan = No changes
2. Ecrire toutes les regles pass necessaires en Terraform
3. terraform plan -> revue complete du diff avant apply
4. Activer block_all sur UNE interface, tester immediatement :
   - 4 pings IPsec cross-site
   - SSH management OK
   - Si KO : ajouter regle pass manquante, reprendre
5. Repeter interface par interface
6. Supprimer en meme temps les 5 routes PARASITES (DT-1 audit)

Precautions operationnelles :
- Garder un terminal SSH OPNsense ouvert en permanence
- Avoir le script rollback-ipsec-migration.sh disponible
- Faire en debut de journee frais, pas en fin de session

Effort estime : 60-90 min

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

### [ ] T-SQUID -- Forward proxy avec whitelist par VLAN

Prerequis : T3 termine (block_all=true). Sans T3, Squid ne sert a rien
car le trafic peut bypasser le proxy par d'autres chemins.

Scope : deployer Squid sur proxy-lyon01 (deja dans alias host_proxy_lyon01,
192.168.20.x) avec politique differenciee par VLAN source.

Whitelist par VLAN :
- BASTION (15.0/29) : whitelist large dev tools
  github.com, registry.terraform.io, deb.debian.org, security.debian.org,
  pypi.org, hub.docker.com, registry-1.docker.io, galaxy.ansible.com,
  packages.debian.org, pythonhosted.org
- SERVERS (20.0/28) : whitelist stricte ops
  deb.debian.org, security.debian.org, pool.ntp.org,
  registry-1.docker.io, github.com, packages.microsoft.com,
  registry.terraform.io
- USERS (30.0/26) : categories Squid (work + news),
  blacklist streaming / social / gambling
- BACKUP (50.0/29) : whitelist minimale B2
  api.backblazeb2.com, f001.backblazeb2.com .. f100.backblazeb2.com

Configuration Squid :
- forwarded_for off (protection L7 -- ne pas exposer IP interne aux sites)
- access_log format JSON (ingestion Wazuh SIEM)
- Retention logs 30 jours (RGPD minimisation)
- TLS interception decline (preserve confidentialite, evite la complexite PKI)
- Mode : proxy explicite d'abord (HTTP_PROXY=http://proxy:3128),
  puis transparent si besoin (redir pf port 80/443 -> Squid)

Sequence :
1. Deployer et configurer Squid sur proxy-lyon01
2. Tester en mode explicite depuis chaque VLAN (curl --proxy)
3. Modifier FW-INT-LYON : rediriger port 80/443 des VLANs vers Squid
4. Basculer les regles *_to_internet de "to any" vers "to proxy-lyon01 port 3128"
5. Supprimer les regles to_internet "raw" apres validation

Effort estime : 90 min
