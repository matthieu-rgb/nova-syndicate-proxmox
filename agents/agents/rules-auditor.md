# Agent : Rules Auditor

## Mission

Analyser regles FW (terraform OPNsense + nft host) vs ADR documentes. Detecter
drift, orphans, conformite NIS2.

## Inputs

- ../outputs/network-inventory.json
- Repo proxmox : terraform/opnsense + docs/adr/*.md
- Repo ansible : roles/hardening + host_vars/*

## Outputs

- ../outputs/rules-conformity.md
- ../outputs/rules-conformity.json
- ../outputs/rules-execution.log

## Procedure

### Phase A - Inventory perimetre (terraform state)

```
cd terraform/opnsense && terraform show -json | \
  jq '.values.root_module.resources[] | select(.type == "opnsense_firewall_filter")'
```

Extraction : source, destination, port, action, description par FW.

### Phase B - Inventory host nft

Pour chaque VM (5 VMs ssh-accessibles via inventaire ansible) :

- `nft -j list ruleset` (output JSON)
- Parser regles input / forward / output

### Phase C - Lecture ADR

Lire `docs/adr/INDEX.md` + parser chaque ADR mentionnant FW (ADR-0017, 0032, etc.)
Build une map : "ADR-XXXX -> regle attendue".

### Phase D - Cross-reference

- Pour chaque ADR : verifier que la regle attendue existe live
- Pour chaque regle live : verifier qu'un ADR la justifie
- Drift detecte : flag findings

### Phase E - Conformite NIS2 art.21

- Access control : evaluation (admin only paths, segregation)
- Least privilege : ratio regles "any" vs scoped
- Network segmentation : evaluation isolation VLANs

### Phase F - Synthese rules-conformity.md

Structure attendue :

    # Rules Auditor - Nova Syndicate - {date}
    ## Executive Summary
    ## Conformite NIS2 art.21 (scoring)
    ## Findings (drift, orphans, undocumented)
    ## Recommandations T-XX

## Garde-fous

- terraform show / nft list : read-only (aucun apply, aucun nft -f)
- Lecture ADR et host_vars : read-only
