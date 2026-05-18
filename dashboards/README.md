# Dashboards Grafana -- Nova Syndicate Security

T-DASHBOARD-WAZUH-2026-05-18 -- single pane of glass pour la securite.

## Vue d'ensemble

4 dashboards versionnes dans `dashboards/grafana/` provisionnes via le
mecanisme natif Grafana (`/etc/grafana/provisioning/dashboards/wazuh.yaml`
-> folder `Nova Syndicate -- Security`). Toutes les requetes ciblent la
datasource `wazuh-opensearch` (type `grafana-opensearch-datasource`).

| UID | Titre | Source | Filtre | Refresh | Default range |
|-----|-------|--------|--------|---------|---------------|
| `nova-nis2-compliance` | NIS2 Compliance | `rule.groups:*nis2*` | rule_groups NIS2, level>=10 | 1m | now-24h |
| `nova-iam-audit` | IAM Audit | `rule.groups:*nova_iam*` | actions IAM, operators, level>=8 | 1m | now-7d |
| `nova-ids-multi-capteurs` | IDS Multi-capteurs | `decoder.name:suricata` | $capteur (FW-EXT-LYON/FW-INT-LYON/FW-EXT-MRS) | 30s | now-24h |
| `nova-auth-failures` | Auth Failures | `rule.groups:*authentication_fail*` | service, username, src.ip | 30s | now-24h |

## Panels par dashboard

### NIS2 Compliance (4 panels)
- Pie chart : alertes par rule_groups NIS2
- Table : top 10 rule.id niveau >= 10
- Time series stacked bars : timeline 24h par 1h
- Stat : total alertes NIS2 dans la fenetre

### IAM Audit (4 panels)
- Bar chart : actions par type (CREATE/GRANT/REVOKE/DISABLE/ENABLE/ADMIN_RESET/BULK_ROTATE/HARD_DELETE)
- Table : top operators (via parse `data.operator.keyword`)
- Time series : actions IAM sur 7 jours
- Table : alertes level >= 8 (privilege escalation + hard delete)

### IDS Multi-capteurs (5 panels)
- Time series stackee : alertes Suricata par capteur (template variable `$capteur`)
- Table : top 20 signatures triggered
- Table : top 10 src.ip
- Table : top 10 dst.ip
- Donut pie : distribution rule.level

### Auth Failures (4 panels)
- Donut : echecs par service (sshd / authelia / smtpd / dovecot)
- Table : top usernames cibles
- Stat : max echecs par minute meme src.ip (brute force indicator)
- Time series : timeline 24h par decoder

## Deploiement

Les fichiers de ce dossier sont la source de verite. Pour pousser sur un
nouvel app01 :

```sh
# Copier les configs de provisioning Grafana
scp datasource-wazuh.yaml app01:/etc/grafana/provisioning/datasources/wazuh.yaml
scp provider-wazuh.yaml   app01:/etc/grafana/provisioning/dashboards/wazuh.yaml

# Copier les dashboards JSON
ssh app01 'mkdir -p /var/lib/grafana/dashboards/nova-security && chown grafana:grafana /var/lib/grafana/dashboards/nova-security'
scp *.json app01:/var/lib/grafana/dashboards/nova-security/

# Restart pour reprovisionner
ssh app01 'systemctl restart grafana-server'
```

Provisioning automatique au demarrage Grafana ; tout edit en UI sera
ecrase au prochain restart (sauf si `allowUiUpdates: true` dans le
provider, ce qui est notre cas).

## Permissions par groupe AD

Cible (non operationnelle aujourd'hui -- requiert SSO Authelia/LDAP
non encore configure sur Grafana) :
- `viewer` : groupe AD `Lyon-Staff`
- `editor` : groupe AD `Lyon-Admins`
- `admin`  : `Administrator`

Path d'implementation :
1. Configurer `[auth.generic_oauth]` ou `[auth.ldap]` dans
   `/etc/grafana/grafana.ini` pointant sur Authelia.
2. Mapper les groupes AD dans `ldap.toml` ou `generic_oauth` `role_attribute_path`.
3. Provisioning access-control YAML dans
   `/etc/grafana/provisioning/access-control/`.

Dette tracee dans ADR-0030 section "Permissions par groupe AD".

## Prerequis OpenSearch (wazuh-indexer)

Au moment de la creation T-DASHBOARD-WAZUH, **wazuh-indexer n'est pas
installe** sur app01 (4 GB RAM serait juste). La datasource pointe sur
`https://127.0.0.1:9200` et les dashboards renvoient "No data" tant que :
1. `wazuh-indexer` n'est pas installe + demarre,
2. `wazuh-manager` n'est pas configure pour shipper les alertes vers
   l'indexer (cf. `<global><logall_json>yes</logall_json>` +
   `<integration>` filebeat ou direct).

Dette tracee dans ADR-0030 section "Prerequis indexer".

## Tests valides (Phase 7)

1. JSON validite syntaxique : 4/4 OK (python json.load)
2. Datasource provisionnee : uid `wazuh-opensearch` type
   `grafana-opensearch-datasource` -> visible dans `data_source` table
3. Folder + 4 dashboards : `cfmgw86nwuebka` "Nova Syndicate -- Security"
   contient 4 dashboards (unified storage `resource` table)
4. Grafana health : `{"database":"ok","version":"13.0.1"}`
5. Tags : chaque dashboard tagge avec `["wazuh","security","nova-syndicate",<topic>]`
