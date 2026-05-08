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
| T2 FS1 shares | DONE | 2026-05-08 | Domain joined, 5 shares (3 browseable + 2 hidden). chgrp domaine sur dirs. full_audit VFS desactive (opnames invalides Samba 4.17) |
| T3 MariaDB | DONE | 2026-05-08 | 3 comptes (app_logistique_rw, app_hr_ro, backup_user), nova_audit, cron 02h00, dump+rsync OK |
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

### T2 FS1 shares [DONE]

FS1 joint a nova-syndicate.local via net ads join.
5 shares crees: lyon, marseille, commun, finance (hidden), it-restricted (hidden).
Dirs avec group domaine winbind (lyon-staff, marseille-staff, finance, it-admins, domain users).
full_audit VFS desactive: opnames mkdir/rename invalides Samba 4.17 -- TODO valider + re-activer.
Test: smbclient Lyon/Finance/IT-Restricted accessibles avec Administrator (ajout aux groupes).

### T3 MariaDB [DONE]

3 comptes: app_logistique_rw (rw nova_logistique), app_hr_ro (ro nova_rh), backup_user (dump privileges MariaDB).
BACKUP_ADMIN invalide MariaDB 10.11 -> utilise SELECT,RELOAD,LOCK TABLES,PROCESS,REPLICATION CLIENT,SHOW VIEW,EVENT,TRIGGER,BINLOG MONITOR.
nova_audit cree. Script /opt/nova-backup/backup-db.sh + cron 02h00.
Cle SSH generee sur DB1 (/root/.ssh/id_backup) et autorisee sur BACKUP01.
DB1 debanni de fail2ban BACKUP01 (ban apres tentatives SSH manuelles).
Test: dump 512K OK, rsync 192.168.50.2:/var/backups/from-db1 OK.

### T4 Wazuh agents [IN PROGRESS]
