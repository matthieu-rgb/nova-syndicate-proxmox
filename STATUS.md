# Nova Syndicate -- STATUS

Derniere mise a jour : 4 juin 2026 (soir) (RECO indexer Wazuh = faux-negatif healthcheck Grafana ; alias wazuh-alerts deploye + porte dans le role IaC ; preuve Borg purgee de l'historique Git + repo de test `/srv/borg-repo` supprime apres confirmation que la fuite etait inerte ; **validation SIEM live sur db01 = faille `su -> root` sans password decouverte sur db01, T-DB01-SU-NO-PASSWORD HIGH a corriger avant soutenance** ; pack NIS2 dashboard Wazuh deploye en IaC -- 12 visus + 1 dashboard organise par article NIS2 cf Bloc 6).

## Session 2026-06-04 -- RECO Wazuh indexing (faux-negatif), alias deploye, hygiene preuves Borg

### Bloc 1 -- Wazuh -> OpenSearch indexing : ALARME = FAUX-NEGATIF

Diagnostic methodique lecture seule sur app01 (VMID 106) via Tailscale +
`qm guest exec`. Hypothese de depart "index wazuh-alerts-* jamais cree" :
**FAUSSE**. Etat live mesure 2026-06-04 14:42 :

| Verification | Resultat |
|---|---|
| `df -h /` | 24G/32G = **80 %** (sous low watermark 85 %, pas de flood-stage) |
| `_cluster/health` (mTLS admin) | **green**, 55 shards, 0 unassigned |
| `_cluster/state/blocks` | `{}` |
| `_settings` sur `wazuh-alerts-*` | aucun `blocks.read_only*` |
| watermarks defaults | `enable_for_single_data_node=false` (donc non appliques sur ce cluster) |
| `_cat/indices` | 16 indices `wazuh-alerts-4.x-YYYY.MM.DD` du 2026.05.18 au 2026.06.04 (trou 05.30 + 05.31) |
| Index du jour | `wazuh-alerts-4.x-2026.06.04`, 423 docs, dernier `@timestamp` `2026-06-04T12:42:17.615Z` |
| `wazuh-alerts-*/_search` | HTTP 200, **8959 hits** cumules |
| Logs Grafana 14:27 | plugin `grafana-opensearch-datasource` 2.33.1, `dsUid=wazuh-opensearch`, `endpoint=queryData`, **`status=ok`** ~60ms |

L'indexation tourne, filebeat publie en live, le datasource Grafana
queryData repond `status=ok` -- les dashboards qui lisent vraiment le
datasource ont des donnees.

Cause exacte du `HTTP 400 Index not found: wazuh-alerts-*` observe sur
`/api/datasources/uid/wazuh-opensearch/health` : faux-negatif cosmetique
du healthcheck plugin, **deja documente** comme dette
[T-WAZUH-INDEXER-ALIAS-DAILY](docs/INFRA-INVENTORY.md#dettes-ouvertes-post-t-wazuh-indexer-install)
(`docs/INFRA-INVENTORY.md:298-300`). Resolution = alias `wazuh-alerts`
sur le pattern `wazuh-alerts-4.x-*`.

### Bloc 2 -- Resolution T-WAZUH-INDEXER-ALIAS-DAILY (IaC + live)

Approche minimale (n'ecrase pas le template `wazuh` package-managed,
order=0/version=1) : **template legacy contributif `wazuh-alias`**
(order=1, pattern `wazuh-alerts-4.x-*`, aliases `wazuh-alerts: {}`).
OpenSearch merge la section `aliases` des templates qui matchent ; les
futurs indices daily recoivent l'alias a la creation. Indices existants
backfilles une fois via `_aliases`.

Porte dans le role Ansible (`nova-syndicate-ansible` commit `7e4c6ec`) :
- `roles/wazuh_indexer/tasks/aliases.yml` : 2 tasks `uri` (PUT template +
  POST `_aliases`) en mTLS admin.pem, idempotentes.
- `roles/wazuh_indexer/tasks/main.yml` : `import_tasks aliases.yml` en
  fin de role (replay du role complet couvre l'alias).
- `playbooks/deploy_wazuh_indexer_alias.yml` : entree surgical via
  `import_role` + `tasks_from=aliases.yml` (evite de rejouer apt/certs/
  security-init).

Applique en live via `curl` admin TLS bit-identique aux tasks `uri`
(`bastion-nova` MFA ControlMaster non actif cette session). Verifie :

```
PUT /_template/wazuh-alias      -> 200 {"acknowledged":true}
POST /_aliases (add wazuh-alerts) -> 200 {"acknowledged":true}
GET /_alias/wazuh-alerts        -> 200, alias sur 16 indices
GET /wazuh-alerts/_search       -> 200, 8962 hits, 48 shards (16 indices x 3 prim)
```

Verification cote Grafana (healthcheck `/api/datasources/.../health`
desormais 200) **reportee** : Grafana admin password introuvable en
lecture seule (cf dette pre-existante T-GRAFANA-13-ADMIN-RESET-BUG).
Si le 400 cosmetique persiste apres alias (parce que le plugin
healthcheck garde le wildcard), suite naturelle = pointer `database`
du datasource sur `wazuh-alerts` (sans `*`) ; non fait cette session,
hors scope de T-WAZUH-INDEXER-ALIAS-DAILY tel que formule.

### Bloc 3 -- Hygiene preuves Borg -- premiere analyse (decision revoquee, cf Bloc 4)

Bloc `key = hqlh...` (repokey base64) expurge du fichier de preuve
`docs/preuves/borg/2026-06-04-1356-borg-local-repo.txt` (SHA pre-rewrite
`1659b35`, post-rewrite `bca93af` -- cf table de mapping Bloc 4).
Remplace par 1 ligne :
`key = *** REDACTED (repokey chiffree par passphrase, stockee hors repo) ***`.
Le reste du fichier (config, README, listing FS) intact. Pre-commit OK.

**Analyse INITIALE** (revoquee soir 2026-06-04, cf Bloc 4) : historique
Git non purge -- repokey protegee par passphrase Borg + repo Nova prive
+ cite dans 1 seul commit recent (`50e69eb`). Cout d'un `git filter-repo`
(force-push, invalidation clones, perte des SHAs cites dans STATUS)
> benefice securite reel. Decision : expurgation suffisante.

### Bloc 4 -- Hygiene preuves Borg -- purge complete (apres revision analyse)

**Decision revisee** suite a confirmation que le jury pourrait avoir
acces au repo : passage de "expurgation seule" (Bloc 3) a "purge
complete" (filter-repo + force-push). Le diagnostic methodique conduit
en preparation de la rotation passphrase a revele un **modele de menace
faux** -- la fuite est INERTE -- ce qui a annule la phase 1 (rotation)
tout en preservant les phases 2-3 (history rewrite, demande explicite jury).

#### Diagnostic factuel -- la fuite est INERTE

| Element | `/srv/borg-repo` (LOCAL = LEAKE) | Hetzner `borguser@10.30.0.1:.../` (PRODUCTION) |
|---|---|---|
| Repo id | `dcb68bbed801...09bbe6` -- **identique au commit Git fuite** | `0cbd03d5664d...a7fb06` -- **different, jamais leake** |
| Archives | **0** | 11 archives (test 05.10 -> backup01 06.03) |
| Donnees reelles | 547 octets metadata init (segments `data/0/0`=530o, `data/0/1`=17o) | KB-MB d'archives production |
| mtime config | 2026-05-12 14:04 -- **jamais touche depuis init** | -- |
| Passphrase | inconnue, distincte de `/etc/borg/passphrase` (rejet `borg key change-passphrase`) | `/etc/borg/passphrase` (`c4a5280f...242c`) -- valide |
| Usage cron / bash_history | **AUCUNE reference** | toutes les operations borg ciblent celui-ci |

`/srv/borg-repo` etait un repo de test initialise le 12 mai, jamais
utilise. Sa cle leake wrap **0 archive**. Production Hetzner a une
cle DIFFERENTE, jamais dans aucun commit Git.

#### Execution

**Phase 0 -- filets** (4 actions read-only, ~5 min) :
| # | Filet | Etat |
|---|---|---|
| 0.1 | Snapshot Proxmox VMID 109 `pre-borg-passphrase-rotation-20260604` (2026-06-04 15:13:53) | en place |
| 0.2 | Mirror Git `/tmp/nova-syndicate-proxmox-prerewrite-20260604.git` (HEAD `a7f79f6...aca08`) | en place |
| 0.3 | Backup `/etc/borg/passphrase` -> `/root/.borg-passphrase-pre-rotation-20260604.bak` (sha `c4a5280f...242c`) | en place |
| 0.4 | Capture SHAs `/tmp/nova-proxmox-sha-pre-rewrite-20260604.txt` (10 commits) | en place |

**Phase 1 -- rotation passphrase : ANNULEE**.
- 1.1 OK : passphrase NEW generee sur backup01 (`openssl rand -base64 33`, sha `d17d34de...6155`, 44 octets, mode 600 root).
- 1.2 ECHEC + DECOUVERTE : `backup-remote-config` via `scp` echoue (la cle SSH `id_ed25519_borg-cloud` est restreinte a `borg serve` dans `~borguser/.ssh/authorized_keys` cote Hetzner -- defense en profondeur correcte, mais incompatible scp). Patch script v2 : `borg key export` au lieu de `scp config` (compatible borg serve). Filet Hetzner cree (`/root/borg-keys/hetzner-2026-06-04.export`, 813 octets, sha `2c506585...0588`).
- 1.2b `rotate-local` ECHEC : `passphrase supplied in BORG_PASSPHRASE is incorrect`. Le contenu de `/etc/borg/passphrase` n'est PAS la passphrase du repo `/srv/borg-repo`. Diagnostic READ-ONLY -> les 2 repos ont des passphrases distinctes ; `/etc/borg/passphrase` est dedie a Hetzner uniquement.
- DECISION : phase 1 annulee (rotation impossible sans passphrase d'origine ET inutile vu que le repo leake est vide).

**Actions de cleanup** (apres confirmation modele de menace) :
| Action | Resultat |
|---|---|
| Restore cron `borg-cloud-backup` (renommage inverse) | OK -- cron actif, prochain run 23:30 |
| `rm -rf /srv/borg-repo` (debris de test, repo de la cle fuitee) | OK -- `/srv/borg-repo` absent |
| `shred -u /etc/borg/passphrase.new` | OK |
| Rename `hetzner-key.pre-rotation` -> `/root/borg-keys/hetzner-2026-06-04.export` (mode 600 root) | OK -- conserve comme backup off-repo legitime de la cle prod Hetzner (best practice Borg) |
| `rmdir /root/borg-rotation-20260604/` | OK |
| Filet 0.3 `/root/.borg-passphrase-pre-rotation-20260604.bak` | conserve cette session, shred ulterieur (doublon de `/etc/borg/passphrase` qui reste la passphrase prod active) |

**Phase 2 -- git filter-repo** (Mac, repo `nova-syndicate-proxmox`) :
- Blob-callback Python (`re.compile(rb'key = hqlhb[A-Za-z0-9+/=\\n\\t ]+dmVyc2lvbgE=', re.DOTALL)`) -> remplacement litteral
  `key = *** REDACTED (repokey expurged from history 2026-06-04, repo deleted) ***`.
- Stash `.DS_Store` avant rewrite, restore apres.
- Nettoyage prealable `.git/filter-repo/` (residu d'un run T-VAULT-PLAINTEXT-FIX du 18/05).
- 197 commits parses, 0.28 s, `git fsck` clean, `git grep "hqlhbGdvcml0aG2"` sur all-revs = **0 match**.

**Mapping SHA pre/post rewrite** (4 commits touches) :
| Commit (avant) | Commit (apres) | Sujet |
|---|---|---|
| `50e69eb2ade81a67e46e2902a3491499b2f31412` | `9ca35e520ffe6133a77bf4a91e62995a8b02970c` | docs(preuves): captures Borg backup01 (LEAK) |
| `a0ae9671ecca1bec0d1b2b179e106d6c34579070` | `23a0107bd0bd8df4a04c5202e26d25cded87bae6` | docs(preuves): captures IaC |
| `1659b35...` | `bca93afbbfd2930ab8565e54710511fbfc373308` | docs(preuves): expurge cle repokey (= Bloc 3) |
| `a7f79f67f7e02a6054ca14d5041f2afebd7aca08` | `df45bd5026deea22edae54db3af26981a020f03a` | docs(status): session 2026-06-04 RECO Wazuh + alias (= Blocs 1-3) |

**Phase 3 -- force-push + verifs GitHub** :
- `git push --force-with-lease=main:a0ae9671... origin main` : exit 0, `+ a0ae967...df45bd5 main -> main (forced update)`.
- Workflow `secret-scan` (gitleaks) sur `df45bd5` : **completed success** 17s.
- **Decouverte secondaire** : le run gitleaks PRECEDENT (`a0ae967`, 2026-06-04 11:57Z) etait **FAILURE** -- gitleaks A detecte la fuite a posteriori via rule `generic-api-key` (entropie-based fallback), fingerprint `50e69eb2...:docs/preuves/borg/...:30`. Mon affirmation precedente (Bloc 3 / proposition initiale Bloc 4) selon laquelle "gitleaks default ruleset NE detecte PAS le repokey Borg" etait **fausse** -- le serveur-side a fonctionne, le pre-commit local non.

**Residu accepte -- T-GITHUB-ORPHAN-COMMIT-RESIDUAL** :
Le commit orphelin `50e69eb` reste resolvable par URL directe sur
github.com (`HTTP 200` confirme, `https://github.com/matthieu-rgb/nova-syndicate-proxmox/commit/50e69eb...`) pendant **~90 jours** post-rewrite (politique GitHub).
Risque absorbe : la cle dans ce commit est INERTE (`/srv/borg-repo` supprime,
repo etait vide, passphrase inconnue, jamais utilise). Pas d'action GitHub
support, pas de recreation du repo.

#### Hetzner backup off-repo (bonus inattendu)

Le fichier `/root/borg-keys/hetzner-2026-06-04.export` (813 octets, sha
`2c506585...0588`, mode 600 root sur backup01) est un **backup legitime
de la cle prod Hetzner** au format `borg key export` (compatible borg
serve, donc rejouable avec la cle SSH actuelle). Best practice Borg
documente : "back up the key file in a different location than the
repository". A re-exporter en cas de rotation Hetzner future (sinon
filet stale).

### Bloc 5 -- Validation SIEM live (evenements reels, dashboards Wazuh)

Au lieu de fabriquer des alertes, declenchement de 5 evenements reels
sur db01 (agent 005) pour valider la chaine de detection NIS2 E2E :
SSH user inexistant, sudo failed auth, useradd+userdel, su simule,
sudo NOPASSWD scoped. Capture des alertes correlees dans la fenetre
`[2026-06-04T14:51:55Z, 14:53:00Z]` via query opensearch direct.

**Resultat** : **43 alertes db01** dont **28 NIS2 custom** dans la
fenetre, pipeline E2E latence ~774ms event->index. Verdict par event :

| Event | Rule(s) firee(s) | Detection NIS2 |
|-------|------------------|----------------|
| 1 `ssh nonexistent@127.0.0.1` | 5710 (Wazuh default) seul | **GAP** : 100001 pas firee (`Invalid user` hors regex) |
| 2 `sudo -S whoami` (debian) | 100002 (NIS2 art.21.2.b) + 5501/5502 PAM | OK -- detecte sudo COMMAND (note : auth a reussi via NOPASSWD) |
| 3 `useradd && userdel` test | 100008 firee **24 fois** + 5901/5902/5903 | OK -- mais bruit massif (decoder audit kernel + user-space, pas dedup) |
| 4 `su - root` simule | 5501/5502 PAM session opened **for root** -- **su a REUSSI sans password** | **GAP CRITIQUE** : 100007 (FAILED SU) pas firee, parce que su a reussi. Faille securite reelle sur db01 (cf dette T-DB01-SU-NO-PASSWORD). |
| 5 `sudo -n nft list ruleset` | 100002 (NIS2 art.21.2.b) + 5501/5502 PAM | OK -- detecte sudo NOPASSWD scoped (pattern AWX runner) |

Les 28 NIS2 alerts capturees sont desormais dans `wazuh-alerts-4.x-2026.06.04` -- requetable via Grafana datasource `Wazuh-OpenSearch`, filtre suggere :
`agent.name : db01 AND rule.groups : nis2 AND @timestamp in [14:51:00Z, 14:53:00Z]`.

### Bloc 6 -- Pack dashboard NIS2 dedie (Wazuh Dashboard, IaC)

Construit + deploye live un pack dashboard NIS2 dedie dans Wazuh Dashboard
(= OpenSearch Dashboards), organise par article NIS2 (21.2.b auth, 21.2.c
continuite, 21.2.e integrite+reseau, 21.2.i comptes). Code IaC : nouveau
role Ansible `wazuh_dashboard_nis2_pack` + playbook
`deploy_wazuh_dashboard_nis2.yml` (ansible repo commit `14cb188`).

**Contenu pack -- 13 saved_objects** :

| ID | Type | Couverture |
|----|------|------------|
| `nis2-m1-total` | metric | Total alertes `rule.groups:nis2` (big number) |
| `nis2-m2-agents` | metric | Cardinality `agent.id` -- cible 8/8 |
| `nis2-m3-high` | metric | Alertes `level>=10` AND `nis2` (high+critical) |
| `nis2-p1-auth-failures-by-rule` | pie | art.21.2.b -- 100001 SSH / 100007 SU / 100011 SMTP / 100014 LDAP |
| `nis2-p2-auth-priv-timeline` | area stacked | art.21.2.b -- timeline 8 regles auth+priv stack par rule.id |
| `nis2-p3-brute-force-table` | table | art.21.2.b -- 100004/100012 (brute force SSH+SMTP) |
| `nis2-p4-service-stop-table` | table | art.21.2.c -- 100006 (samba/mariadb/wazuh/nginx/squid stop) |
| `nis2-p5-fim-critical-bar` | histogram | art.21.2.e -- 100003/100010 FIM critiques |
| `nis2-p6-firewall-drops-line` | line | art.21.2.e -- 100009 firewall drops volumetrie |
| `nis2-p7-network-pivot-table` | table | art.21.2.e -- 100013 pivot mail01 hors flux |
| `nis2-p8-account-lifecycle` | area stacked | art.21.2.i -- 100008/100400-402 customs + 5901/5902/5903 Wazuh defaults |
| `nis2-p9-top-users` | bar horizontal | art.21.2.i -- top agents (proxy identite) sur ops comptes |
| `nis2-nova-syndicate` | dashboard | layout 48-col grille, 6 rows, 12 panneaux |

**Pattern technique** (apprentissages session) :
- **Filter `bool/match_phrase` au lieu de KQL `query`** -- pilote v1 (KQL `rule.id : ("100001" or ...)`) rendait camembert vide cote UI ; pilote v2 (filter bool) rend correctement. KQL parser cote OpenSearch Dashboards 2.16 a un comportement subtil pour les terms quotes ; bool filter est universel.
- **References explicites** : 1 entry pour `query.index` + 1 par `filter[i].meta.index` -- omettre la 2e casse le rendu silencieusement.
- **migrationVersion** : `visualization: 7.10.0` + `dashboard: 7.9.3` -- correspond a la matrice de compat OpenSearch Dashboards 2.x heritee Kibana.
- **POST multipart sur `_import?overwrite=true`** -- idempotent ; remplace si IDs deja presents.

**Application live** : `curl` admin bit-identique a la task `uri` Ansible, faute de bastion-nova ControlMaster actif (meme pattern que pour T-WAZUH-INDEXER-ALIAS-DAILY du matin). Verification import :
```
{"success":true,"successCount":13, ...}
```

**URL acces jury** :
```
https://siem.nova-syndicate.local/app/dashboards#/view/nis2-nova-syndicate
```
Necessite Authelia SSO + admin OpenSearch security (mdp = `WAZUH_INDEXER_PASSWORD` live dans `/etc/default/grafana-server`, drift connu avec rotation file cf T-VAULT-OPNSENSE-PASSWORDS-MIGRATE).

**Note jury sur panneaux vides** : P4 (service stop) + P7 (network pivot mail01) afficheront vide -- 0 hit historique pour 100006/100013. Comportement attendu (le panel capture l'event si declenche). Pour la demo : montrer P1/P2/P3/P5/P8/P9 qui ont des donnees grace au test live db01 du Bloc 5.

### Dettes ouvertes ce jour

| Ticket | Severite | Description |
|--------|----------|-------------|
| **T-DB01-SU-NO-PASSWORD** | **HIGH (a corriger avant soutenance -- faille triviale qu'un jury verrait)** | `su - root` depuis l'utilisateur `debian` sur db01 **REUSSIT sans demander de mot de passe**. Preuve empirique Bloc 5 : event #4, log `Jun 04 14:52:00 db01 su[121378]: pam_unix(su-l:session): session opened for user root(uid=0) by (uid=0)` -- PAM session ouverte pour root sans prompt password. Risque : escalade root triviale depuis tout compte debian compromis (par ex. session SSH apres vol de cle). **Audit a faire (hors session) sur les 8 VMs Wazuh-agentees (app01, backup01, proxy-lyon01, dc01, fs01, db01, bastion01, mail01)** : (a) inspecter `/etc/pam.d/su` -- chercher `pam_rootok.so` mal place ou `pam_wheel.so trust` ; (b) verifier appartenance `debian` aux groupes `wheel`/`sudo`/`root` (`id debian` puis `getent group wheel sudo root`) ; (c) verifier `/etc/shadow` ligne `root` (compte locked attendu : `root:!:...`). Correction probable : retirer `pam_rootok` ou ajouter `auth required pam_wheel.so use_uid` apres le rootok. **A corriger avant soutenance.** |
| **T-WAZUH-NIS2-100001-INVALID-USER-COVERAGE** | MEDIUM | Rule 100001 (NIS2 art.21.2.b "Tentative authentification SSH echouee") **ne couvre pas le pattern `Invalid user`** (user enumeration). Preuve Bloc 5 event #1 : `ssh nonexistent_siem_test@127.0.0.1` -> rule 5710 firee (Wazuh default sshd), rule 100001 silencieuse car la regex stricte `Failed password\|Failed keyboard-interactive\|authentication failure` ne match pas `Invalid user nonexistent_siem_test from 127.0.0.1`. Fix : ajouter `<if_sid>5710</if_sid>` en variant (heritage de la detection sshd default) OU elargir la regex avec `Invalid user`. Affecte la posture audit NIS2 (vecteur user-enumeration non remonte au SOC). Fichier a editer : `roles/wazuh_manager/templates/nova_nis2_rules.xml.j2` (ou equivalent) cote ansible. |
| **T-WAZUH-NIS2-100008-AUDIT-DEDUP** | LOW | Un seul `useradd` + un seul `userdel` genere **24 alertes 100008** (chaque message kernel audit : SYSCALL/PATH/EXECVE/ADD_USER/ADD_GROUP/DEL_USER/DEL_GROUP/EXIT match `useradd\|userdel\|usermod\|groupadd\|groupdel`). Sature les dashboards. Fix : contraindre rule 100008 a `<match>useradd:\|userdel:\|new user:\|delete user '\|new group:\|delete group '</match>` (formats user-space stables) et/ou exclure les events `kind=audit` du decoder. Volet complementaire a T-WAZUH-AUDIT-DEDUP (deja resolu sur scope dc01 audit.log nova-iam le 24/05). |
| **T-WAZUH-ALIAS-ANSIBLE-SYNC** | LOW | Le code IaC de l'alias est dans `roles/wazuh_indexer/tasks/aliases.yml` (+ playbook `deploy_wazuh_indexer_alias.yml`) mais a ete applique cette session via `curl` admin TLS faute de `bastion-nova` ControlMaster actif. Replay attendu : `ansible-playbook playbooks/deploy_wazuh_indexer_alias.yml --limit app01` doit reporter `ok=2 changed=0` (template PUT idempotent, _aliases backfill `changed_when=false`). A faire a la prochaine session avec MFA bastion ouverte. |
| **T-WAZUH-INDEXER-INDICES-GAP-2026-05-30-31** | LOW (post-certif) | Trou de 2 jours dans la sequence `wazuh-alerts-4.x-YYYY.MM.DD` (pas de 05.30 ni 05.31). A confronter aux logs app01 de ces dates (potentiellement OOM recidive entre T-APP01-SWAP-ADD du 24/05 et le menage du 03/06). N'affecte pas l'indexation courante. |
| **T-GITHUB-ORPHAN-COMMIT-RESIDUAL** | LOW (accepte) | Le commit `50e69eb` (pre-rewrite, contient la cle leake) reste resolvable par URL directe sur github.com pendant ~90 jours post force-push. Cle INERTE (cf Bloc 4 -- `/srv/borg-repo` supprime, repo etait vide). Pas d'action GitHub support, pas de recreation du repo. Echeance d'expiration GitHub estimee : **~2026-09-02**. Pas de monitoring requis, le risque est nul. |
| **T-PRECOMMIT-BORG-REPOKEY-PATTERN** | MEDIUM | Le pre-commit `gitleaks` (filet local) n'a pas catch le repokey Borg lors du commit `50e69eb` (10:56). Le pattern entropie-based `generic-api-key` a fonctionne **server-side seulement** (workflow GitHub Actions, scan full-history). Action : ajouter au `.pre-commit-config.yaml` une regex ad-hoc sur le pattern `^key = hqlh[A-Za-z0-9+/=]{40,}` (debut du wrapper repokey Borg) pour bloquer au commit local. Cible : nova-syndicate-proxmox + nova-syndicate-ansible (les 2 repos qui captent des preuves). |
| **T-BACKUP01-LEFTOVER-CLEANUP** | LOW | Apres validation finale par operateur : `shred -u /root/.borg-passphrase-pre-rotation-20260604.bak` (filet 0.3, doublon de `/etc/borg/passphrase`) + `rm /usr/local/sbin/borg-rotation-step.sh` (script de session, contient des chemins mais aucun secret) + retrait snapshot Proxmox `pre-borg-passphrase-rotation-20260604` VMID 109 + retrait mirror `/tmp/nova-syndicate-proxmox-prerewrite-20260604.git` Mac. |
| **T-WAZUH-DASHBOARD-NIS2-ANSIBLE-SYNC** | LOW | Pack NIS2 (role `wazuh_dashboard_nis2_pack` commit ansible `14cb188`) applique live cette session via `curl` admin (bastion-nova MFA ControlMaster non actif). Replay attendu : `ansible-playbook playbooks/deploy_wazuh_dashboard_nis2.yml --limit app01 --ask-vault-pass` doit reporter `ok=4 changed=0` (overwrite=true idempotent). A faire prochaine session bastion ouverte. |
| **T-VAULT-WAZUH-INDEXER-PASSWORD** | MEDIUM | `vault_wazuh_indexer_admin_password` reference dans le role `wazuh_dashboard_nis2_pack/defaults` mais ABSENT du vault `inventory/group_vars/all/vault.yml`. Le secret vit actuellement en plaintext dans `/etc/default/grafana-server` + `nova-iac-secrets/rotation-2026-05-18.txt` (off-repo). Action : `ansible-vault edit` pour ajouter `vault_wazuh_indexer_admin_password: <valeur live>`. Volet de T-VAULT-OPNSENSE-PASSWORDS-MIGRATE etendu aux secrets Wazuh. |

### Dette fermee ce jour

- **T-WAZUH-INDEXER-ALIAS-DAILY** (`docs/INFRA-INVENTORY.md:298-300`) :
  RESOLUE 2026-06-04. Alias `wazuh-alerts -> wazuh-alerts-4.x-*` cree
  via template contributif `wazuh-alias` (order=1), backfille sur les
  16 indices existants. Code IaC dans role `wazuh_indexer` (commit
  ansible `7e4c6ec`). Verification cote Grafana renvoyee a la prochaine
  session (cf bloc 2).
- **T-WAZUH-DASHBOARD-NIS2-CUSTOM** : **RESOLUE 2026-06-04 (soir)**.
  Pack 13 saved_objects (3 metrics + 9 visus + 1 dashboard) deploye via
  `_import?overwrite=true`, organise par article NIS2 (21.2.b auth, .c
  continuite, .e integrite+reseau, .i comptes). Code IaC : role
  `wazuh_dashboard_nis2_pack` + playbook `deploy_wazuh_dashboard_nis2.yml`
  (ansible commit `14cb188`). URL acces :
  `https://siem.nova-syndicate.local/app/dashboards#/view/nis2-nova-syndicate`.
  Verification import : `success:true successCount:13`. Cf Bloc 6.
  Replay Ansible : dette T-WAZUH-DASHBOARD-NIS2-ANSIBLE-SYNC ouverte.

## Session 2026-06-03 (soir) -- RECO IPsec + WireGuard road-warrior, dettes IaC ouvertes

### Bloc 1 -- RECO IPsec inter-sites (lecture seule)

Diagnostic Phase 1 audit sante du matin **corrige** : IPsec FONCTIONNE deja.
Mon "charon Command not found" etait un artefact tcsh+ssh. Realite : 1 IKE SA
ESTABLISHED depuis ~7h36 entre 10.0.0.2 et 10.0.2.2, 4 child SAs INSTALLED
(bastion/29 + servers/28 + users/26 + backup/29 <-> MRS /26), trafic reel sur
le tunnel SERVERS. Plan de demo livre dans
[docs/runbook-ipsec-buildout.md](docs/runbook-ipsec-buildout.md) (commit `a6aad27`).

Tickets ouverts par cette RECO :
- **T-IPSEC-PERSISTENCE-SCRIPTS** (MEDIUM) -- `nova_ipsec_fix` + `fix_ipsec_children.py` absents, risque ecrasement swanctl.conf via GUI OPNsense.
- **T-OPNSENSE-IPSEC-SERVICE-WRAPPER** (LOW) -- `service ipsec onestatus` ment ("not running" alors que charon tourne). Healthcheck a corriger.
- **T-IPSEC-CERT-MIGRATION** (LOW post-certif) -- migration PSK -> certs step-ca, V2.
- **T-ADR-2-5-SYNC-RUNTIME** (LOW) -- ADRs 0002 et 0005 utilisent prefixes 10.x non deployes, runtime utilise 192.168.x.
- **T-OPNSENSE-TCSH-BASE64-PATTERN** (DOC) -- pattern SSH base64-encoded vers OPNsense pour bypass tcsh.

### Bloc 2 -- WireGuard road-warrior demo (Option 3 revue) -- handshake OK, data routing reste a finaliser

Plan d'execution dans
[docs/runbook-wireguard-roadwarrior-demo.md](docs/runbook-wireguard-roadwarrior-demo.md).
Ecart vs plan initial : DNAT cote Proxmox host (cf ADR-0017), pas cote
OPNsense (provider Terraform ne supporte pas).

**Etat au soir 2026-06-03** :

| Etape | Statut | Detail |
|-------|--------|--------|
| Prerequis P1 vmbr3 IP | **RESOLU** | Runtime + persistance, cf ticket T-VMBR3-DMZ-IP RESOLU ci-dessous |
| Prerequis P2 DNAT iptables | DEJA EN PLACE | regle pre-existante `udp dpt:51820 -> 172.16.1.4:51820` (compteurs DNAT=10/1188, FORWARD vmbr0->vmbr3=442/77792) ; restriction `-i vmbr0` toujours active mais suffisante pour le path `box -> nic0 -> vmbr0` |
| Handshake matthieu-mac | **RESOLU 2026-06-03 20:50:40** | dmesg kernel : `Receiving handshake initiation from peer 1 (185.55.247.170:59081)`, `Sending handshake response`, `Keypair 44 created for peer 1`. wg show : `endpoint 185.55.247.170:59081`, transfer `7.23 KiB received, 4.49 KiB sent`. Persistent keepalive 25s. |
| Side-fix client | -- | Address Mac corrigee en `10.20.0.10/24` (etait `/32` initialement). Pubkey serveur dans `[Peer]` confirmee `9ExSPQD6PWsFChdoX3SDEkY8ZppRnvXmH78SKM0vvy4=`. |
| MASQUERADE vpn-gw01 (Option A) | **APPLIQUE 2026-06-04** | `iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE` + persistance dans `/usr/local/sbin/wg-policy-routing.sh` (up/down) avec pattern `-C` puis `-A` idempotent. Backup `/usr/local/sbin/wg-policy-routing.sh.bak-pre-wg-masq-20260604`. Snapshot Proxmox `pre-wg-data-fix-20260604` (VMID 110 @ 08:40:06). Survit reboot via PostUp `wg-quick@wg0`. Compteur 0/0 a date (aucun data plane confirme via cette regle, cf ligne suivante). |
| Data plane intra-tunnel | **PARTIEL** | Diag tcpdump 4 captures (wg0, eth0, vmbr0 Proxmox, conntrack ICMP) en parallele avec pings 4G + LAN client : 0 paquet ICMP arrive sur `wg0` cote serveur, 0 sur `eth0`, 0 evenement conntrack ICMP, MASQUERADE counter 0/0. Le tunnel WG cote serveur ne recoit QUE des handshakes (UDP 148/92 bytes a intervalle 5s), aucun paquet data. Validation externe non finalisable depuis l'environnement de test : (a) box Regies Moselle (`185.55.247.170`) ne hairpinne pas l'UDP pour le data flow (handshake passe mais pas le data continu) ; (b) 4G du Mac = IPv6-only avec NAT64 (destination `64:ff9b::/96`), Endpoint WG IPv4 inatteignable. **Tunnel etabli + chiffrement prouve cote serveur** (wg show : endpoint `92.184.125.86:49689` actif depuis 4G, transfer 153.78 KiB rcv / 1.01 MiB sent). Validation acces ressources internes via tunnel = reportee post-certif (besoin client externe IPv4-routable hors environnement actuel). |

Dettes ouvertes par cette RECO :

| Ticket | Severite | Description |
|--------|----------|-------------|
| **T-VMBR3-DMZ-IP** | RESOLU 2026-06-03 (soir) | IP `172.16.1.5/29` posee runtime (`ip addr add`) + persistance `/etc/network/interfaces` (stanza `inet manual` -> `inet static address 172.16.1.5/29`). Backup `/etc/network/interfaces.bak-pre-vmbr3-ip-20260603`. Effet immediat verifie : `ip route show 172.16.1.0/29 -> dev vmbr3`, `ping 172.16.1.4 0.09 ms`. Cote WireGuard : forward `vmbr0 -> vmbr3 = 268 pkts` (avant 0), paquets arrivent enfin a vpn-gw01. |
| **T-TF-OPNSENSE-NAT-NO-SUPPORT** | LOW | Provider `browningluke/opnsense` 0.16 ne supporte pas `opnsense_firewall_nat` ni `_port_forward`. Confirmation STATUS Phase II §1. Consequence : aucun DNAT/port-forward sur OPNsense codable en Terraform. Alternative -> Ansible-on-Proxmox-host (cf T-IPTABLES-ANSIBLE-PROXMOX). |
| **T-IPTABLES-ANSIBLE-PROXMOX** | MEDIUM | Pas de role Ansible pour les regles iptables sur Proxmox host (`/etc/iptables/rules.v4`). Aujourd'hui modifications manuelles persistees via `iptables-save` (operationnel mais non reproductible). A integrer dans **T-IAC-BRIDGES-PROXMOX-HOST** (cf audit IaC §6.1). |
| **T-IPTABLES-MASQUERADE-DUPLICATE** | LOW | Chain POSTROUTING Proxmox contient des MASQUERADE en doublon pour `192.168.15.0/29`, `192.168.20.0/28`, `192.168.50.0/29` (3 IPs x 2 entrees identiques). A investiguer + nettoyer hors session demo. |
| **T-WG-WGCONF-CLIENT-VAULT** | LOW | Configs client `matthieu-mac` + `vps-hetzner-test` referencees mais cles privees off-repo, sans convention de stockage definie. A definir (1Password, vault Ansible, ...). |
| **T-WG-ROADWARRIOR-VALIDATION-EXTERNE** | LOW (post-certif) | Validation acces ressources internes via tunnel WG Nova depuis un vrai client externe IPv4-routable. Bloque aujourd'hui par contraintes environnement de test : hairpinning UDP partiel de la box Regies Moselle (handshake OK, data plane KO) + IPv6-only NAT64 sur 4G personnelle (Endpoint WG IPv4 inatteignable). Le VPS Hetzner existant joue le role de serveur du tunnel backup BACKUP01 (`10.30.0.1`), pas client road-warrior -- a transformer en client necessiterait un wg1 dedie + nouvelle paire de cles + update peer cote serveur Nova (scenario C/D). A reprendre en session dediee depuis un VPS externe dedie OU un client IPv4-routable hors box Regies Moselle (ex : co-working, 4G IPv4 dual-stack, ou VM cloud temporaire). Tunnel + chiffrement + acquis infra (MASQUERADE, vmbr3) deja prouves cote serveur. |
| **T-WG-CLEAN-PEER-VPS-HETZNER** | LOW | Peer `vps-hetzner-test` (`fPVzZDtvUydP4gi+4yNulEwuG9+JFtVjdZtYAKbvx3o=`, AllowedIPs `10.20.0.20/32`) configure dans `/etc/wireguard/wg0.conf` cote vpn-gw01 mais jamais utilise en pratique (le VPS sert le tunnel backup, pas un client road-warrior). Cleanup propre = retrait dans la source Ansible (`host_vars/vpn-gw01.yml` ou role `vpn_gateway`) puis replay du role. NE PAS editer live (fichier annote `# Managed by Ansible -- role: vpn_gateway -- DO NOT EDIT MANUALLY`). |
| **T-WG-ANSIBLE-ROLE-MASQUERADE-SYNC** | MEDIUM | Le MASQUERADE pose live ce matin dans `/usr/local/sbin/wg-policy-routing.sh` (PostUp/PostDown wg0) sera ecrase par le prochain `ansible-playbook deploy_vpn_gw.yml`. A re-synchroniser dans le role Ansible `vpn_gateway` (tasks/policy_routing.yml ou equivalent) : ajout des lignes `iptables -t nat -C/-A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE` (up) + `-D` (down). Backup off-repo : `/usr/local/sbin/wg-policy-routing.sh.bak-pre-wg-masq-20260604`. |

## Session 2026-06-03 -- audit sante + menage services failed -- 13/13 VMs propres

Audit complet runtime + remise en marche avant session captures jury.
Diagnostic lecture seule puis reparations ciblees apres validation.

### Resultat ménage (13/13 VMs avec 0 service failed)

| Action | Cibles | Effet |
|--------|--------|-------|
| `systemctl disable --now openipmi` + reset-failed | 10 VMs (web01, mail01, bastion01, dc01, fs01, db01, app01, proxy-lyon01, proxy-mrs01, backup01) | LSB OpenIPMI driver desactive (hardware inexistant sur VM, BENIN). 3 VMs sans le paquet (vpn-gw01, awx01, pki01). |
| `systemctl disable --now isc-dhcp-server` + reset-failed | dc01 | Service ne pouvait pas servir (subnet declare 192.168.30.0/26 VLAN Users mais dc01 = eth0 192.168.20.10/28 VLAN 20). JAMAIS-FINALISE. -> dette **T-DHCP-USERS-VLAN** ouverte. |
| `systemctl reset-failed cloud-final` | pki01 | Echec one-shot APT update au 1er install (1er juin, DNS template 9000 KO). step-ca tourne. Etat failed historique nettoye. |
| drop-in `/etc/systemd/system/dnsmasq.service.d/wait-wg0.conf` (`After=wg-quick@wg0.service` + `Requires=`) + restart | vpn-gw01 | Race condition systemd resolue : dnsmasq tente de bind 10.20.0.1 avant wg0 up. Persiste au reboot. -> dette **T-DNSMASQ-WG0-ORDERING** marquee RESOLUE. |

Verification finale : `systemctl --failed --no-legend | wc -l` retourne `0` sur les 13 VMs Linux.

### Borg backups -- correction de diagnostic

Diagnostic initial Phase 1 erronne ("borgbackup-nova.timer inactive"). En realite :
- **Le timer systemd N'EXISTE PAS**. La planification est via cron classique :
  `/etc/cron.d/borg-cloud-backup : 30 23 * * * root /usr/local/bin/borg-cloud-sync.sh ...`
- **Le backup CLOUD vers Hetzner FONCTIONNE deja** (preuve dry-run 2026-06-03 12:57) :
  - Tunnel WireGuard backup01 (10.30.0.2) -> Hetzner (10.30.0.1) actif (handshake 1 min 39 s avant le check).
  - 5 archives sur le VPS, dont **backup01-2026-06-02-2330** (hier soir).
  - Ping 37 ms, transfer 603 KiB recus + 3.37 MiB envoyes (compteur live).

**Dette T-IAC-BORG-ROLE** (audit catégorie B EVOLUTIONS) reste valide UNIQUEMENT pour la dimension "role Ansible reproductible". Le DRP runtime est operationnel des aujourd'hui.

### Precisions IPsec Phase II §4 -- "daemon non demarre" -> "package non installe"

Diagnostic SSH FW-EXT-LYON via `-J opn-fw-int-lyon root@10.0.1.1` confirme :
- `charon: Command not found` (binaire absent du PATH).
- `pgrep charon` = vide.
- `swanctl --list-sas` et `--list-conns` = vides.
- `last reboot` depuis 2026-05-07 -- aucune trace de demarrage strongswan.
- ping FW-EXT-LYON -> 10.0.2.2 (WAN MRS) ou 192.168.40.1 (LAN MRS) : 100 % packet loss.

**STATUS Phase II §4 ("strongSwan present mais daemon non demarre") etait imprecis** :
le binaire `charon` n'est meme pas installe. C'est plus profond qu'un service down.
Effort de remise en service Phase IV = install pkg + cert step-ca + swanctl.conf x 2 firewalls.

FW-EXT-MRS non sonde directement (reseau coupe, chaine SSH cassee). Posture presumee identique.

### Services metier critiques au jour de cette session

13/13 services actifs (cf [docs/health-snapshot-2026-06-03.md](docs/health-snapshot-2026-06-03.md)
pour le detail visuel). Aucune regression metier detectee.

### Snapshots Proxmox a nettoyer (apres validation finale par l'operateur)

Snapshots filets pris avant le menage du 3 juin :
- VMID 103 (dc01) : `dc01-pre-menage-failed-services-20260603` (2026-06-03 12:52:22)
- VMID 110 (vpn-gw01) : `vpn-gw01-pre-dnsmasq-ordering-20260603` (2026-06-03 12:52:22)

A supprimer apres :
1. Confirmation que les changements (openipmi/isc-dhcp/dnsmasq drop-in) tiennent au reboot.
2. Aucune regression detectee lors de la session captures jury.

Snapshots residuels des sessions precedentes a nettoyer egalement (cf STATUS sections 2026-06-02 et plus anciennes) :
- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (2026-06-02 09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps`, `dc01-pre-strong-auth`, `dc01-pre-iac-reformat-smbconf`
- 5 snapshots dc01 cumules en moins de 24 h, a nettoyer en lot.

## Session 2026-06-02 -- audit IaC READ-ONLY -- tickets ouverts

Audit lecture seule de la couverture IaC vs runtime reel : 17 VMs + 4 OPNsense,
3 dirs Terraform, 20 roles Ansible, 34 ADRs. Livrable :
[docs/iac-coverage-audit-2026-06-02.md](docs/iac-coverage-audit-2026-06-02.md).

Couverture mesuree : **~75 % en volume / ~30 % en sequencabilite** (chaine
rebuild enchainable). 8 ruptures identifiees dont 5 manuels irreductibles
(install PVE, OPNsense ISO+1er boot, OPNsense API keys, step-ca Root CA init,
Vault un-sealing). Posture realiste = "une commande par phase" atteignable en
4-6 semaines de chantiers M.

Tickets ouverts a partir de l'audit, scindes en deux categories :

### Categorie A -- CORRECTIONS (bugs reels a fixer)

| Ticket | Severite | Description | Reference |
|--------|----------|-------------|-----------|
| **T-IAC-SITE-YML-ETAPE-7** | LOW | `nova-syndicate-ansible/site.yml` ligne 59 : ETAPE 7 ("VPN WireGuard + IPsec") cible `hosts: domain_controllers` au lieu de `vpn_gateways`. Probable copier-coller. Aucun apply recent n'a tourne cette etape (sinon dc01 aurait recu une config WireGuard). Trivial a corriger : changer une ligne + verifier en `--check`. | Audit §3.2 (anomalie ETAPE 7) |
| **T-IAC-WIREGUARD-DRIFT** | MEDIUM | Source de verite WireGuard ambigue : 3 fichiers candidats hors `nova-syndicate-proxmox` -- `nova-syndicate-ansible/terraform/environments/lyon/wireguard.tf` (910 oct, contenu), `nova-syndicate-ansible/terraform/environments/lyon/ireguard.tf` (0 oct, **typo**), `terraform/environments/lyon/wireguard.tf` (888 oct, top-level). Aucun fichier dans le repo proxmox. Decision a prendre : consolider dans `nova-syndicate-proxmox/terraform/environments/opnsense/` ou ailleurs, supprimer les duplicats et la typo. | Audit §7.1 (decouverte 2) |
| **T-IAC-CLEAN-LEGACY-TF** | LOW | Deux dirs `terraform/environments/lyon/` (sous `nova-syndicate-ansible/` et top-level) sont des orphelins Phase II pre-renommage en `opnsense/`. Pas de tfstate visible dans les deux. Recouvre partiellement T-IAC-WIREGUARD-DRIFT : nettoyer les 2 dirs ferme aussi le drift WireGuard si la source est migree avant. | Audit §3.1 (Repos legacy) |

### Categorie B -- EVOLUTIONS post-certification (chantiers de couverture, non bloquants)

Aucun de ces tickets n'est requis pour la certification. Ils ferment la dette
"reproductibilite IaC" identifiee par l'audit. Ordre suggere = ordre du tableau.

| Ticket | Effort | Valeur | Description | Reference |
|--------|--------|--------|-------------|-----------|
| **T-IAC-BRIDGES-PROXMOX-HOST** | S (~1 jour) | ELEVEE | Scripter `/etc/network/interfaces` Proxmox host (bridges vmbr0..5 + sub-VLAN .15/.20/.50/.60) via un mini-role Ansible ciblant un group `proxmox` (`ansible_user=root`). Ferme dette Phase II §5 partiellement. Risque bas (rollback `/etc/network/interfaces`). | Audit §4.1, §6.1 #1 |
| **T-IAC-TEMPLATE-9000-BUILD** | M (~3-5 jours) | ELEVEE | Scripter la creation du template Debian 12 cloud-init VMID 9000 : download cloud image -> `qm create` -> `qm importdisk` -> `qm set --ide2 cloudinit` -> customisation (fix systemd-resolved DNS cf memory `nova-cloud-init-template-dns-issue`, `qm set --sshkeys`) -> `qm template`. Cle de voute Phase VI : sans ce script, terraform apply ne tourne pas. | Audit §4.2, §6.1 #2 |
| **T-IAC-AWX01-K3S-AWX** | M (~5-10 jours) | MOYENNE | 3 sous-roles Ansible : (1) `k3s_server` (binaire + config `disable: [traefik]`, files presents dans `nova-syndicate-ansible/files/awx/k3s-config.yaml`) ; (2) `awx_operator` (helm + CR YAML) ; (3) `awx_objects` (Org + Credentials + Project + Inventory + JT + Teams + AUTH_LDAP_TEAM_MAP via API REST, cf ADR-0031/0033). Risque : objets crees a chaud, prevoir tests en sandbox. | Audit §4.9, §6.1 #3 |
| **T-IAC-AUTHELIA-ROLE** | M (~3-5 jours) | MOYENNE | Role Ansible `authelia` (install + `configuration.yml` template + secrets vault + LDAP backend ldaps://dc01:636). Touche tout l'acces SSO (Grafana, futur Wazuh dashboard, portail metier). Faible risque, gros gain narratif NIS2. | Audit §4.5, §6.1 #4 |
| **T-IAC-BORG-ROLE** | S-M (~3-5 jours) | MOYENNE | Roles `borg_repo` (backup01 cote serveur, init repo append-only) + `borg_client` (cles, exclusions, scheduling). Reference ADR-0008 (`repokey-append-only`) + ADR-0009 (3-2-1-1-0). Sans ca, le DRP est partiellement manuel. | Audit §4.6, §6.1 #5 |
| **T-IAC-APP01-STACKS-NOT-CODED** | M (par stack, MEDIUM agrege) | HIGH (NIS2 reproductibilite) | Meta-ticket : Authelia (cf T-IAC-AUTHELIA-ROLE), Grafana, Vault, nginx reverse-proxy = pas de role Ansible. ADRs 0019 (Authelia), 0030 (Grafana), 0026 (Vault plaintext fix lab) existent mais le code IaC manque. Dette importante en termes de NIS2 "reproductibilite". A decomposer en 3 sous-tickets Grafana/Vault/nginx une fois T-IAC-AUTHELIA-ROLE clos (modele de reference). | Audit §4.5, §7.1 #4 |

Chantiers explicitement **ECARTES** (effort eleve, gain nul ou anti-pattern,
detail audit §6.2) :
- step-ca Root CA init (decision humaine NIS2, irreductible)
- OPNsense ISO bootstrap + 4 API keys (limite produit, pas de cloud-init OPNsense)
- Install PVE sur le fer (pre-requis physique)
- Vault APP01 un-sealing automatique (anti-pattern securite tant que `tls_disable=true` reste choix lab)

## Session 2026-06-02 -- complement (Phase 7a) -- Strong auth applique, listener 389 conserve

Pre-check tcpdump cote serveur dc01 (eth0 any, `tcp port 389 or udp port 389`,
fenetre 90 s avec triggers : Authelia restart, mail01 doveadm, fs01 wbinfo,
samba-tool user list) : **28 paquets capturees, source unique 192.168.20.11
(fs01)** = `winbindd` (PID 12858, FD 24, ESTAB 39546->389) + CLDAP UDP.

Analyse ASN.1 du premier payload : `searchRequest base="" filter=objectclass=*
attr=currentTime` -- requete **anonyme au RootDSE** (decouverte AD standard).
Apres : bind GSSAPI/Kerberos avec `client ldap sasl wrapping = seal` (chiffrement
+ integrite). Pas un cleartext simple bind.

**Decision retenue** : decoupler Phase 7 en deux. **7a applique** (refus simple
bind cleartext) ; **7b refusee** (fermeture listener 389) car casserait winbind
fs01 jusqu'a migration sssd-ad ou Samba membre 636.

| Action | Statut | Detail |
|--------|--------|--------|
| Pre-check tcpdump cote dc01 | **DONE** | pcap archive : `docs/evidence/389-incoming-pre-strong-auth-2026-06-02.pcap` (20855 octets). |
| Snapshot `dc01-pre-strong-auth` | **DONE** | 2026-06-02 17:38:01 (VMID 103). |
| Default Samba 4.15+ deja a `Yes` -- `testparm` confirme | **DONE** | Pin explicite necessaire pour survivre aux upgrades futurs. |
| `inventory/group_vars/domain_controllers/vars.yml` : `samba_ldap_require_strong_auth: false -> true` | **DONE** | Aligne IaC (template `dc/templates/smb.conf.j2` avait deja le toggle conditionnel). |
| Edition live `/etc/samba/smb.conf` + `ldap server require strong auth = yes` sous `[global]` | **DONE** | Backup `smb.conf.bak-prestrongauth-2026-06-02`. |
| `systemctl restart samba-ad-dc` | **DONE** | `active` apres 6 s. `testparm` post-restart : `Yes`. Listeners 389 + 636 toujours presents (decision 7b assume). |
| Cross-checks 8/8 | **DONE** | fs01 wbinfo -u (94 users), wbinfo -t (trust OK), getent passwd fabien.bonnet/marine.fleury (resolu), **wbinfo -a "svc-mail-ldap%..." = plaintext + challenge/response succeeded** ; Authelia HTTP 200 ; mail01 doveadm auth succeeded ; Wazuh 8 Active ; samba-tool user list 95 lignes. |
| Phase 7b -- desactivation listener 389 | **REFUSEE (posture finale assumee)** | 389 reste ouvert, durci par strong-auth. Seuls binds GSSAPI-sealed l'empruntent (= winbind fs01). Detail ADR-0034. |

Findings clos cette session **definitivement** :
- **P-001** (bind LDAP anonyme HIGH) : **RESOLU** via `ldap server require strong auth = yes` pinne dans smb.conf. Refus simple bind cleartext applique cote dc01. Verifie effectif par testparm + cross-checks. Les binds GSSAPI-sealed (winbind) et LDAPS (Authelia + Dovecot) restent autorises.
- **P-002** (mkcert non-PKI LOW) : **RESOLU** via step-ca. mail01 et Authelia chaines sur Nova Root + Intermediate CA.
- **T-LDAPS-MIGRATION** : **CLOS**.

Nouvelle dette filiale :
- **T-FS01-LDAPS-OR-SSSD** (LOW, decision d'archi differee, hors scope certification) -- pour permettre une eventuelle fermeture future du listener 389 sur dc01 (Phase 7b), il faudrait au prealable basculer fs01 vers un client AD nativement LDAPS-capable. Trois options documentees, **aucune tranchee** :
  1. **Migration winbind -> sssd-ad** : sssd supporte nativement `ldap_uri = ldaps://dc01.nova-syndicate.local`. Refonte complete du daemon d'auth + PAM + NSS sur fs01. Effort eleve, gain principal = chemin LDAPS pur.
  2. **Reconfiguration Samba membre pour LDAPS 636** : ajuster `client ldap sasl wrapping`, `ldap server`, et resolution SRV `_ldap._tcp.NOVA-SYNDICATE.LOCAL.` pour forcer 636. Non trivial (Samba historique est cable 389+SASL), risque de regression silencieuse sur SMB join/trust.
  3. **nft allowlist 389 sur dc01** : conserver le listener 389 mais filtrer en host nft pour n'accepter que `192.168.20.11/32` (fs01) + IPs admin legit. Conserve la posture actuelle avec un perimetre reseau plus etroit. Compatible avec Phase 7a (strong auth) deja en place.

Posture finale assumee Phase 7 (a documenter dans ADR-0034) : **389 reste
ouvert, hardened par strong-auth + chiffrement GSSAPI cote winbind + listeners
distincts 389/636**. Surface d'attaque reduite a "simple bind cleartext refuse"
+ "anonymous bind limite au RootDSE". Mitigation conforme NIS2 art.21 §2 (e+i).

Snapshots Proxmox a nettoyer post-validation finale :
- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps` (09:14:04), `dc01-pre-strong-auth` (17:38:01)

ADR de cloture : [ADR-0034](docs/adr/ADR-0034-ldaps-migration-strong-auth.md).

**Drift IaC ouvert (non commit ce soir)** : `nova-syndicate-ansible/inventory/group_vars/domain_controllers/vars.yml` doit passer `samba_ldap_require_strong_auth` a `true` pour aligner l'IaC avec l'etat live dc01. Non commit cette session : la branche actuellement checked-out (`fix/wazuh-agent-pin-411-adr0013`) contient 6 autres fichiers M WIP non lies a Phase 7a + 3 dossiers untracked (`group_vars/pki/`, `roles/pki_client/`, `roles/pki_server/`). A normaliser au prochain merge sur `main` (toggle + bloc `samba_ldaps_*` keys + commentaires Phase 7a).

## Session 2026-06-02 (T-LDAPS-MIGRATION) -- Bascule trust anchor Dovecot vers step-ca

Migration LDAPS de Dovecot (mail01) de l'ancienne CA mkcert vers la chaine
PKI interne step-ca. Plan d'execution autoritatif :
[runbook-ldaps-migration.md](docs/runbook-ldaps-migration.md) (versionne
explicitement pour survivre a `/clear`). Rapport detaille :
[ldaps-migration-report.md](docs/ldaps-migration-report.md).

| Etape | Statut | Detail |
|-------|--------|--------|
| 6.3 (10 etapes) | **RESOLU** | Snapshots OK ; CA bundle deploye sur mail01 (nova-root + intermediate via `qm guest exec`) ; `update-ca-certificates` 2 added ; handshake `Verify return code: 0 (ok)` ; sed chirurgical 2 cles (`tls_require_cert demand->hard`, `tls_ca_cert_file nova-CA.crt -> ca-certificates.crt`) ; `doveadm auth test svc-mail-ldap` **AUTH SUCCEEDED** (etat AVANT : `temp_fail`, cause `Can't connect to server: ldaps://dc01:636` confirme dans dovecot.log) ; cross-checks tous verts. |
| 6.6 | **RESOLU** | tcpdump 25 s `dst dc01:389` sur mail01 + 10 binds auth generes -> **0 packets captured**. Aucun fallback LDAP cleartext applicatif. |
| Phase 7 | **STOP OBLIGATOIRE** | Desactivation listener 389 sur dc01 + `--ldap-require-strong-auth=yes` : validation manuelle requise (point de non-retour cross-clients). Snapshot dedie `dc01-pre-disable-389` a prevoir au moment de l'apply. |

Findings clos cette session :
- **P-001** (bind LDAP anonyme HIGH) : cote mail01 = plus de path 389 utilise ; cote AD = attend Phase 7.
- **P-002** (mkcert non-PKI LOW) : step-ca operationnelle, trust anchor effectif sur mail01 + Authelia.
- **T-PKI-INTERNE-CA** : root + intermediate dans system trust mail01 ; cert dc01:636 (validite 2026-06-01 -> 2027-06-01) valide.
- **T-LDAPS-MIGRATION** : RESOLU.
- **T-CLOUD-INIT-DNS** : RESOLU (pre-existant a cette session ; `/etc/hosts` statique mail01, `manage_etc_hosts: false`).

Ecart vs plan reconstruit (transparence) : l'etat de depart etait deja `uris = ldaps://...`, le delta reel = trust anchor + `tls_require_cert`. Bloc `tls = yes` du runbook **omis volontairement** (redondant/conflictuel avec `ldaps://`). Edit chirurgical sed 2 lignes, autres cles preservees. Detail dans rapport, section "Ecart vs plan reconstruit".

Snapshots Proxmox pre-changement (a nettoyer apres validation Phase 7) :
- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (2026-06-02 09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps` (2026-06-02 09:14:04)

Backups configs locales mail01 (rollback de proximite, sans toucher au snapshot LVM) :
- `/etc/dovecot/conf.d/auth-ldap.conf.ext.bak-preldaps-2026-06-02`
- `/etc/dovecot/dovecot-ldap.conf.ext.bak-preldaps-2026-06-02`
- `/etc/dovecot/conf.d/10-auth.conf.bak-preldaps-2026-06-02`

Dettes decouvertes en passant :
- **T-ANSIBLE-MUX-CORRUPTION** : ControlMaster bastion-nova absent au demarrage de session (socket inexistant). Mitigation = execution via `proxmox-hypervisor` (Tailscale, pas de MFA), pattern documente en section "Voies d'acces" du runbook.
- **TCP/53 DMZ follow-up (LOW)** : `manage_etc_hosts: false` + entree `/etc/hosts` mail01 marche, mais a repliquer si autre VM DMZ doit resoudre dc01. Alternative = regle FW-INT DMZ -> dc01:53, decision a documenter.

NIS2 recalcule : auth LDAPS effectivement chainee PKI interne, `tls_require_cert = hard`, plus de mkcert dans le path d'auth -> renforce le pilier confidentialite/integrite des credentials. Wazuh = 8/8 Active (mise a jour : 8 et non 7 -- 000 app01 self-managed etait deja compte).

## Session 2026-05-27 (T-AGENTS-KEY-DEPLOY) -- PoC agents : phases intra-VM debloquees

Deploiement d'une cle SSH dediee `nova-agents` (privee sur awx01 uniquement, JAMAIS
dans le coffre AWX) pour debloquer les phases intra-VM des agents d'audit
(network-mapper A3/A4, rules-auditor Phase B), via `ProxyJump=proxmox-hypervisor`.

| Ticket | Statut | Detail |
|--------|--------|--------|
| T-AGENTS-KEY-DEPLOY | **RESOLU (partiel 4/9)** | cle deployee sur les 4 SERVERS (dc01/fs01/db01/app01) ; `authorized_keys` `from=192.168.60.0/29` + `restrict` ; sudoers NOPASSWD scoped nft. E2E OK (4 hostnames + 4 nft rulesets). |
| T-AGENTS-RULES-AUDITOR-VM-ACCESS | **RESOLU (ferme)** | Phase B nft live debloquee pour les 4 SERVERS. Reliquat -> dettes filles. |

Exclusions justifiees (security-by-design) :
- **bastion01** : exclu - le MFA TOTP reste l'autorite d'acces, aucun bypass cle (defense-in-depth NIS2).
- **DMZ (web01/mail01/vpn-gw01) + backup01** : non routables depuis le management Proxmox (seul VLAN 20 accessible) -> differe.

Donnees intra-VM (4 SERVERS) : Debian 12 ; nft host input policy = **drop** (default-deny) sur les 4 ; dc01 AD = nova-syndicate.local, **94 users** ; services confirmes (samba-ad-dc, smbd/nmbd, mariadb, nginx/authelia/grafana/wazuh/suricata). NIS2 recalcule : segmentation **9.5** (host default-deny confirme), least-privilege **6** (R-006), global **7.9**.

Nouvelles dettes (low prio) :
- **T-AGENTS-DMZ-AUDIT** -- audit intra-VM DMZ via session bastion+TOTP supervisee.
- **T-AGENTS-BACKUP-AUDIT** -- idem backup01.
- **R-006 (debian NOPASSWD:ALL sur SERVERS)** -- la cle agents est root-capable de fait (mitige par source-lock VLAN60 + restrict) ; envisager un user d'audit dedie a privileges scopes.

## Session supervisee 2026-05-25 (T-FW-PERIMETER-CLOSE) -- 4 dettes RESOLU

Cloture des 3 dettes perimetre OPNsense heritees de l'AFK (toutes sur FW-INT-LYON)
+ 1 dette fille decouverte en passant.

| Dette | Resolution | Verif E2E |
|-------|------------|-----------|
| T-FW-VLAN60-DMZ-VPNGW-OPEN | regle FW-INT `opt5` : `net_lyon_admin -> net_dmz_lyon:22` (+ alias `net_dmz_lyon`) | awx01 -> `172.16.1.4:22` = **OPEN** |
| T-FW-DMZ-WAZUH-OPEN | 2 regles FW-INT `wan` : `host_mail01 -> host_app01:1514` + `:1515` (pattern LDAP existant) | enrollment mail01 OK |
| T-MAIL-WAZUH-ENROLL | rôle ansible `wazuh_agent` rejoue sur mail01 (auto-enroll via 1515 desormais ouvert) | `agent_control -ls` = `007,mail01,any,Active` |
| T-MAIL-LDAP (dette fille) | drift detecte au plan : regle `fwint_mail01_to_dc01_ldaps` + alias `host_mail01` codes mais jamais appliques -> crees ; alias preexistant importe dans le state | state FW-INT : **0 drift** |

Notes techniques :
- Modeling Terraform : reutilisation des aliases existants (`net_lyon_admin`, `net_dmz_lyon`, `net_lyon_servers`, `host_app01`). Least-privilege NIS2 : wazuh cible `host_app01` (192.168.20.13) et non tout le /28 ; source `host_mail01` seul ; `log=true`.
- `host_mail01` existait dans OPNsense mais absent du state -> `terraform import` (UUID `cc3810e5-...`) + alignement description (in-place).
- **Hypothese NAT validee** : la regle FW-INT seule suffit pour VLAN60->DMZ (double-firewall transparent en NAT auto) -> AUCUNE regle FW-EXT necessaire.
- Fix rôle ansible `wazuh_agent` : garde `agent-auth` corrigee (le paquet livre un `client.keys` VIDE -> ancienne garde `creates:` skippait l'enrollment a tort ; nouvelle garde teste le contenu reel).
- Connectivite ce jour : seul FW-INT-LYON (192.168.99.1, via Tailscale) joignable depuis le Mac -> plan/apply **cibles FW-INT** ; 3 autres providers en dette (voir ci-dessous).

## AFK 2026-05-24 (T-AFK-MEGA) -- Recap

### Resolues cette session (7 taches traitees, 6 DONE + 1 ABORTED justifie)
- **T1 T-AWX-KEY-DEPLOY** -- cle pub `awx-runner` deployee sur 5 VMs (+ dc01 = 6/6) via playbook idempotent. CI green.
- **T2 T-APP01-SWAP-ADD** -- 2 GB swap app01 + role `swap_file` (gate `enable_swap`). OOM mitige. CI green.
- **T3 T-AWX-VPNGW-NFT-MODEL** -- `/60` applique sur vpn-gw01 sans wiper mangle/MSS/ct-state (flush chirurgical `hardening_nft_filter_only` + fix handler restart->reload). T-AWX-NFT-ALLOWLIST host 6/6. CI green. *Nouvelle dette perimetre : T-FW-VLAN60-DMZ-VPNGW-OPEN.*
- **T4 T-MAIL-TLS-WILDCARD** -- mail01 sert le cert wildcard mkcert (STARTTLS 587/143 verify=0). Role `mail_server` + `mail_tls_use_wildcard`. CI green.
- **T5 T-MAIL-WAZUH-ENROLL** -- **ABORTED** (R4) : path DMZ->SERVERS:1514/1515 bloque au perimetre. *Nouvelle dette : T-FW-DMZ-WAZUH-OPEN* (+ T-MAIL-WAZUH-ENROLL reste ouverte).
- **T6 T-BASTION-TAILSCALE-CLEANUP** -- **SKIP** (sudo MFA bastion01, session supervisee).
- **T7 T-WAZUH-AUDIT-DEDUP + T-WAZUH-LOGCOLLECTOR-HEALTHCHECK** -- dedup nova-iam audit.log sur dc01 + watchdog timer (Restart=always insuffisant car unit fire-and-forget). E2E auto-recovery OK. CI green.
- **T8 T-AWX-RBAC (Phase 8)** -- 4 groupes AD + 4 Teams AWX + `AUTH_LDAP_TEAM_MAP` (via API, no downtime) + perms. E2E dual-role OK. ADR-0033. CI green.

### Dettes ouvertes apres ce AFK
- **T-BASTION-TAILSCALE-CLEANUP** -- sudo MFA bastion01, session supervisee.
- **T-WIREGUARD-POC** -- 1 agent demo + test client (non adresse en AFK).
- **T-SPLIT-MONITORING-VM** -- **URGENT** : sortir wazuh-indexer + stack lourde d'app01 (OOM confirme).
- **T-SQUID-PROXY** -- proxy filtrant non deploye.
- **T-GRAFANA-AUTHELIA-SSO** -- SSO Grafana via Authelia.
- **T-AWX-VAULT-INVENTORY** -- inventaire AWX peuple + `vault_default_user_password` dans les jobs (+ inventaire Nova-MRS).
- **T-AWX-TEMPLATES-IAC** -- Config-as-Code AWX (Teams/TEAM_MAP/JT non versionnes).
- **T-SSH-CONFIG-DEDUP** -- doublon `~/.ssh/config` Mac.
- **MFA TOTP bastion** -- finalisation.
- ~~**T-FW-VLAN60-DMZ-VPNGW-OPEN**~~ -- **RESOLU 2026-05-25** (regle FW-INT opt5 ; E2E `OPEN`).
- ~~**T-FW-DMZ-WAZUH-OPEN**~~ -- **RESOLU 2026-05-25** (2 regles FW-INT wan, 1514/1515).
- ~~**T-MAIL-WAZUH-ENROLL**~~ -- **RESOLU 2026-05-25** (mail01 agent `Active` sur manager ; note T5 "install incomplete" obsolete : /var/ossec present, seul l'enrollment manquait).
- ~~**T-MAIL-LDAP**~~ -- **RESOLU 2026-05-25** (dette fille : drift regle LDAP `mail01->dc01:636` + alias host_mail01, appliques + importes).
- **T-TF-WANSIM-CONNECTIVITY** (NOUVELLE) -- provider WAN-SIM (10.0.0.1) injoignable depuis le Mac -> plan/apply impossibles sur ce FW.
- **T-TF-FWEXTMRS-CONNECTIVITY** (NOUVELLE) -- provider FW-EXT-MRS (192.168.40.1) injoignable depuis le Mac.
- **T-TF-FWEXTLYON-CONNECTIVITY** (NOUVELLE) -- provider FW-EXT-LYON (172.16.1.1) injoignable depuis le Mac -> bloque toute future regle FW-EXT (ex. fallback DMZ->SERVERS si l'hypothese NAT cessait de tenir).

### Snapshots Proxmox a nettoyer (apres validation)
- VMID 106 (app01) : `pre-app01-swap-add-2026-05-24`
- VMID 110 (vpn-gw01) : `pre-awx-vpngw-nft-2026-05-24`
- VMID 101 (mail01) : `pre-mail-tls-wildcard-2026-05-24`
- VMID 103 (dc01) : `pre-wazuh-audit-dedup-2026-05-24`, `pre-awx-rbac-2026-05-24`
- VMID 111 (awx01) : `pre-awx-rbac-2026-05-24`
- dc01 : fichier `/var/ossec/etc/ossec.conf.bak-prededup-2026-05-24`

## Etat infra Proxmox

- 10 VMs Linux deployees + 10 roles Ansible appliques (`common`, `hardening`, `dc`, `fileserver`, `database`, `app`, `bastion`, `web`, `mail`, `backup`)
- Wazuh Manager + 7 agents actifs (regles NIS2 100001-100010 sur APP01)
- Tailscale OK (proxmox = 100.112.113.2)
- 4 OPNsense (deployes via Terraform Telmate/proxmox) :
  - WAN-SIMULATOR (VMID 200) : https://10.0.0.1     -- transit ISP simule
  - FW-EXT-LYON  (VMID 201)  : https://172.16.1.1   -- DMZ (web, mail)
  - FW-INT-LYON  (VMID 202)  : https://192.168.99.1 -- VLANs internes
  - FW-EXT-MRS   (VMID 203)  : https://192.168.40.1 -- LAN Marseille
- Routage Lyon -> WAN-SIM -> MRS OK (ping bidirectionnel valide)

---

## Phase II OPNsense IaC -- TERMINEE (8 mai 2026)

### Securisation acces management
- SSH par cle ED25519 dediee (`~/.ssh/nova_opnsense_ed25519`)
- Password login desactive sur les 4 firewalls
- Alias SSH dans `~/.ssh/config` : `opn-wansim`, `opn-fw-ext-lyon`, `opn-fw-int-lyon`, `opn-fw-ext-mrs`
- 1 user `terraform` dedie par firewall (groupe `admins`), 4 paires API keys stockees
  hors repo dans `~/Documents/Nova-syndicate-Code/nova-iac-secrets/`

### IaC OPNsense (Terraform browningluke 0.16)
Code dans `terraform/environments/opnsense/` (renomme depuis `lyon/` pour refleter
le scope reel des 4 firewalls).

Fichiers :
- `main.tf`        : 4 providers OPNsense (1 alias par firewall)
- `variables.tf`   : 12 variables IP/key/secret + maps VLSM et VLAN IDs
- `outputs.tf`     : urls API + plan VLSM + recap VLANs
- `aliases.tf`     : 24 aliases (networks, hosts, ports) repartis sur 4 firewalls
- `fw_int_vlans.tf`: 4 sous-interfaces VLAN 802.1Q sur FW-INT-LYON
- `fw_ext.tf`      : regles FW-EXT-LYON (10 regles : DMZ, IPsec prep, transit)
- `fw_int.tf`      : regles FW-INT-LYON (16 regles : 4 VLANs + WAN block)
- `fw_ext_mrs.tf`  : regles FW-EXT-MRS (5 regles : LAN, IPsec prep, WAN block)
- `fw_wansim.tf`   : regles WAN-SIM (3 regles : transit + WAN block)
- `terraform.tfvars` : secrets (gitignore strict)

Total : 33 ressources Terraform deployees, 1 fichier en `.bak` pour Phase IV (`wireguard.tf.bak`).

### Pattern firewall applique
Par interface : `pass` specifiques + `block all + log` final.
Trace toute denegation pour audit NIS2.

### Validations end-to-end
- `terraform plan` : 0 drift apres apply
- `pfctl -s info` : Status Enabled sur les 4 firewalls
- Ping inter-VLAN (FW-INT -> BASTION01 / DC01) : OK
- SSH management preserve sur les 4 firewalls

---

## Dette technique restante (a traiter Phase IV / VI)

### 1. NAT outbound en mode "Automatic" OPNsense
Le provider browningluke 0.16 ne supporte pas la ressource `firewall_source_nat`.
Le mode Automatic d'OPNsense couvre les besoins essentiels (NAT auto pour
les RFC1918 vers WAN). Migration en mode "Hybrid" en Phase IV pour ajouter
les regles NO-NAT du tunnel IPsec.

### 2. Routes statiques cross-site Lyon <-> MRS
La ressource `opnsense_route` existe dans le provider, mais necessite des
Gateways pre-configurees dans OPNsense que le provider ne sait pas creer.
A traiter en Phase IV : creation manuelle des Gateways, puis routes en
Terraform.

### 3. Management FW-INT-LYON sur 192.168.99.0/29 (hors VLSM)
Choix temporaire pour faciliter la phase IaC (acces preserve pendant le
deploiement). A aligner sur le plan VLSM en Phase VI (bootstrap idempotent).
**MAJ 2026-05-21 (T-AWX-DEPLOY)** : acces mgmt (`192.168.99.5/29` sur `vmbr1`
cote Proxmox) desormais **persiste** dans `/etc/network/interfaces` (etait
runtime-only, wipe par un `ifreload` -- cf ADR-0031 sec.2). Reste l'alignement
VLSM du subnet.

### 4. Tunnel IPsec FW-EXT-LYON <-> FW-EXT-MRS non configure
strongSwan present mais daemon non demarre (config heritee de GNS3 obsolete).
Regles d'autorisation UDP 500/4500/ESP deja codees en Terraform sur FW-EXT-LYON
et FW-EXT-MRS, prepare la Phase IV.

### 5. Bootstrap manuel template 9000 + interfaces Proxmox
La creation du template Debian VMID 9000 et la conf des bridges vmbr0-5 sont
manuelles. Phase VI = scripter ces operations one-shot.

### 6. tls_disable=true Vault APP01
Choix lab uniquement -- a documenter explicitement dans le rapport Phase II.

### 7. T-AWX-DEPLOY -- 6 dettes filles (detail dans ADR-0031)
- **T-AWX-VAULT-INVENTORY** : `vault_default_user_password` non charge dans les jobs AWX (inventory DB-backed).
- **T-AWX-BULK-ROTATE-DRY-RUN** : variante `users_rotate_test.yml` filtre `OU=Test`.
- **T-AWX-IAM-SPACES-FIX** : RESOLU 2026-05-21 (commit ansible 86fc623) -- voir Dettes resolues.
- **T-WAZUH-LOGCOLLECTOR-DC01** : INVESTIGUEE 2026-05-21 -- root cause INDETERMINEE (voir Dettes resolues).
- **T-AWX-AUDIT-ATTRIBUTION** : audit "by root" au lieu de l'utilisateur AWX/AD.
- **T-AWX-RBAC** (Phase 8) : **RESOLU 2026-05-24** (T-AFK-MEGA, ADR-0033). 4 groupes AD (IT-Officers-Lyon/MRS, IT-Managers, IT-Auditors, dans CN=Users) + 4 Teams AWX (org Nova Syndicate) + `AUTH_LDAP_TEAM_MAP` via API (pas de CR/downtime, LDAP hors CR) + permissions (Officers: exec create/enable ; Managers: exec tous iam-* + admin inv Nova-Lyon ; Auditors: org auditor read-only). **E2E** : user jetable `rbac.test` dual-role -> Teams {IT-Officers, Auditors}, create/enable EXECUTE + reste read-only (conforme), supprime apres test. Snapshots `pre-awx-rbac-2026-05-24` (VMID 103+111). Workflow Onboarding (bonus) reporte. TEAM_MAP a sauvegarder en IaC (-> T-AWX-TEMPLATES-IAC).

### 8. T-AWX-NFT-ALLOWLIST -- 7 dettes filles (session 2026-05-23/24)
- **T-AWX-VPNGW-NFT-MODEL** : **RESOLU 2026-05-24** (T-AFK-MEGA) -- allowlist `/60` appliquee sur vpn-gw01 SANS wiper `ip mangle` (mark WG, ADR-0017) ni les forward MSS clamp/`ct state`. Approche retenue (deviation justifiee de `hardening_extra_nft_tables`) : **flush chirurgical** `table inet filter` only via nouveau `hardening_nft_filter_only` (le mangle est cree dynamiquement par `wg-policy-routing.sh` PostUp en `iptables -A` non idempotent -> le modeliser aurait duplique la regle au reboot). **Bug corrige** : handler `reload nftables` etait `state: restarted` -> `ExecStop=nft flush ruleset` wipait tout ; passe en `state: reloaded` (atomique). Forward rules vpn-gw01 completees (capturees du live : 2 MSS clamp + 2 ct state, etaient incompletes). Pre-declare `table inet filter {}` corrige aussi un bug cold-boot latent. extra_nft_tables loop ajoute (feature generique). Snapshot `pre-awx-vpngw-nft-2026-05-24` (VMID 110). Dry-run conforme, run OK, idempotence 0 changed, post-checks live tous verts.
- **T-FW-VLAN60-DMZ-VPNGW-OPEN** : **NOUVELLE dette (decouverte T-AFK-MEGA)** -- E2E awx01->vpn-gw01:22 = BLOCKED, mais au PERIMETRE (OPNsense), pas au host : SYN n'atteint jamais vpn-gw01 (NFT-DROP counter=0). VLAN60 (AWX 192.168.60.0/29) -> DMZ 172.16.1.4:22 non autorise (DMZ isolee ; control awx01->dc01:22 = OPEN). A ouvrir via `terraform/environments/opnsense/` (FW-INT + FW-EXT). **Decision securite NIS2 (admin->DMZ) -> session supervisee**, non tente en AFK. Host nft vpn-gw01 est pret.
- **T-APP01-OOM-INVESTIGATION** : OOM CONFIRME (`journalctl -k -b -1` : Grafana killee par OOM-killer le 19/05 ; hang 23-24/05 cause analogue ; `Swap: 0B` sur app01).
- **T-APP01-SWAP-ADD** : **RESOLU 2026-05-24** (T-AFK-MEGA) -- 2 GB swap actif sur app01 (`/swapfile`, fstab persiste) via nouveau role `swap_file` (gate `enable_swap`/`swap_size`, inclus dans `common`). `free -h` = `Swap: 2.0Gi`. Idempotence OK (0 changed, mkswap/swapon skipped). Snapshot `pre-app01-swap-add-2026-05-24` (VMID 106). Mitigation en attendant T-SPLIT-MONITORING-VM.
- **T-SPLIT-MONITORING-VM** : **URGENT** -- sortir wazuh-indexer + la stack lourde (nginx/Authelia/Grafana/portail/wazuh-manager/filebeat/cloudflared) hors d'app01 (declenche par l'OOM confirme -- stabilite SIEM).
- **T-BASTION-TAILSCALE-CLEANUP** : retirer `100.64/10` de `host_vars/bastion01.yml` OU installer Tailscale (decision pending ; sudo MFA -> session supervisee requise).
- **T-AWX-KEY-DEPLOY** : **RESOLU 2026-05-24** (T-AFK-MEGA) -- cle publique `awx-runner` (fp `5PnAWh…`, identique a dc01) deployee sur les 5 VMs (fs01, db01, app01, backup01, vpn-gw01) via playbook `deploy_awx_runner_key.yml` + `group_vars/all/awx.yml` (nova-syndicate-ansible). Idempotence OK (0 changed au re-run), cle presente 1x/host verifiee. Acces AWX 6/6 (5 VMs + dc01).
- **T-SSH-CONFIG-DEDUP** : nettoyer le doublon dans le `~/.ssh/config` du Mac (heritage session T2 BASTION).
- **T-MAIL-WAZUH-ENROLL** : **ABORTED en AFK (T-AFK-MEGA), bloque par T-FW-DMZ-WAZUH-OPEN.** wazuh-agent 4.11.2 deja installe sur mail01 (paquet present, MAIS `/var/ossec` absent -> install incomplete a verifier), repo `wazuh.list` configure. Enrollment impossible : path DMZ->SERVERS bloque. A finaliser une fois le FW ouvert (session supervisee).
- **T-FW-DMZ-WAZUH-OPEN** : **NOUVELLE dette (T-AFK-MEGA).** mail01 (DMZ 172.16.1.3) -> app01 wazuh-manager (192.168.20.13) :1515 (enrollment) + :1514 (data) = BLOCKED au perimetre OPNsense (le host nft d'app01 autorise deja 172.16.1.0/29 sur 1514 + 1515 ouvert). A ouvrir via `terraform/environments/opnsense/` (FW-INT-LYON, DMZ->SERVERS:1514,1515). **Non tente en AFK** : `terraform plan` lent + interrompu (pas de baseline drift propre), apply perimetre = blast radius + decision NIS2 -> session supervisee. (tfvars + state presents, terraform v1.14.3 OK pour reprise.)

### Dettes resolues (T-AFK-MEGA-2026-05-24)
- **T-MAIL-TLS-WILDCARD** : **RESOLU 2026-05-24** -- mail01 (Postfix+Dovecot) sert le cert wildcard mkcert `*.nova-syndicate.local` (partage avec nginx app01) au lieu du self-signed. STARTTLS SMTP :587 + IMAP :143 = `Verify return code: 0 (ok)` (issuer mkcert CA, verify_hostname mail.nova-syndicate.local OK). Modelise dans role `mail_server` (`mail_tls_use_wildcard` + copy depuis `files/_certs-LOCAL/` gitignore) + host_vars/mail01.yml (+ symlink `inventory/host_vars/mail01.yml`). Snapshot `pre-mail-tls-wildcard-2026-05-24` (VMID 101).

### Dettes resolues (T-AFK-DETTES-2026-05-20)
- **T-AWX-NFT-ALLOWLIST** : RESOLU 2026-05-23/24 puis **host-allowlist 6/6 le 2026-05-24** (T-AFK-MEGA, vpn-gw01 via T-AWX-VPNGW-NFT-MODEL). Les 6 VMs (fs01, db01, app01, backup01, bastion01, vpn-gw01) ont `/60` dans leur nft host. **E2E :22 OPEN depuis awx01 confirme 5/6** ; vpn-gw01 reste BLOCKED au perimetre OPNsense (DMZ isolee) -> dette `T-FW-VLAN60-DMZ-VPNGW-OPEN`. Host nft du 6e pret.
- **T-K3S-DISABLE-TRAEFIK** : RESOLU 2026-05-21. traefik desactive sur K3s awx01 (`disable: [traefik]`, cf `files/awx/k3s-config.yaml`). ~190 MB RAM economises. nginx app01 reste le reverse proxy.
- **T-WAZUH-LOGCOLLECTOR-DC01** : INVESTIGUEE 2026-05-21, **root cause INDETERMINEE**. Remediee (restart, logcollector stable 6h+, pipeline audit valide CHECKPOINT 8).
  - Evidence : dernier evenement systemd = restart du 18/05 19:44 (changement ossec.conf, logcollector demarre OK alors). Mort ulterieure SANS trace : daemons independants du unit `active(exited)`, pas de reboot (uptime depuis 07/05), pas d'OOM, `ossec.log` pre-crash tronque au restart (non rotate/preserve).
  - Sous-findings (nouvelles dettes filles) :
    - **T-WAZUH-AUDIT-LOCALFILE-DEDUP** (= T-WAZUH-AUDIT-DEDUP) : **RESOLU 2026-05-24** (T-AFK-MEGA). Le 2e bloc `<localfile>` `/var/log/nova-iam/audit.log` (sur 2) retire de l'ossec.conf de dc01 (count 2->1, 2 blocs `<ossec_config>` preserves, perms conservees). Restart wazuh-agent OK, ossec.log clean, **0 WARNING "duplicated"**. Fix live one-time (le role wazuh_agent ne gere pas ce localfile -> pas de recurrence). Backup `ossec.conf.bak-prededup-2026-05-24` sur dc01.
    - **T-WAZUH-LOGCOLLECTOR-HEALTHCHECK** : **RESOLU 2026-05-24** (T-AFK-MEGA). Decouverte : l'unit wazuh-agent est `Type=forking` + `RemainAfterExit=yes` (MainPID=0) -> `Restart=always` seul NE recupere PAS un daemon enfant mort. Solution effective = **watchdog** : `wazuh-agent-watchdog.{sh,service,timer}` (timer 30s) qui restart wazuh-agent si `wazuh-control status` voit un daemon down (+ drop-in Restart=always en filet). E2E : kill `wazuh-logcollector` -> AUTO-RECOVERED via timer ~33s. Modelise dans role `wazuh_agent` (tag `wazuh:watchdog`, vars `wazuh_agent_restart_policy`/`wazuh_agent_watchdog_enabled`/`wazuh_agent_watchdog_interval`), idempotent (0 changed au re-run). Note : 1er script bugge (`set -o pipefail` + `wazuh-control status` exit!=0 -> SIGPIPE) corrige.
- **T-AWX-IAM-SPACES-FIX** : RESOLU 2026-05-21. Repo nova-syndicate-ansible commit `86fc623` : 20 appels `cmd: samba-tool ...` -> `argv:` dans les 7 playbooks IAM. Valide E2E via AWX (grant/revoke `test.spacesfix` sur "Domain Admins" -- le groupe avec espace qui echouait avant -- jobs successful, membership verifiee, cleanup count=94). AWX project synced a 86fc623.

---

## Snapshots a nettoyer (post-validation)

Snapshots Proxmox a supprimer apres validation des modifications (T-AWX-NFT-ALLOWLIST) :
- VMID 104 (fs01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 105 (db01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 106 (app01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 109 (backup01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 110 (vpn-gw01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 102 (bastion01) : `pre-awx-nftallowlist-2026-05-23` (intervention manuelle)
- VMID 106 (app01) : tout snapshot precedent (`pre-awx-nftallowlist-2026-05-21` du 12:02, etc.)

---

## Roadmap

- **Phase III** : Reporting + livrables Phase II (architecture diagram a jour, doc technique docx, screenshots) -- en cours
- **Phase IV** : VPN site-to-site IPsec + WireGuard 20 agents + MFA TOTP
- **Phase V** : Bastion zero-trust (post-WireGuard)
- **Phase VI** : Bootstrap script idempotent (template, bridges, OPNsense ISO, gateways)
- **Phase VII** : Cartographie auto (terraform-to-d2 ou similaire)
- **Phase VIII** : Tests pentest externes

---

## GitHub
matthieu-rgb/nova-syndicate-proxmox
