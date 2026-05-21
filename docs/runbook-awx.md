# Runbook -- AWX (Ansible Tower OSS) sur K3s

Ticket : T-AWX-DEPLOY. ADR : [`ADR-0031`](adr/ADR-0031-awx-operator-k3s-iam-automation.md).

## Acces

- **UI** : `https://awx.nova-syndicate.local` (reverse proxy nginx app01 -> NodePort 30080).
  Acces navigateur comme grafana/auth (meme wildcard cert, meme chemin reseau).
- **Login** : compte AD (LDAPS). Admin local `admin` (mdp dans vault `vault_awx_admin_password`, no_log).
- **Shell awx01** : `ssh -J proxmox-hypervisor -i ~/.ssh/id_ed25519 -o UserKnownHostsFile=~/.ssh/known_hosts_nova debian@192.168.60.2`
  (le bastion = MFA, inutilisable pour l'automation ; passer par le ProxyJump Proxmox).
- **kubectl** : `sudo kubectl ...` sur awx01 (kubeconfig `/etc/rancher/k3s/k3s.yaml`).

## Architecture

- VM `awx01` (VMID 111), VLAN 60 ADMIN 192.168.60.2/29, 8 GB / 4 vCPU / 50 GB, `cpu: host`.
- K3s v1.35 single-node (traefik **DESACTIVE** -- `disable: [traefik]` dans `/etc/rancher/k3s/config.yaml`, cf `files/awx/k3s-config.yaml` ; le RP est nginx app01, `ingress_type: none`. ~190 MB RAM economises, T-K3S-DISABLE-TRAEFIK).
- AWX Operator 3.2.1 (helm release `awx-operator`, ns `awx`) -> AWX 24.6.1.
- Pods (ns `awx`) :
  - `awx-operator-controller-manager` (operateur, 2 conteneurs)
  - `awx-postgres-15-0` (StatefulSet, PVC 8Gi `local-path`)
  - `awx-web` (3 conteneurs : redis, awx-web, rsyslog) -- UI/API
  - `awx-task` (4 conteneurs : redis, awx-task, awx-ee, rsyslog) -- execution
  - `automation-job-*` (ephemeres, 1 par job, image EE `awx-ee:latest`)
- Service NodePort `awx-service` 80:30080.

Verif sante : `sudo kubectl get pods -n awx` (tous Running) ;
`curl -s http://localhost:30080/api/v2/ping/` (JSON) depuis awx01.

## Objets AWX

- Organization `Nova Syndicate`.
- Credentials : `awx-scm-nova` (deploy key GitHub ro), `nova-ansible-vault-pass`
  (vault), `nova-debian-ssh` (cle awx-runner-ssh + sudo).
- Project `Nova-IAM` (git `ssh://git@ssh.github.com:443/matthieu-rgb/nova-syndicate-ansible.git`,
  branch main, update-on-launch).
- Inventory `Nova-Lyon` (group `domain_controllers` -> dc01).
- Job Templates : `iam-user-create`, `iam-user-delete`, `iam-user-enable`,
  `iam-user-grant-privilege`, `iam-user-revoke-privilege`, `iam-user-reset-password`,
  `iam-users-rotate-bulk` (defaut `job_tags=dry-check`).

## Procedures jour-le-jour

### Ajouter un utilisateur AD
UI > Templates > `iam-user-create` > Launch. Survey : first name, last name,
email (optionnel), AD groups (multiselect -- valeurs reelles : Users,
Commerciaux, Marseille-Staff... PAS Users-Lyon qui n'existe pas), initial
password. Le user est cree avec must-change-at-next-login.

### Activer / desactiver / reset / privileges
Templates `iam-user-enable`, `iam-user-delete` (defaut = DISABLE soft,
retention 90j NIS2), `iam-user-reset-password` (output_password = "true"/"false"
en STRING), `iam-user-grant-privilege` / `iam-user-revoke-privilege`
(group_target SANS espace tant que T-AWX-IAM-SPACES-FIX n'est pas faite).

### Bulk rotate (prudence)
`iam-users-rotate-bulk` est en `job_tags=dry-check` par defaut (liste seulement,
ne modifie rien). Pour une rotation reelle : changer `job_tags` -> `bulk-rotate`
au lancement (action deliberee). Necessite la resolution de T-AWX-VAULT-INVENTORY
(le playbook lit `vault_default_user_password`).

### Ajouter une cible a l'inventory
Pre-requis : le nft host de la VM cible doit autoriser `192.168.60.0/29 -> :22`
(cf T-AWX-NFT-ALLOWLIST). Puis UI > Inventories > Nova-Lyon > Hosts (ou groupe
correspondant au `hosts:` du playbook) + variable `ansible_host`.

### Ajouter / modifier un playbook (GitOps flow)
1. Commit + push sur `github.com/matthieu-rgb/nova-syndicate-ansible` (branch main).
2. UI > Projects > Nova-IAM > Sync (ou auto via update-on-launch).
3. Pour un nouveau playbook : creer un Job Template (Project Nova-IAM, le
   playbook, Inventory Nova-Lyon, credentials `nova-debian-ssh` + `nova-ansible-vault-pass`,
   survey matchant les vars du playbook). Verifier l'interface AVANT (vars
   requises, `hosts:`, become).

## Disaster recovery

### Re-sync / redeploy AWX (config CR)
`sudo kubectl apply -f /home/debian/awx/awx-cr.yaml` ; l'operateur reconcilie.
Suivre : `sudo kubectl rollout status deployment/awx-web -n awx`.

### Backup PostgreSQL (donnees AWX : JT, creds chiffres, jobs)
```
sudo kubectl exec -n awx awx-postgres-15-0 -- bash -lc \
  'pg_dump -U $POSTGRES_USER $POSTGRES_DB' > awx-pg-$(date +%F).sql
```
A planifier (cron / borg). Inclut les credentials chiffres par la
`SECRET_KEY` AWX (secret `awx-secret-key` ns awx -- a sauvegarder AUSSI,
sinon les creds sont irrecuperables).

### Rebuild awx01 from scratch
1. Re-cloner le template : `qm clone 9000 111 ... --cpu host`, NUMA on, net0
   vmbr1 tag=60, ip 192.168.60.2/29, **online la RAM hotplug** (udev rule +
   `memhp_default_state=online` GRUB).
2. Reinstaller K3s + Helm + AWX Operator + appliquer `awx-cr.yaml`.
3. Restaurer le secret `awx-secret-key` PUIS le dump PostgreSQL (sinon les
   credentials stockes sont illisibles).
4. Reconfigurer LDAP (Settings API) + reattacher la deploy key SCM.

### Snapshots de reference
`pre-k3s-2026-05-20`, `pre-awx-nginx-2026-05-20` (app01),
`pre-awx-ldap-2026-05-20` / `post-checkpoint-8-batch-2026-05-20` (dc01).

## Gotchas connus
- 1er job lent (~5 min) : pull EE `awx-ee:latest`. Suivants : cache.
- Survey multiplechoice : valeurs en STRING ("true"), pas bool JSON.
- LDAPS par IP -> cert non valide volontairement (OPT_X_TLS_REQUIRE_CERT:0).
- Login FQDN -> exige CSRF_TRUSTED_ORIGINS (deja dans le CR).
- Voir les 6 dettes filles dans ADR-0031.
