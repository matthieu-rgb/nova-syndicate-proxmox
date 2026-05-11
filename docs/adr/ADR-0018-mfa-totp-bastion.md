# ADR-0018 : MFA TOTP sur bastion01 (SSH + sudo)

## Status
Accepted

## Date
2026-05-11

## Contexte

Bastion01 (192.168.15.2) est le point d'entree administratif unique de l'infrastructure Nova Syndicate. Toute connexion SSH vers les VMs internes passe par ce bastion (ProxyCommand ou ProxyJump). Un compromis du bastion equivaut a un compromis total de l'infrastructure.

NIS2 Article 21.b impose le recours a l'authentification multifacteur pour l'acces aux systemes essentiels. La cle SSH seule constitue un facteur unique (facteur "possession") : le vol de la cle privee suffit a compromettre l'acces.

Deux options evaluees pour le perimetre MFA :

- **Option A (SSH uniquement)** : MFA sur le login SSH. Sudo conserve le mot de passe Unix seul.
- **Option B (SSH + sudo)** : MFA sur le login SSH ET sur chaque elevation sudo. Couverture NIS2 maximale.

Option B retenue : un administrateur authentifie par SSH (2FA) qui execute sudo sans second facteur peut mener des actions privilegiees avec seulement son mot de passe Unix. Option B cloture ce vecteur.

## Decision

Mise en place de **libpam-google-authenticator** (TOTP RFC 6238) sur bastion01, couvrant SSH et sudo.

**Facteurs d'authentification resultants :**

| Action | Facteur 1 | Facteur 2 |
|---|---|---|
| SSH login | Cle publique SSH (possession) | TOTP 6 chiffres (device) |
| sudo | Mot de passe Unix (connaissance) | TOTP 6 chiffres (device) |

**Parametres TOTP :**
- Algorithme : TOTP (time-based, RFC 6238), fenetre 30s
- Tolerance clock drift : window=3 (+-90s)
- Rate limit : 3 tentatives / 30s
- Replay protection : DISALLOW_REUSE active
- Backup codes : 5 codes a usage unique

**PAM sshd** (`/etc/pam.d/sshd`) :
- `pam_google_authenticator.so nullok` en tete (avant common-auth supprime)
- Pas de `@include common-auth` : le mot de passe Unix n'est pas requis car la cle SSH est le premier facteur
- sshd_config : `AuthenticationMethods publickey,keyboard-interactive`

**PAM sudo** (`/etc/pam.d/sudo`) :
- `pam_google_authenticator.so nullok` avant `@include common-auth`
- sudo = mot de passe Unix + TOTP
- `timestamp_timeout=15` : cache TOTP 15 minutes dans la session (confort)

**`nullok`** : les utilisateurs sans fichier `~/.google_authenticator` peuvent s'authentifier sans TOTP. Permet l'enrollment progressif des admins sans lockout. A supprimer apres enrollment de tous les admins.

**Gestion** : role Ansible `mfa_totp` (tasks install/configure-sshd/configure-sudo, templates pam-sshd.j2/pam-sudo.j2). Enrollment individuel hors-Ansible (interactif).

## Alternatives considerees

### Authelia + LDAP (OIDC/proxy MFA)

**Pour** : MFA centralisee via proxy, interface web, integration LDAP AD, support hardware keys, audit centralise.

**Contre** : complexite de deploiement (Authelia + reverse proxy + certificats TLS + LDAP) disproportionnee pour le perimetre Phase II. Le SSH ne s'integre pas nativement a Authelia sans couche supplementaire (ex : Teleport). Reporte en Phase III.

### YubiKey (hardware FIDO2/OTP)

**Pour** : facteur hardware physique, resistance au phishing superieure au TOTP, support FIDO2 par les navigateurs modernes.

**Contre** : cout materiel (50-80 EUR par cle, minimum 2 par admin pour backup). Dependance hardware : perte de la YubiKey = lockout jusqu'a recuperation. Hors budget et scope d'un POC de formation. Rejete.

### SMS-based MFA (OTP par SMS)

**Pour** : familier, pas d'app a installer.

**Contre** : non conforme NIS2 (SIM swapping documentee comme vecteur d'attaque). ANSSI et ENISA deconseillent le SMS comme facteur MFA pour les systemes critiques. Rejete.

### Duo Security / Okta Verify (cloud MFA)

**Pour** : gestion centralisee, push notifications, audit cloud.

**Contre** : dependance externe cloud US. Pour un systeme critique, externaliser l'authentification vers un fournisseur tiers introduit un SPOF hors de controle (cf. outages Duo 2023). Incompatible avec le principe de souverainete NIS2 art. 21.e. Rejete.

### Teleport (bastion + MFA integree)

**Pour** : ADR-0014 prevoit Teleport pour Phase III. Teleport integre MFA, audit de session, recording, et gestion des certificats SSH courts.

**Contre** : Teleport remplace le bastion (infrastructure change majeure) plutot que de l'augmenter. Non disponible en Phase II. La solution libpam est complementaire et sera remplacee par Teleport en Phase III. Non retenue pour Phase II.

## Consequences

**Positives :**
- NIS2 Art. 21.b satisfait : 2 facteurs pour l'acces SSH et sudo sur le bastion.
- Pas de dependance externe : TOTP local, app standard (Google Authenticator, Authy, Bitwarden).
- Revocation immediate : supprimer `~/.google_authenticator` du compte suffit.
- Backup codes : 5 codes a usage unique en cas de perte du device.

**Negatives et risques :**

- **Lockout risque** : si `~/.google_authenticator` corrompu ou device perdu sans backup codes, l'utilisateur est locke. Mitigation : console Proxmox disponible (acces hors-bande), backup codes stockes hors-ligne, snapshot pre-mfa-totp-2026-05-11.
- **`nullok` temporaire** : pendant la phase d'enrollment, les users sans TOTP peuvent acceder. A durcir (`nullok` -> supprime) apres enrollment de tous les admins.
- **Ansible non automatisable** : Ansible ne peut pas fournir le TOTP keyboard-interactive en mode batch. Workaround : ControlMaster pre-authentifie (voir dette T-ANSIBLE-SERVICE-ACCOUNT). Solution definitive : compte service ansible exempt de TOTP via PAM conditionnel (`pam_succeed_if.so user = ansible`).
- **Clock drift** : si l'horloge du serveur ou du device derive de plus de 90s, les codes sont rejetes. Mitigation : chrony configure sur bastion01 (synchronisation NTP).

## Validation experimentale (2026-05-11)

| Test | Resultat |
|---|---|
| SSH avec cle seule (sans TOTP) | Refuse - "Verification code:" requis |
| SSH avec cle + mauvais TOTP | Refuse - "Permission denied" |
| SSH avec cle + bon TOTP | Succes - shell ouvert |
| sudo avec password seul (sans TOTP) | Refuse - "Verification code:" requis |
| sudo avec password + TOTP | Succes - root |
| sudo dans les 15 min suivantes | Succes sans redemande (cache timestamp_timeout=15) |
| Nouvelle session SSH, sudo | TOTP redemande (cache par session) |

## References

- NIS2 Article 21.b : authentification multifacteur pour acces distants
- RFC 6238 : TOTP - Time-Based One-Time Password Algorithm
- libpam-google-authenticator : https://github.com/google/google-authenticator-libpam
- ANSSI guide MFA (PA-079)
- ADR-0014 : Bastion Teleport MFA (Phase III -- remplacera cette solution)
- Runbook : `docs/runbook-mfa-bastion.md`
- Role Ansible : `ansible/roles/mfa_totp/`
- Dette : T-ANSIBLE-SERVICE-ACCOUNT (compte service Ansible exempt TOTP)
