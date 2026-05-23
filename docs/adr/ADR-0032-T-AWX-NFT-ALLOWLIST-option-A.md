# ADR-0032 : T-AWX-NFT-ALLOWLIST -- ouverture VLAN 60 ADMIN -> :22 sur la flotte (option A)

- Statut : Accepte (option A). Modelisation host_vars FAITE et pushee (commit
  "feat(hardening): model app01/bastion01 nft + cleanup app_servers comment", CI green).
  Run `hardening:firewall` sur les 5 VMs + intervention bastion01 : A EXECUTER en
  session supervisee (cf runbook).
- Date : 2026-05-23
- Auteur : matthieu-rgb
- Tickets : T-AWX-NFT-ALLOWLIST (dette fille de T-AWX-DEPLOY / ADR-0031),
  precede par T-AUDIT-ACCESS-MATRIX (pre-flight de decouverte)
- Lien : [`docs/runbook-extend-nft-allowlist.md`](../runbook-extend-nft-allowlist.md),
  [`docs/access-matrix.md`](../access-matrix.md),
  [`ADR-0031`](ADR-0031-awx-operator-k3s-iam-automation.md),
  [`ADR-0015`](ADR-0015-hardening-custom-role.md),
  [`ADR-0018`](ADR-0018-mfa-totp-bastion.md)

## Contexte

ADR-0031 a deploye AWX sur un VLAN 60 ADMIN segregue (`192.168.60.0/29`, awx01 =
`192.168.60.2`). AWX pilote l'IAM AD en SSH **direct** vers les VMs cibles (cle
dediee `awx-runner`, bypass bastion documente ADR-0031 sec.7). Or chaque VM porte
un pare-feu local nftables (role `hardening`, ADR-0015) en politique `INPUT drop`.
**Seul dc01 autorise aujourd'hui `192.168.60.0/29 -> :22`** (regle ajoutee a la main
pendant T-AWX-DEPLOY, hors role). Les autres VMs gerables **bloquent la source
VLAN 60** : AWX ne peut donc piloter qu'une seule cible. C'est la dette
**T-AWX-NFT-ALLOWLIST**.

Le pare-feu local est genere par `roles/hardening/templates/nftables.conf.j2`. Point
structurant : le template commence par **`flush ruleset`** puis reconstruit une unique
table `inet filter`. Consequence : **un run du role ne fait PAS qu'ajouter une regle,
il REECRIT integralement le ruleset de l'hote**. L'allowlist SSH derive de
`hardening_allowed_ssh_nets`, les regles de service de `hardening_extra_nft_rules`.
`192.168.60.0/29` a ete ajoute au niveau `inventory/group_vars/all/vars.yml`.

Un premier essai en mode autonome (T-AFK-DETTES, 2026-05-20) a ete **ABORTED** : lancer
un role qui remplace `/etc/nftables.conf` sur 6 VMs de prod, sans supervision, via un
contournement SSH instable, viole la regle AFK (decision non triviale -> STOP). Deux
blocages techniques avaient ete identifies :

1. Le control plane historique (`ansible-playbook` depuis le Mac via ProxyJump bastion)
   exige le **MFA TOTP** du bastion (ADR-0018) -> echoue en non-interactif.
2. Le contournement (ProxyJump via Proxmox) declenchait le bug macOS
   `worker found in a dead state` (fork-safety Python/ObjC) -> ansible instable.

Reprise supervisee : d'abord un **pre-flight de decouverte** (T-AUDIT-ACCESS-MATRIX,
[`access-matrix.md`](../access-matrix.md)) qui capture l'etat **LIVE** des 7 VMs
(`nft list ruleset`, `authorized_keys`, sources de connexion). Constats critiques :

- **Drift generalise** : aucun hote n'a l'allowlist du repo. Le live est
  `15.0/29 + 20.0/28` (parfois +), le repo cible `10/24, 15/24, 18/24, 20/28, 60/29`.
  Un run reecrit donc l'allowlist (ex. `15.0/29 -> 15.0/24`, ajout `10/24` + `18/24`),
  pas seulement `/60`.
- **app01** porte des regles de **service non modelisees** (nginx 80/443, grafana 3000,
  Wazuh dashboard/indexer/API, remoted 1514 par source, Suricata 5141, syslog 514) que
  `group_vars/app_servers` declarait `hardening_extra_nft_rules: []`. Un run **les aurait
  supprimees** -> coupure monitoring.
- **bastion01** a une allowlist **atypique** (`100.64.0.0/10` Tailscale + ports Teleport
  443/3023-3025) non derivable de `group_vars`. Un run l'aurait ecrasee -> perte
  Tailscale/Teleport.
- **Proxmox** (`root@proxmox`) n'a sa cle que sur **app01 + vpn-gw01** ; il ne joint pas
  fs01/db01/backup01/bastion01 en SSH.
- **awx-runner** n'est present que sur **dc01**.

## Options evaluees

### Option A -- Discovery-first + modelisation host_vars + run cible depuis Mac->bastion (RETENUE)

Modeliser dans `host_vars/` l'etat LIVE observe des hotes qui divergent legitimement de
`group_vars` (app01 : allowlist etroite + regles service ; bastion01 : Tailscale +
Teleport ; vpn-gw01 : allowlist large DMZ) pour rendre le run **non destructif / diff
minimal**, puis re-jouer le role `hardening` (tag `firewall`) **avec un perimetre reduit**
depuis le control plane **Mac -> bastion en ControlMaster** (`bastion-nova` : TOTP saisi
**une fois**, multiplexage persiste 4 h -> ansible s'execute ensuite en non-interactif sur
la connexion deja etablie). Snapshots Proxmox prealables, validation E2E SSH depuis awx01.

- **Pour** : reste de l'IaC (source unique de verite Git, idempotent, auditable). Le
  control plane Mac->bastion **resout les deux blocages AFK** (le MFA n'est demande qu'a
  l'etablissement du master ; pas de ProxyJump Proxmox -> pas de bug fork macOS). La source
  du bastion (`192.168.15.x`) est allowlistee dans le **nouveau** ruleset de chaque cible
  -> le run ne peut pas se couper l'acces lui-meme. Le pre-flight transforme un run aveugle
  sur 6 VMs en run modelise/scope/snapshotte/valide sur 5.
- **Contre** : ne supprime pas le `flush ruleset` (toujours une reecriture complete) ;
  exige la modelisation prealable du live (travail de capture) ; bastion01 reste hors batch
  (cf cas particulier).

### Option B -- Lancer Ansible depuis Proxmox (ABANDONNEE en pre-flight)

Utiliser le clone bootstrap `/root/nova-syndicate-ansible` sur Proxmox comme controleur,
pour contourner le MFA bastion et le bug fork macOS.

- **Pour** : Proxmox porte une patte sur tous les VLANs internes, pas de MFA local,
  controleur Linux (pas de bug fork ObjC macOS).
- **Contre / cause d'abandon** : le pre-flight access-matrix (sec.4) montre que la cle
  `root@proxmox` n'est presente que sur **app01 et vpn-gw01**. Proxmox ne s'authentifie pas
  en SSH sur **fs01, db01, backup01, bastion01** (cle absente), et backup01/vpn-gw01 ne sont
  de toute facon pas joignables directement (VLAN 50 / DMZ). **Proxmox ne couvre que 1 a 2
  cibles sur 6** -> ne peut pas piloter le run sur le scope. Abandonnee **avant** toute
  action destructive (decouverte, pas echec en prod).

### Option C -- Patch manuel `nft` par VM, hors role (REJETEE)

Ajouter a la main la regle `ip saddr 192.168.60.0/29 tcp dport 22 accept` sur chaque hote
(`nft add rule ...` + persistance manuelle), sans rejouer le role.

- **Pour** : additif, chirurgical, zero reecriture du ruleset, pas de probleme de control
  plane non plus (intervention locale par VM).
- **Contre / cause de rejet** : **anti-IaC** (l'etat live diverge encore plus du repo,
  source de verite), non idempotent, non rejouable, non auditable en Git, et surtout **ne
  corrige pas la cause** : au prochain run du role hardening (inevitable), le `flush ruleset`
  ecrasera le patch manuel. On reconstruirait du drift au lieu de le resorber.

## Decision

**Option A.** Detail :

1. **Modeliser le live dans `host_vars/` pour les hotes divergents** (FAIT, pushe, CI green) :
   - `host_vars/app01.yml` : allowlist etroite observee (`15.0/29 + 20.0/28`) **+ `/60`**,
     et **toutes** les regles de service capturees dans `hardening_extra_nft_rules` (override
     volontaire ; pas d'elargissement a 10/24/15/24/18/24). `group_vars/app_servers` =
     `hardening_extra_nft_rules: []` documente (regles deplacees en host_vars : liste de
     groupe vide legitime).
   - `host_vars/bastion01.yml` : allowlist live (`15.0/29, 18.0/24, 20.0/28, 100.64/10
     Tailscale`) **+ `/60`**. Regles Teleport laissees dans `group_vars/bastions` (source
     unique, non dupliquees).
   - `host_vars/vpn-gw01.yml` : allowlist large existante **+ `/60`** ; regles WireGuard
     (51820/udp) et forward conservees.
   - fs01, db01, backup01 : **pas d'override** -> heritent `group_vars/all`. Le run les
     **converge sur la baseline documentee** (`10/24, 15/24, 18/24, 20/28, 60/29`), ce qui
     **resorbe leur drift** (live narrowed `15/29 + 20/28`). Convergence voulue, actee
     explicitement, pas une regression.

2. **Control plane** : Mac -> bastion en ControlMaster `bastion-nova` (TOTP 1x, persist 4 h).

3. **Scope reduit = 5 VMs** : **fs01, db01, app01, backup01, vpn-gw01**.
   - **dc01** : hors scope (deja `/60`, sert de reference "cible atteinte").
   - **bastion01** : hors scope automatise -> intervention manuelle dediee (ci-dessous).

4. **Validation E2E depuis awx01** (`192.168.60.2`, le vrai futur client) : reachability
   `:22` par VM (le run change le **nft host** ; l'auth SSH effective d'AWX exige en plus la
   cle `awx-runner` -- companion, hors scope nft).

## bastion01 -- cas particulier (intervention manuelle dediee)

bastion01 est **exclu du batch non-interactif** pour deux raisons cumulatives :

1. **sudo MFA** (`mfa_totp_sudo_required: true`, host_vars/bastion01 + ADR-0018) : le tag
   `hardening:firewall` exige `become` (ecrire `/etc/nftables.conf`, restart nftables).
   En non-interactif, ce `become` declenche le **challenge TOTP sudo** -> echec. Aucun
   mot de passe statique ne le contourne (c'est un OTP).
2. **Allowlist atypique a fort enjeu** : Tailscale `100.64/10` + ports Teleport. Une
   application maladroite couperait l'acces admin/zero-trust du bastion lui-meme.

Procedure : session **interactive** sur bastion01 (MFA SSH), passage root via `sudo -i`
(TOTP saisi **une fois** -> shell deja privilegie, plus de `become` ansible requis),
application de la conf **deja modelisee** (`host_vars/bastion01.yml`), reload, **puis
verification que Tailscale ET Teleport survivent AVANT de fermer la session** (la session
root reste le filet de securite). Detail dans le runbook.

## Risques et mitigations

| Risque | Mitigation |
|---|---|
| Le `flush ruleset` reecrit tout le ruleset (pas un simple ajout) | Modelisation host_vars (app01/bastion01/vpn-gw01) -> diff attendu = `+/60` uniquement ; fs01/db01/backup01 convergent sur la baseline group_vars (acte) ; **dry-run `--check --diff` obligatoire** avant le run reel |
| Coupure SSH pendant le run (lockout) | La source du bastion (`192.168.15.x`) est dans le **nouveau** ruleset de chaque cible -> auto-preservation ; **garder la session ControlMaster ouverte** tout le run (shell vivant meme si nouvelles connexions filtrees) ; capture `nft list ruleset > .bak` par hote pour rollback `nft -f` immediat |
| Perte d'une regle de service (ex. monitoring app01) | Regles capturees en host_vars AVANT le run (pre-flight) ; dry-run diff verifie l'absence de suppression |
| Etat instable / regression non rattrapable | **Snapshots Proxmox** `pre-awx-nftallowlist-2026-05-23` sur les 5 VMs (104/105/106/109/110) avant le run ; rollback `qm rollback` |
| Set dynamique anti-bruteforce `@addr-set-sshd` (db01, backup01) wipe par `flush ruleset` | Benin pour l'objectif (ADR access-matrix sec.6) ; `systemctl restart fail2ban` post-run reconstruit le set |
| bastion01 (Tailscale/Teleport) casse | Hors batch ; intervention manuelle supervisee + verif Tailscale/Teleport avant fermeture session |
| Scope trop large / aveugle | Scope reduit a 5 VMs ; dc01 reference exclue ; `--limit` strict |
| Reachability FW-INT/FW-EXT (backup01 VLAN 50, vpn-gw01 DMZ) | Le ticket ouvre le **nft host** ; si l'E2E depuis awx01 echoue au niveau **chemin firewall** (et non nft host), c'est un finding pour un ticket companion (regle de path VLAN60->VLAN50/DMZ), pas une regression du run |

## Lesson learned -- discovery-first

Le run autonome de 2026-05-20 etait **a un cheveu d'une coupure de prod** : applique tel
quel, il aurait (a) supprime les regles de monitoring d'app01, (b) ecrase l'allowlist
Tailscale/Teleport du bastion, (c) elargi silencieusement toutes les allowlists -- le tout
via un control plane (Proxmox) qui ne joignait meme pas 4 des 6 cibles. La regle AFK
(STOP sur decision non triviale) a evite l'incident.

**Principe acte** : avant tout run d'un role qui **reecrit** un etat critique (`flush
ruleset`, `/etc/nftables.conf`, regles d'acces), **capturer d'abord l'etat LIVE et le
diff vs repo** (ici via T-AUDIT-ACCESS-MATRIX). C'est le pre-flight qui a (1) revele le
drift generalise, (2) identifie app01/bastion01 comme cas a modeliser, (3) **tue
l'option B par les faits** (cle Proxmox absente sur 4/6 cibles) au lieu de la decouvrir en
prod, (4) reduit le scope de 6 a 5 VMs + 1 cas manuel. L'IaC ne dispense pas de connaitre
l'etat reel ; sur une flotte ayant derive, **on modelise le live avant de re-appliquer le
desire**.

## Consequences

**Positives** : AWX (VLAN 60) pourra atteindre les VMs gerables une fois `/60` ouvert ;
le drift nftables des hotes touches est resorbe et **modelise dans Git** (fin du "live !=
repo") ; le pattern "pre-flight access-matrix avant run destructif" est reutilisable.

**Negatives / dettes residuelles** :
- L'ouverture `/60` est **necessaire mais pas suffisante** pour qu'AWX se connecte : la cle
  publique `awx-runner` doit aussi etre deployee sur les 5 cibles (presente sur dc01
  uniquement) -> **companion T-AWX-KEY-DEPLOY** + onboarding inventory AWX.
- backup01 (VLAN 50) et vpn-gw01 (DMZ) peuvent exiger une **regle de chemin firewall**
  VLAN60 -> VLAN50/DMZ (a confirmer par l'E2E).
- La cle `root@proxmox` reste sur app01 & vpn-gw01 -> a rationaliser (Proxmox n'est plus
  control plane d'orchestration).
- bastion01 reste un point de friction operationnel (toute reconfig nft passe par une
  intervention manuelle MFA).

## References

- ADR-0031 (AWX / VLAN 60 ADMIN, dette T-AWX-NFT-ALLOWLIST) :
  `docs/adr/ADR-0031-awx-operator-k3s-iam-automation.md`
- ADR-0015 (role hardening custom, `hardening_extra_nft_rules`) :
  `docs/adr/ADR-0015-hardening-custom-role.md`
- ADR-0018 (MFA TOTP bastion sudo + SSH) : `docs/adr/ADR-0018-mfa-totp-bastion.md`
- Pre-flight de decouverte : `docs/access-matrix.md`
- Runbook d'execution : `docs/runbook-extend-nft-allowlist.md`
- Role : `nova-syndicate-ansible/roles/hardening/` (template `nftables.conf.j2`,
  task `firewall.yml`)
- Vars : `inventory/group_vars/all/vars.yml`, `host_vars/{app01,bastion01,vpn-gw01}.yml`
