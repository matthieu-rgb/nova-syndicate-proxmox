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

### DT-1 -- 9 routes Terraform-orphan dans OPNsense

Routes creees par Phase 4 (avortee), non managees Terraform apres rollback.
Restent actives dans OPNsense mais absentes du state Terraform.

Repartition :
- 5 routes FW-EXT-LYON : fwext_to_bastion (15.0/29), fwext_to_servers (20.0/28),
  fwext_to_users (30.0/26), fwext_to_backup (50.0/29), fwext_to_mrs_lan (40.0/26 via WAN)
- 1 route FW-EXT-MRS : fwextmrs_to_lyon (192.168.0.0/16 via WAN_GW)
- 3 routes WAN-SIM : wansim_to_lyon_internal_subnets (192.168.0.0/16),
  wansim_to_lyon_transit (10.0.1.0/30), wansim_to_mrs_lan (192.168.40.0/26)

Contenu .tf archive : /tmp/routes.tf.removed-20260508-2103
A reimporter en mode import-only (terraform import) avant toute modif routes.

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
