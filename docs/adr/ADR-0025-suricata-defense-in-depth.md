# ADR-0025 : Suricata IDS multi-capteurs (defense in depth)

- Statut : Accepté
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-SURICATA-MULTI-CAPTEURS

## Contexte

Suricata était déjà déployé sur FW-EXT-LYON (cf. [ADR-précédent](../runbook/suricata-fw-ext-lyon.md), commit `fb538b4`) comme capteur périmétrique du site Lyon. Ce capteur unique laisse plusieurs angles morts :

- **Lateral movement intra-VLAN Lyon** : un attaquant qui compromet un poste user (192.168.30.0/26) et tente de pivoter vers les servers (192.168.20.0/28) reste invisible — le trafic ne traverse que FW-INT-LYON, pas FW-EXT.
- **Site Marseille** : aucune visibilité sur le trafic externe entrant côté MRS (185.55.247.171 → 192.168.40.0/26). FW-EXT-MRS n'avait pas d'IDS actif.
- **Trafic IPsec décapsulé** : visible sur FW-EXT-LYON après déchiffrement, mais quand un payload latéral est généré DEPUIS Lyon vers MRS, l'aller transite via FW-EXT-LYON (vu) mais le retour via FW-INT côté MRS reste opaque.

L'objectif : étendre la couverture IDS à 3 capteurs pour réaliser un schéma defense-in-depth complet (périmètre + lateral + multi-site).

## Décision

Déployer Suricata IDS (pas IPS — pas d'inline drop pour ne pas casser le trafic légitime) sur 3 points de capture :

```
                Internet (185.55.247.170, 185.55.247.171)
                       |                    |
                       v                    v
              FW-EXT-LYON [IDS #1]   FW-EXT-MRS [IDS #3]
              (perimeter Lyon)       (perimeter MRS)
                       |                    |
                       v                    v
              [VLANs Lyon] <- IPsec tunnel -> [LAN MRS]
              vlan02 Bastion             192.168.40.0/26
              vlan03 Servers
              vlan04 Users
              vlan01 Backup
                       |
                       v
              FW-INT-LYON [IDS #2]
              (lateral movement)
```

### Configuration par capteur

| Capteur | Interfaces ecoute | HOME_NET | Rulesets actives |
|---|---|---|---|
| **FW-EXT-LYON** (existant) | vtnet0 (WAN, inclut 185.55.247.170) | 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 185.55.247.170 | emerging-{scan,attack_response,exploit,current_events} + local.rules (~3-5k regles) |
| **FW-INT-LYON** (nouveau) | wan (peering 10.0.1.0/30), opt2 (Bastion), opt3 (Servers), opt4 (Users) | 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 | emerging-{scan,attack_response,exploit,current_events,malware,mobile_malware} (~3-5k regles) |
| **FW-EXT-MRS** (nouveau) | vtnet0 (WAN peering 10.0.2.0/30), vtnet1 (LAN 192.168.40.0/26) | 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 | emerging-{scan,attack_response,exploit,current_events} |

### Pourquoi pas IPS

Mode IPS (drop inline) écarté pour le POC :
- Risque de coupure de trafic légitime si un faux positif tape une rule générique (ex: User-Agent suspect mais légitime).
- Tuning long requis avant production.
- Suricata 7 supporte le mode inline via NFQUEUE/divert, mais OPNsense en mode IDS classique fait du `--pcap` (passive). Bascule en IPS demande un changement structurel.

À revoir en Phase IV : enable IPS sur FW-EXT-LYON pour quelques rules critiques (drop.rules, ciarmy.rules), garder IDS sur FW-INT et FW-EXT-MRS.

### Ruleset minimal et justification

Le brief J2 imposait `~3-5k regles` (cf. lessons-learned 12 mai : 30k+ règles causent OOM avec 2 GB RAM). Sélection :

| Ruleset | Rationale |
|---|---|
| `emerging-scan` | Détection scans nmap, masscan, port-scan distribué |
| `emerging-attack_response` | Réponses post-compromission (shell upload, cmd&ctrl basic) |
| `emerging-exploit` | Exploits connus (CVE) |
| `emerging-current_events` | Campagnes actives (ransomware, malware récent) |
| `emerging-malware` (FW-INT only) | Beaconing, persistance malware |
| `emerging-mobile_malware` (FW-INT only) | Trafic IoT/mobile compromis |

Ajout local.rules pour des règles de test/contexte spécifique Nova (SID 9100xxx pour FW-INT, 9200xxx pour FW-EXT-MRS).

### Ressources

| Capteur | RAM avant | RAM après | Swap | Note |
|---|---|---|---|---|
| FW-EXT-LYON | 4 GB | 4 GB | 2 GB | Pas de changement (deja à jour 17/05) |
| FW-INT-LYON | 2 GB | **4 GB** | (à ajouter) | Hot-add KO en FreeBSD → `--hotplug disk,network,usb` + reboot |
| FW-EXT-MRS | 2 GB | **4 GB** | (à ajouter) | Idem reboot fixed-allocation |

Total dédié IDS : ~12 GB RAM (3×4) sur 32 GB Proxmox.

## Alternatives évaluées

| Option | Verdict |
|---|---|
| **3 capteurs Suricata IDS** | **Retenu**. Visibilité complète, ruleset ET Open gratuit, configuration cohérente entre les 3, intégration OPNsense native (API + GUI). |
| **Capteur unique FW-EXT-LYON étendu** | Rejeté. Ne couvre pas lateral Lyon (trafic intra-VLAN ne traverse jamais FW-EXT). Ne couvre pas MRS. |
| **NSM/Zeek en complément** | Évalué pour Phase IV. Zeek produit des logs structurés (conn.log, dns.log, http.log) très utiles pour le forensic. Pas implémenté pour le POC car double maintenance + cumul RAM. T-NSM-ZEEK noté en dette. |
| **Solution commerciale (Trellix, Snort++ Talos)** | Hors scope budget POC. Mention dans le rapport "Phase III/IV : évaluer Snort++ avec Talos pour la maintenance de signatures plus à jour". |
| **eBPF-based (Cilium, Tetragon)** | Évalué. Plus moderne mais nécessite Linux côté firewall (incompatible OPNsense/FreeBSD). Vue applicative requise pour analyser le contenu (Cilium L7 sniff). Hors scope. |

## Conséquences

### Bénéfices

- **Defense in depth réelle** : un compromis sur un capteur (par exemple FW-EXT-LYON désactivé par un attaquant) ne supprime pas la détection — FW-INT-LYON continue d'observer le lateral movement.
- **Détection multi-site** : un scan venant de l'extérieur sur MRS est désormais loggué (avant : trou noir).
- **Centralisation possible** : les 3 capteurs écrivent en `/var/log/suricata/eve.json` (format JSON Suricata standard). Future intégration Wazuh manager (T-SURICATA-WAZUH-INTEGRATION) pour vue unifiée.
- **Tests reproductibles** : `scripts/opnsense/suricata-multi-test.sh` check les 3 capteurs en une commande.

### Coûts / risques

- **+8 GB RAM consommée** (2× 4 GB pour FW-INT et FW-EXT-MRS) sur le serveur Proxmox. OK sur la config actuelle (32 GB total), à monitorer si on ajoute beaucoup d'autres VMs.
- **Reboot des firewalls** : chacun ~60s de downtime. Pour FW-INT-LYON : coupe l'accès LAN Lyon ↔ Internet et inter-VLAN. Pour FW-EXT-MRS : coupe MRS ↔ Internet. IPsec auto-recovery sur FW-EXT-LYON garde les SAs si FW-INT pingue moins de 5 min. Tous deux rebootés en dehors d'usage métier (heures de travail).
- **Ruleset minimal = faux négatifs** : on rate les attaques applicatives sophistiquées qui nécessitent les rulesets `emerging-web_specific_apps`, `emerging-sql`, etc. Compensation : Cloudflare WAF côté `nova.0xmatthieu.dev`, et nginx-level filtering. Dette : T-SURICATA-RULESET-PROD.
- **Pas d'agrégation centralisée encore** : il faut SSH/API sur chaque capteur pour lire les alertes. T-SURICATA-WAZUH-INTEGRATION.
- **Trafic HTTPS chiffré non inspecté** : Suricata ne voit que le SNI + les patterns IP/port. Les payloads applicatifs HTTPS sont opaques (sauf si TLS inspection — non installé). C'est attendu et conforme RGPD (on n'intercepte pas le contenu utilisateur).

### Dette dérivée

- **T-SURICATA-WAZUH-INTEGRATION** : forwarder eve.json des 3 capteurs vers Wazuh manager (APP01 wazuh-manager). Permet corrélation logs + dashboard centralisé.
- **T-SURICATA-GRAFANA-DASHBOARD** : Grafana panel par capteur (alerts/s, top sids, source IPs, geo-map). Datasource : prometheus + node_exporter custom OU Wazuh API.
- **T-SURICATA-RULESET-PROD** : passage à un ruleset étendu (10-15k règles) une fois la baseline de faux positifs identifiée + tuning local.
- **T-SURICATA-IPS-CRITIQUE** : enable mode IPS sur FW-EXT-LYON pour quelques rules `drop.rules` + `ciarmy.rules` (block automatique IPs malveillantes connues).
- **T-NSM-ZEEK** : déployer Zeek en complément (logs structurés) sur les 3 mêmes points.

## Validation

### Status des 3 capteurs (2026-05-18 ~12:40 UTC)

```bash
bash scripts/opnsense/suricata-multi-test.sh
# [OK]   opn-fw-ext-lyon Suricata running    RAM ~74 MB
# [OK]   opn-fw-int-lyon Suricata running    RAM used ~515 MB
# [OK]   opn-fw-ext-mrs  Suricata running    RAM ~76 MB
```

### Configuration vérifiable

- FW-EXT-LYON : `pgrep suricata` + `cat /var/log/suricata/eve.json | head` (depuis SSH `opn-fw-ext-lyon`)
- FW-INT-LYON : `curl -k -u $K:$S https://192.168.99.1/api/ids/service/status` (depuis Proxmox)
- FW-EXT-MRS : `pgrep suricata` (depuis SSH `opn-fw-ext-mrs`)

## Références

- Runbook existant : [docs/runbook/suricata-fw-ext-lyon.md](../runbook/suricata-fw-ext-lyon.md)
- Script test : [scripts/opnsense/suricata-multi-test.sh](../../scripts/opnsense/suricata-multi-test.sh)
- ET Open ruleset : https://rules.emergingthreats.net/open/suricata-7.0/
- [ADR-0013 Wazuh SIEM NIS2](ADR-0013-wazuh-siem-nis2.md) — corrélation future
