# ADR-0027 : IAM industrialise via Ansible playbooks (preparation AWX)

- Statut : Accepte
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-IAM-PLAYBOOKS-2026-05-18
- Lien : extension de la remediation [ADR-0026](ADR-0026-vault-plaintext-fix-2026-05-18.md)
  pour la dette DETTE-009 (rotation users AD)

## Contexte

L'AD Samba `nova-syndicate.local` heberge 92 users + 5 service accounts
(Administrator, admin-t0/t1/t2, krbtgt, svc-authelia). La creation initiale
de ces 92 users a ete faite via `playbooks/create_users.yml` qui itere sur
`files/new_users.csv` avec un **default_password en clair** dans le playbook
(`"Nova****"`), defait par T-VAULT-PLAINTEXT-FIX (cf. ADR-0026).

Apres remediation T-VAULT-PLAINTEXT-FIX :
- Le default_password est devenu `{{ vault_default_user_password }}` (variable
  vault chiffree AES256).
- Les 92 users existants ont toujours leur ancien password initial ("Nova****")
  -- dette DETTE-009.
- Aucun outil industrialise n'existe pour les operations IAM standard
  (creation, suppression, ajout a groupe) en dehors du bulk `create_users.yml`.

Le besoin :
- Operations IAM standardisees, idempotentes et **auditees** (NIS2 art.30
  -- journalisation des activites d'administration).
- Surface attaque reduite : `samba-tool` directement sur dc01 expose des
  options destructives (delete) facilement, et il n'y a pas de trace de
  qui a fait quoi.
- Preparer la migration future vers AWX (self-service utilisateur pour
  managers / RH) sans tout reecrire.

## Decision

3 playbooks Ansible idempotents dans `playbooks/iam/` du repo
`nova-syndicate-ansible` :

| Playbook | Action | Defaut securise |
|---|---|---|
| `user_create.yml` | Creer user + groupes + force change next login | password = vault var |
| `user_delete.yml` | Disable (90j retention) ou hard-delete via `--tags hard-delete` | DISABLE par defaut |
| `user_grant_privilege.yml` | Ajout user a groupe avec verif assert post-add | n/a |

### Audit log structure

Fichier `/var/log/nova-iam/audit.log` sur dc01, mode 0640 root:root, format :

```
<ISO8601 UTC>  <ACTION>  <username>  [-> <group>]  by <operator>  [groups=...] [reason="..."]
```

Append-only par Ansible (module `lineinfile`). Ingere par Wazuh agent dc01 via
`<localfile>` clause dans `ossec.conf` (a confirmer en T-FOLLOW-UP).

### Conventions non-negociables

- `no_log: true` sur toute tache qui voit un password (samba-tool user create,
  setpassword). Sinon le password fuit dans `ansible-playbook -vvv` et dans
  `/var/log/syslog` des hosts cibles.
- Operator name = `$USER` sur le controller Ansible (Mac). Pas `ansible_user`
  qui est l'utilisateur SSH cote dc01 (`debian` toujours).
- Extra-vars JSON obligatoire pour les listes et chaines multi-mots :
  `-e '{"reason":"multi-word reason here"}'`. La syntaxe `-e reason="..."`
  tronque a l'espace.
- `user_delete.yml` defaut = DISABLE (pas DELETE), pour aligner avec NIS2
  retention 90j. Hard-delete cible le test/QA via tag explicite.

## Conformite NIS2 / RGPD / ISO 27001

- **NIS2 art.21 (mesures techniques)** -- chaque modification IAM est
  centralisee dans un playbook, code reviewable, idempotent, auditable.
- **NIS2 art.30 (journalisation)** -- audit.log structure horodatee +
  ingestion Wazuh pour correlation SIEM.
- **RGPD art.32 (mesures techniques)** -- secrets vault chiffre, no_log
  enforce, principle of least privilege (default disable vs delete).
- **ISO 27001 A.9.2 (User access management)** -- separation create / grant
  / delete avec authorization explicite par operator nomme dans l'audit.

## Tests effectues (T-IAM-PLAYBOOKS-2026-05-18 Phase 6)

| # | Test | Resultat |
|---|---|---|
| T1 | `user_create.yml` avec `Demo/Iam2026b/[Lyon-Staff,Commerciaux]` | CREATED + 2 group memberships + must-change set |
| T2 | `user_grant_privilege.yml` `test.iam2026 -> Lyon-Staff` | GRANTED + assert post-add OK |
| T3 | `user_delete.yml` defaut sur `test.iam2026` | DISABLED (samba-tool user show -> userAccountControl=514) |
| T4 | `user_delete.yml --tags hard-delete` sur `test.iam2026` | HARD_DELETE + assert removed |
| T5 | Audit log `/var/log/nova-iam/audit.log` 5 entrees | OK -- 3 test.iam2026 + 1 CREATE demo.iam2026b + 1 HARD_DELETE demo.iam2026b |
| T6 | Cleanup test/demo users | OK -- `samba-tool user list \| wc -l` retombe a 92 (= avant tests) |

## Option B rotation appliquee (DETTE-009 partielle)

4 demo users identifies (les plus susceptibles d'apparaitre dans les
demos jury) ont eu leur password rotate vers `vault_default_user_password` :

| User | Groupes | Persona demo |
|---|---|---|
| fabien.bonnet | Lyon-Staff + Commerciaux | login portail / Authelia / Grafana |
| alexandre.gautier | Lyon-Staff | utilisateur standard Lyon |
| lucie.lefevre | Mobile-Agents | road-warrior persona |
| matthieu.gerard | Marseille-Staff | inter-sites IPsec persona |

Validation :
- `wbinfo --authenticate='fabien.bonnet%Nova****'` -> FAIL (plaintext +
  challenge/response auth failed)
- `wbinfo --authenticate='fabien.bonnet%<nouveau>'` -> PASS (plaintext +
  challenge/response auth succeeded)

Les 88 autres users gardent leur password initial leak. Documentation
restante : T-FOLLOW-UP DETTE-009-bis (rotation full + force-change-next-login
sur les 88 restants, via playbook one-shot iterant sur la CSV).

## Consequences

### Positives
- 3 operations IAM courantes industrialisees, code reviewable, idempotent,
  audite.
- Surface attaque reduite : pas de root SSH sur dc01 + samba-tool a la main.
  Passage par le bastion + ansible.
- Preparation AWX : les 3 playbooks sont AWX-ready (extra-vars JSON,
  templating clair, no_log enforce). Migrating vers AWX = creation de 3 Job
  Templates pointant sur ces fichiers + survey form (UI utilisateur).
- Audit log structure permet l'ingestion Wazuh + dashboards Grafana.

### Negatives
- Extra-vars JSON obligatoire pour les listes -- pas user-friendly en CLI
  (mitigee par README + exemples).
- Le `--tags hard-delete` necessite que le caller comprenne le mecanisme
  des tags Ansible (risque d'usage accidentel limite par le mot "hard-delete"
  explicite).
- Audit log local seulement (pas encore ingestion Wazuh). DETTE-012 ouverte.

### Neutres
- Le playbook `playbooks/create_users.yml` existant n'est pas migre vers
  `playbooks/iam/` -- garde son role de bulk-create CSV pour les onboarding
  massifs. Les 3 nouveaux playbooks sont pour les operations unitaires.
- `vault_default_user_password` partage entre create_users.yml (bulk) et
  user_create.yml (unitaire) -- coherent.

## Dettes ouvertes apres ADR-0027

### DETTE-009-bis -- Rotation des 81 users AD restants (**RESOLUE 2026-05-18**)
Playbook `playbooks/iam/users_rotate_bulk.yml` cree et execute. 81 users
rotates vers `vault_default_user_password` + must-change-at-next-login
(pwdLastSet=0 verifie). Exclusions actives : Administrator, Guest, krbtgt,
admin-t0/t1/t2, svc-authelia, et les 4 demo deja faits en Option B.
Snapshot `pre-dette-009-bis-2026-05-18` sur dc01. 81 entrees BULK_ROTATE
dans `/var/log/nova-iam/audit.log`.

### DETTE-012 -- Ingestion Wazuh de l'audit.log IAM (**RESOLUE 2026-05-18**)
- Agent dc01 : `<localfile>` syslog ajoute dans `/var/ossec/etc/ossec.conf`
  (snippet versionne : `roles/wazuh_agent/templates/iam_localfile.snippet.xml`)
- Manager app01 : `/var/ossec/etc/rules/nova-iam_rules.xml` cree avec 3
  regles custom IDs 100400-100402 (template versionne
  `roles/wazuh_manager/templates/nova-iam_rules.xml.j2`) :
  - 100400 level 3  -- catch-all CREATE/GRANT/DISABLE/HARD_DELETE/BULK_ROTATE
  - 100401 level 10 -- ALERT HARD_DELETE irreversible (NIS2 art.30)
  - 100402 level 8  -- ALERT GRANT privilege escalation (NIS2)
- Test E2E : injection 3 events dans audit.log dc01 -> 2 alertes propages
  dans alerts.log app01 (rules 100401 + 100402). Snapshots pre-modif :
  `pre-dette-012-2026-05-18` sur VMID 103 (dc01) et VMID 106 (app01).

### DETTE-013 -- Playbooks symetriques (**RESOLUE 2026-05-18**)
3 playbooks symetriques ajoutes dans `playbooks/iam/` :
- `user_revoke_privilege.yml` (symmetric to grant, verify post-remove)
- `user_reset_password.yml` (admin-initiated reset, openssl rand -base64 16
  + must-change-at-next-login defaut, optional output_password=true)
- `user_enable.yml` (re-enable disabled user, verify uAC=512)

Suite IAM **complete** = **7 playbooks** : create, delete, enable,
grant, revoke, reset, rotate_bulk. Pretes pour Job Templates AWX
(DETTE-014).

Test lifecycle 7-steps PASS (snapshot `pre-dette-013-2026-05-18` sur dc01) :
CREATE -> GRANT -> REVOKE -> DISABLE -> ENABLE -> ADMIN_RESET -> HARD_DELETE.
7 entrees audit.log + propagation Wazuh dc01 -> app01 (4 alertes generees).

### DETTE-014 -- Migration AWX self-service (P3)
Deploiement AWX (community edition) sur app01 ou container Proxmox, avec :
- Job Templates pointant sur les 3 playbooks IAM
- Survey UI pour les variables (first_name, last_name, etc.)
- Workflow approbation pour HARD_DELETE et CREATE
- RBAC AWX : RH peut creer users mais pas hard-delete
Priorite : P3 (apres consolidation infra).

## References

- ADR-0023 (portail metier) -- consommateur des users AD via Authelia
- ADR-0019 (Authelia MFA) -- les users crees doivent ensuite onboard MFA TOTP
- ADR-0013 (Wazuh SIEM NIS2) -- futur ingest de l'audit.log
- ADR-0026 (vault plaintext fix) -- contexte declenchant de l'industrialisation IAM
- Samba documentation : <https://wiki.samba.org/index.php/Samba_AD_DC_Administration>
