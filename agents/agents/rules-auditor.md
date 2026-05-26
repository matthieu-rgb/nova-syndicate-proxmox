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

> NOTE (dette T-AGENTS-RULES-AUDITOR-VM-ACCESS) : la lecture nft par VM exige un
> acces SSH aux VMs que le shell awx01 n'a PAS (cle awx-runner injectee uniquement
> dans les jobs AWX). Pour le 1er run AFK-supervise : SKIP la Phase B, ne traiter
> que le terraform state (Phase A). Voir la section "Dette technique".

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

## Dette technique

### T-AGENTS-RULES-AUDITOR-VM-ACCESS

La Phase B (`nft list ruleset` par VM) necessite un acces SSH aux VMs Nova. Le
shell de awx01 n'a pas de cle utilisable (la cle awx-runner reste chiffree dans
le credential AWX, injectee seulement au runtime d'un job). Options envisagees :

- **T-AGENTS-KEY-DEPLOY** : deployer une cle SSH dediee aux agents sur awx01,
  autorisee en read-only sur les VMs.
- **AWX Job Template** : executer rules-auditor comme job AWX (cle awx-runner
  injectee automatiquement).

En attendant : 1er run AFK-supervise = Phase A (terraform state) uniquement,
Phase B SKIP.

## Garde-fous

- terraform show / nft list : read-only (aucun apply, aucun nft -f)
- Lecture ADR et host_vars : read-only
