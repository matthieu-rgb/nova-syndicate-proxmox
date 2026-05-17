# Runbook -- Suricata IDS sur FW-EXT-LYON

Reference : T-SURICATA-FW-EXT, incident 2026-05-12 (OOM premiere tentative)

## Configuration

| Parametre | Valeur | Raison |
|---|---|---|
| Mode | IDS uniquement (`ips=0`) | Pas de drop, alertes seulement |
| Interface | WAN (vtnet0) | Detection trafic entrant |
| Homenet | 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 | Couvre tous les VLANs internes |
| RAM VM | 4 GB | Up de 1 GB apres OOM 2026-05-12 |
| Swap | 2 GB (/var/.swap via md99) | Filet de securite |

## Rulesets actives (4 fichiers, ~2700 regles)

| Fichier | Regles | Categorie |
|---|---|---|
| emerging-scan.rules | 285 | Detection scans (nmap, port sweep) |
| emerging-attack_response.rules | 679 | Reponses post-compromission (shells, exfil) |
| emerging-exploit.rules | 1684 | Exploits publics (CVE, RCE) |
| emerging-current_events.rules | 54 | Menaces actives du moment |

**Exclus volontairement** :
- abuse.ch.threatfox, abuse.ch.urlhaus : gros volumes, beaucoup de bruit
- emerging-malware : 30k+ regles, trop gourmand en RAM

## Verification

```sh
ssh opn-fw-ext-lyon 'configctl ids status'
# Attendu : suricata is running as pid XXXXX

ssh opn-fw-ext-lyon 'ps -aux | grep suricata | grep -v grep'
# RSS attendu : ~150-250 MB

ssh opn-fw-ext-lyon 'tail -20 /var/log/suricata/eve.json | grep alert'
# Alertes recentes si trafic suspect
```

## Tests de detection (a faire manuellement)

```sh
# Depuis l'exterieur (poste sans VPN) :
nmap -sS -p 1-100 <IP_PUBLIC_FW_EXT>
# -> attendu : alerte ET SCAN dans /var/log/suricata/eve.json
```

## Procedure de demarrage from-scratch

Pre-requis : RAM >= 4 GB, swap configure, snapshot pris.

```sh
# 1. Snapshot Proxmox
ssh root@100.112.113.2 'qm snapshot 201 pre-suricata-$(date +%s) --description "Pre Suricata"'

# 2. Activer 4 rulesets minimaux dans /conf/config.xml (par ID UUID via API)
#    OU edit direct du XML + grep enabled

# 3. Recharger le template OPNsense pour generer rule-updater.config
ssh opn-fw-ext-lyon 'configctl template reload OPNsense/IDS'

# 4. Telecharger les regles (~2.4 MB, source ET Open)
ssh opn-fw-ext-lyon '/usr/local/opnsense/scripts/suricata/rule-updater.py'

# 5. Installer dans suricata.yaml
ssh opn-fw-ext-lyon 'configctl ids install rules'

# 6. Demarrer
ssh opn-fw-ext-lyon 'configctl ids start'

# 7. Verifier RAM apres 60s
ssh opn-fw-ext-lyon 'vmstat -h 1 2; ps aux | grep suricata | grep -v grep'

# 8. Verifier IPsec invariant maintenu
ssh opn-fw-ext-lyon 'swanctl --list-sas | grep -c "INSTALLED, TUNNEL"'
# Doit etre 4
```

## Procedure d'arret d'urgence

Si RAM critique ou OOM imminent :

```sh
ssh opn-fw-ext-lyon 'configctl ids stop'
# Liberation immediate de ~200 MB RAM
```

Si SSH bloque par OOM : `ssh root@100.112.113.2 'qm reboot 201'`. Le script
auto-recovery IPsec va remonter les 4 SAs dans les 5 min suivant le reboot.

## Snapshots de rollback

- `pre-suricata-2026-05-12` : etat avant la PREMIERE tentative (OOM). NE PAS
  utiliser comme cible de rollback : config IPsec vide dans ce snapshot.
- `pre-suricata-retry-1779036361` : etat avec 4 GB RAM + swap + IPsec OK,
  AVANT activation Suricata round 2. Rollback safe.
- `pre-hotadd-ram-4gb-1779036127` : etat 1 GB RAM, IPsec OK + recovery script.
  Permet de revert le hot-add.

## Dettes liees

- **T-SURICATA-MONITORING** : exporter les metriques Suricata vers Prometheus
  (regle compte, alertes par categorie, RAM consommee). Cible : panel Grafana
  dedie.
- **T-SURICATA-IPS-MODE** : evaluer le passage en mode IPS (drop) apres
  validation 30 jours sans faux positifs critiques.
