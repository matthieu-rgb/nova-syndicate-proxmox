# ADR-0033 : AWX RBAC -- 4 Teams + mapping LDAP des groupes AD (Phase 8)

- Statut : Accepte. 4 groupes AD + 4 Teams AWX + `AUTH_LDAP_TEAM_MAP` + permissions
  DEPLOYES et valides E2E (2026-05-24, T-AFK-MEGA). Workflow "Onboarding-Employee"
  (bonus) : reporte (non bloquant).
- Date : 2026-05-24
- Auteur : matthieu-rgb
- Tickets : T-AWX-RBAC (dette fille de T-AWX-DEPLOY / ADR-0031), Phase 8
- Lien : [`ADR-0031`](ADR-0031-awx-operator-k3s-iam-automation.md),
  [`ADR-0027`](ADR-0027-iam-industrialise-ansible.md),
  [`docs/access-matrix.md`](../access-matrix.md)

## Contexte

ADR-0031 a deploye AWX (k3s, awx01 = `192.168.60.2`) qui industrialise l'IAM AD via
7 Job Templates `iam-*` (create/delete/enable/grant/revoke/reset-password/rotate-bulk).
L'auth est deja branchee sur l'AD Samba en LDAPS (`AUTH_LDAP_SERVER_URI =
ldaps://192.168.20.10:636`, bind `svc-awx-ldap`, `MemberDNGroupType`) -- les users AD
se connectent a AWX. **Mais tous les operateurs avaient le meme niveau d'acces** : aucune
separation des roles. La directive **NIS2 art.21** (mesures de gestion des risques,
**separation of duties**) impose de cloisonner qui peut creer/activer un compte, qui peut
tout faire sur l'IAM, et qui ne peut que lire (audit). C'est la dette **T-AWX-RBAC**.

Contrainte de modelisation : `AUTH_LDAP_TEAM_MAP` n'est **pas** gere par le CR AWX
(`spec.extra_settings` ne contient que `CSRF_TRUSTED_ORIGINS`) -> il est stocke en base
et modifiable via l'**API REST** (`PATCH /api/v2/settings/ldap/`), sans `kubectl edit`
ni reconciliation de l'operateur (pas de downtime). Les groupes AD vivent dans
`CN=Users` (pas d'`OU=Groups` dans cet annuaire) -> les DN du TEAM_MAP utilisent le DN
reel `CN=<groupe>,CN=Users,DC=nova-syndicate,DC=local`.

## Options considerees

1. **Permissions directes user-par-user dans AWX** -- rejete : non scalable, derive
   immediate, aucune source de verite (l'appartenance doit venir de l'AD).
2. **Organization map (`AUTH_LDAP_ORGANIZATION_MAP`) seul** -- insuffisant : gere
   l'appartenance a l'org mais pas le cloisonnement fin par fonction.
3. **Teams AWX + `AUTH_LDAP_TEAM_MAP` (groupes AD -> Teams) + roles par Team** --
   **RETENU**. L'AD reste la source de verite (separation of duties pilotee par les
   groupes), AWX applique le mapping a chaque login LDAP, les permissions sont portees
   par les Teams (pas par les users).
4. Edition du `AUTH_LDAP_TEAM_MAP` via `kubectl edit awx` (extra_settings) -- ecarte au
   profit du `PATCH` API (LDAP non gere par le CR ici -> l'API est la voie propre, sans
   downtime).

## Decision

4 groupes AD (CN=Users), 4 Teams AWX (org "Nova Syndicate"), mapping et permissions :

| Groupe AD (DN `...,CN=Users,DC=nova-syndicate,DC=local`) | Team AWX | Permissions |
|---|---|---|
| `CN=IT-Officers-Lyon` | **IT-Officers** | Execute : `iam-user-create`, `iam-user-enable` |
| `CN=IT-Officers-MRS`  | **IT-Officers-MRS** | Execute : `iam-user-create`, `iam-user-enable` |
| `CN=IT-Managers`      | **IT-Managers** | Execute : **tous** les `iam-*` + Admin inventaire `Nova-Lyon` |
| `CN=IT-Auditors`      | **Auditors** | **Auditor** de l'org (lecture seule : templates, jobs, inventaires) |

- `AUTH_LDAP_TEAM_MAP` : `{<Team>: {organization: "Nova Syndicate", users: "<group DN>",
  remove: true}}` (`remove: true` = un user retire du groupe AD perd la Team au login suivant).
- Inventaire `Nova-MRS` inexistant -> IT-Officers-MRS scope sur `Nova-Lyon` (a affiner
  quand l'inventaire MRS sera cree -- cf T-AWX-VAULT-INVENTORY).
- Le Workflow "Onboarding-Employee" (`iam-user-create` -> `iam-user-grant-privilege`)
  est reporte (bonus non bloquant).

### Validation E2E (2026-05-24)

User AD jetable `rbac.test` (dual-role `IT-Officers-Lyon` + `IT-Auditors`), login AWX via
API (`GET /api/v2/me/` en LDAP) -> **Teams = {IT-Officers, Auditors}**. Job templates
visibles : `iam-user-create` + `iam-user-enable` en **EXECUTE**, les 5 autres `iam-*` en
**read-only** (via Auditor). Conforme. User jetable supprime (AD + AWX) apres test.

## Risques & Mitigations

- **Escalade via l'IAM** (un Officer pourrait se grant Domain Admins) : mitige -- les
  Officers n'ont **que** create/enable, pas `iam-user-grant-privilege`. Le filtre
  `svc-*` du `AUTH_LDAP_USER_SEARCH` reste actif (les comptes de service ne se
  connectent pas a AWX) et l'**ACE DENY Tier0** sur les groupes privilegies (cf modele
  Tier0/1/2, OU=Tier0_Admins) reste en place : un job IAM ne peut pas toucher Tier0.
- **Derive du mapping** : `remove: true` reconcilie l'appartenance Team a chaque login.
  La source de verite reste l'AD (groupes), pas AWX.
- **TEAM_MAP non versionne** (stocke en base AWX, pas dans le repo) : a sauvegarder /
  modeliser (Configuration-as-Code AWX -- cf T-AWX-TEMPLATES-IAC).
- **Pas de downtime** : `PATCH` API (LDAP hors CR) -> aucune reconciliation operateur.

## Consequences

- Separation of duties NIS2 art.21 effective : Officers (provisioning de base),
  Managers (IAM complet + admin inventaire), Auditors (lecture seule).
- L'AD devient le point de controle unique des roles AWX (un mouvement RH = un
  changement de groupe AD).
- Reste a faire : Workflow Onboarding, inventaire `Nova-MRS`, et sauvegarde IaC du
  TEAM_MAP / Teams (T-AWX-TEMPLATES-IAC).
