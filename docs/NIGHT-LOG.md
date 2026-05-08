# NIGHT-LOG -- Session nocturne 2026-05-08

## Debut session

Timestamp: 2026-05-08
Operateur: automation pipeline (mode autonome)
Contraintes actives:
- AUCUN terraform apply qui modifie infra firewall
- AUCUNE modif IPsec/strongSwan
- PAS de MFA TOTP enrollment
- Skip si fail 3x

## Decisions prises de maniere autonome

| Heure | Tache | Decision | Raison |
|-------|-------|----------|--------|
| START | Pre-vol | Verification SSH + tunnels | Protocole obligatoire |
| START | KANBAN T3 | SKIP -> TODO MATIN | terraform apply infra firewall = contrainte absolue #1 + KANBAN "pas en fin de session" |

## Taches

| Tache | Statut | Timestamp | Notes |
|-------|--------|-----------|-------|
| PRE-FLIGHT | DONE | START | DC1 OK, DB1 OK, APP1 OK, 4 tunnels OK, TF No changes |
| T1 AD Users | DONE | 2026-05-08 | 5 OUs, 8 groupes, 85 users. Total AD=91. Fixes: become:true + --given-name/surname + --userou relatif |
| T2 FS1 shares | PENDING | - | - |
| T3 MariaDB | PENDING | - | - |
| T4 Wazuh agents | PENDING | - | - |
| T5 Grafana+Prometheus | PENDING | - | - |
| T6 BorgBackup | PENDING | - | - |
| T7 rclone template | PENDING | - | - |
| T8 Runbooks | PENDING | - | - |
| T9 Health+Report | PENDING | - | - |

## Incidents

Aucun incident a ce stade.

## Log detail

### PRE-FLIGHT [DONE]

- DC1 192.168.20.10 : samba-tool domain info -> nova-syndicate.local OK
- DB1 192.168.20.12 : SHOW DATABASES -> nova_logistique + nova_rh presents
- APP1 192.168.20.13 : wazuh-manager active
- FW-EXT-LYON : 78112723 ESTABLISHED + 4 children INSTALLED (reqids 1-4) -- 4 modernes OK
  DT-3 note: con1 legacy #2 encore ESTABLISHED, children #38-41 present, aucun trafic entrant
- terraform plan : "No changes. Your infrastructure matches the configuration."
- Vault : ~/.ansible/nova_vault_pass present, ansible.cfg pointe dessus

### T1 AD Users [DONE]

Tentatives: 3 echecs playbook (permission denied, --fullname invalide, --userou avec domainDN)
Fixes appliques:
- become: true au niveau play (non herite de ansible.cfg)
- --fullname -> --given-name + --surname (split du fullname CSV)
- --userou: suppression du domainDN (OU=Lyon seulement, pas OU=Lyon,DC=...)
- passwords passes via fichier JSON temp (evite shlex.split sur JSON inline)

Resultat: Created=85, Skipped=0, Failed=0. samba-tool user list = 91 users (85+6 systeme)

### T2 FS1 shares [IN PROGRESS]
