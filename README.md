# Nova Syndicate - Modernisation Infrastructure IT

## Contexte

Nova Syndicate est une entreprise de logistique specialisee dans la distribution
de composants critiques (medical, aerospatial, defense).
Ce projet modernise l'infrastructure IT : annuaire centralise, segmentation reseau,
VPN, supervision et automatisation.

## Architecture

- **Sites** : Lyon HQ + Marseille + 20 agents distants
- **Firewalls** : 2x OPNsense 25.1 en serie (FW-EXT + FW-INT) avec DMZ isolee
- **Annuaire** : Samba AD (DC01)
- **Services** : FS01, DB01 (MariaDB), APP01 (Squid + Vault), BASTION01
- **DMZ** : WEB01 (Nginx + HAProxy), MAIL01 (Postfix + Dovecot)
- **VPN** : WireGuard (agents) + IPsec IKEv2 (Lyon-Marseille)

## Structure du projet

```
nova-syndicate/
|-- terraform/          # Configuration OPNsense via API REST
|-- ansible/            # Configuration serveurs Linux
|-- gns3/               # Deploiement topologie GNS3
`-- docs/               # Documentation technique
```

## Plan VLSM

| Zone          | Reseau            | Masque | Usages                        |
|---------------|-------------------|--------|-------------------------------|
| Transit Lyon  | 10.0.0.0          | /30    | RTR-LYON1 <-> FW-EXT          |
| Transit interne | 10.0.1.0        | /30    | FW-EXT <-> FW-INT             |
| Transit MRS   | 10.0.2.0          | /30    | RTR-MRS1 <-> FW-EXT-MRS1     |
| DMZ           | 172.16.1.0        | /29    | WEB01, MAIL01                 |
| VLAN 15       | 192.168.15.0      | /29    | BASTION01                     |
| VLAN 20       | 192.168.20.0      | /28    | DC01, FS01, DB01, APP01       |
| VLAN 30       | 192.168.30.0      | /26    | Postes Lyon                   |
| VLAN 40       | 192.168.40.0      | /27    | Agents WireGuard              |
| VLAN 50       | 192.168.50.0      | /29    | BACKUP01                      |
| LAN MRS       | 192.168.31.0      | /26    | Postes Marseille              |

## Deploiement

### Prerequis

- Ansible >= 2.14
- Terraform >= 1.5
- Acces SSH au serveur GNS3 (192.168.158.179)
- OPNsense 25.1 demarre dans GNS3

### Ordre de deploiement

```
# 1. Topologie GNS3
cd gns3/
ansible-playbook -i hosts gns3_topology.yml

# 2. Infrastructure firewalls (depuis BASTION01 ou local)
cd terraform/environments/lyon/
terraform init && terraform apply

cd terraform/environments/marseille/
terraform init && terraform apply

# 3. Configuration serveurs
cd ansible/
ansible-playbook -i inventory/hosts.yml site.yml
```

## Conformite

- NIS2 : journalisation 12 mois, MFA, double pare-feu, PCA/PRA
- RGPD : chiffrement repos et transit, RBAC, DPO

## Contact client

Jean Thalor - DSI Nova Syndicate
j.thalor@nova-syndicate.fr

## Setup dev environment

Pre-commit hooks (anti-vault-plaintext + anti-leaked-secrets) :
```bash
brew install pre-commit
pre-commit install                 # active .git/hooks/pre-commit
pre-commit run --all-files         # smoke test
```

GitHub Action `secret-scan.yml` (gitleaks) tourne automatiquement sur chaque
push / PR vers `main`. C'est le filet final non-contournable.
Documentation : [ADR-0028](docs/adr/ADR-0028-precommit-gitleaks-anti-secret-leak.md)
