# Nova Syndicate - PoC Agents Audit

Multi-agent system based on Claude Code sub-agents (Task tool).

## Architecture

4 agents read-only orchestrated for Nova Syndicate infrastructure audit :
- `network-mapper` : scans infra, generates draw.io diagram + JSON inventory
- `pentest-light` : safe vuln scan (nmap scripts safe/vuln, ssh-audit, testssl)
- `rules-auditor` : analyzes FW rules (OPNsense terraform + nft) vs ADRs
- `report-writer` : consolidates outputs into a docx audit report

## Conventions

- All agents are STRICTLY READ-ONLY
- Outputs in `outputs/` (gitignored)
- Diagram conventions in `conventions/drawio-nova-skill.md`
- Tools deployed on awx01 (VLAN ADMIN 60)

## Usage

See `orchestrator.md` for the workflow.
