# ADR-0026 : Vault plaintext detection and remediation (T-VAULT-PLAINTEXT-FIX-2026-05-18)

- Statut : Accepte
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-VAULT-PLAINTEXT-FIX-2026-05-18
- Detection : T-INFRA-FULL-TEST-2026-05-18 (FAIL 10.02)

## Contexte

Le test exhaustif d'infrastructure T-INFRA-FULL-TEST a detecte que le fichier
`nova-syndicate-ansible/inventory/group_vars/all/vault.yml` etait stocke en
clair (ASCII text, NON chiffre) et commited dans Git (commits `0866095`,
`7b09cce`, `99bc182`), exposant 8 secrets sensibles a tout consommateur du
repo GitHub :

- vault_ansible_sudo_password ("debian" -- mot de passe = nom d'utilisateur)
- vault_samba_admin_password ("Nova****")
- vault_krb5_admin_password ("Nova****")
- vault_mariadb_root_password ("Nova****")
- vault_mariadb_backup_password ("Nova****")
- vault_mariadb_app_password ("Nova****")
- vault_ipsec_psk_lyon_mrs ("Nova****")
- vault_wireguard_server_privkey ("kHr1****REDACTED****FK0U=")

Le mot de passe "Nova****" etait reutilise sur 5 services distincts ET etait
aussi le mot de passe du vault Ansible lui-meme (~/.ansible/nova_vault_pass).

L'audit P0 a etendu le perimetre a 6 fichiers supplementaires contenant les
memes patterns dans l'historique des 2 repos GitHub :

| Repo | Fichier | Occurrences (HEAD + historique) |
|---|---|---|
| ansible | `inventory/group_vars/all/vault.yml` | 7 Nova**** + 1 WG key |
| ansible | `playbooks/create_users.yml` | 1 Nova**** (hardcoded `default_password` pour 92 users AD) |
| ansible | `terraform/environments/lyon/terraform.tfstate.1776775724.backup` | 1 WG key (tracked malgre .gitignore) |
| ansible | `terraform/environments/lyon/terraform.tfvars.example` | 1 WG key |
| proxmox | `inventory/group_vars/all/vault.yml` | 14 (vault chiffre dans HEAD mais historique pre-encryption ouvert) |
| proxmox | `playbooks/create_users.yml` | 1 |
| proxmox | `SESSION_FINAL_REPORT.md` + `STATUS.md` | 3 (docs avec password en clair) |
| proxmox | `terraform/environments/lyon/terraform.tfvars.example` + tfstate.backup | 4 |

Triple violation :
- **NIS2 art.21** -- mesures techniques d'acces et controle
- **RGPD art.32** -- chiffrement et confidentialite des donnees
- **OWASP A02:2021** -- Cryptographic Failures

## Decision

Operation atomique en 6 phases sous CHECKPOINT 1 force-push :

### Phase 0 -- Audit complet
Scan recursive des 2 repos pour identifier 9 fichiers + ~30 occurrences en
historique git. Documentation tabulee des cibles. Verification que
`nova-iac-secrets/` est hors-git (siblings repository, no `.git`).

### Phase 1 -- Generation de 9 nouveaux secrets
- 7 service passwords via `openssl rand -base64 24 | tr -d /+= | head -c 24`
- 1 IPsec PSK via `openssl rand -base64 32 | tr -d /+= | head -c 32`
- 1 nouveau vault password Ansible (different des secrets services)
- WireGuard server keypair generee in-place sur vpn-gw01 via `wg genkey`
- Stockage : `nova-iac-secrets/rotation-2026-05-18.txt` mode 600

### Phase 2 -- Rotation services runtime (ordre critique)

Snapshots `pre-vault-rotation-2026-05-18` sur 8 VMs avant rotation :
dc01, fs01, db01, app01, backup01, fw-ext-lyon01, fw-ext-mrs01, vpn-gw01.

| Ordre | Service | Action | Test |
|---|---|---|---|
| 2.1 | MariaDB | ALTER USER root/backup_nova/backup_user/nova_portail | curl /api/tarifs == 30 lignes |
| 2.2 | Samba / Krb5 | samba-tool user setpassword Administrator + admin-t0 | smbclient -U Administrator -L //127.0.0.1 OK |
| 2.3 | Sudo (debian) | chpasswd sur 10 VMs (via SSH key + sudo+old pwd) | sudo whoami == root avec nouveau pwd |
| 2.4 | IPsec PSK | API OPNsense setItem + reconfigure (LYON+MRS simultane) | ping inter-sites 0% loss |
| 2.5 | WireGuard | wg genkey sur vpn-gw01 + sed wg0.conf + restart | wg show active, peers declares |

Passwords passes via stdin (`<<<"$VAR"`) ou heredoc -- jamais en argv pour
eviter exposition via `ps`/`history`.

### Phase 3 -- Re-encryption vault.yml
- Backup `~/.ansible/nova_vault_pass.OLD-2026-05-18-ROTATED` (old) et
  `.PLAINTEXT-BACKUP-2026-05-18` / `.OLDENC-BACKUP-2026-05-18` (vault.yml)
- Nouveau vault.yml plaintext en /tmp avec 9 secrets + portail_db_password
  + portail_flask_secret (1 nouveau Flask secret)
- `ansible-vault encrypt --vault-password-file ~/.ansible/nova_vault_pass.NEW`
  sur les **2 repos** (synchronisation des secrets)
- Activation du nouveau pass file en remplacement de l'ancien
- Verification : `head -1 vault.yml` == `$ANSIBLE_VAULT;1.1;AES256` et
  `ansible-vault view ...` decrypte 11 variables.

### Phase 4 -- Nettoyage historique git
- Bundle backup pre-filter : `/tmp/nova-vault-fix-2026-05-18/nova-{ansible,proxmox}-pre-filter.bundle` (~12 MB chacun)
- Edition working tree : create_users.yml utilise `{{ vault_default_user_password }}`,
  docs MD subs Nova**** -> [REDACTED], terraform.tfstate.backup `git rm --cached`
- Commit "chore(security): re-encrypt vault.yml and rotate all secrets" dans
  les 2 repos
- `git filter-repo --force --replace-text /tmp/nova-vault-fix-2026-05-18/replacements.txt`
  - Substitutions appliquees a TOUS les fichiers de TOUS les commits :
    `Nova****` -> `[REDACTED-OLD-PASSWORD]` ;
    cle WG -> `[REDACTED-OLD-WG-PRIVKEY]`
  - Ansible : 52 commits reecrits en 1.37s
  - Proxmox : 136 commits reecrits en 0.21s
- Re-add origin remote (filter-repo le supprime par defaut)
- **CHECKPOINT 1** -- Pause obligatoire : afficher diff/log/grep, demander
  confirmation utilisateur AVANT le force push.
- Faux positif lors du checkpoint : `git log --all -p | grep -c` incluait
  `refs/remotes/origin/main` (encore l'ancien historique GitHub) -- diagnostic
  per-ref confirme `git log main -p | grep -c == 0`. Apres force push +
  re-fetch, le compteur `--all` retombe a 0.
- `git push --force-with-lease origin main` sur les 2 repos.

### Phase 5 -- Validation post-rotation
10/10 PASS sur les checks fonctionnels (cf. section Verification).

### Phase 6 -- Documentation
ADR-0026 (ce document) + mise a jour INFRA-FULL-TEST-2026-05-18.md (FAIL 10.02
-> PASS) + ajout patterns .gitignore preventifs sur les 2 repos.

## Verification (Phase 5 -- 10/10 PASS)

| # | Test | Resultat |
|---|---|---|
| V1  | `git log --all -p \| grep -cE 'Nova****\|kHr1****'` ansible+proxmox | **0 + 0** |
| V2  | Portail HTTP GET / + API tarifs (DB connection avec nouveau pwd) | 200 + 30 tarifs |
| V3  | Site public Cloudflare HTTPS + cf-ray | HTTP/2 200 + cf-ray 9fdbb94e-CDG |
| V4  | IPsec P1 connected (Lyon + MRS) apres rotation PSK | 1 + 1 |
| V5  | Ping inter-sites data plane (bastion -> 192.168.40.1) | 0% loss, 0.557 ms |
| V6  | Wazuh agents Active | 7/7 |
| V7  | Authelia state + Samba smbclient Administrator new pwd | 200 + sharename OK |
| V8  | mysql -h db01 -u nova_portail (new pwd) SELECT COUNT(*) tarifs | 30 |
| V9  | sudo -k + sudo -S new pwd whoami | root |
| V10 | wg show vpn-gw01 (interface up, peers declares, handshake pending) | active + 2 peers |

## Consequences

### Positives
- **0 secret en clair** dans les 2 repos GitHub (force-push reussi, fetch
  confirme grep count = 0 universellement).
- **Rotation complete** : 8 secrets services + 1 IPsec PSK + 1 nouveau vault
  password Ansible. Aucun reuse "Nova****" sur differents services.
- **Pipeline RGPD/NIS2 enforce** : encryption AES256 du vault, MFA TOTP +
  default_policy deny inchanges, audit_consultations toujours actif.
- **Snapshots de rollback** disponibles sur 8 VMs (jusqu'a la prochaine purge).
- **Bundles backup** archive `/tmp/nova-vault-fix-2026-05-18/` permettent un
  restore complet en cas de probleme post-push (commande
  `git bundle unbundle <file>` puis reset).

### Negatives
- **Historique git completement reecrit** sur main des 2 repos. Tout collaborateur
  ayant un clone local doit `git fetch && git reset --hard origin/main` (perte
  des branches locales basees sur l'ancien historique). N/A actuellement car
  Matthieu est seul contributeur.
- **WireGuard road-warriors deconnectes** -- les 2 clients (matthieu-mac,
  vps-hetzner-test) ont l'ancienne pubkey du serveur dans leur config. Nouvelle
  pubkey serveur (a redistribuer manuellement) :
  `9ExSPQD6PWsFChdoX3SDEkY8ZppRnvXmH78SKM0vvy4=`
- **Anciens commits SHAs orphelins** sur GitHub jusqu'a la prochaine gc (30j
  par defaut chez GitHub). En theorie accessibles via reflog interne GitHub
  pendant ~30j -- ne PAS considerer la rotation comme "effective immediate"
  vis-a-vis d'un attaquant qui aurait clone le repo avant la purge.
- **Decalage temporaire** : vault.yml HEAD (chiffre nouveau pwd) vs vault.yml
  origin GitHub (anciennement chiffre / plaintext) corrige par force push.
  Hooks pre-commit non installes a ce jour pour empecher la recidive.

### Neutres
- Le mot de passe vault Ansible (`~/.ansible/nova_vault_pass`) est passe de
  "Nova****" (10 bytes inc. newline) a 32 chars random. Stockage local mode
  600. Ancien sauve `~/.ansible/nova_vault_pass.OLD-2026-05-18-ROTATED`.
- Le mot de passe sudo Ansible (`vault_ansible_sudo_password`) etait declare
  dans vault.yml mais N'ETAIT REFERENCE NULLE PART dans les playbooks (sudoers
  utilise `ansible ALL=(ALL) NOPASSWD` via user "ansible", pas "debian").
  Rotation effectuee par mesure d'hygiene mais sans impact ops.
- terraform.tfstate.backup supprime du repo Ansible (etait tracked malgre
  .gitignore -- commit anterieur a l'ajout du pattern). Le state actif
  (.tfstate) reste gitignore comme avant.

## Dettes ouvertes apres remediation

### DETTE-009 -- Rotation passwords des 92 users AD (PARTIELLEMENT RESOLUE)
- **Option B chirurgicale traitee le 2026-05-18 via T-IAM-PLAYBOOKS-2026-05-18** :
  4 demo users (fabien.bonnet, alexandre.gautier, lucie.lefevre, matthieu.gerard)
  rotates vers `vault_default_user_password`. Validation
  `wbinfo --authenticate` : ancien pwd Nova**** FAIL, nouveau pwd PASS.
- 3 playbooks IAM industrialises crees pour la suite : user_create.yml,
  user_delete.yml, user_grant_privilege.yml + audit log
  `/var/log/nova-iam/audit.log`. Cf. [ADR-0027](ADR-0027-iam-industrialise-ansible.md).
- **DETTE-009-bis** (P1) -- les 88 users restants gardent toujours leur password
  initial "Nova****". Traiter via playbook `users_rotate_bulk.yml` iterant sur
  samba-tool user list (excluant 5 service accounts + 4 demo deja faits).

### DETTE-010 -- WireGuard road-warriors a reconfigurer
Distribuer la nouvelle pubkey serveur `9ExSPQD6PWsFChdoX3SDEkY8ZppRnvXmH78SKM0vvy4=`
aux 2 clients WG. Mettre a jour leur fichier conf (champ `PublicKey` sous `[Peer]`).
Verifier handshake actif via `wg show` cote serveur. Priorite : P1.

### DETTE-011 -- Pre-commit hook anti-vault-plaintext
Cf. section "Recommendations" infra. Priorite : P2.

### DETTE-008 (rappel, inchange)
Placeholders "CHANGE_ME" dans vault.yml restent : vault_b2_*, vault_hcv_*,
vault_teleport_join_token. A renseigner quand les services correspondants
seront deployes (Backblaze B2, HashiCorp Vault, Teleport).

## Lessons learned

1. **Detection automatique** -- un scan recursif `grep -rln "$BAD_STRING"` sur
   les repos devrait etre un check CI permanent. Le seul rappel manuel via
   audit annuel n'a pas suffi (vault.yml plaintext est passe en commit `0866095`
   et a perdure 47 commits sans alerte).
2. **Defaut "ansible-vault encrypt" hors workflow** -- la commande
   `ansible-vault create` aurait empeche le bug initial. Une fois cree
   plaintext, le pipeline humain ne l'a jamais re-encrypte.
3. **Reuse de password** -- "Nova****" sur 5 services + le vault = single
   point of compromise. Un secret par usage est une regle de base.
4. **Decoupler discovery vs reach** -- T-INFRA-FULL-TEST a trouve la fuite,
   T-VAULT-PLAINTEXT-FIX l'a remediee. Process audit -> fix decouple permet
   d'ouvrir la dette publique (jury), pas seulement en silence.
5. **Filter-repo "--all" et refs remotes** -- le checkpoint a ete declenche
   par un faux positif (`git log --all -p | grep -c == 11`). La cause etait
   le tracking ref `refs/remotes/origin/main` non touche par filter-repo.
   Le diagnostic correct est per-ref : `git log refs/heads/main -p | grep -c`.
   A inclure dans la doc filter-repo interne.

## Recommendations (a implementer en T-FOLLOW-UP)

### Pre-commit hook anti-vault-plaintext

Installer le framework [pre-commit](https://pre-commit.com) et ajouter dans
`.pre-commit-config.yaml` des 2 repos :

```yaml
repos:
  - repo: local
    hooks:
      - id: check-vault-encrypted
        name: Check Ansible vault.yml is encrypted
        entry: bash -c 'head -1 inventory/group_vars/all/vault.yml | grep -q "^\$ANSIBLE_VAULT" || { echo "vault.yml is NOT encrypted -- aborting"; exit 1; }'
        language: system
        pass_filenames: false
        files: ^inventory/group_vars/all/vault\.yml$

      - id: forbid-known-secrets
        name: Forbid known-leaked patterns in staged files
        entry: bash -c '! git diff --cached | grep -E "Nova****|kHr1****"'
        language: system
        pass_filenames: false
```

Activation : `pre-commit install` une fois clone. Tournera avant chaque commit.

### CI scan (GitHub Actions)

Ajouter un workflow `.github/workflows/secrets-scan.yml` qui execute
[gitleaks](https://github.com/gitleaks/gitleaks) ou [trufflehog](https://github.com/trufflesecurity/trufflehog)
sur chaque push. Bloque le merge si secret detecte.

### Rotation policy

Documenter dans `docs/runbook-rotation-secrets.md` :
- Frequence cible : 90j pour passwords services, 365j pour cles asymetriques
- Procedure : reprendre Phase 2 de cet ADR comme template
- Test post-rotation : reproduire Phase 5 (10 checks)

## References

- Detection : T-INFRA-FULL-TEST-2026-05-18 (cf. `docs/INFRA-FULL-TEST-2026-05-18.md`
  section 10.02 -- statut PASS apres remediation, voir section "Mise a jour
  post-remediation" du meme document)
- ADR-0011 (Ansible IaC) -- contexte du vault Ansible
- ADR-0019 (Authelia MFA) -- politique deny + two_factor inchangee
- ADR-0009 (Backup 3-2-1-1-0) -- rotation des secrets repos Borg non
  concernee (cle de chiffrement Borg distincte du vault Ansible)
