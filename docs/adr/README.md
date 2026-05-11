# ADR -- Architecture Decision Records

Nova Syndicate Phase II -- Decisions architecturales documentees.

Format : Michael Nygard (status / date / contexte / decision / alternatives / consequences / references)

Toutes les decisions sont au statut `Accepted` : elles ont ete implementees et validees au cours du projet Phase II (cloturer le 2026-05-10).

## Index

| ADR | Titre | Status | Date |
|-----|-------|--------|------|
| [ADR-0001](ADR-0001-proxmox-hyperviseur.md) | Choix de Proxmox VE comme hyperviseur principal | Accepted | 2026-05-10 |
| [ADR-0002](ADR-0002-plan-adressage-vlan.md) | Plan d'adressage VLAN avec VLSM | Accepted | 2026-05-10 |
| [ADR-0003](ADR-0003-architecture-dual-firewall.md) | Architecture dual firewall avec zone de transit DMZ | Accepted | 2026-05-10 |
| [ADR-0004](ADR-0004-opnsense-vs-pfsense.md) | Choix d'OPNsense comme appliance firewall | Accepted | 2026-05-10 |
| [ADR-0005](ADR-0005-ipsec-ikev2-site-to-site.md) | IPsec IKEv2 pour la liaison site-to-site Lyon-Marseille | Accepted | 2026-05-10 |
| [ADR-0006](ADR-0006-wireguard-backup-vpn.md) | WireGuard pour le tunnel backup cloud et les acces road-warrior | Accepted | 2026-05-10 |
| [ADR-0007](ADR-0007-tailscale-admin-perso.md) | Tailscale pour l'acces administratif personnel uniquement | Accepted | 2026-05-10 |
| [ADR-0008](ADR-0008-borg-repokey-append-only.md) | BorgBackup avec chiffrement repokey-blake2 et mode append-only | Accepted | 2026-05-10 |
| [ADR-0009](ADR-0009-strategie-backup-3-2-1-1-0.md) | Strategie de sauvegarde 3-2-1-1-0 | Accepted | 2026-05-10 |
| [ADR-0010](ADR-0010-vps-hetzner-hors-site.md) | VPS Hetzner Helsinki pour le stockage hors-site | Accepted | 2026-05-10 |
| [ADR-0011](ADR-0011-ansible-iac-config-os.md) | Ansible pour la configuration OS (IaC niveau 2) | Accepted | 2026-05-10 |
| [ADR-0012](ADR-0012-terraform-opnsense-browningluke.md) | Terraform avec le provider browningluke/opnsense | Accepted | 2026-05-10 |
| [ADR-0013](ADR-0013-wazuh-siem-nis2.md) | Wazuh comme SIEM centralise pour NIS2 art. 21.f | Accepted | 2026-05-10 |
| [ADR-0014](ADR-0014-bastion-teleport-mfa.md) | Bastion jumpbox avec Teleport planifie pour MFA | Accepted | 2026-05-10 |
| [ADR-0015](ADR-0015-hardening-custom-role.md) | Role hardening Ansible custom plutot qu'outillage CIS automatise | Accepted | 2026-05-10 |
| [ADR-0016](ADR-0016-vpn-concentrator-architecture.md) | Architecture VPN concentrateur road-warriors (VM dediee DMZ) | Accepted | 2026-05-11 |
| [ADR-0017](ADR-0017-nat-asymmetry-policy-routing.md) | Resolution NAT asymetrique par policy-based routing | Accepted | 2026-05-11 |

## Dependances entre ADRs

Les decisions ne sont pas independantes. Les relations principales :

```
ADR-0001 (Proxmox)
  --> ADR-0003 (dual firewall, VMs OPNsense sur Proxmox)
  --> ADR-0011 (Ansible, configure les VMs Proxmox)

ADR-0002 (VLSM)
  --> ADR-0003 (segments transit, VLANs)
  --> ADR-0005 (prefixes IPsec child SAs)

ADR-0004 (OPNsense)
  --> ADR-0012 (Terraform provider browningluke/opnsense)
  --> ADR-0005 (IPsec IKEv2 configure sur OPNsense)
  --> ADR-0006 (WireGuard configure sur OPNsense)

ADR-0008 (Borg)
  --> ADR-0009 (strategie 3-2-1-1-0, Borg en est l'outil)
  --> ADR-0010 (VPS Hetzner, destination Borg distante)
  --> ADR-0006 (WireGuard, tunnel pour Borg vers VPS)

ADR-0011 (Ansible)
  --> ADR-0015 (role hardening, deploye par Ansible)
  --> ADR-0013 (Wazuh agents, deployes par Ansible)
  --> ADR-0016 (role vpn_gateway, deploye par Ansible)

ADR-0016 (concentrateur VPN)
  --> ADR-0017 (policy routing, complement technique obligatoire)
  --> ADR-0015 (hardening, applique sur vpn-gw01)
  --> ADR-0014 (MFA bastion, Phase III complement)

ADR-0014 (bastion)
  --> ADR-0007 (Tailscale, couche d'acces complementaire)
  --> ADR-0013 (Wazuh, audit des connexions bastion)
```

## Contexte du projet

- **Formation** : Titre Professionnel AIS (RNCP 37680 niveau 6), Jedha Academy
- **Stage** : Thales Luxembourg, debut mi-septembre 2026
- **Hyperviseur** : Proxmox VE 8.x, serveur physique unique
- **IaC** : Terraform (Proxmox + OPNsense) + Ansible (configuration OS)
- **Sites** : Lyon (principal) + Marseille (DR), liaison IPsec IKEv2
- **Domaine** : nova-syndicate.local, realm NOVA-SYNDICATE.LOCAL
- **Compliance cible** : NIS2 Article 21 (documentation de reference, pas entite soumise)
