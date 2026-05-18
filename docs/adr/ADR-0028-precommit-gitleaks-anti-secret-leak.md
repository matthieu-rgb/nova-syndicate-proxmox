# ADR-0028 : Pre-commit hooks + CI secret scanning anti-vault-plaintext

- Statut : Accepte
- Date : 2026-05-18
- Auteur : matthieu-rgb
- Ticket : T-IAM-PLAYBOOKS-2026-05-18 (DETTE-011 follow-up)
- Lien : remediation defensive de [ADR-0026](ADR-0026-vault-plaintext-fix-2026-05-18.md)

## Contexte

T-VAULT-PLAINTEXT-FIX (cf. ADR-0026) a corrige a posteriori la fuite de
`vault.yml` en clair dans 3 commits + 6 fichiers historiques sur les 2 repos
GitHub. La rotation + filter-repo + force-push ont neutralise l'incident,
mais rien n'empechait techniquement la recidive : un futur `git add
inventory/group_vars/all/vault.yml` non chiffre + `git commit + git push`
serait passe sans alerte.

Le risque n'est pas hypothetique :
- Un nouveau contributeur (ou Claude/Cursor agent) clone le repo, edit le
  vault sans le chiffrer (oubli de `ansible-vault encrypt`), commit, push.
- Un script de rotation foire et regenere vault.yml plaintext.
- Un merge entre branches retablit accidentellement une vieille version.

Besoin : **defense en profondeur**.
- Filet 1 (rapide, local) : pre-commit hooks sur le poste dev. Bloque
  AVANT que le commit existe.
- Filet 2 (lent, fiable, server-side) : GitHub Action gitleaks. Bloque
  les PR meme si l'attaquant contourne le filet 1 (clone sans
  `pre-commit install`).

## Decision

### Filet 1 -- pre-commit local

Framework [pre-commit](https://pre-commit.com) installe via `brew install
pre-commit`. Config dans `.pre-commit-config.yaml` a la racine de chaque repo
(ansible + proxmox). Active par developpeur via `pre-commit install`.

Hooks configures :

| Hook | Source | Role |
|---|---|---|
| `ansible-vault-encrypted` | local script `scripts/check-vault-encrypted.sh` | Refuse tout fichier `vault\.yml$` dont l'entete != `$ANSIBLE_VAULT;1.1` |
| `forbid-known-leaked-strings` | local script `scripts/check-no-leaked-strings.sh` | Refuse les patterns Nova**** et la cle WG historique dans tout diff staged |
| `detect-secrets` | Yelp/detect-secrets v1.5.0 | Scan generique (entropy + ruleset) avec baseline `.secrets.baseline` |
| `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-merge-conflict`, `detect-private-key` | pre-commit-hooks v5.0.0 | Hygiene bonus + double check cle privee |

Test fonctionnel realise (test fail volontaire) :
- `echo "test: notencrypted" > inventory/group_vars/all/test-fake-vault.yml ; git add ; git commit` -> BLOQUE avec message explicite citant la commande de fix.
- `echo "old: Nova2026!" > test.txt ; git add ; git commit` -> BLOQUE avec reference T-VAULT-PLAINTEXT-FIX.

### Filet 2 -- GitHub Action gitleaks (server-side, OBLIGATOIRE)

Workflow `.github/workflows/secret-scan.yml` sur les 2 repos :
- Trigger : `push` (main) + `pull_request` (main)
- Action : `gitleaks/gitleaks-action@v2`
- Fetch-depth : 0 (scanne TOUT l'historique du push, pas juste le HEAD diff)
- Custom config : `.gitleaks.toml` a la racine avec allowlist
  (`.PLAINTEXT-BACKUP-*`, `.secrets.baseline`, redacted refs `Nova****`)

C'est le filet **non-contournable** : meme si le developpeur n'a pas
`pre-commit install` localement, GitHub Action s'execute sur chaque push.
PR rejetee (status check) si secret detecte.

## Importance relative

| Filet | Cout setup | Force | Faiblesse | Conclusion |
|---|---|---|---|---|
| Pre-commit local | OPTIONNEL par dev | Bloque AVANT push (cycle court) | Contournable (`--no-verify`, clone sans install) | Confort dev |
| GH Action gitleaks | Active automatiquement | Bloque le merge serveur-side | Plus lent (cycle CI), reactive a chaque push | **OBLIGATOIRE -- filet final** |

**Position : pre-commit local est un confort dev a recommander mais pas a imposer.
GitHub Action gitleaks est la ligne defensive non-negociable.**

## Verification (test realise 2026-05-18)

| # | Test | Resultat |
|---|---|---|
| T1 | `pre-commit install` ansible+proxmox | OK -- hook ecrit dans .git/hooks/pre-commit |
| T2 | `pre-commit run --all-files` (1er passage) | Auto-fix trailing whitespace + EOF sur ~20 fichiers existants (hygiene) |
| T3 | `pre-commit run --all-files` (2eme passage) | Tous les hooks PASS |
| T4 | Commit volontaire fake vault plaintext | BLOQUE par `ansible-vault-encrypted` |
| T5 | Commit volontaire avec Nova2026! | BLOQUE par `forbid-known-leaked-strings` |
| T6 | Git log apres T4/T5 | Inchange (commits non crees) |

GitHub Action verification effectuee post-push (status check workflow_run sur
le commit T-DETTE-011).

## Conformite NIS2 / RGPD

- **NIS2 art.21 (mesures techniques)** -- defense automatisee contre la
  recidive de la non-conformite identifiee en ADR-0026.
- **RGPD art.32 (mesures appropriees)** -- protection systematique du
  chiffrement des secrets (vault.yml AES256).
- **ISO 27001 A.12.6.2 (Restrictions on software installation)** -- les
  hooks sont code source, reviewable et versionnes (pas un binary opaque).

## Consequences

### Positives
- Re-leak vault.yml plaintext **techniquement impossible** sans `--no-verify`
  + GitHub Action bloque le push meme dans ce cas.
- Detection generique via detect-secrets : capture tout pattern d'entropie
  haute (tokens, API keys, etc.) au-dela des patterns connus.
- Commit-msg hook anti-Claude/Anthropic preserve (independant de
  pre-commit-config.yaml).
- Hygiene bonus : tous les fichiers du repo passent les checks
  trailing-whitespace + EOF fixer.

### Negatives
- `pre-commit run --all-files` initial a auto-modifie ~20 fichiers existants
  (whitespace/EOF) -- les patches sont triviaux mais polluent l'historique
  d'un commit "fix" inclu dans le commit feature.
- detect-secrets necessite une baseline `.secrets.baseline` versionnee.
  Tout nouveau finding doit etre review + add au baseline ou rotated.
- Si pas de connectivite internet, `pre-commit run` echoue au premier run
  (clone des hooks externes). Mitigation : `pre-commit install-hooks`
  une fois en environnement avec internet, puis cache local.
- gitleaks-action @v2 est gratuit pour les orgas personnelles mais
  GITLEAKS_LICENSE requis pour orgas entreprise. Migrer vers
  `gitleaks/gitleaks` CLI dans un job custom si futur multi-tenant.

### Neutres
- `~/.cache/pre-commit/` peut grossir (envs Python clonees). Cleanup
  manuel via `pre-commit gc` annuellement.
- Le hook `check-yaml` est exclu pour `vault.yml` (parsing impossible
  une fois chiffre) et `*.j2` (templates Jinja2 ne sont pas du YAML pur).

## Dettes ouvertes apres ADR-0028

### DETTE-015 -- detect-secrets baseline (P3)
Baseline `.secrets.baseline` initialisee vide. Devrait etre re-generee
periodiquement (`detect-secrets scan --update .secrets.baseline`) et
auditee a chaque ajout pour ne pas masquer un vrai leak.
Priorite : P3 (audit trimestriel).

### DETTE-016 -- yamllint (P3)
Ajouter le hook `yamllint` (deja installe localement) pour qualite
des YAML. Necessite ecriture d'un `.yamllint` minimal accepte par
l'existant. Priorite : P3.

### DETTE-017 -- ruleset gitleaks custom (P3)
Etendre `.gitleaks.toml` avec des regles pour les patterns specifiques
Nova Syndicate (clefs API OPNsense, formats WireGuard, IPsec PSK
formats). Defaut gitleaks couvre AWS/GCP/Azure/etc., pas notre stack.
Priorite : P3.

## References

- ADR-0026 (vault plaintext fix) -- contexte declenchant
- pre-commit framework : <https://pre-commit.com>
- gitleaks : <https://github.com/gitleaks/gitleaks>
- detect-secrets (Yelp) : <https://github.com/Yelp/detect-secrets>
