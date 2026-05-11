# ADR-0019 : Authelia comme portail MFA pour les services web internes

## Status
Accepted

## Date
2026-05-11

## Contexte

Les services web internes (Grafana, Prometheus, Wazuh) sont exposes directement sur leurs ports natifs (3000, 9090, 55000) sans authentification forte. Un acces au VLAN 20 (192.168.20.0/28) suffit a acceder a ces services.

NIS2 Article 21.b impose le MFA pour les acces aux systemes essentiels, y compris les interfaces d'administration et de supervision. L'ADR-0018 couvre le bastion SSH ; les interfaces web necessitent une couverture complementaire.

Trois vecteurs identifies :
- **Pas d'auth** : Grafana et Prometheus accessibles sans credential depuis le VLAN 20
- **Auth locale faible** : Grafana a son propre mecanisme auth local, sans MFA, sans LDAP
- **Pas de SSO** : chaque service a sa propre auth locale, pas de revocation centralisee

## Decision

Deploiement d'**Authelia v4.39.19** sur APP01 (192.168.20.13) comme reverse proxy MFA (forward authentication pattern).

**Architecture :**

```
Client VLAN 20 --> Nginx (443/TLS) --> [auth_request /authelia/api/verify]
                                              |
                              Authelia (127.0.0.1:9091)
                                              |
                                      AD LDAP (DC01 LDAPS 636)
                                              |
                                Approve --> Grafana (127.0.0.1:3000)
                                Deny   --> 302 /authelia/?rd=...
```

**Composants :**

| Composant | Role |
|---|---|
| Nginx | Reverse proxy TLS, forward auth, protection des locations |
| Authelia | Portail MFA : 1er facteur LDAP, 2eme facteur TOTP |
| Samba AD (DC01) | Backend LDAP : authentification des utilisateurs du domaine |
| SQLite | Stockage Authelia : sessions, TOTP secrets, webauthn |

**Protocoles :**

| Acces | Facteur 1 | Facteur 2 |
|---|---|---|
| Grafana via Nginx | Login AD (LDAPS) | TOTP 6 chiffres |
| Portal Authelia | Login AD (LDAPS) | TOTP 6 chiffres |

**Parametres LDAP :**
- Implementation : `activedirectory` (Samba AD DC01.nova-syndicate.local)
- Base DN : `DC=nova-syndicate,DC=local`
- Bind account : `CN=svc authelia,OU=Service-Accounts,DC=nova-syndicate,DC=local`
- Filtre utilisateurs : `(&({username_attribute}={input})(objectCategory=person)(objectClass=user))`
- TLS : LDAPS port 636, `skip_verify: true` (cert Samba autosigne, Phase III : CA distribuee)

**Access Control Authelia :**
```
default_policy: deny
rules:
  - domain: app01.nova-syndicate.local
    resources: ['^/authelia']
    policy: bypass
  - domain: app01.nova-syndicate.local
    policy: two_factor
```

**Session :** cookies domaine `nova-syndicate.local`, expiration 1h, inactivite 5min

**TLS Nginx :** certificat autosigne 2048 RSA, valide 2 ans. Phase III : Let's Encrypt ou PKI interne.

## Alternatives considerees

### Authentification native Grafana (LDAP plugin)

**Pour** : zero composant supplementaire, Grafana supporte LDAP nativement.

**Contre** : authentification unique par service, pas de SSO, pas de TOTP natif sans plugin tiers. Chaque nouveau service (Prometheus, Wazuh) necessite sa propre integration LDAP. Maintenance multipliee. Rejete : ne satisfait pas le MFA de maniere generalisable.

### Keycloak (IdP OIDC/SAML)

**Pour** : standard OIDC/SAML, support natif par de nombreuses applications, gestion fine des roles, interface admin avancee.

**Contre** : necessite minimum 2 Go RAM, PostgreSQL ou H2, JVM. Complexite de deploiement disproportionnee pour le perimetre Phase II. APP01 a 4 Go RAM, partages avec Grafana/Prometheus/Wazuh. Reporte Phase III.

### Authentik

**Pour** : alternative Python a Keycloak, plus legere, interface moderne, flows personnalisables.

**Contre** : necessite PostgreSQL + Redis + worker, overhead similaire a Keycloak pour le perimetre Phase II. Meme conclusion que Keycloak. Rejete.

### Nginx + auth_basic + LDAP module

**Pour** : zero composant supplementaire, auth basique LDAP via ngx_http_auth_request_module.

**Contre** : Basic Auth = mot de passe en base64 dans chaque requete, pas de MFA, pas de session, rejete par tous les navigateurs modernes sur HTTPS non securise. Non conforme NIS2. Rejete.

### Pas d'authentification (acces VLAN uniquement)

**Contre** : violation directe NIS2 Art. 21.b et 21.e. Acces non authentifie aux metriques systeme (Prometheus) et dashboards supervision (Grafana) = information disclosure. Rejete.

## Consequences

**Positives :**
- NIS2 Art. 21.b : MFA 2 facteurs (AD + TOTP) sur les services web de supervision
- SSO : un login Authelia donne acces a tous les services proteges pendant la duree de session
- Revocation centralisee : desactiver un compte AD suffit a revoquer l'acces a tous les services
- Pattern extensible : tout nouveau service nginx-proxied peut etre protege en ajoutant `auth_request`
- Audit : logs Authelia (`/var/lib/authelia/authelia.log`) + logs Nginx access

**Negatives et risques :**

- **TLS autosigne** : les clients doivent accepter le certificat (exception navigateur). Phase III : PKI interne ou Let's Encrypt avec DNS challenge.
- **`skip_verify: true` LDAPS** : le certificat Samba autosigne n'est pas verifie par Authelia. Mitigation : cert verifie manuellement lors du deploiement, CA distribuee Phase III.
- **SPOF** : si Authelia ou Nginx tombe, tous les services web deviennent inaccessibles. Mitigation : Authelia supervise par Wazuh (agent local), alertes Prometheus.
- **SQLite** : pas de haute disponibilite. Acceptable pour un lab mono-noeud. Phase III : Redis + PostgreSQL si replique.
- **Mot de passe `svc-authelia` en clair dans configuration.yml** : fichier protege (440 authelia:authelia). Phase IV (role Ansible) : Ansible-vault + variable d'environnement `AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE`.

## Validation experimentale (2026-05-11)

| Test | Resultat |
|---|---|
| HTTP port 80 -> redirect HTTPS | 301 vers https://app01.nova-syndicate.local/ |
| HTTPS / sans auth -> redirect Authelia | 302 vers /authelia/?rd=... |
| HTTPS /authelia/ -> portal accessible | 200 OK |
| LDAP bind svc-authelia sur DC01 LDAPS 636 | Succes (ldapsearch valide) |
| Authelia startup avec backend LDAP | "Startup complete" dans les logs |

## Dette technique

- **T-AUTHELIA-TLS-PKI** : remplacer le certificat autosigne par une PKI interne (Phase III)
- **T-AUTHELIA-LDAP-CERT** : distribuer le CA Samba aux clients pour LDAPS (Phase III)  
- **T-AUTHELIA-ANSIBLE** : role Ansible `authelia` avec secrets dans vault (Phase IV)
- **T-AUTHELIA-PROMETHEUS** : ajouter la protection Prometheus et Wazuh dans nginx (Phase III)

## References

- ADR-0013 : Wazuh SIEM (service protege)
- ADR-0018 : MFA TOTP bastion (complementaire)
- ADR-0011 : Ansible IaC (Phase IV role)
- Authelia documentation : https://www.authelia.com/docs/
- NIS2 Article 21.b : MFA pour acces distants et privilegies
- Runbook : `docs/runbook-authelia.md`
- Role Ansible : `ansible/roles/authelia/` (Phase IV)
