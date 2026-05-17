# ADR-0023 : Architecture du portail metier Nova Syndicate (Flask + Authelia + MariaDB)

## Status
Accepted

## Date
2026-05-17

## Contexte

Nova Syndicate a besoin d'un portail metier interne pour consulter le catalogue tarifaire (filieres medical / aerospace / defense / standard) et la liste des clients. L'application doit satisfaire les contraintes suivantes :

- **Authentification AD** : exclusivement avec les comptes du domaine `nova-syndicate.local` (Samba AD sur DC01).
- **MFA obligatoire** : NIS2 art. 21.b impose le second facteur sur les acces aux ressources de production.
- **Audit trail** : NIS2 art. 21 + RGPD impose la tracabilite des consultations.
- **Reutiliser** la stack deja en place (nginx, Authelia v4.39, MariaDB) plutot que d'introduire de nouvelles dependances.
- **Separation** stricte entre site public vitrine (anonyme) et portail metier (authentifie + MFA).

## Decision

Deploiement de l'application sur **APP01 (192.168.20.13)** sous le vhost `portail.nova-syndicate.local`, derriere le memes reverse proxy nginx que les autres services internes.

### Stack retenue

| Couche | Technologie | Justification |
|---|---|---|
| Reverse proxy + TLS | nginx (deja installe APP01) | Reutilise ADR-0019 forward auth |
| Authentification | Authelia v4.39.19 + AD LDAP DC01 | Reutilise ADR-0019 |
| MFA | TOTP (Authelia) | Reutilise enrollement existant ([[user_role.md]]) |
| Backend HTTP | Flask 3.0 + gunicorn 4 workers | Empreinte minimale, lecture seule a ce stade |
| Acces DB | mysql-connector-python (pool de 5) | Stable, supportee, pool natif |
| Base de donnees | MariaDB sur DB01 (deja existante) | Pas de nouvelle VM, ADR-0007 reaffirme |
| Templates | Jinja2 (HTML pre-stylises) | Cohesion visuelle avec le site public |
| Audit | Table `audit_consultations` dediee | Recherche rapide, conservation NIS2 |

### Flux d'authentification

```
Navigateur -> nginx (443 portail.nova-syndicate.local)
                 |
                 +-- subrequest /auth/verify -> Authelia (127.0.0.1:9091)
                 |       |
                 |       +-- LDAPS DC01 (636) + TOTP check
                 |       +-- Cookie domaine .nova-syndicate.local
                 |
                 +-- OK -> proxy_pass 127.0.0.1:5000 (gunicorn/Flask)
                 |          Headers : Remote-User, Remote-Name,
                 |                    Remote-Email, Remote-Groups
                 |
                 +-- KO -> 302 vers https://auth.nova-syndicate.local/?rd=...
```

### Modele de donnees

5 tables sous le schema `nova_portail` :

| Table | Cardinalite | Role |
|---|---|---|
| `tarifs` | 30 references (catalogue actuel) | Catalogue produits |
| `clients` | 15 entreprises | Portefeuille commercial |
| `devis` | 0 (reserve T-PORTAIL-CRUD) | Devis envoyes |
| `devis_lignes` | FK -> devis + tarifs | Decomposition devis |
| `audit_consultations` | grandit avec usage | Trail NIS2 art. 21 |

### Compte de service DB

Utilisateur MariaDB dedie `nova_portail@192.168.20.13` avec privileges minimaux : `SELECT, INSERT, UPDATE` sur `nova_portail.*`. Aucun DROP / CREATE / DELETE. Le password est stocke dans `inventory/group_vars/all/vault.yml` (vault-encrypted).

### Controles d'acces applicatifs

Au-dela d'Authelia MFA, Flask applique un controle base sur les groupes AD :

| Route | Acces |
|---|---|
| `/` (dashboard) | Tout utilisateur du domaine |
| `/tarifs`, `/tarifs/<id>` | Tout utilisateur du domaine |
| `/api/tarifs` | Tout utilisateur du domaine (JSON read-only) |
| `/profil` | Tout utilisateur (donnees personnelles uniquement) |
| `/clients` | Membres de `Domain Admins`, `Administrators`, `Logistique Admins` |
| `/historique` | Idem `/clients` (audit trail) |

Les acces refuses retournent 403 avec page d'erreur.

### Audit trail

Chaque action authentifiee insere une ligne dans `audit_consultations` :

- `user_ad` : Remote-User (compte AD)
- `user_groups` : Remote-Groups (CSV)
- `action` : VIEW_DASHBOARD / LIST_TARIFS / VIEW_TARIF / LIST_CLIENTS / VIEW_AUDIT / VIEW_PROFILE / API_TARIFS
- `resource_type`, `resource_id` : si applicable
- `ip_source` : X-Forwarded-For (IP reelle)
- `user_agent`, `timestamp`

Index sur `(user_ad)` et `(timestamp)` pour requete dashboard et historique.

## Alternatives envisagees

### Alt 1 -- Django plutot que Flask
Rejete : surdimensionne pour un MVP read-only, ORM inutilise au stade actuel, migrations Django ajoutent une couche de complexite face a un schema deja gere par DBA.

### Alt 2 -- Auth applicative LDAP directe (sans Authelia)
Rejete : duplique la logique MFA, oblige Flask a manipuler les cookies de session, perd la centralisation SSO (autres services nginx-forward-auth-isent deja sur Authelia).

### Alt 3 -- Nouveau host metier dedie (VM portail01)
Rejete a ce stade : empreinte additionnelle (VM + IP + cert + monitoring) non justifiee pour le MVP. Si la charge ou le besoin d'isolation evolue, T-PORTAIL-VM-DEDIEE pourra reconsiderer.

### Alt 4 -- PostgreSQL plutot que MariaDB
Rejete : MariaDB DB01 deja en production, pas de gain fonctionnel justifie pour un schema read-only de cette taille.

## Consequences

### Positives
- Reutilise ~100% de la stack existante (nginx, Authelia, MariaDB).
- Le MFA est garanti au niveau reverse proxy : Flask ne peut etre atteint sans cookie Authelia valide.
- Audit trail centralise et requetable en SQL.
- Compte DB cantonne aux operations applicatives (pas de privileges admin).
- Le portail et le site public vivent sur le meme host avec des vhost distincts -- TLS wildcard mkcert mutualise.

### Negatives / dettes
- T-PORTAIL-CRUD-ADMIN : ajout des operations d'ecriture (creer/modifier tarifs et clients) avec controle d'acces fin.
- T-PORTAIL-API-AUTH : si l'API JSON doit etre exposee a des integrations externes, basculer sur tokens (PAT ou OIDC) plutot que cookies Authelia.
- T-PORTAIL-EXPORT-PDF : generation devis PDF (WeasyPrint ou ReportLab) -- pas dans le MVP.
- T-PORTAIL-BACKUP-AUDIT : strategie de retention / archivage de `audit_consultations` (croissance lineaire).

### Risques
- Si Authelia tombe, le portail devient inaccessible. Le healthcheck `/health` reste exempte (pour Prometheus / probe externe) mais ne contourne pas l'auth pour le reste.
- gunicorn 4 workers sur APP01 (4 GB RAM) : peu impactant tant que la charge reste interne. A surveiller au-dela de 50 utilisateurs concurrents.

## References

- ADR-0019 : Authelia comme portail MFA pour les services web internes
- ADR-0018 : MFA TOTP bastion (politique MFA globale)
- runbook/nova-portail.md : procedures operationnelles
- runbook/nova-website.md : site public vitrine
- db/nova-portail-schema.sql : schema executable

## Validation operationnelle (2026-05-17)

- `scripts/test-nova-portail.sh` : 20 OK / 0 KO
- Service `nova-portail.service` : active (gunicorn 4 workers, 127.0.0.1:5000)
- Compte AD `fabien.bonnet` enrolle TOTP -- test bout-en-bout valide via Authelia
- Wildcard cert mkcert : valide jusqu'a 2028-08-01
