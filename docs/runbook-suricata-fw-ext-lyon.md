# Runbook -- Suricata IDS sur FW-EXT-LYON

Reference : T-SURICATA-FW-EXT, incident 2026-05-12 (OOM premiere tentative)

## Configuration

| Parametre | Valeur | Raison |
|---|---|---|
| Mode | IDS uniquement (`ips=0`) | Pas de drop, alertes seulement |
| Interface | WAN (vtnet0) | Detection trafic entrant |
| Homenet | 185.55.247.170/32, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12 | Inclut IP publique WAN -- voir piege ci-dessous |
| RAM VM | 4 GB | Up de 1 GB apres OOM 2026-05-12 |
| Swap | 2 GB (/var/.swap via md99) | Filet de securite |

## Piege HOME_NET et IP publique (T-SURICATA-DETECTION-FIX, 2026-05-17)

Les regles ET (emerging-scan, exploit, etc.) sont presque toutes structurees :

```
alert tcp $EXTERNAL_NET any -> $HOME_NET any (...)
```

Avec `EXTERNAL_NET: "!$HOME_NET"`. Si Suricata voit du trafic vers l'IP publique
WAN (185.55.247.170) et que cette IP n'est pas dans HOME_NET, alors :
- src = $EXTERNAL_NET (OK, IP externe)
- dst = ni $HOME_NET ni explicitement EXTERNAL -> **regle ne match pas**

C'est pourquoi le nmap initial du 2026-05-17 vers 185.55.247.170 a genere 0 alerte
malgre 2702 regles chargees. Fix : ajouter 185.55.247.170/32 a HOME_NET via le
champ `<homenet>` dans /conf/config.xml puis `configctl template reload OPNsense/IDS`.

NB : selon que l'upstream NAT change la destination ou pas, Suricata peut voir
dst=185.55.247.170 OU dst=10.0.0.2 (IP locale vtnet0). Inclure les deux dans
HOME_NET couvre les deux cas.

## Rules locales de validation (local.rules)

4 regles custom (sid 9000001-9000004) presentes dans
`/usr/local/etc/suricata/opnsense.rules/local.rules`, incluses via
`/usr/local/etc/suricata/custom.yaml`. Servent a valider rapidement le pipeline
detection -> eve.json sans dependre du trafic naturel.

| sid | Regle | Usage |
|---|---|---|
| 9000001 | ICMP -> 185.55.247.170 | ping outbound depuis l'interieur (test rapide) |
| 9000002 | SYN -> 185.55.247.170:80,443,8080 | curl outbound |
| 9000003 | content "Nmap" any -> any | signature User-Agent nmap |
| 9000004 | ICMP -> 10.0.0.2 | ping inbound vers IP locale WAN |

A retirer ou reduire une fois le pipeline valide en production reelle.

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

## Tests de detection

Script automatise : `scripts/opnsense/suricata-test.sh <target_public_ip>`. A executer
depuis un poste **externe** au reseau Nova (4G, VPS, autre site). Sinon le trafic
ne traverse pas vtnet0 avec la bonne destination.

```sh
# Depuis VPS Hetzner (ou autre point externe) :
./suricata-test.sh 185.55.247.170
# Output : ping + curl + nmap puis count alertes generees + top signatures.
```

Test manuel sans le script :

```sh
ping -c 5 185.55.247.170
curl -m 2 http://185.55.247.170
sudo nmap -sS -p1-65535 --min-rate 5000 -T5 185.55.247.170

# Verifier cote FW-EXT
ssh opn-fw-ext-lyon 'wc -l /var/log/suricata/eve.json'
ssh opn-fw-ext-lyon 'tail -20 /var/log/suricata/eve.json' | jq -r 'select(.event_type=="alert") | "\(.alert.signature_id) \(.alert.signature)"'
```

Attendu :
- sid 9000001 (NOVA Test ICMP to WAN public IP) sur le ping outbound depuis FW-EXT.
- sid 9000004 (NOVA Test ICMP to WAN local IP) sur le retour du ping ou sur ping inbound.
- ET emerging-scan rules sur nmap externe (sid 2000+).

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
- `pre-suricata-homenet-fix-2026-05-17` : Suricata UP mais HOME_NET sans IP
  publique -> 0 alerte. Pris avant T-SURICATA-DETECTION-FIX.

## Dettes liees

- **T-SURICATA-MONITORING** : exporter les metriques Suricata vers Prometheus
  (regle compte, alertes par categorie, RAM consommee). Cible : panel Grafana
  dedie.
- **T-SURICATA-IPS-MODE** : evaluer le passage en mode IPS (drop) apres
  validation 30 jours sans faux positifs critiques.
- **T-SURICATA-HOME-NET-IAC** : passer la config HOME_NET (et plus largement
  toute la section `<IDS>` du config.xml) en Ansible/Terraform via API OPNsense
  pour eviter qu'un rollback efface le fix detection.
- **T-SURICATA-LOCAL-RULES-PROD** : les sids 9000001-9000004 sont des regles de
  test du pipeline. A retirer ou remplacer par des regles metier nettes une fois
  que l'invariant "alertes sur scan externe" est valide en duree.
