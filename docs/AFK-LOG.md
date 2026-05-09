# AFK Session Log

## Session start

- **Date** : 2026-05-09
- **Debut** : 16:20 Europe/Paris
- **Fin prevue** : ~19:20 Europe/Paris

## Pre-flight checks (16:20)

| Check | Commande | Resultat |
|-------|----------|----------|
| 1. git tag afk-session-start | `git tag \| grep afk` | OK — tag existant |
| 2. health-check.sh | `bash scripts/health-check.sh` | OK — 0 failures, 0 warnings |
| 3. terraform plan | dans health-check | OK — No changes |
| 4. IPsec >= 4 INSTALLED | `swanctl --list-sas \| grep -c INSTALLED` | OK — 8 INSTALLED |
| 5. Wazuh agents >= 7 Active | dans health-check | OK — 7 Active |

## Etat initial

- IPsec : 4 tunnels UP (8 Child SAs INSTALLED)
- Terraform : No changes
- Wazuh : 7 agents Active
- AD : 91 users, 8 groupes
- FS1 : 6 shares
- MariaDB : nova_logistique + nova_rh OK
- Prometheus : active
- Grafana : active
- Borg : 3 repos, 4 scripts

---

## T-AFK-1 — Validation T3 + tag + push prep

