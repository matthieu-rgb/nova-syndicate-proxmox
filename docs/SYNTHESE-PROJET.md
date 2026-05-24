# Synthese projet -- Nova Syndicate (BROUILLON)

> **Statut : BROUILLON / squelette de rapport jury.** Genere le 2026-05-24 (T-AFK-MEGA).
> A enrichir et finaliser par Matthieu (chiffres, captures, diagramme v5). Les references
> ADR pointent vers `docs/adr/INDEX.md`.

## 1. Vision Nova Syndicate

Nova Syndicate : entreprise fictive **multi-secteurs** (3 secteurs metier), **multi-sites**
(HQ Lyon + site Marseille), **~85 employes**. Objectif du projet : concevoir et operer une
infrastructure d'entreprise **conforme NIS2 et RGPD**, entierement en Infrastructure-as-Code,
avec une posture de securite "defense in depth" et une administration zero-trust.

- 2 sites relies en IPsec IKEv2 (Lyon <-> Marseille), [ADR-0005].
- Segmentation reseau stricte (VLAN + VLSM), double pare-feu + DMZ, [ADR-0002], [ADR-0003].
- ~12 VM Linux (Debian 12) + 4 firewalls OPNsense, pilotage IaC (Ansible + Terraform).

## 2. Architecture

> *(A illustrer avec le diagramme v5 -- cf `docs/NOVA-TOPOLOGY-MAP.md`.)*

- **Hyperviseur** : Proxmox VE [ADR-0001]. Inventaire detaille : `docs/INFRA-INVENTORY.md`.
- **Reseau** : VLAN management / bastion / servers / users / DMZ / backup + VLAN 60 ADMIN
  (plan de controle AWX). Firewalls OPNsense en IaC Terraform [ADR-0004], [ADR-0012].
- **Acces administratif** : modele two-tier (Tier0/1/2) [ADR-0020], bastion MFA TOTP
  [ADR-0018], Teleport planifie [ADR-0014]. Matrice d'acces : `docs/access-matrix.md`.
- **Identite / IAM** : AD Samba (dc01), industrialisation via AWX (k3s) [ADR-0031], RBAC par
  Teams + mapping LDAP [ADR-0033].
- **Monitoring / SIEM** : Wazuh manager (app01) + agents, Suricata IDS, Grafana
  single-pane-of-glass [ADR-0013], [ADR-0025], [ADR-0030].
- **Sauvegarde** : BorgBackup chiffre, strategie 3-2-1-1-0, hors-site VPS Hetzner
  [ADR-0008], [ADR-0009], [ADR-0010].
- **Services** : portail metier (Flask + Authelia + MariaDB) [ADR-0023], site vitrine
  expose via Cloudflare Tunnel [ADR-0024], mail interne Postfix/Dovecot [ADR-0029].

## 3. Conformite NIS2 (art.21 -- mesures de gestion des risques)

| Mesure NIS2 art.21 | Mise en oeuvre Nova | Reference |
|---|---|---|
| Controle d'acces | Two-tier admin, bastion MFA, RBAC AWX (separation of duties) | ADR-0018, ADR-0020, **ADR-0033** |
| Detection / monitoring (21.f) | Wazuh SIEM + regles NIS2, Suricata IDS, watchdog agents | ADR-0013, ADR-0025, T-WAZUH-LOGCOLLECTOR-HEALTHCHECK |
| Reponse a incident | Runbooks (`docs/runbook-*`), auto-recovery IPsec, watchdog wazuh | ADR-0022 |
| Continuite / backup | BorgBackup append-only, 3-2-1-1-0, drills de restauration | ADR-0008, ADR-0009 |
| Securisation reseau | Double FW + DMZ, nft host par VM, allowlist /60 controle plane | ADR-0003, ADR-0015, ADR-0032 |
| Chiffrement des flux | IPsec, WireGuard, TLS (wildcard mkcert mail/web), LDAPS | ADR-0005, ADR-0006, T-MAIL-TLS-WILDCARD |

## 4. Conformite RGPD (art.32 -- securite du traitement)

| Exigence RGPD art.32 | Mise en oeuvre | Reference |
|---|---|---|
| Chiffrement | TLS partout (web/mail), tunnels chiffres, backups chiffres | ADR-0008, ADR-0029 |
| Controle d'acces / minimisation | RBAC AWX (moindre privilege), Tier0 DENY, comptes de service dedies | ADR-0033, ADR-0020 |
| Journalisation / audit | Audit log IAM (nova-iam) collecte par Wazuh, retention SIEM | ADR-0013, ADR-0027 |
| Resilience / disponibilite | Backups 3-2-1-1-0, auto-recovery, swap OOM mitigation | ADR-0009 |
| Gestion des secrets | Ansible Vault, pre-commit/CI anti-leak, cles hors repo | ADR-0026, ADR-0028 |

## 5. Lessons learned (ADR structurants)

1. **ADR-0017** -- l'asymetrie NAT/routing impose un policy-based routing explicite ; un
   flush global de pare-feu peut casser ces marques (lecon T-AWX-VPNGW-NFT-MODEL : flush
   chirurgical + handler `reload` plutot que `restart`).
2. **ADR-0031 / ADR-0033** -- industrialiser l'IAM (AWX) puis cloisonner par RBAC LDAP : la
   source de verite reste l'AD (un mouvement RH = un changement de groupe).
3. **ADR-0015 / ADR-0032** -- un role hardening qui REECRIT le ruleset est puissant mais
   dangereux ; modeliser les exceptions (tables custom, flush scope) avant d'appliquer.
4. **ADR-0013** -- un SIEM n'est fiable que si ses agents le sont : unit systemd
   fire-and-forget -> watchdog necessaire (le `Restart=` seul ne suffit pas).
5. **ADR-0028 / ADR-0026** -- secret scanning en pre-commit + CI = filet indispensable
   (jamais de cle privee dans le repo ; certs locaux hors git).
6. **ADR-0018** -- le MFA bastion protege le control plane mais complique l'automatisation
   AFK (ControlMaster persistant comme compromis operationnel).

## 6. Roadmap residuelle

> Source de verite a jour : section "Dettes ouvertes" de `STATUS.md`.

- **Urgent** : T-SPLIT-MONITORING-VM (sortir la stack lourde d'app01, OOM confirme).
- **Perimetre (supervise)** : T-FW-VLAN60-DMZ-VPNGW-OPEN, T-FW-DMZ-WAZUH-OPEN.
- **IAM / IaC** : T-AWX-VAULT-INVENTORY, T-AWX-TEMPLATES-IAC (Config-as-Code AWX), workflow Onboarding.
- **Reseau / VPN** : T-WIREGUARD-POC, finalisation MFA TOTP bastion, T-SQUID-PROXY.
- **Observabilite** : T-GRAFANA-AUTHELIA-SSO.
- **Hygiene** : T-SSH-CONFIG-DEDUP, nettoyage snapshots AFK, T-MAIL-WAZUH-ENROLL (post-FW).
