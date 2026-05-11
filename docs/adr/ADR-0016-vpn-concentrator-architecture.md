# ADR-0016 : Architecture VPN concentrateur road-warriors

## Status
Accepted

## Date
2026-05-11

## Contexte

NIS2 Article 21.b impose des mesures de securite pour l'acces a distance aux systemes de l'organisation. Pour Nova Syndicate (85 employes fictifs, sites Lyon HQ et Marseille), les cas d'usage sont :

- Administrateurs en mobilite accedant aux ressources internes (VLAN SERVERS 192.168.20.0/28, partages fichiers FS01)
- Acces d'urgence hors-site pour les equipes IT
- Acces securise depuis des postes non geres (BYOD temporaire)

L'infrastructure expose deja un point d'entree Internet sur l'adresse publique de la box Huawei (NAT sur Proxmox). L'objectif est de creer un concentrateur VPN qui :

1. Authentifie les road-warriors par cryptographie asymetrique (pas de mot de passe transportable sur le reseau)
2. S'integre dans la DMZ existante (172.16.1.0/29) sans modifier l'architecture firewall
3. Peut etre deploye et maintenu par Ansible (role idempotent)
4. Reste auditable lors de la soutenance AIS

Le protocole WireGuard a ete retenu comme base (reference : ADR-0009 pour le concentrateur backup VPS). La question ici est le placement du concentrateur dans l'architecture.

## Decision

Deploiement d'une VM dediee **vpn-gw01** (VMID 110, Debian 12) en DMZ sur 172.16.1.4/29.

Architecture retenue :

```
Internet
    |
    | UDP 51820
    v
Box Huawei (NAT)
    |
    | DNAT -> 172.16.1.4:51820
    v
Proxmox vmbr3 (172.16.1.5/29)
    |
FW-EXT-LYON (172.16.1.1) -- [trafic metier road-warrior pass]
    |
vpn-gw01 (172.16.1.4)
    |
    | wg0 : 10.20.0.1/24
    |
Road-warriors (10.20.0.10-20)
    |
    | [via FW-INT-LYON ACLs]
    v
SERVERS VLAN (192.168.20.0/28)
```

**Subnet road-warriors** : 10.20.0.0/24 (isole, distinct du LAN interne et des VLANs operationnels)

**Authentification** : cle publique WireGuard par peer (equivalent d'un certificat client). Chaque peer a un AllowedIPs distinct. Revocation = suppression du bloc [Peer] dans wg0.conf + re-deploy Ansible.

**DNS** : dnsmasq sur vpn-gw01 (10.20.0.1:53) forwardant vers DC01 (192.168.20.10). Les road-warriors resolvent `nova-syndicate.local` sans acces direct au DC.

**Gestion** : role Ansible `vpn_gateway` (tasks/wireguard.yml, tasks/dnsmasq.yml, tasks/policy_routing.yml). Les peers sont declares dans `host_vars/vpn-gw01.yml`. Ajout/revocation = modification YAML + re-run playbook.

## Alternatives considerees

### Cloudflare Access (ZTNA)

**Pour** : Zero Trust Network Access, pas de VPN client a deployer, integration MFA native, audit log Cloudflare.

**Contre** : dependance a un tiers cloud US (Cloudflare). Pour une organisation soumise a NIS2, externaliser l'authentification d'acces a l'infrastructure core vers un fournisseur hors UE introduit une dependance souveraine non acceptable. Incompatible avec le principe de maitrise des acces critiques (NIS2 Art. 21.e). Rejete.

### FortiClient VPN / Palo Alto GlobalProtect

**Pour** : solutions enterprise avec MFA integre, gestion centralisee, posture-check des postes.

**Contre** : cout de licence enterprise incompatible avec le budget d'un POC de formation. Complexite operationnelle disproportionnee pour 85 utilisateurs. Courbe d'apprentissage detourne de l'objectif IaC. Rejete.

### WireGuard sur APP01 (reseau SERVERS interne)

**Pour** : APP01 (192.168.20.13) existe deja, pas de nouvelle VM a creer.

**Contre** : violation du principe single-responsibility (APP01 heberge deja Prometheus/Grafana). Violation de la defense-in-depth : un road-warrior compromis aurait un acces direct au VLAN SERVERS sans passer par les ACLs firewall de FW-INT-LYON. Placement en reseau interne = pas de segment de confinement. Rejete.

### WireGuard sur FW-EXT-LYON (OPNsense)

**Pour** : OPNsense supporte nativement WireGuard. Moins de VMs a gerer.

**Contre** : couplage fort entre le firewall perimetrique et le concentrateur VPN. Si le concentrateur est compromis, l'attaquant a un acces direct aux interfaces de routage du firewall. Gestion du concentrateur via l'UI OPNsense = sortie du paradigme IaC Ansible. Configuration WireGuard OPNsense non geree par Terraform (provider browningluke). Rejete.

### VPS Hetzner standalone (concentrateur public)

**Pour** : IP publique dediee, pas de DNAT box FAI, latence potentiellement meilleure pour les road-warriors distants.

**Contre** : cree un second SPOF hors du perimetre controle. L'authentification des road-warriors se ferait sur une machine hors DMZ sans les ACLs FW-INT-LYON. Cout mensuel VPS supplementaire. Le VPS Hetzner existant est deja affecte au concentrateur backup (ADR-0009) ; doubler l'usage changerait son role. Rejete.

## Consequences

**Acceptees** :

- vpn-gw01 est un SPOF en Phase II. La haute disponibilite (VRRP/keepalived sur une IP virtuelle DMZ) est reportee en Phase III.
- Le controle d'acces granulaire des road-warriors vers les VLANs internes est delegue aux ACLs de FW-INT-LYON (regles Terraform), pas au concentrateur lui-meme.
- La cle WireGuard constitue le facteur "device" d'authentification. L'ajout d'un second facteur (TOTP via authelia ou Teleport) est prevu en Phase III (ADR-0014 Teleport).

**Positives** :

- Isolation forte : les road-warriors arrivent sur 10.20.0.0/24, jamais directement sur les VLANs production.
- Gestion Ansible idempotente : ajout/revocation de peer en < 5 minutes, traçabilite Git.
- WireGuard : protocole moderne, audit cryptographique public (Noise protocol), surface d'attaque reduite vs OpenVPN/IPsec.
- Pas de modification de l'architecture Terraform OPNsense existante.

**Negatives** :

- Gestion des cles out-of-band : la distribution des fichiers .conf aux peers se fait par canal securise hors Ansible (Signal, SFTP chiffre). Pas de PKI automatisee en Phase II.
- Visibilite limitee : pas de logging des connexions WireGuard au niveau applicatif (WireGuard est intentionnellement silencieux). Les connexions sont visibles uniquement via `wg show` et les logs nftables.
- MFA absent en Phase II : la cle WireGuard seule est le seul facteur. Vol de la cle privee = acces road-warrior valide jusqu'a revocation manuelle.

## References

- ANSSI : Guide de securite des VPN, version 2.0 (ANSSI-PA-079)
- NIS2 Article 21.b : mesures pour la gestion des acces
- NIS2 Article 21.e : authentification multifacteur
- WireGuard whitepaper : https://www.wireguard.com/papers/wireguard.pdf
- ADR-0009 : WireGuard concentrateur backup VPS Hetzner
- ADR-0014 : Bastion Teleport MFA (Phase III)
- ADR-0017 : Resolution NAT asymetrique (complement technique de cette decision)
- Runbook : `docs/runbook-wireguard-road-warriors.md`
- Role Ansible : `ansible/roles/vpn_gateway/`
