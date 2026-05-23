# Runbook -- Etendre l'allowlist nft VLAN 60 ADMIN -> :22 sur la flotte

Ticket : T-AWX-NFT-ALLOWLIST. ADR : [`ADR-0032`](adr/ADR-0032-T-AWX-NFT-ALLOWLIST-option-A.md).
Pre-flight de decouverte : [`access-matrix.md`](access-matrix.md).

**Objectif** : autoriser la source AWX `192.168.60.0/29` vers `:22` dans le pare-feu local
nftables des VMs gerables, en re-jouant le role `hardening` (tag `firewall`), **sans casser
les regles existantes** (drift modelise au prealable).

> ATTENTION -- le template `nftables.conf.j2` commence par `flush ruleset` : **chaque run
> REECRIT integralement le ruleset de l'hote**. Ce n'est pas un ajout chirurgical. Ne jamais
> lancer sans dry-run `--check --diff` et sans snapshots.

## Scope

| Lot | VMs | VMID | IP cible | Methode |
|---|---|---|---|---|
| **Batch (5 VMs)** | fs01 | 104 | 192.168.20.11 | role `hardening:firewall` non-interactif |
| | db01 | 105 | 192.168.20.12 | idem |
| | app01 | 106 | 192.168.20.13 | idem |
| | backup01 | 109 | 192.168.50.2 | idem |
| | vpn-gw01 | 110 | 172.16.1.4 | idem |
| **Manuel** | bastion01 | 102 | 192.168.15.2 | intervention dediee (sudo MFA) -- section 6 |
| **Hors scope** | dc01 | -- | 192.168.20.10 | deja `/60` (reference) |

État repo (FAIT, pushe, CI green) :
- `host_vars/app01.yml` : allowlist etroite + `/60` + **regles de service capturees**.
- `host_vars/bastion01.yml` : allowlist live (Tailscale incl.) + `/60`.
- `host_vars/vpn-gw01.yml` : allowlist large + `/60` + WireGuard.
- `host_vars/fs01.yml`, `db01.yml`, `backup01.yml` : **pas d'override** -> heritent
  `group_vars/all` (`10/24,15/24,18/24,20/28,60/29`) -> convergence baseline (resorbe drift).

## 0. Pre-requis

- Repo `nova-syndicate-ansible` a jour (commit modelisation host_vars). Verifier :
  ```
  cd ~/dev/Nova-syndicate-Code/nova-syndicate-ansible
  git log --oneline -1     # doit etre le commit "feat(hardening): model app01/bastion01 nft ..."
  git status               # clean
  ```
- Acces Proxmox (pour snapshots / rollback) : `ssh proxmox-hypervisor` (alias ~/.ssh/config).
- Acces awx01 (validation E2E) : `ssh -J proxmox-hypervisor -i ~/.ssh/id_ed25519 \
  -o UserKnownHostsFile=~/.ssh/known_hosts_nova debian@192.168.60.2`.
- Le mot de passe vault ansible (le run touche du template, pas de secret, mais `site.yml`
  charge le vault) -- `--vault-password-file` ou `--ask-vault-pass` selon l'usage local.

## 1. Etablir le control plane (Mac -> bastion, ControlMaster TOTP)

Le MFA TOTP du bastion n'est demande **qu'a l'etablissement** du master ; ansible reutilise
ensuite la connexion multiplexee en non-interactif (resout le blocage AFK).

```
# Etablit/rafraichit le master ; saisir le TOTP UNE fois ici.
ssh bastion-nova true

# Confirmer que le master est actif (persist 4 h) :
ssh -O check bastion-nova        # -> "Master running (pid=...)"
```

> NE PAS fermer ce master pendant toute l'operation : il garantit un shell vivant meme si un
> run cassait l'allowlist (la source bastion 192.168.15.x reste allowlistee dans le nouveau
> ruleset, donc en principe pas de lockout -- mais on garde le filet).

## 2. Pre-flight checks (AVANT toute ecriture)

### 2.1 Joignabilite ansible non-interactive des 5 cibles
```
cd ~/dev/Nova-syndicate-Code/nova-syndicate-ansible
ansible fs01,db01,app01,backup01,vpn-gw01 -m ping
```
Attendu : `SUCCESS` (pong) pour les 5, **sans nouvelle invite TOTP** (preuve que le master
porte bien le run). Si une invite TOTP apparait ou un host echoue -> STOP, diagnostiquer
avant d'aller plus loin.

### 2.2 Capture du ruleset LIVE par hote (backup rollback rapide)
```
for h in fs01 db01 app01 backup01 vpn-gw01; do
  ansible $h -b -m shell -a "nft list ruleset > /root/nft-pre-awx-$(date +%F).bak && \
    echo backed-up:/root/nft-pre-awx-$(date +%F).bak"
done
```
Permet un rollback `nft -f` immediat sans rollback de VM complete (cf section 5).

### 2.3 Snapshots Proxmox (filet lourd)
```
ssh proxmox-hypervisor '
for vmid in 104 105 106 109 110; do
  qm snapshot $vmid pre-awx-nftallowlist-2026-05-23 \
    --description "T-AWX-NFT-ALLOWLIST avant run hardening:firewall" && \
    echo "snap OK vmid=$vmid"
done'
```
Verifier : `ssh proxmox-hypervisor 'for v in 104 105 106 109 110; do qm listsnapshot $v; done'`.

### 2.4 DRY-RUN diff -- le check critique
```
cd ~/dev/Nova-syndicate-Code/nova-syndicate-ansible
ansible-playbook site.yml --tags hardening:firewall \
  --limit fs01,db01,app01,backup01,vpn-gw01 \
  --check --diff
```
**Inspecter le diff de `/etc/nftables.conf` hote par hote** :
- app01 / vpn-gw01 : diff attendu = **uniquement l'ajout de la ligne `/60`** (allowlist
  + regles service inchangees). Si une regle de service disparait -> STOP (host_vars
  incomplet).
- fs01 / db01 / backup01 : diff attendu = convergence baseline (`15.0/29 -> 15.0/24`,
  ajout `10/24` + `18/24` + `/60`). Acte (resorption drift). Pas de suppression de service.
- Aucun hote ne doit perdre une regle non prevue.

> Si `--check` ne montre aucune tache firewall executee, verifier que le tag selectionne est
> bien `hardening:firewall` (defini sur l'include dans `roles/hardening/tasks/main.yml`).

## 3. Run reel (batch 5 VMs)

Pre-conditions : 2.1 OK, 2.2 backups faits, 2.3 snapshots faits, 2.4 diff valide.

```
cd ~/dev/Nova-syndicate-Code/nova-syndicate-ansible
ansible-playbook site.yml --tags hardening:firewall \
  --limit fs01,db01,app01,backup01,vpn-gw01 \
  --diff
```
Attendu : `changed` sur le template `/etc/nftables.conf` + handler `reload nftables` (restart
nftables) sur chaque hote. `failed=0`.

Reconstruire le set anti-bruteforce fail2ban (le `flush ruleset` l'a wipe ; benin mais
hygiene -- surtout db01/backup01 qui avaient `@addr-set-sshd`) :
```
ansible fs01,db01,app01,backup01,vpn-gw01 -b -m systemd -a "name=fail2ban state=restarted"
```

## 4. Validation E2E depuis awx01

awx01 (`192.168.60.2`) est le **vrai futur client**. Test de reachability `:22` (valide le
nft host + le chemin firewall ; independant de la cle SSH) :

```
ssh -J proxmox-hypervisor -i ~/.ssh/id_ed25519 \
  -o UserKnownHostsFile=~/.ssh/known_hosts_nova debian@192.168.60.2 \
  'for h in 192.168.20.11 192.168.20.12 192.168.20.13 192.168.50.2 172.16.1.4; do
     timeout 5 bash -c "echo > /dev/tcp/$h/22" 2>/dev/null \
       && echo "$h:22 OPEN" || echo "$h:22 BLOCKED"; done'
```
- AVANT le run : attendu `BLOCKED` (seul dc01 `192.168.20.10` etait OPEN, hors liste ici).
- APRES le run : attendu **OPEN** pour fs01/db01/app01 (VLAN 20, joints via FW-INT).
- backup01 (VLAN 50) / vpn-gw01 (DMZ) : si `BLOCKED` **alors que le nft host autorise `/60`**
  (verifier `ansible backup01 -b -m shell -a "nft list ruleset | grep 60.0/29"`), le blocage
  est au niveau **chemin firewall** (FW-INT/FW-EXT), pas du host -> finding companion
  (regle VLAN60 -> VLAN50/DMZ), hors scope de ce ticket.

Validation **auth complete** (optionnelle, depend de la cle `awx-runner`, presente sur dc01
seulement -> companion T-AWX-KEY-DEPLOY) : une fois la cle deployee, lancer un job AWX trivial
(ou `ssh -i <awx-runner> debian@<vm> hostname`) sur chaque cible.

Verif idempotence : re-jouer `ansible-playbook ... --tags hardening:firewall --limit ... --check`
-> doit etre `ok` (0 changed).

## 5. Rollback

### 5.1 Par hote, rapide (restaure le ruleset capture en 2.2)
```
ansible <host> -b -m shell -a "nft -f /root/nft-pre-awx-$(date +%F).bak && \
  cp /root/nft-pre-awx-$(date +%F).bak /etc/nftables.conf && nft list ruleset | head"
```
> NE PAS faire `systemctl stop nftables` pour "annuler" : le template fait `flush ruleset`,
> stopper le service laisse l'hote SANS table -> politique implicite accept -> tout ouvert.
> Le rollback correct REINJECTE l'ancien ruleset (`nft -f <bak>`).

### 5.2 Par VM, complet (snapshot Proxmox)
```
ssh proxmox-hypervisor 'qm rollback <vmid> pre-awx-nftallowlist-2026-05-23'
```
(VMID : fs01=104, db01=105, app01=106, backup01=109, vpn-gw01=110.) Rollback d'etat complet.

### 5.3 Si lockout total (plus aucune connexion neuve n'aboutit)
La session ControlMaster `bastion-nova` (section 1) est restee ouverte -> ouvrir un shell
multiplexe dessus (`ssh bastion-nova`), rejoindre l'hote et appliquer 5.1. Sinon : console
Proxmox (`qm terminal <vmid>` / noVNC) puis 5.1.

### 5.4 Nettoyage des snapshots (apres validation stable, J+1 a J+3)
```
ssh proxmox-hypervisor 'for v in 104 105 106 109 110; do \
  qm delsnapshot $v pre-awx-nftallowlist-2026-05-23; done'
```

## 6. Intervention manuelle dediee -- bastion01

bastion01 est **hors batch** : `become` non-interactif declenche le **sudo TOTP** (echec) et
l'allowlist atypique (Tailscale `100.64/10` + Teleport) est a fort enjeu. La config cible est
**deja modelisee** dans `host_vars/bastion01.yml`. Procedure supervisee :

1. **Session interactive root** (TOTP saisi une fois -> plus de `become` ansible requis) :
   ```
   ssh debian@192.168.15.2      # via Mac (MFA SSH TOTP)
   sudo -i                       # sudo TOTP -> shell root
   ```
   Garder cette session **ouverte** comme filet de securite jusqu'a la fin.

2. **Backup + snapshot** :
   ```
   # dans le shell root bastion01 :
   nft list ruleset > /root/nft-pre-awx-$(date +%F).bak
   tailscale status > /root/tailscale-pre-awx.txt
   ss -lntp | grep -E ':(443|3023|3024|3025)\b' > /root/teleport-pre-awx.txt
   # depuis le Mac :
   ssh proxmox-hypervisor 'qm snapshot 102 pre-awx-nftallowlist-2026-05-23 \
     --description "T-AWX-NFT-ALLOWLIST bastion01 manuel"'
   ```

3. **Appliquer la config modelisee** (au choix) :
   - **(a) Role en local, deja root** (pas de `become` -> pas de TOTP sudo) : disposer du
     repo sur bastion01 (rsync depuis le Mac ou clone), puis :
     ```
     ansible-playbook site.yml --tags hardening:firewall --limit bastion01 \
       -c local -e ansible_become=false --check --diff   # verifier le diff d'abord
     ansible-playbook site.yml --tags hardening:firewall --limit bastion01 \
       -c local -e ansible_become=false --diff            # appliquer
     ```
   - **(b) Rendu + application manuelle** (fallback si pas de repo sur bastion01) : rendre la
     cible depuis le Mac (`ansible-playbook ... --limit bastion01 --check --diff` pour LIRE le
     `/etc/nftables.conf` attendu), reporter dans le fichier, puis dans le shell root :
     `nft -f /etc/nftables.conf && systemctl reload nftables`.

   Le diff attendu = ajout `/60` uniquement (l'allowlist Tailscale + le reste sont preserves
   par host_vars ; les regles Teleport viennent de `group_vars/bastions`).

4. **Verifications CRITIQUES avant de fermer la session root** :
   ```
   nft list ruleset | grep -E '60.0/29|100.64'          # /60 present ET Tailscale conserve
   tailscale status                                      # tailnet OK (diff vs pre-awx)
   ss -lntp | grep -E ':(443|3023|3024|3025)\b'          # ports Teleport ecoutent
   ```
   - Depuis une **2e fenetre** (Mac), valider un SSH NEUF vers bastion01 ET un login Teleport
     **avant** de liberer la session root. Si KO -> `nft -f /root/nft-pre-awx-*.bak` (5.1) /
     `qm rollback 102 ...` (5.2).
   - `systemctl restart fail2ban` (reconstruire le set apres `flush ruleset`).

5. **E2E** : depuis awx01, `timeout 5 bash -c "echo > /dev/tcp/192.168.15.2/22"` -> OPEN.

## Checklist de cloture

- [ ] 5 VMs : `/60` present dans `nft list ruleset`, aucune regle de service perdue.
- [ ] E2E awx01 : fs01/db01/app01 OPEN (backup01/vpn-gw01 OPEN ou finding chemin FW note).
- [ ] Run idempotent (`--check` -> 0 changed).
- [ ] fail2ban actif sur les 5 (+ bastion01).
- [ ] bastion01 : `/60` ajoute, Tailscale + Teleport intacts (verifies en 2e session).
- [ ] Snapshots conserves jusqu'a validation stable, puis supprimes (5.4).
- [ ] Companion notes : T-AWX-KEY-DEPLOY (cle awx-runner sur les 5) + eventuel ticket
      chemin firewall VLAN60->VLAN50/DMZ -> STATUS.md / ADR-0031 dettes.
- [ ] STATUS.md : T-AWX-NFT-ALLOWLIST passe de "ABORTED / a reprendre" a "RESOLU".
