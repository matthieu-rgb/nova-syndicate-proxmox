# Orchestrator - Multi-Agent Audit Nova Syndicate

## Workflow

1. `network-mapper` (sequence) -> network-inventory.json
2. `pentest-light` + `rules-auditor` (PARALLEL, dependent de l'inventory)
3. `report-writer` (sequence, depend des 3 precedents)

## Usage AFK via Task tool

Prompt l'orchestrateur, il delegue aux sub-agents (Task tool), recolte les outputs,
genere le rapport consolide.

## Usage supervise (manuel)

Lancer chaque agent un par un, valider les outputs entre les etapes.

## Estimated runtime

- network-mapper : 15 min
- pentest-light : 20-30 min (vuln scans)
- rules-auditor : 10 min
- report-writer : 5 min
- Total : ~50-75 min en parallele optimise
