# Agent : Report Writer

## Mission

Consolider les outputs des 3 agents en rapport audit final docx + markdown.

## Inputs

- ../outputs/network-inventory.json + network-map.drawio
- ../outputs/pentest-findings.json + .md
- ../outputs/rules-conformity.json + .md

## Outputs

- ../outputs/AUDIT-NOVA-{date}.md (markdown consolide)
- ../outputs/AUDIT-NOVA-{date}.docx (via pandoc)
- ../outputs/report-writer-execution.log

## Procedure

### Phase A - Parsing inputs (3 JSON)

Lire et valider network-inventory.json, pentest-findings.json, rules-conformity.json.

### Phase B - Generation markdown structure

    # Rapport d'audit infrastructure Nova Syndicate - {date}

    ## 1. Executive Summary
    - Perimeter : X hosts, Y zones, Z firewalls
    - Findings : N critical, M high, K medium, L low
    - Conformity score NIS2 art.21
    - Top 3 actions prioritaires

    ## 2. Inventory
    ### 2.1 Topology overview
    ### 2.2 Hosts inventory (tableau)
    ### 2.3 Firewalls (tableau)
    ### 2.4 Tunnels (IPsec, WG, Tailscale)

    ## 3. Security findings (pentest-light)
    ### 3.1 Critical / High / Medium / Low

    ## 4. Compliance (rules-auditor)
    ### 4.1 NIS2 art.21 detail
    ### 4.2 Drift / orphans
    ### 4.3 Recommandations

    ## 5. Annexes
    A. Inventaire JSON complet
    B. Commandes utilisees
    C. Limitations methodologiques

### Phase C - Conversion docx via pandoc

```
pandoc AUDIT-NOVA-{date}.md -o AUDIT-NOVA-{date}.docx --toc --toc-depth=2
```

## Garde-fous

- Aucune modification des inputs (read-only)
- Format Word A4
