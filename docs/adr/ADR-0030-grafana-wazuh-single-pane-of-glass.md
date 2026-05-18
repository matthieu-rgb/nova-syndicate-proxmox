# ADR-0030 : Grafana + Wazuh single-pane-of-glass securite

- Statut : Accepte (deploiement partiel -- prerequis wazuh-indexer ouvert)
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-DASHBOARD-WAZUH-2026-05-18
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

## Prerequis indexer (T-WAZUH-INDEXER-INSTALL)

**wazuh-indexer n'est pas installe** sur app01 a la cloture de
T-DASHBOARD-WAZUH. Les dashboards renvoient "No data" tant que :
1. `apt install wazuh-indexer=4.x` + Java OpenJDK 11.
2. Configuration initiale (`initialize.sh`, certificat indexer-side).
3. wazuh-manager `<integration>` ou Filebeat pour shipping
   `alerts.json` -> index `wazuh-alerts-*`.
4. Datasource Grafana credentials (admin user wazuh-indexer + pwd dans
   vault).

Cout RAM estime : ~2 GB JVM heap. app01 = 4 GB total, deja 1 GB
wazuh-manager + 200 MB Grafana + 500 MB Nginx/Authelia -> il faudra
soit upgrade la VM a 6-8 GB, soit deplacer Grafana sur un autre noeud.

**Dette ouverte** : `T-WAZUH-INDEXER-INSTALL`. Estimation : 30 min
install + 30 min ingest pipeline + 30 min tuning JVM.

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

**Dette ouverte** : `T-GRAFANA-13-ADMIN-RESET-BUG`. A reporter upstream
Grafana ou contourner par migration sur Grafana 12.x si bloquant.

## Consequences

Positives :
- 4 dashboards immediatement disponibles pour la DSI / l'audit, source
  de verite versionnee dans le repo.
- Provisioning natif = pas de derive entre dev et prod.
- Tags + folder = navigation facile.

Negatives :
- "No data" tant que indexer pas en place (T-WAZUH-INDEXER-INSTALL).
- Permissions par groupe AD differees (T-GRAFANA-AUTHELIA-SSO).
- Bug reset admin pwd contournable par provisioning, mais inquietant
  pour la maintenance manuelle.

## Annexes

- Dashboards JSON : `dashboards/grafana/0[1-4]-*.json`
- Datasource provisioning : `dashboards/grafana/datasource-wazuh.yaml`
- Dashboard provider : `dashboards/grafana/provider-wazuh.yaml`
- README detaille : `dashboards/README.md`
