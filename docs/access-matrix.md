# Access Matrix — accès SSH & allowlists nftables

> **Tâche** : T-AUDIT-ACCESS-MATRIX (préalable à T-AWX-NFT-ALLOWLIST)
> **Date** : 2026-05-23
> **Auteur** : audit automatisé depuis le Mac via ControlMaster `bastion-nova` (TOTP 4h)
> **Méthode** : 1 SSH par VM (multiplexé via bastion), collecte `hostname` / `ip -4` /
> `nft list ruleset` (sudo) / `authorized_keys` + fingerprints / `ip route` / `$SSH_CONNECTION`.
> Données = **état LIVE observé**, pas l'état souhaité du repo ansible.

## 1. Matrice

| VM (VMID) | IPs principales | Allowlist nft SSH (dport 22, CIDRs LIVE) | Clés `authorized_keys` (fp courts + identité) | Source IP de connexion observée | Notes |
|-----------|-----------------|------------------------------------------|-----------------------------------------------|---------------------------------|-------|
| **fs01** (104) | eth0 192.168.20.11/28 | `192.168.15.0/29`, `192.168.20.0/28` | `5iKWFr…` jedha-lab · `55x6DF…` bastion01@nova | 192.168.15.2 (bastion) | ⚠️ pas de `/60` · drift vs group_vars · samba 139/445 |
| **db01** (105) | eth0 192.168.20.12/28 | `192.168.15.0/29`, `192.168.20.0/28` + `@addr-set-sshd reject` | `5iKWFr…` jedha-lab | 192.168.15.2 (bastion) | ⚠️ pas de `/60` · drift · mysql 3306 · 1 seule clé · set dynamique anti-bruteforce |
| **app01** (106) | eth0 192.168.20.13/28 | `192.168.15.0/29`, `192.168.20.0/28` | `5iKWFr…` jedha-lab · `55x6DF…` bastion01@nova · `+vYdyY…` root@proxmox (RSA) | 192.168.15.2 (bastion) | ⚠️ pas de `/60` · drift · serveur monitoring (wazuh/suricata, nombreux ports) · **clé Proxmox présente** (d'où l'accès Proxmox→app01) |
| **backup01** (109) | eth0 192.168.50.2/29 · wg0 10.30.0.2/24 | `192.168.15.0/29`, `192.168.20.0/28` + `@addr-set-sshd reject` | `5iKWFr…` jedha-lab · `HGEnjO…` root@db01 · `55x6DF…` bastion01@nova | 192.168.15.2 (bastion) | ⚠️ pas de `/60` · drift · clé `root@db01` (backup rsync db01→backup01) · injoignable direct depuis Proxmox (src 192.168.50.6 non allowlistée) |
| **vpn-gw01** (110) | eth0 172.16.1.4/29 · wg0 10.20.0.1/24 | `10.0.0.0/8`, `192.168.10.0/24`, `192.168.15.0/24`, `192.168.18.0/24`, `192.168.20.0/28` | `+vYdyY…` root@proxmox (RSA) · `5iKWFr…` jedha-lab | **10.0.1.2** (transit DMZ) | ⚠️ pas de `/60` · allowlist = `host_vars/vpn-gw01.yml` (large, distincte) · DMZ, injoignable direct depuis Proxmox |
| **bastion01** (102) | eth0 192.168.15.2/29 | `192.168.15.0/29`, `192.168.18.0/24`, `192.168.20.0/28`, `100.64.0.0/10` | `5iKWFr…` jedha-lab | 192.168.15.6 (Mac via SNAT Proxmox/Tailscale) | ⚠️ pas de `/60` · **allowlist atypique** (Tailscale `100.64/10`) · ports Teleport 443/3023/3024/3025 · **non dérivable de group_vars** → géré hors rôle hardening ? (à vérifier) |
| **dc01** (—) | eth0 192.168.20.10/28 | `192.168.15.0/29`, `192.168.20.0/28`, **`192.168.60.0/29`** ✅ | `5iKWFr…` jedha-lab · `55x6DF…` bastion01@nova · `5PnAWh…` awx-runner@nova | 192.168.15.2 (bastion) | ✅ **déjà `/60`** (seul AWX-managed) · DC AD (kerberos/ldap/dns nombreux ports) · clé `awx-runner` présente |

## 2. Détail allowlists SSH — état LIVE vs cible repo

État souhaité dans le repo ansible **après** commit `06df57f` :
- `group_vars/all` (fs01, db01, app01, backup01, bastion01, dc01) :
  `10.0/24, 15.0/24, 18.0/24, 20.0/28, 60.0/29`
- `host_vars/vpn-gw01` : `10.0.0.0/8, 10.0/24, 15.0/24, 18.0/24, 20.0/28, 60.0/29`

| VM | LIVE | Repo cible | `/60` live ? | Écart |
|----|------|-----------|--------------|-------|
| fs01 | `15.0/29, 20.0/28` | `10/24,15/24,18/24,20/28,60/29` | ❌ | **drift** : 15 en /29 (≠/24), manque 10/24+18/24+60/29 |
| db01 | `15.0/29, 20.0/28` | idem | ❌ | idem drift |
| app01 | `15.0/29, 20.0/28` | idem | ❌ | idem drift |
| backup01 | `15.0/29, 20.0/28` | idem | ❌ | idem drift |
| bastion01 | `15.0/29, 18.0/24, 20.0/28, 100.64/10` | idem group_vars | ❌ | **atypique** : a `100.64/10`, manque 10/24+15/24+60/29 → source non tracée |
| vpn-gw01 | `10/8, 10/24, 15/24, 18/24, 20/28` | + `60/29` | ❌ | manque seulement `60/29` (le reste matche host_vars) |
| dc01 | `15.0/29, 20.0/28, 60.0/29` | idem group_vars | ✅ | a déjà `/60` mais 15 en /29 + manque 10/24,18/24 |

## 3. Inventaire des clés `authorized_keys`

| Fingerprint (SHA256) | Identité (commentaire) | Type | Présente sur |
|----------------------|------------------------|------|--------------|
| `5iKWFrbJCaWlqRXjItnIUQRaU27WzRjlI6CsoRllvkE` | **jedha-lab** (= `id_ansible` Mac de Matthieu) | ED25519 | **toutes (7/7)** |
| `55x6DFsTZ9owpAUJqRAaDxBDwwtEwgHyJc7mDWZlb3A` | bastion01@nova-syndicate.local | ED25519 | fs01, app01, backup01, dc01 |
| `+vYdyYedLdfnWe1yo4Q7FHI5pRDOpPEGPnaRqMQqTtM` | **root@proxmox** | RSA | app01, vpn-gw01 |
| `5PnAWhFvxeVypwK+SbB6omyng+UwY/+cBkE+sY8xNRU` | **awx-runner@nova-syndicate.local** | ED25519 | **dc01 uniquement** |
| `HGEnjOwOsHFnd+FhRn0fLqtyCaAbNyAf9YJitAkEr8M` | root@db01 | ED25519 | backup01 (rsync de sauvegarde) |

## 4. Sources de connexion connues

### Mac (`jedha-lab` / `id_ansible`, fp `5iKWFr…`)
- Clé autorisée sur **les 7 VMs**.
- Atteint toutes les VMs via le ControlMaster `bastion-nova` (ProxyJump bastion, TOTP saisi, persist 4h).
- Source perçue par les VMs : `192.168.15.2` (bastion) pour VLAN20/50, `10.0.1.2` pour vpn-gw01 (transit DMZ), `192.168.15.6` pour bastion01 (SNAT Proxmox/Tailscale).
- Toutes ces sources sont déjà dans les allowlists → **accès 7/7 fonctionnel**. ✅ C'est le control plane retenu pour le run.

### Proxmox (`root@proxmox`, RSA fp `+vYdyY…`)
- Clé autorisée uniquement sur **app01** et **vpn-gw01**.
- Réseau : atteint directement VLAN20 (src 192.168.20.5, allowlistée) et VLAN15.
- **Mais** : clé absente sur fs01/db01/bastion01 ; backup01 dropé (src 192.168.50.6 non allowlistée) ; vpn-gw01 injoignable direct (DMZ).
- ⇒ Proxmox ne pilote réellement que **app01**. **C'est pourquoi l'Option B (Proxmox contrôleur) a été abandonnée.**

### AWX (`awx-runner@nova-syndicate.local`, fp `5PnAWh…`)
- Clé autorisée uniquement sur **dc01**.
- `dc01` est la **seule** VM dont l'allowlist contient déjà `192.168.60.0/29`.
- ⇒ AWX (192.168.60.2) n'atteint aujourd'hui que **dc01**. **C'est exactement la dette T-AWX-NFT-ALLOWLIST** : ouvrir `/60` sur les 6 autres + déployer la clé `awx-runner` dessus.

### Bastion (`bastion01@nova-syndicate.local`, fp `55x6DF…`)
- En tant que **transport** (ProxyJump) : tout passe — sa source `192.168.15.2` est allowlistée partout (`15.0/29` ou `15.0/24`). C'est le pivot du control plane Mac.
- En tant qu'**identité propre** (sa clé `55x6DF…`) : présente seulement sur fs01, app01, backup01, dc01.
- Allowlist propre atypique : `100.64.0.0/10` (Tailscale) + ports Teleport (443/3023-3025).

## 5. ⚠️ Constats critiques (pour ADR-0032 / avant le run `hardening:firewall`)

1. **DRIFT généralisé.** Aucun des 7 hôtes n'a l'allowlist du repo. Le live est `15.0/29 + 20.0/28`
   (parfois +). Le repo `group_vars/all` vise `10/24,15/24,18/24,20/28(,60/29)`.
   ⇒ Un run `hardening:firewall` **ne fait pas qu'ajouter `/60`** : il **réécrit** toute
   l'allowlist (ex : `15.0/29 → 15.0/24`, ajout `10/24` + `18/24`). À acter explicitement.
2. **bastion01 = cas spécial.** Allowlist live (`100.64/10` Tailscale + Teleport) **non
   dérivable** de `group_vars/all` et aucun `host_vars/bastion01` trouvé dans le repo.
   ⇒ Soit nft géré hors rôle hardening, soit config manuelle dérivée. **Appliquer le rôle
   tel quel risque de supprimer `100.64/10` et de casser l'accès Teleport/Tailscale.**
   À investiguer **avant** d'inclure bastion01 dans le run.
3. **dc01 déjà conforme `/60`** (et seul porteur de la clé `awx-runner`) → hors scope du run,
   sert de référence "cible atteinte".
4. **vpn-gw01** : seul écart = `/60` manquant (le reste de son allowlist host_vars matche le
   live). Run le plus "propre" / additif des 6.
5. **Clé `root@proxmox`** encore présente sur app01 & vpn-gw01 : à rationaliser une fois AWX
   en place (Proxmox n'est pas/plus control plane).
6. Les sets `@addr-set-sshd reject` (db01, backup01) = blocklist SSH dynamique : sans effet
   sur l'ajout `/60`, mais à connaître.
