# Incident 2026-05-12 -- Suricata FW-EXT-LYON OOM

## Resume
Tentative activation Suricata IDS sur FW-EXT-LYON. RAM saturee pendant 
compilation des regles (214k loaded). SSH et strongSwan degradent. 
Rollback Proxmox snapshot. Aucune trace persistante.

## Timeline
- 15:54 : Snapshot Proxmox pre-suricata-2026-05-12 cree
- 15:58 : Backup /conf/config.xml
- 16:05 : Config IDS XML deployee (11 rulesets, vtnet0 WAN, mode IDS)
- 16:08 : Telechargement regles ET Open + abuse.ch (214 235 regles alert)
- 16:12 : configctl ids start, Suricata PID 10055
- 16:15 : SSH banner exchange timeout, IPsec SAs = 0
- 16:18 : Rollback Proxmox execute
- 16:20 : SSH retabli, reboot OK
- 16:22 : swanctl --initiate x 3, IPsec SAs = 4 restaure
- 16:25 : Invariants finaux verifies (IPsec=4, Wazuh=7)

## Root cause
FW-EXT-LYON VM allocated 2 GB RAM.
Selection rulesets : 11 categories incluant feeds lourds abuse.ch :
- abuse.ch.threatfox : ~146 000 regles
- urlhaus : ~38 000 regles
- emerging-malware : ~18 000 regles
Total : 214 235 regles a compiler.

RAM saturee pendant compilation, OOM-kill silencieux des processus 
moins prioritaires (sshd fork, strongSwan).

## Symptomes confirmes
- SSH "Connection timed out during banner exchange"
- swanctl --list-sas | grep INSTALLED a 0 (etait 4)
- ps aux | grep suricata absent
- ping FW-EXT : OK (kernel L3 forwarding intact)
- NAT WAN : OK (app01 sortait toujours sur internet)

## Mitigation appliquee
Rollback Proxmox snapshot pre-suricata-2026-05-12 :
ssh root@100.112.113.2 'qm rollback 201 pre-suricata-2026-05-12'

Apres reboot : re-initialisation IPsec :
ssh opn-fw-ext-lyon 'swanctl --initiate --child <name>' x 3

## Lecons apprises
1. OPNsense Web UI ne warn pas sur conso RAM des rulesets actives
2. Suricata compile TOUTES les regles en memoire au start
3. 2 GB RAM insuffisant pour rulesets feeds threat intel (abuse.ch)
4. Snapshot Proxmox AVANT activation services lourds = anti-lockout valide
5. Rollback rapide preserve invariants critiques (IPsec, Wazuh)

## Dettes derivees
- T-SURICATA-FW-EXT-RAM (haute) : Upgrade VM a 4 GB RAM avant retry
- T-SURICATA-RULESET-CURATION (haute) : Ruleset minimal 3-5k regles
  (emerging-scan, attack_response, exploit, current_events)
- T-FW-EXT-QEMU-AGENT (moyenne) : Installer qemu-guest-agent pour 
  diagnostic break-glass via qm guest exec
- T-SURICATA-OPNSENSE-RAM-WARN (basse) : Documenter contrainte RAM 
  dans runbook avant retry

## Plan de retry
1. Stop VM FW-EXT
2. qm set 201 --memory 4096
3. Start VM, verifier invariants
4. Snapshot pre-suricata-retry
5. Activer Suricata avec ruleset minimal (~3000 regles)
6. Mesurer RAM Suricata en regime etabli (sysstat 30 min)
7. Scaling progressif si OK

## Etat post-incident
- IPsec SAs : 4 INSTALLED
- Wazuh Active : 7
- SSH FW-EXT : OK
- NAT WAN : OK
- Snapshot pre-suricata-2026-05-12 : conserve pour reference
- Zero modification persistante sur FW-EXT
- Zero commit Git impacte
