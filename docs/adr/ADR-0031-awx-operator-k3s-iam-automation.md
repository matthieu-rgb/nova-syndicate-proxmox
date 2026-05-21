# ADR-0031 : AWX Operator sur K3s -- automation IAM (VLAN 60 ADMIN)

- Statut : Accepte (deploiement complet : K3s + AWX 24.6.1 + LDAP + 7 job templates IAM + pipeline audit Wazuh valide)
- Date : 2026-05-20 / 2026-05-21
- Auteur : matthieu-rgb
- Tickets : T-AWX-DEPLOY (DETTE-014)
- Lien : voir [`docs/runbook-awx.md`](../runbook-awx.md), [`scripts/opnsense-api/assign-vlan60-admin.sh`](../../scripts/opnsense-api/assign-vlan60-admin.sh)

## Contexte

L'IAM AD etait industrialise via 7 playbooks Ansible (ADR-0027) lances a la
main depuis le poste admin. Objectif T-AWX-DEPLOY : exposer ces playbooks via
AWX (Ansible Tower OSS) pour : self-service controle (RBAC), audit centralise,
authentification AD, et suppression du "ansible-playbook depuis le Mac".

AWX deploye sur K3s single-node dans une VM dediee, UI via reverse proxy nginx
app01, authentification LDAP directe sur le DC Samba.

## Decision

VM dediee `awx01` (VMID 111, Debian 12, 8 GB / 4 vCPU / 50 GB) sur un **nouveau
VLAN 60 ADMIN** segregue. K3s v1.35 + AWX Operator 3.2.1 (AWX 24.6.1). UI sur
`https://awx.nova-syndicate.local` (reverse proxy nginx app01 -> NodePort 30080).
Auth LDAPS sur dc01. SSH direct AWX -> VMs cibles (cle dediee).

## 1. Plan admin segregue du plan SERVERS (NIS2 art.21)

VLAN 20 SERVERS (/28) etait quasi sature et melange les workloads metier
(DC/FS/DB/APP) avec ce qui serait le plan d'orchestration. Decision : creer
`VLAN 60 ADMIN` (192.168.60.0/29, gw 192.168.60.1 sur FW-INT-LYON opt5) pour
heberger AWX et les futurs outils d'ops.

Justification NIS2 art.21 (segmentation) : isoler le plan d'administration
(orchestration, secrets d'execution) du plan applicatif. Une compromission
d'une VM metier ne donne pas acces au plan AWX et reciproquement, sauf flux
explicitement autorises et journalises sur FW-INT-LYON (regles A5).

Implementation : VLAN 60 cree en Terraform (`opnsense_interfaces_vlan` tag 60
sur vtnet1 + aliases `net_lyon_admin`, `host_awx01`), interface OPT5 assignee
manuellement (l'API OPNsense 25.1 n'expose pas l'assignation d'interface --
endpoints 404, cf `scripts/opnsense-api/assign-vlan60-admin.sh`), puis 5 regles
filter (LDAPS+DNS+NTP vers dc01, SSH vers VLANs internes, HTTP/HTTPS sortie,
block+log).

## 2. Incident vmbr1 / ifreload + restore IP mgmt 192.168.99.5

En ajoutant le VLAN 60 au trunk `vmbr1` (bridge-vids), un `ifreload -a` sur
Proxmox a **supprime une IP runtime non persistee** : `192.168.99.5/29` sur
`vmbr1` (untagged), qui etait le SEUL chemin d'acces mgmt de Proxmox vers la
LAN OPNsense FW-INT (192.168.99.1). Symptome : timeout total ping/SSH/API vers
.99.1, paquets fuyant vers le default gw (traceroute -> IP publiques).

Cause racine : `vmbr1` declare `inet manual` (sans address), l'IP .99.5 ajoutee
a la main en J0 jamais persistee. `ifreload` reconcilie l'etat live a la config
-> wipe.

Remediation + cloture dette : `192.168.99.5/29` desormais **persiste** dans
`/etc/network/interfaces` (`iface vmbr1 inet static`, commentaire "NE PAS
SUPPRIMER"). Lecon : toute IP/route mgmt runtime DOIT etre persistee avant tout
`ifreload`.

## 3. Acces mgmt awx01 : leg L2 vs route statique

Le Mac et Proxmox ne routent pas vers VLAN 60 par defaut. Pour permettre
l'install K3s/AWX et les ops, deux options :
- (a) leg L2 : Proxmox porte `vmbr1.60 = 192.168.60.3/29` (coherent avec les
  legs existants .15/.20/.30/.50/.99).
- (b) route statique via FW-INT (192.168.20.1) -- traverse le firewall.

**Decision : (a) leg L2**, persiste dans `/etc/network/interfaces`. Justification :
coherence avec les autres VLANs + simplicite operationnelle pour les phases
d'install. **Ce n'est PAS un bypass de la segmentation NIS2** : Proxmox est le
plan technique hypervisor (il porte deja une patte sur tous les VLANs internes
et peut console n'importe quelle VM) ; AWX reste segmente fonctionnellement.
Acces ops : `ssh -J proxmox-hypervisor debian@192.168.60.2`. Le bastion (MFA
TOTP) reste inutilisable pour l'automation non-interactive.

## 4. CPU host requis (postgres 15 x86-64-v2)

Le pod postgres-15 d'AWX crashait : `Fatal glibc error: CPU does not support
x86-64-v2`. La VM utilisait le modele CPU Proxmox par defaut `kvm64` (pas de
SSE4.2/POPCNT). Les images conteneur modernes (postgres 15) exigent le
baseline x86-64-v2.

Decision : `qm set 111 --cpu host` (passthrough du Ryzen 9 9900X de l'hote).
Single-node Proxmox -> pas de contrainte de migration. Power-cycle requis
(les donnees PVC sont preservees).

## 5. SSH-over-443 GitHub (egress 80/443 only)

Les regles A5 limitent l'egress ADMIN a 80/443 (pas de :22 sortant). Le clone
SCM du repo prive `nova-syndicate-ansible` par cle deploy SSH (`git@github.com:22`)
est donc bloque (confirme : timeout). Solution : **SSH-over-443 via
`ssh.github.com:443`** (supporte par GitHub), URL SCM
`ssh://git@ssh.github.com:443/matthieu-rgb/nova-syndicate-ansible.git`. Aucune
modification firewall, egress reste verrouille 80/443. Project sync valide E2E.

## 6. LDAPS par IP + OPT_X_TLS_REQUIRE_CERT:0 (compromis)

Config LDAP AWX : `ldaps://192.168.20.10:636` (IP directe, evite la resolution
DNS flaky depuis les pods). Consequence : le CN du certificat Samba
(`dc01.nova-syndicate.local`) ne matche pas l'IP -> validation cert impossible.
Compromis : `AUTH_LDAP_CONNECTION_OPTIONS = {OPT_X_TLS_REQUIRE_CERT:0,
OPT_X_TLS_NEWCTX:0}` (connexion TLS chiffree, cert non valide). Acceptable car
le flux est verrouille `:636` vers dc01 uniquement et journalise (regle A5 +
nft DC ouvert sur les ports AD). Search base corrigee : `DC=nova-syndicate,
DC=local` SCOPE_SUBTREE (il n'existe PAS d'OU=Employees ; users sous OU=Lyon /
OU=Marseille). `AUTH_LDAP_GROUP_SEARCH` obligatoire (sinon erreur "GROUP_SEARCH
must be an LDAPSearch instance"). Login via FQDN -> `CSRF_TRUSTED_ORIGINS`
ajoute dans le CR `extra_settings`.

## 7. Trust boundary AWX (cle dediee, bypass bastion)

AWX accede en SSH **direct** aux VMs cibles, sans passer par bastion01 + MFA.
Le bastion sert les humains (MFA TOTP, audit interactif) ; AWX est le plan
d'orchestration et doit paralleliser sans interaction. C'est la pratique
industrielle standard (Red Hat Ansible Tower).

Mitigations en place :
1. **Cle SSH dediee `awx-runner-ssh`** (ed25519, jamais de cle humaine ni cle
   bastion), PRIVEE dans la Machine credential AWX `nova-debian-ssh`, PUBLIQUE
   dans `authorized_keys` debian des cibles. User `debian` (NOPASSWD sudo).
2. **RBAC AWX** (Phase 8 T-AWX-RBAC) : Teams mappees aux groupes AD, job
   templates restreints par team.
3. **Audit centralise** : chaque playbook ecrit dans
   `/var/log/nova-iam/audit.log` -> Wazuh (rules 100400 lifecycle L3, 100401
   HARD_DELETE L10, 100402 GRANT L8). Pipeline AWX -> dc01 -> Wazuh **valide E2E**
   (CHECKPOINT 8 etendu).
4. **nft host par VM** : chaque cible doit autoriser SSH depuis VLAN 60 (fait
   sur dc01 ; cf dette T-AWX-NFT-ALLOWLIST).

## Tests valides (CHECKPOINT 8 etendu, 2026-05-21)

- iam-user-create E2E (user cree, attributs AD, audit, must-change).
- iam-user-enable (514 -> 512), grant -> revoke (pair reversible, Commerciaux),
  reset-password (output_password + force-change), delete soft (DISABLE
  retention 90j). Tous audites + verifies + cleanup (count revient a 94).
- iam-users-rotate-bulk : cree avec `job_tags=dry-check` par defaut (securite),
  NON execute (touche 81 users -- cf dette).
- Pipeline audit Wazuh valide (rule 100400 sur CREATE).

## Dettes filles ouvertes

| Ticket | Description |
|---|---|
| T-AWX-NFT-ALLOWLIST | Le nft host de CHAQUE VM geree doit autoriser `192.168.60.0/29 -> :22` (fait sur dc01 uniquement). A integrer dans la role hardening (allowlist SSH) pour fs01/db01/app01/etc. |
| T-AWX-VAULT-INVENTORY | Les `group_vars/all/vault.yml` du repo ne se chargent pas auto dans les jobs AWX (inventory DB-backed) -> `vault_default_user_password` indefini. Contourne au test via `user_initial_password` explicite. Resoudre via project extra_vars / custom credential type. |
| T-AWX-BULK-ROTATE-DRY-RUN | Creer une variante `users_rotate_test.yml` avec filtre `OU=Test` pour tester bulk-rotate sans toucher la prod. |
| T-AWX-IAM-SPACES-FIX | Bug playbooks grant/revoke : `cmd: "samba-tool group show {{ group_target }}"` casse sur les groupes avec ESPACE ("Domain Admins"). Passer en `argv:`. Repo `nova-syndicate-ansible`, session dediee avec tests. |
| T-WAZUH-LOGCOLLECTOR-DC01 | `wazuh-logcollector` etait arrete sur dc01 (pre-existant) -> audit.log non forwarde. Redemarre. Investiguer la cause (crash ? boot ?) + monitoring du daemon. |
| T-AWX-AUDIT-ATTRIBUTION | L'audit log montre "by root" (user become), pas l'utilisateur AWX/AD qui a lance le job. Le playbook devrait consommer la var `awx_user_name` injectee par AWX. |

## Cloture dette pre-existante

- **Dette mgmt-hors-VLSM #3** (cf STATUS.md) : l'acces mgmt FW-INT via .99.5 est
  desormais persiste cote Proxmox (point 2). Reste : aligner 192.168.99.0/29 sur
  le plan VLSM (hors scope T-AWX-DEPLOY).
