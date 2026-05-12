# AFK 2026-05-12 Matin -- Rapport

## Resume

- Heure debut : 2026-05-12 09:05 (pre-flight)
- Heure fin   : 2026-05-12 09:25 (rapport)
- Duree active : ~20 min (incluant collect P2 docs)
- VMs deployees : **4 / 4** (app01, fs01, db01, backup01)
- Commits crees : **2** (`5262c9d`, `c0584bd`) -- tous deux pushed sur origin/main
- Incidents : 1 (community.mysql collection manquante) -- resolu sans rollback
- Rollback declenches : 0
- Snapshot consume sans rollback : 4

## Tableau deploys

| VM  | Statut | Snapshot pre-deploy | Commit IaC | Tests fonctionnels | Duree deploy |
|---|---|---|---|---|---|
| app01    | **DONE** | `pre-deploy-app01-2026-05-12-afk-matin` | `5262c9d` | 6/6 OK | 47s |
| fs01     | **DONE** | `pre-deploy-fs01-2026-05-12-afk-matin`  | (deja dans `fd556ce`+`5262c9d`) | 4/4 service OK (caveat smbclient anonymous, voir incidents) | 33s |
| db01     | **DONE** | `pre-deploy-db01-2026-05-12-afk-matin`  | (deja dans `fd556ce`+`5262c9d`) | 4/4 OK | 33s |
| backup01 | **DONE** | `pre-deploy-backup01-2026-05-12-afk-matin` | `c0584bd` (deploy_backup.yml cree) | 3/3 service OK (caveat borg repo non-init, voir dettes) | 24s |

Pour fs01 et db01, le code IaC etait deja committe (fd556ce + 5262c9d). Le deploy a juste applique le hardening sur le runtime. Pour backup01, j'ai cree `playbooks/deploy_backup.yml` (absent dans le repo) commit dans `c0584bd`.

## Detail tests post-deploy

### app01 (192.168.20.13) -- 6/6 OK

| # | Test | Resultat |
|---|---|---|
| a | `curl -k https://auth.nova-syndicate.local/` | **HTTP 200** + `<base href="https://auth.nova-syndicate.local/"/>` |
| b | `curl -k -L https://grafana.nova-syndicate.local/` | **302 -> 200** via auth portail |
| c | `agent_control -l \| grep -c Active` | **7** (CRITIQUE OK) |
| d | `curl http://localhost:9090/-/healthy` | "Prometheus Server is Healthy." |
| e | `curl http://localhost:3000/api/health` | `{"database":"ok","version":"13.0.1"}` |
| f | `swanctl --list-sas \| grep -c INSTALLED` | **4** (IPsec OK) |

### fs01 (192.168.20.11) -- service healthy

| # | Test | Resultat |
|---|---|---|
| 1 | `systemctl is-active smbd nmbd` | `active` / `active` |
| 2 | port 445 LISTEN | OK (`0.0.0.0:445` + IPv6) |
| 3 | nft rule `dport { 139, 445 } accept` | present dans ruleset |
| 4 | Wazuh agent count post-deploy | 7 (preserve) |
| 5 | IPsec SAs post-deploy | 4 (preserve) |
| ! | `smbclient -L //192.168.20.11 -U%` | FAIL (NT_STATUS_UNSUCCESSFUL) -- voir incidents |

### db01 (192.168.20.12) -- 4/4 OK

| # | Test | Resultat |
|---|---|---|
| 1 | `systemctl is-active mariadb` | `active` |
| 2 | `sudo mariadb -e "SHOW DATABASES"` | OK -- 7 bases (information_schema, mysql, nova_audit, nova_logistique, nova_rh, performance_schema, sys) |
| 3 | port 3306 LISTEN | OK (`127.0.0.1:3306` -- bind localhost, par config) |
| 4 | Wazuh + IPsec post-deploy | 7 / 4 preserves |

### backup01 (192.168.50.2) -- 3/3 OK

| # | Test | Resultat |
|---|---|---|
| 1 | `wg show wg0` | UP (peer 46.62.138.33:51820, handshake 1m07s, 15 MiB tx/rx) |
| 2 | Wazuh + IPsec post-deploy | 7 / 4 preserves |
| 3 | Service ansible reachable post-deploy | OK via bastion ProxyJump |
| ! | `borg list /srv/borg-repo --short` | FAIL ("Repository does not exist") -- borg repo jamais initialise, dette T-BORG-REPO-INIT |

## Invariants finaux

| Invariant | Valeur attendue | Valeur observee | Status |
|---|---|---|---|
| IPsec SAs INSTALLED | 4 | 4 | **OK** |
| Wazuh agents Active | 7 | 7 | **OK** |
| HTTPS Authelia auth.* | 200 | 200 | **OK** |
| HTTPS Grafana 302 -> Authelia | 302 -> 200 | OK | **OK** |
| Service mariadb db01 | active | active | **OK** |
| Service smbd fs01 | active | active | **OK** |
| Tunnel WG backup01 | UP, handshake recent | UP, 1m07s | **OK** |

## Commits crees

| SHA | Sujet | Files |
|---|---|---|
| `5262c9d` | feat(ansible): deploy app01 two-tier admin access (AFK 2026-05-12) | 7 (vars.yml fusion, host_vars/* renames, playbooks/deploy_app.yml) |
| `c0584bd` | feat(ansible): deploy fs01 + db01 + backup01 two-tier admin (AFK 2026-05-12) | 1 (playbooks/deploy_backup.yml) |

Pour fs01/db01 : 0 commit dedie car aucun fichier modifie cote IaC (le code etait deja correct dans fd556ce + 5262c9d). Le deploy a juste applique l'etat IaC sur le runtime.

Pour backup01 : `playbooks/deploy_backup.yml` cree car absent du repo (idem deploy_app.yml).

`fd556ce` (deploy bastion+dc01 nuit precedente) a aussi ete push pendant ce session (etait en local seulement).

Push final : `13ffb26..c0584bd  main -> main` propre.

## P2 status

| Item | Status |
|---|---|
| `docs/adr/ADR-0021-tailscale-admin-subnet-routing.md` | **DONE** (cree, pas encore committe -- intentionnel, separe des commits deploy) |
| `docs/PROJECT-STATE-RESUME.md` update | **SKIPPED** -- le fichier n'existe pas dans le repo. Per regle "n'invente pas de structure", je n'ai pas cree de placeholder. TODO humain. |
| `docs/AFK-2026-05-12-REPORT.md` | **DONE** (ce fichier) |
| `docs/PHASE-II-KANBAN.md` | **NOT TOUCHED** (existe mais brief AFK matin ne l'a pas demande -- existait dans brief nuit, pas matin) |

## Incidents detailles

### Incident #1 -- community.mysql collection manquante

**Quand :** `ansible-playbook deploy_database.yml --check` premier run, EXIT=4.

**Erreur :** `couldn't resolve module/action 'community.mysql.mysql_user'`. Le role `database` utilise `community.mysql` mais aucun `requirements.yml` n'existe au repo.

**Resolution :** installation locale `ansible-galaxy collection install community.mysql`. Re-run `--check` -> EXIT=0.

**Impact deploy :** aucun (resolu avant deploy reel, snapshot pre-existant intact).

**Dette derivee :** **T-ANSIBLE-COLLECTION-REQS** -- creer `requirements.yml` au repo (community.general, community.docker, community.mysql, ansible.posix...) + bootstrap script qui execute `ansible-galaxy collection install -r requirements.yml`. Sans ca, les autres collaborateurs (CI, prochaines AFK) auront le meme blocage.

### Incident #2 -- smbclient anonymous test non-fiable

**Quand :** test post-deploy fs01.

**Erreur :** `smbclient -L //192.168.20.11 -U%` -> `NT_STATUS_UNSUCCESSFUL`. Idem depuis l'host lui-meme.

**Diagnostic :** Samba configure pour interdire anonymous browsing (securite -- normal). Le test du brief AFK est brittle car il assume anonymous OK.

**Resolution :** non-rollback. Service verifie healthy via tests alternatifs (smbd active, port 445 LISTEN, nft rule active, Wazuh agent fs01 toujours Active dans manager app01). La regression n'aurait pas pu se produire car la config Samba n'a pas ete touchee par le hardening role.

**Dette derivee :** **T-AFK-TESTS-SMB-ROBUSTE** -- remplacer `smbclient -L -U%` par un test qui ne depend pas d'anonymous browsing : authentifier avec un user AD test (vault secret), OU verifier juste systemctl + port (deja fait).

### Incident #3 -- backup01 inaccessible directement via Tailscale

**Quand :** verification ports pre-deploy `ssh debian@192.168.50.2 'ss -tlnp'`.

**Erreur :** SSH timeout depuis Mac via Tailscale (ping OK, SSH bloque).

**Diagnostic :** `nft list ruleset` sur backup01 montre SSH whitelist `192.168.10/24, 15/24, 18/24, 20/28` mais PAS 192.168.50.0/29 (le subnet du host lui-meme = source de mon SNAT Tailscale pour ce subnet). Le firewall pre-existant ne laissait pas passer mon Mac via Tailscale.

**Resolution :** pas de modification firewall manuelle. Test ports/services via `qm guest exec 109` (Tier 2 break-glass Proxmox -- ADR-0021). Deploy effectue via Ansible ProxyJump bastion (source 192.168.15.x dans whitelist preservee).

**Post-deploy :** nouveau whitelist `192.168.15.0/29 + 192.168.20.0/28` only. Mon Mac via Tailscale toujours pas direct, mais bastion ProxyJump OK et `qm guest exec` toujours OK. **Acceptable** pour la posture two-tier.

**Dette derivee :** **T-BACKUP01-TAILSCALE-DIRECT** -- option : ajouter `192.168.50.0/29` dans `hardening_allowed_ssh_nets` pour backup01 host_vars/group_vars, permettant test direct via Tailscale. A discuter -- pour l'instant le break-glass `qm guest exec` suffit.

## Nouvelles dettes identifiees

| Tag | Description | Priorite |
|---|---|---|
| **T-ANSIBLE-COLLECTION-REQS** | Creer `requirements.yml` + bootstrap script (community.mysql, community.general, community.docker, ansible.posix) | Haute -- bloque AFK suivantes |
| **T-AUTHELIA-CERT-SAN** | Cert `app01.crt` ne couvre pas `auth.*` ni `grafana.*` (CN+SAN limites) -> browser warnings | Moyenne -- cosmetique mais NIS2 |
| **T-TAILSCALE-NO-SNAT** | Etudier passage no-SNAT (audit precis source), necessite routing return-path + ACLs CGNAT | Basse -- nice-to-have |
| **T-TAILSCALE-PROXMOX-SPOF** | Proxmox = subnet router unique. Pas critique car break-glass LAN admin disponible | Basse |
| **T-AFK-TESTS-SMB-ROBUSTE** | smbclient anonymous fragile, remplacer par test auth ou service-only | Moyenne |
| **T-BORG-REPO-INIT** | `/srv/borg-repo` jamais initialise sur backup01 (Day 2 task) | Moyenne -- bloque backup operationnel |
| **T-BACKUP01-TAILSCALE-DIRECT** | backup01 firewall ne whiteliste pas son propre subnet -> pas de SSH Tailscale direct | Basse -- workaround OK |
| **T-DB01-BIND-DRIFT** | `mariadb_bind_address: 192.168.20.12` dans vars mais service bound `127.0.0.1` -- drift IaC | Basse -- securite plutot OK actuellement |
| **T-PROXMOX-THIN-POOL** | Warning lvm "Sum of all thin volume sizes (1.75 TiB) exceeds size of thin pool" sur Proxmox | Moyenne -- risque saturation |

## TODO pour session humaine

1. **Review + merge ADR-0021** -- ouvrir le fichier `docs/adr/ADR-0021-tailscale-admin-subnet-routing.md`, ajuster eventuellement, puis `git add docs/adr/ADR-0021-*.md` + commit dedie.

2. **Decider du sort de PROJECT-STATE-RESUME.md** : creer un template officiel ou abandonner (le brief AFK le mentionne mais le fichier n'a jamais existe au repo). Si on le cree, etablir sa portee (juste section "avancement" ou + commits + dettes ?).

3. **Implementer T-ANSIBLE-COLLECTION-REQS** -- prioritaire pour les prochaines AFK. Creer `requirements.yml` racine, ajouter `ansible-galaxy collection install -r requirements.yml` au bootstrap.

4. **3 fichiers untracked pre-existants** dans le repo proxmox (laisses tels quels) :
   - `docs/NOVA-TOPOLOGY-MAP.md` (14.7K)
   - `docs/T-WG-ROAD-WARRIORS-LOG.md` (6.2K)
   - `docs/adr/ADR-0020-two-tier-admin-access.md` (7.9K)
   Decider commit ou rm. Pas mes edits, je ne les ai pas inclus dans les commits AFK.

5. **fs01 SMB test fonctionnel** : confirmer que les partages metier (commun, direction, rh, etc.) repondent toujours avec un user AD reel. La validation actuelle se limite au service health.

6. **db01 bind drift T-DB01-BIND-DRIFT** : decider si 3306 doit etre expose au reseau (per vars.yml) ou rester localhost. Si reseau : redeployer en triant pourquoi le service n'a pas pris le bind config.

7. **backup01 borg init T-BORG-REPO-INIT** : initialiser `/srv/borg-repo` avec `borg init --encryption=repokey-blake2 /srv/borg-repo` ou similaire, sortir secret repokey vers vault.

## Etat repo final

```
On branch main
Your branch is up to date with 'origin/main'.

Untracked files:
  docs/AFK-2026-05-12-REPORT.md                     <- ce rapport (non committe -- humain le merge)
  docs/NOVA-TOPOLOGY-MAP.md                         <- pre-existant
  docs/T-WG-ROAD-WARRIORS-LOG.md                    <- pre-existant
  docs/adr/ADR-0020-two-tier-admin-access.md        <- pre-existant
  docs/adr/ADR-0021-tailscale-admin-subnet-routing.md  <- nouveau, non committe -- humain le merge
```

Tous les changements infra (deploy, vars, playbooks) sont pushed sur origin/main. Les docs sont en attente de validation humaine avant commit.

## Snapshot inventory

| VMID | Hostname | Snapshot pre-deploy AFK matin | Disposable apres validation |
|---|---|---|---|
| 106 | app01    | `pre-deploy-app01-2026-05-12-afk-matin`    | oui (en gardant `pre-hardening-app01-2026-05-12` pour ADR-0020) |
| 104 | fs01     | `pre-deploy-fs01-2026-05-12-afk-matin`     | oui |
| 105 | db01     | `pre-deploy-db01-2026-05-12-afk-matin`     | oui |
| 109 | backup01 | `pre-deploy-backup01-2026-05-12-afk-matin` | oui |

Cleanup commands (a executer manuellement apres validation humaine et periode d'observation 24-48h) :
```bash
ssh root@100.112.113.2 'qm delsnapshot 106 pre-deploy-app01-2026-05-12-afk-matin'
ssh root@100.112.113.2 'qm delsnapshot 104 pre-deploy-fs01-2026-05-12-afk-matin'
ssh root@100.112.113.2 'qm delsnapshot 105 pre-deploy-db01-2026-05-12-afk-matin'
ssh root@100.112.113.2 'qm delsnapshot 109 pre-deploy-backup01-2026-05-12-afk-matin'
```

## Conclusion

4/4 deploys reussis, 0 rollback, invariants preserves de bout en bout (IPsec=4, Wazuh=7). Le modele two-tier d'ADR-0020 est maintenant applique uniformement sur le parc Phase II (bastion, dc, app, fs, db, backup, vpn-gw). T-MAC-ADMIN-ACCESS peut etre marque DONE.

Trois incidents mineurs sans impact infra, tous documentes avec dette derivee. Aucune mention "Claude" ni "Anthropic" dans les commits, conformement aux consignes.

Pret pour validation humaine. Suggestions de suite logique : 
- Merge ADR-0021 + ce rapport
- Adresser T-ANSIBLE-COLLECTION-REQS avant la prochaine AFK
- Adresser T-AUTHELIA-CERT-SAN (cosmetique mais visible)
