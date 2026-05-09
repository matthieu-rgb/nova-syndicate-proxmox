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

**Status : PASS (commit e59cce6)**
- DC1 (192.168.20.10) : whitelist active, 192.168.15.0/29 confirme
- FS1 (192.168.20.11) : whitelist active, 192.168.15.0/29 confirme
- APP1 (192.168.20.13) : whitelist active, 192.168.15.0/29 confirme
- BACKUP01 (192.168.50.2) : whitelist active, 192.168.15.0/29 confirme
- proxy-lyon01 (192.168.20.14) : fail2ban actif, whitelist active, 192.168.15.0/29 confirme
- Skip DB1 (192.168.20.12) : probleme SSH agent pre-existant (instruction utilisateur)
- Fichier deploye : /etc/fail2ban/jail.d/00-nova-whitelist.conf sur 5 hotes

## T-AFK-3 — Cle SSH BASTION vers 6 hotes

**Status : PASS (commit 1f90bec)**
- Cle ed25519 generee sur bastion01 (SHA256:55x6DFsTZ9owpAUJqRAaDxBDwwtEwgHyJc7mDWZlb3A)
- DC1 (192.168.20.10) : PASS
- FS1 (192.168.20.11) : PASS
- APP1 (192.168.20.13) : PASS
- BACKUP01 (192.168.50.2) : PASS
- proxy-lyon01 (192.168.20.14) : PASS
- WEB01 (172.16.1.2) : PASS
- DB1 : SKIP (instruction utilisateur -- probleme SSH agent)
- Test depuis BASTION : 6/6 hostname sans password

## T-AFK-5 -- Squid PROXY-MRS01

**Status : PASS**
- squid 5.7 installe et actif sur proxy-mrs01 (192.168.40.11)
- Config adaptee de proxy-lyon01 : subnet MRS 192.168.40.0/26, visible_hostname proxy-mrs01.nova-syndicate.local
- forwarded_for off + via off (NIS2)
- Port 3128 actif (ss -tlnp confirme)
- Test fonctionnel : TCP_MISS/302 confirme (relais http://www.debian.org)
- Wazuh absent sur proxy-mrs01 : TODO runbook
- runbook-squid.md cree

## T-AFK-4 -- nginx WEB01 + page placeholder

**Status : PASS**
- nginx 1.22.1 installe et actif sur WEB01 (172.16.1.2)
- Page placeholder Nova Syndicate deployee (/var/www/html/index.html)
- Config nginx avec headers securite (X-Frame-Options, X-Content-Type-Options, Referrer-Policy)
- Test BASTION -> WEB01 : HTTP 200 OK, contenu "Nova Syndicate" confirme
- Wazuh agent absent sur WEB01 : note TODO runbook
- runbook-web01.md cree


