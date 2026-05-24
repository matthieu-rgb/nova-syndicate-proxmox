# Index des ADR -- Nova Syndicate

33 Architecture Decision Records, regroupes par theme. Statut par defaut : **Accepté**
(se referer a l'en-tete de chaque ADR pour le statut precis et la date).

Derniere mise a jour : 2026-05-24 (T-AFK-MEGA).

## Infrastructure & Virtualisation
- [ADR-0001](ADR-0001-proxmox-hyperviseur.md) -- Proxmox VE comme hyperviseur principal

## Reseau & Pare-feu
- [ADR-0002](ADR-0002-plan-adressage-vlan.md) -- Plan d'adressage VLAN avec VLSM
- [ADR-0003](ADR-0003-architecture-dual-firewall.md) -- Architecture dual firewall + zone de transit DMZ
- [ADR-0004](ADR-0004-opnsense-vs-pfsense.md) -- OPNsense comme appliance firewall
- [ADR-0005](ADR-0005-ipsec-ikev2-site-to-site.md) -- IPsec IKEv2 Lyon-Marseille
- [ADR-0017](ADR-0017-nat-asymmetry-policy-routing.md) -- Resolution asymetrie NAT par policy routing
- [ADR-0022](ADR-0022-ipsec-stability-script.md) -- IPsec auto-recovery script (FW-EXT-LYON)
- [ADR-0032](ADR-0032-T-AWX-NFT-ALLOWLIST-option-A.md) -- Ouverture VLAN 60 ADMIN -> :22 (nft allowlist)

## VPN & Acces distant
- [ADR-0006](ADR-0006-wireguard-backup-vpn.md) -- WireGuard (backup cloud + road-warriors)
- [ADR-0007](ADR-0007-tailscale-admin-perso.md) -- Tailscale pour l'acces administratif personnel
- [ADR-0016](ADR-0016-vpn-concentrator-architecture.md) -- Architecture VPN concentrateur road-warriors
- [ADR-0021](ADR-0021-tailscale-admin-subnet-routing.md) -- Tailscale subnet routing (acces admin hors LAN)

## Identite, IAM & Acces administratif
- [ADR-0014](ADR-0014-bastion-teleport-mfa.md) -- Bastion jumpbox + Teleport (MFA + session recording)
- [ADR-0018](ADR-0018-mfa-totp-bastion.md) -- MFA TOTP sur bastion01 (SSH + sudo)
- [ADR-0019](ADR-0019-authelia-mfa-portail-web.md) -- Authelia comme portail MFA web interne
- [ADR-0020](ADR-0020-two-tier-admin-access.md) -- Modele d'acces administratif two-tier (Tier0/1/2)
- [ADR-0027](ADR-0027-iam-industrialise-ansible.md) -- IAM industrialise via Ansible (preparation AWX)
- [ADR-0031](ADR-0031-awx-operator-k3s-iam-automation.md) -- AWX Operator sur K3s (automation IAM, VLAN 60)
- [ADR-0033](ADR-0033-awx-rbac-teams-ldap-mapping.md) -- AWX RBAC : 4 Teams + mapping LDAP (separation of duties NIS2)

## Monitoring, SIEM & Securite
- [ADR-0013](ADR-0013-wazuh-siem-nis2.md) -- Wazuh comme SIEM centralise (NIS2 art.21.f)
- [ADR-0025](ADR-0025-suricata-defense-in-depth.md) -- Suricata IDS multi-capteurs (defense in depth)
- [ADR-0030](ADR-0030-grafana-wazuh-single-pane-of-glass.md) -- Grafana + Wazuh single-pane-of-glass

## Sauvegarde
- [ADR-0008](ADR-0008-borg-repokey-append-only.md) -- BorgBackup (repokey-blake2, append-only)
- [ADR-0009](ADR-0009-strategie-backup-3-2-1-1-0.md) -- Strategie de sauvegarde 3-2-1-1-0
- [ADR-0010](ADR-0010-vps-hetzner-hors-site.md) -- VPS Hetzner Helsinki (stockage hors-site)

## IaC & Outillage
- [ADR-0011](ADR-0011-ansible-iac-config-os.md) -- Ansible pour la configuration OS (IaC niveau 2)
- [ADR-0012](ADR-0012-terraform-opnsense-browningluke.md) -- Terraform (provider browningluke/opnsense)
- [ADR-0015](ADR-0015-hardening-custom-role.md) -- Role hardening Ansible custom (vs CIS automatise)
- [ADR-0026](ADR-0026-vault-plaintext-fix-2026-05-18.md) -- Detection/remediation vault plaintext
- [ADR-0028](ADR-0028-precommit-gitleaks-anti-secret-leak.md) -- Pre-commit hooks + CI secret scanning

## Applications & Services metier
- [ADR-0023](ADR-0023-portail-metier-architecture.md) -- Portail metier (Flask + Authelia + MariaDB)
- [ADR-0024](ADR-0024-exposition-publique-cloudflare.md) -- Exposition publique (Cloudflare Tunnel)
- [ADR-0029](ADR-0029-mail-server-postfix-dovecot.md) -- Mail server interne (Postfix + Dovecot + OpenDKIM)
