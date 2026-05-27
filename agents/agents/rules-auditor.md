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

> NOTE (T-AGENTS-KEY-DEPLOY) : Phase B **debloquee pour les 4 SERVERS** (dc01, fs01,
> db01, app01) via la cle nova-agents depuis awx01 (`sudo -n nft list ruleset`).
> DMZ/BACKUP non routables depuis Proxmox + bastion01 MFA-exclu -> hors scope
> (T-AGENTS-DMZ-AUDIT / T-AGENTS-BACKUP-AUDIT). Phase B = 4/9 hosts.

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

### T-AGENTS-RULES-AUDITOR-VM-ACCESS - RESOLU (partiel, ferme)

Resolu via **T-AGENTS-KEY-DEPLOY** : la cle dediee `nova-agents` (privee sur awx01,
source-locked `from=192.168.60.0/29` + `restrict`) debloque la Phase B pour les
**4 SERVERS** (dc01/fs01/db01/app01). Resolution partielle (4/9) ; reliquat dans des
dettes filles low-prio :

- **T-AGENTS-DMZ-AUDIT** : audit intra-VM DMZ (web01/mail01/vpn-gw01) via session
  bastion+TOTP supervisee (non routable depuis Proxmox).
- **T-AGENTS-BACKUP-AUDIT** : idem backup01.
- **bastion01** : exclu par design (MFA gate, aucun bypass cle).

Note securite : sur les SERVERS, `debian` dispose de `(ALL) NOPASSWD: ALL` - la cle
nova-agents (auth en debian) est donc root-capable de fait, pas read-only au sens
strict ; le controle effectif est le source-lock VLAN60 + restrict (cf R-006).

## Garde-fous

- terraform show / nft list : read-only (aucun apply, aucun nft -f)
- Lecture ADR et host_vars : read-only
