# Phase II -- KANBAN Nova Syndicate OPNsense IaC
# Date : 2026-05-08

## Taches

### [x] T-MIGRATION -- IPsec legacy -> Connections moderne

Migration complete sur FW-EXT-LYON (initiator) et FW-EXT-MRS (responder).
4 Child SAs separes avec reqids distincts. Backend moderne natif.
Legacy Phase1/Phase2 supprimes. Scripts fix_ipsec_children supprimes.
Ref : docs/SESSION-LOG.md Phases 1-3.

### [ ] T2 -- Internet BASTION

Activer acces internet pour VLAN BASTION (192.168.15.0/29).
Prerequis : regles pass explicites sur FW-INT-LYON et FW-EXT-LYON.
A faire apres resolution dette technique block_all.

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
