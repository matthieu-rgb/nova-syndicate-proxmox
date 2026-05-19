# ADR-0030 : Grafana + Wazuh single-pane-of-glass securite

- Statut : Accepte (deploiement complet : indexer + filebeat + 3/4 dashboards data-populated)
- Date : 2026-05-18 / mis a jour 2026-05-19
- Auteur : matthieu-rgb
- Tickets : T-DASHBOARD-WAZUH-2026-05-18, T-WAZUH-INDEXER-INSTALL-2026-05-19
- Lien : voir [`dashboards/README.md`](../../dashboards/README.md)

## Contexte

Wazuh manager v4.11 tournait deja sur app01 avec :
- 14 regles NIS2 custom (rules 100001-100014) couvrant auth, IAM, mail,
  pivot, IDS suricata.
- Agents Wazuh deployes sur la majorite des VMs.
- `alerts.json` accumule dans `/var/ossec/logs/alerts/`.

Mais **pas de visualisation centralisee**. L'analyste devait `tail -f`
ou requeter manuellement. Pour le poste analyste / DSI / audit NIS2, il
faut un dashboard "single pane of glass" interactif sur 4 axes :
1. **Conformite NIS2** : alertes par article 21.2 / level / trend.
2. **IAM audit** : qui a fait quoi (CREATE/GRANT/REVOKE/...).
3. **IDS multi-capteurs** : Suricata cross-FW (LYON/INT/MRS).
4. **Auth failures** : brute force / lockout par service.

Grafana 13.0.1 etait deja installe sur app01 (port 3000), avec un
dashboard "Nova Syndicate Overview" mais sans datasource Wazuh.

## Decision

**1. Plugin** : `grafana-opensearch-datasource` v2.33.1 (fork OS du plugin
Elasticsearch officiel) -- supporte les Wazuh-flavored OpenSearch indices.

**2. Provisioning natif** : tout passe par fichiers YAML/JSON dans
`/etc/grafana/provisioning/` et `/var/lib/grafana/dashboards/`. Pas
d'edition UI persistante. Source de verite = repo
`nova-syndicate-proxmox/dashboards/grafana/`.

**3. Datasource unique** : uid `wazuh-opensearch` pointant
`https://127.0.0.1:9200`, index pattern `wazuh-alerts-*`, timeField
`@timestamp`. `tlsSkipVerify=true` (cert auto-signe Samba-style).

**4. Folder unique** : "Nova Syndicate -- Security" (uid genere par
Grafana au premier demarrage). Permettra plus tard d'attacher des
permissions AD-group au niveau folder.

**5. 4 dashboards** : un par axe (cf. tableau dans `dashboards/README.md`).
Tous tagges `wazuh,security,nova-syndicate,<topic>` pour search rapide.

**6. Refresh rates** : 30s pour IDS/Auth (volume eleve), 1m pour
NIS2/IAM (analyse manuelle). Time range par defaut 24h sauf IAM Audit
(7j -- les actions IAM sont sporadiques).

**7. Tests** : Phase 7 valide la syntaxe JSON (`python json.load`),
la presence dans la table `resource` unified storage de Grafana 13,
les tags, et la sante Grafana globale.

## Bascule de Grafana 13 vers unified storage

Grafana 13.0.1 introduit le "unified storage" : les dashboards et folders
ne sont plus dans les tables `dashboard`/`folder` historiques mais dans
la table generique `resource` (avec `"group"="dashboard.grafana.app"` et
`"group"="folder.grafana.app"`). Le JSON spec est stocke dans la colonne
`value`. Les anciennes queries SQL deviennent caduques ; pour verifier
les dashboards proviennes, utiliser :

```sql
SELECT json_extract(value, '$.metadata.name') AS uid,
       json_extract(value, '$.spec.title')    AS title,
       json_extract(value, '$.metadata.annotations."grafana.app/folder"') AS folder
FROM resource
WHERE "group"='dashboard.grafana.app';
```

Cette decouverte a allonge le temps de la mission ; elle est documentee
ici pour epargner la decouverte au futur operateur.

## Pipeline indexer + filebeat (T-WAZUH-INDEXER-INSTALL -- RESOLU 2026-05-19)

**wazuh-indexer 4.11.2 installe** sur app01 en single-node bound 127.0.0.1.
Pipeline E2E confirme : `agents -> wazuh-manager -> /var/ossec/logs/alerts/alerts.json -> filebeat 7.10.2 (module wazuh) -> wazuh-indexer https://127.0.0.1:9200 -> index wazuh-alerts-4.x-YYYY.MM.DD -> Grafana opensearch datasource -> dashboards`.

### Steps executes

1. **RAM bump app01 4 -> 6 GB** (PROXMOX 106) :
   - Hotplug memory + cpu active : `qm set 106 --hotplug network,disk,usb,memory,cpu`
   - NUMA requis pour memory hotplug : `qm set 106 --numa 1`
   - `qm set 106 --memory 6144`
   - VM redemarrage requis (hotplug non actif avant config). Au boot, DIMMs
     hot-added arrivent en `offline` -> udev rule
     `/etc/udev/rules.d/40-memory-hotplug.rules` les online automatiquement
     (`SUBSYSTEM=="memory", ACTION=="add", ATTR{state}=="offline", ATTR{state}="online"`).

2. **wazuh-indexer install** :
   - `apt install wazuh-indexer=4.11.2-1` (match version manager).
   - Certs generes via `/usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-certs-tool.sh`
     pour 127.0.0.1 (node-1/wazuh-1/dashboard).
   - Copie dans `/etc/wazuh-indexer/certs/` :
     `root-ca.{pem,key}`, `indexer.pem`, `indexer-key.pem`, `admin.{pem,key}`.
   - `opensearch.yml` patche : `network.host: 127.0.0.1`, `cluster.name: wazuh-cluster-local`,
     `discovery.type: single-node`. Bloc `cluster.initial_master_nodes` retire (incompatible single-node).
   - JVM heap 1G : `-Xms1g -Xmx1g` dans `/etc/wazuh-indexer/jvm.options`.
   - `vm.max_map_count=262144` (sysctl) persiste dans `/etc/sysctl.conf`.
   - `systemctl enable --now wazuh-indexer`.
   - Init security : `/usr/share/wazuh-indexer/bin/indexer-security-init.sh` -> cluster GREEN, 1 node, 4 primary shards.
   - **Password admin rotate** : 32-char alphanum genere via `secrets.choice`, hash bcrypt via `hash.sh` (avec `JAVA_HOME=/usr/share/wazuh-indexer/jdk`), inject dans `internal_users.yml`, reload via `securityadmin.sh -icl`.

3. **Filebeat install** :
   - `apt install filebeat=7.10.2` (version Wazuh-bundled).
   - Module wazuh 0.4 telecharge depuis `packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz`.
   - Template `wazuh-template.json` recupere depuis le repo Wazuh v4.11.2.
   - Certs filebeat copies depuis le cert tool (`wazuh-1.pem`, `wazuh-1-key.pem`).
   - Password indexer stocke dans **filebeat keystore** (`filebeat keystore add OUTPUT_PASSWORD`),
     reference dans `filebeat.yml` via `${OUTPUT_PASSWORD}`. Pas de mdp en clair.
   - `filebeat setup --pipelines --modules wazuh` : 1 pipeline d'ingestion charge.
   - `systemctl enable --now filebeat`.

4. **Hold packages** : `wazuh-manager`, `wazuh-indexer`, `filebeat` mis en `hold` via
   `dpkg --set-selections` pour eviter qu'`unattended-upgrades` ne casse l'alignement
   de versions (incident detecte pendant la mission : apt voulait upgrader manager
   4.11.2 -> 4.14.5 -- mismatch avec agents 4.11.2).

### Validation flow E2E (Phase 4)

- Indices presents : `wazuh-alerts-4.x-2026.05.18` (1 doc), `wazuh-alerts-4.x-2026.05.19` (1646+ docs et croissant).
- Cluster status `green`, 4 primary shards active, 0 unassigned.
- Aggregation `rule.groups` revele : 1380 syslog, 1040 auth_success, 706 sshd, 662 pam,
  151 nis2, 85 privilege_escalation, 55 account_management, 8 auth_failed, 3 brute_force, 0 suricata.

### Status dashboards

| Dashboard | Population | Query principale | Count |
|---|---|---|---|
| `nova-nis2-compliance` | **OK** | `rule.groups:*nis2*` | 186 docs |
| `nova-iam-audit` | **OK** | `rule.id:100008` (account mgmt) | 55 docs |
| `nova-auth-failures` | **OK** | `rule.groups:authentication_failed OR brute_force` | 15+ docs |
| `nova-ids-multi-capteurs` | **VIDE** | `rule.groups:suricata` | 0 docs |

Pourquoi IDS vide : Suricata tourne sur OPNsense (3 FW) et n'envoie pas
ses alertes au wazuh-manager. Integration possible via :
- (a) Wazuh agent sur OPNsense (FreeBSD pkg) lisant `/var/log/suricata/eve.json`.
- (b) Forward syslog OPNsense -> wazuh-manager (decoder syslog).
**Dette ouverte** : `T-WAZUH-SURICATA-INTEGRATION`.

### RAM cible vs realite

Cost reel apres demarrage indexer : 1G JVM heap + 200M overhead.
Total app01 6 GB : ~3 GB libre pour buff/cache, OK pour le labo.
Si volume alertes explose -> envisager `T-SPLIT-MONITORING-VM` (monitoring sur VM dediee).

## Permissions par groupe AD (T-GRAFANA-AUTHELIA-SSO)

La cible viewer=`Lyon-Staff` / editor=`Lyon-Admins` / admin=`Administrator`
ne peut pas etre implementee aujourd'hui : Grafana est en local auth
seul (admin/admin par defaut). Pour mapper les groupes AD :
1. Configurer `[auth.generic_oauth]` Grafana pointant Authelia.
2. Authelia deja en place sur app01 (port 443 derriere nginx) avec
   integration AD/LDAP.
3. Mapper `role_attribute_path` Grafana sur le claim `groups` Authelia.
4. Provisioning `/etc/grafana/provisioning/access-control/*.yaml` avec
   role bindings par groupe.

**Dette ouverte** : `T-GRAFANA-AUTHELIA-SSO`.

## Note d'execution -- auth admin Grafana cassee

Pendant la mission, `grafana-cli admin reset-admin-password` retournait
"changed successfully" mais l'auth basic `admin:<new-pwd>` echouait
("invalid password"). Hypothese : bug Grafana 13 unified-storage avec
le reset CLI qui ecrit dans la table `user` historique et non dans le
nouveau backend. Workaround : **passer 100% par provisioning YAML** qui
ne necessite pas d'auth admin. C'est le pattern infra-as-code correct
de toute facon ; ce bug nous a juste force a l'adopter plus tot.

Pendant T-WAZUH-INDEXER-INSTALL, le bug a ete contourne d'une autre
maniere : reset direct du hash PBKDF2 dans `user.password` via un petit
script Python (`hashlib.pbkdf2_hmac('sha256', pwd, user.salt, 10000, dklen=50)`).
Cela permet enfin l'auth admin. C'est valide en attendant
`T-GRAFANA-AUTHELIA-SSO`.

**Dette ouverte** : `T-GRAFANA-13-ADMIN-RESET-BUG`. A reporter upstream
Grafana ou contourner par migration sur Grafana 12.x si bloquant.

## Note -- health check datasource "Index not found"

`GET /api/datasources/uid/wazuh-opensearch/health` renvoie HTTP 400
"Index not found: wazuh-alerts-\*" alors que les queries via le proxy
fonctionnent (1647 docs retournes). Le plugin opensearch-datasource v2.33.1
fait un health-probe sur `_alias/<database>` qui retourne `{}` car aucun
alias n'est defini (que des indices physiques `wazuh-alerts-4.x-YYYY.MM.DD`).
Cosmetique : les dashboards utilisent le proxy direct et fonctionnent.

**Dette ouverte mineure** : `T-WAZUH-INDEXER-ALIAS-DAILY` -- definir un
alias `wazuh-alerts -> wazuh-alerts-4.x-*` (rollover ILM) pour faire taire
le health check + faciliter le rolling daily.

## Consequences

Positives :
- 4 dashboards immediatement disponibles pour la DSI / l'audit, source
  de verite versionnee dans le repo.
- Provisioning natif = pas de derive entre dev et prod.
- Tags + folder = navigation facile.
- 3/4 dashboards data-populated post T-WAZUH-INDEXER-INSTALL (NIS2, IAM, Auth).
- Pipeline E2E confirme : 1500+ alertes indexees en quelques minutes.

Negatives :
- IDS Multi-capteurs reste vide tant que `T-WAZUH-SURICATA-INTEGRATION` non
  faite (Wazuh agent sur OPNsense ou syslog forward).
- Permissions par groupe AD differees (T-GRAFANA-AUTHELIA-SSO).
- Bug reset admin pwd contournable par PBKDF2 direct ou provisioning, mais
  inquietant pour la maintenance manuelle.
- Health check datasource renvoie "Index not found" cosmetique
  (T-WAZUH-INDEXER-ALIAS-DAILY).
- Indexer + Grafana + Wazuh manager sur la meme VM : si load monte, envisager
  `T-SPLIT-MONITORING-VM`.

## Annexes

- Dashboards JSON : `dashboards/grafana/0[1-4]-*.json`
- Datasource provisioning : `dashboards/grafana/datasource-wazuh.yaml`
- Dashboard provider : `dashboards/grafana/provider-wazuh.yaml`
- README detaille : `dashboards/README.md`
