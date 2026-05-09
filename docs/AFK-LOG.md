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

**Status : PASS**
- 8/8 interfaces block_all actives (23-35 rules par FW)
- 8 Child SAs INSTALLED, 4 tunnels IPsec UP
- Cross-site Lyon->MRS (APP1->192.168.40.11) : 0% loss
- Cross-site MRS->Lyon (DC1, APP1, BASTION) : 0% loss
- Samba : nova-syndicate.local OK, DC01 OK
- SMB shares : lyon, marseille, commun
- MariaDB : nova_logistique, nova_rh, nova_audit OK
- Wazuh : 7 Active agents
- Borg : 3 repos (configs, databases, filesystem), 4 scripts
- KANBAN mis a jour, commit e43c13f

## T-AFK-2 — Whitelist fail2ban BASTION

**Status : PASS**
- DC1 (192.168.20.10) : whitelist active, 192.168.15.0/29 confirme
- FS1 (192.168.20.11) : whitelist active, 192.168.15.0/29 confirme
- APP1 (192.168.20.13) : whitelist active, 192.168.15.0/29 confirme
- BACKUP01 (192.168.50.2) : whitelist active, 192.168.15.0/29 confirme
- proxy-lyon01 (192.168.20.14) : fail2ban actif, whitelist active, 192.168.15.0/29 confirme
- Skip DB1 (192.168.20.12) : probleme SSH agent pre-existant (instruction utilisateur)
- Fichier deploye : /etc/fail2ban/jail.d/00-nova-whitelist.conf sur 5 hotes


