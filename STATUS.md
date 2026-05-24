# Nova Syndicate -- STATUS

Derniere mise a jour : 8 mai 2026

## Etat infra Proxmox

- 10 VMs Linux deployees + 10 roles Ansible appliques (`common`, `hardening`, `dc`, `fileserver`, `database`, `app`, `bastion`, `web`, `mail`, `backup`)
- Wazuh Manager + 7 agents actifs (regles NIS2 100001-100010 sur APP01)
- Tailscale OK (proxmox = 100.112.113.2)
- 4 OPNsense (deployes via Terraform Telmate/proxmox) :
  - WAN-SIMULATOR (VMID 200) : https://10.0.0.1     -- transit ISP simule
  - FW-EXT-LYON  (VMID 201)  : https://172.16.1.1   -- DMZ (web, mail)
  - FW-INT-LYON  (VMID 202)  : https://192.168.99.1 -- VLANs internes
  - FW-EXT-MRS   (VMID 203)  : https://192.168.40.1 -- LAN Marseille
- Routage Lyon -> WAN-SIM -> MRS OK (ping bidirectionnel valide)

---

## Phase II OPNsense IaC -- TERMINEE (8 mai 2026)

### Securisation acces management
- SSH par cle ED25519 dediee (`~/.ssh/nova_opnsense_ed25519`)
- Password login desactive sur les 4 firewalls
- Alias SSH dans `~/.ssh/config` : `opn-wansim`, `opn-fw-ext-lyon`, `opn-fw-int-lyon`, `opn-fw-ext-mrs`
- 1 user `terraform` dedie par firewall (groupe `admins`), 4 paires API keys stockees
  hors repo dans `~/Documents/Nova-syndicate-Code/nova-iac-secrets/`

### IaC OPNsense (Terraform browningluke 0.16)
Code dans `terraform/environments/opnsense/` (renomme depuis `lyon/` pour refleter
le scope reel des 4 firewalls).

Fichiers :
- `main.tf`        : 4 providers OPNsense (1 alias par firewall)
- `variables.tf`   : 12 variables IP/key/secret + maps VLSM et VLAN IDs
- `outputs.tf`     : urls API + plan VLSM + recap VLANs
- `aliases.tf`     : 24 aliases (networks, hosts, ports) repartis sur 4 firewalls
- `fw_int_vlans.tf`: 4 sous-interfaces VLAN 802.1Q sur FW-INT-LYON
- `fw_ext.tf`      : regles FW-EXT-LYON (10 regles : DMZ, IPsec prep, transit)
- `fw_int.tf`      : regles FW-INT-LYON (16 regles : 4 VLANs + WAN block)
- `fw_ext_mrs.tf`  : regles FW-EXT-MRS (5 regles : LAN, IPsec prep, WAN block)
- `fw_wansim.tf`   : regles WAN-SIM (3 regles : transit + WAN block)
- `terraform.tfvars` : secrets (gitignore strict)

Total : 33 ressources Terraform deployees, 1 fichier en `.bak` pour Phase IV (`wireguard.tf.bak`).

### Pattern firewall applique
Par interface : `pass` specifiques + `block all + log` final.
Trace toute denegation pour audit NIS2.

### Validations end-to-end
- `terraform plan` : 0 drift apres apply
- `pfctl -s info` : Status Enabled sur les 4 firewalls
- Ping inter-VLAN (FW-INT -> BASTION01 / DC01) : OK
- SSH management preserve sur les 4 firewalls

---

## Dette technique restante (a traiter Phase IV / VI)

### 1. NAT outbound en mode "Automatic" OPNsense
Le provider browningluke 0.16 ne supporte pas la ressource `firewall_source_nat`.
Le mode Automatic d'OPNsense couvre les besoins essentiels (NAT auto pour
les RFC1918 vers WAN). Migration en mode "Hybrid" en Phase IV pour ajouter
les regles NO-NAT du tunnel IPsec.

### 2. Routes statiques cross-site Lyon <-> MRS
La ressource `opnsense_route` existe dans le provider, mais necessite des
Gateways pre-configurees dans OPNsense que le provider ne sait pas creer.
A traiter en Phase IV : creation manuelle des Gateways, puis routes en
Terraform.

### 3. Management FW-INT-LYON sur 192.168.99.0/29 (hors VLSM)
Choix temporaire pour faciliter la phase IaC (acces preserve pendant le
deploiement). A aligner sur le plan VLSM en Phase VI (bootstrap idempotent).
**MAJ 2026-05-21 (T-AWX-DEPLOY)** : acces mgmt (`192.168.99.5/29` sur `vmbr1`
cote Proxmox) desormais **persiste** dans `/etc/network/interfaces` (etait
runtime-only, wipe par un `ifreload` -- cf ADR-0031 sec.2). Reste l'alignement
VLSM du subnet.

### 4. Tunnel IPsec FW-EXT-LYON <-> FW-EXT-MRS non configure
strongSwan present mais daemon non demarre (config heritee de GNS3 obsolete).
Regles d'autorisation UDP 500/4500/ESP deja codees en Terraform sur FW-EXT-LYON
et FW-EXT-MRS, prepare la Phase IV.

### 5. Bootstrap manuel template 9000 + interfaces Proxmox
La creation du template Debian VMID 9000 et la conf des bridges vmbr0-5 sont
manuelles. Phase VI = scripter ces operations one-shot.

### 6. tls_disable=true Vault APP01
Choix lab uniquement -- a documenter explicitement dans le rapport Phase II.

### 7. T-AWX-DEPLOY -- 6 dettes filles (detail dans ADR-0031)
- **T-AWX-VAULT-INVENTORY** : `vault_default_user_password` non charge dans les jobs AWX (inventory DB-backed).
- **T-AWX-BULK-ROTATE-DRY-RUN** : variante `users_rotate_test.yml` filtre `OU=Test`.
- **T-AWX-IAM-SPACES-FIX** : RESOLU 2026-05-21 (commit ansible 86fc623) -- voir Dettes resolues.
- **T-WAZUH-LOGCOLLECTOR-DC01** : INVESTIGUEE 2026-05-21 -- root cause INDETERMINEE (voir Dettes resolues).
- **T-AWX-AUDIT-ATTRIBUTION** : audit "by root" au lieu de l'utilisateur AWX/AD.
- **T-AWX-RBAC** (Phase 8) : Teams IT-Officers/IT-Admins + LDAP team mapping + workflow onboarding.

### 8. T-AWX-NFT-ALLOWLIST -- 7 dettes filles (session 2026-05-23/24)
- **T-AWX-VPNGW-NFT-MODEL** : **RESOLU 2026-05-24** (T-AFK-MEGA) -- allowlist `/60` appliquee sur vpn-gw01 SANS wiper `ip mangle` (mark WG, ADR-0017) ni les forward MSS clamp/`ct state`. Approche retenue (deviation justifiee de `hardening_extra_nft_tables`) : **flush chirurgical** `table inet filter` only via nouveau `hardening_nft_filter_only` (le mangle est cree dynamiquement par `wg-policy-routing.sh` PostUp en `iptables -A` non idempotent -> le modeliser aurait duplique la regle au reboot). **Bug corrige** : handler `reload nftables` etait `state: restarted` -> `ExecStop=nft flush ruleset` wipait tout ; passe en `state: reloaded` (atomique). Forward rules vpn-gw01 completees (capturees du live : 2 MSS clamp + 2 ct state, etaient incompletes). Pre-declare `table inet filter {}` corrige aussi un bug cold-boot latent. extra_nft_tables loop ajoute (feature generique). Snapshot `pre-awx-vpngw-nft-2026-05-24` (VMID 110). Dry-run conforme, run OK, idempotence 0 changed, post-checks live tous verts.
- **T-FW-VLAN60-DMZ-VPNGW-OPEN** : **NOUVELLE dette (decouverte T-AFK-MEGA)** -- E2E awx01->vpn-gw01:22 = BLOCKED, mais au PERIMETRE (OPNsense), pas au host : SYN n'atteint jamais vpn-gw01 (NFT-DROP counter=0). VLAN60 (AWX 192.168.60.0/29) -> DMZ 172.16.1.4:22 non autorise (DMZ isolee ; control awx01->dc01:22 = OPEN). A ouvrir via `terraform/environments/opnsense/` (FW-INT + FW-EXT). **Decision securite NIS2 (admin->DMZ) -> session supervisee**, non tente en AFK. Host nft vpn-gw01 est pret.
- **T-APP01-OOM-INVESTIGATION** : OOM CONFIRME (`journalctl -k -b -1` : Grafana killee par OOM-killer le 19/05 ; hang 23-24/05 cause analogue ; `Swap: 0B` sur app01).
- **T-APP01-SWAP-ADD** : **RESOLU 2026-05-24** (T-AFK-MEGA) -- 2 GB swap actif sur app01 (`/swapfile`, fstab persiste) via nouveau role `swap_file` (gate `enable_swap`/`swap_size`, inclus dans `common`). `free -h` = `Swap: 2.0Gi`. Idempotence OK (0 changed, mkswap/swapon skipped). Snapshot `pre-app01-swap-add-2026-05-24` (VMID 106). Mitigation en attendant T-SPLIT-MONITORING-VM.
- **T-SPLIT-MONITORING-VM** : **URGENT** -- sortir wazuh-indexer + la stack lourde (nginx/Authelia/Grafana/portail/wazuh-manager/filebeat/cloudflared) hors d'app01 (declenche par l'OOM confirme -- stabilite SIEM).
- **T-BASTION-TAILSCALE-CLEANUP** : retirer `100.64/10` de `host_vars/bastion01.yml` OU installer Tailscale (decision pending ; sudo MFA -> session supervisee requise).
- **T-AWX-KEY-DEPLOY** : **RESOLU 2026-05-24** (T-AFK-MEGA) -- cle publique `awx-runner` (fp `5PnAWh…`, identique a dc01) deployee sur les 5 VMs (fs01, db01, app01, backup01, vpn-gw01) via playbook `deploy_awx_runner_key.yml` + `group_vars/all/awx.yml` (nova-syndicate-ansible). Idempotence OK (0 changed au re-run), cle presente 1x/host verifiee. Acces AWX 6/6 (5 VMs + dc01).
- **T-SSH-CONFIG-DEDUP** : nettoyer le doublon dans le `~/.ssh/config` du Mac (heritage session T2 BASTION).
- **T-MAIL-WAZUH-ENROLL** : **ABORTED en AFK (T-AFK-MEGA), bloque par T-FW-DMZ-WAZUH-OPEN.** wazuh-agent 4.11.2 deja installe sur mail01 (paquet present, MAIS `/var/ossec` absent -> install incomplete a verifier), repo `wazuh.list` configure. Enrollment impossible : path DMZ->SERVERS bloque. A finaliser une fois le FW ouvert (session supervisee).
- **T-FW-DMZ-WAZUH-OPEN** : **NOUVELLE dette (T-AFK-MEGA).** mail01 (DMZ 172.16.1.3) -> app01 wazuh-manager (192.168.20.13) :1515 (enrollment) + :1514 (data) = BLOCKED au perimetre OPNsense (le host nft d'app01 autorise deja 172.16.1.0/29 sur 1514 + 1515 ouvert). A ouvrir via `terraform/environments/opnsense/` (FW-INT-LYON, DMZ->SERVERS:1514,1515). **Non tente en AFK** : `terraform plan` lent + interrompu (pas de baseline drift propre), apply perimetre = blast radius + decision NIS2 -> session supervisee. (tfvars + state presents, terraform v1.14.3 OK pour reprise.)

### Dettes resolues (T-AFK-MEGA-2026-05-24)
- **T-MAIL-TLS-WILDCARD** : **RESOLU 2026-05-24** -- mail01 (Postfix+Dovecot) sert le cert wildcard mkcert `*.nova-syndicate.local` (partage avec nginx app01) au lieu du self-signed. STARTTLS SMTP :587 + IMAP :143 = `Verify return code: 0 (ok)` (issuer mkcert CA, verify_hostname mail.nova-syndicate.local OK). Modelise dans role `mail_server` (`mail_tls_use_wildcard` + copy depuis `files/_certs-LOCAL/` gitignore) + host_vars/mail01.yml (+ symlink `inventory/host_vars/mail01.yml`). Snapshot `pre-mail-tls-wildcard-2026-05-24` (VMID 101).

### Dettes resolues (T-AFK-DETTES-2026-05-20)
- **T-AWX-NFT-ALLOWLIST** : RESOLU 2026-05-23/24 puis **host-allowlist 6/6 le 2026-05-24** (T-AFK-MEGA, vpn-gw01 via T-AWX-VPNGW-NFT-MODEL). Les 6 VMs (fs01, db01, app01, backup01, bastion01, vpn-gw01) ont `/60` dans leur nft host. **E2E :22 OPEN depuis awx01 confirme 5/6** ; vpn-gw01 reste BLOCKED au perimetre OPNsense (DMZ isolee) -> dette `T-FW-VLAN60-DMZ-VPNGW-OPEN`. Host nft du 6e pret.
- **T-K3S-DISABLE-TRAEFIK** : RESOLU 2026-05-21. traefik desactive sur K3s awx01 (`disable: [traefik]`, cf `files/awx/k3s-config.yaml`). ~190 MB RAM economises. nginx app01 reste le reverse proxy.
- **T-WAZUH-LOGCOLLECTOR-DC01** : INVESTIGUEE 2026-05-21, **root cause INDETERMINEE**. Remediee (restart, logcollector stable 6h+, pipeline audit valide CHECKPOINT 8).
  - Evidence : dernier evenement systemd = restart du 18/05 19:44 (changement ossec.conf, logcollector demarre OK alors). Mort ulterieure SANS trace : daemons independants du unit `active(exited)`, pas de reboot (uptime depuis 07/05), pas d'OOM, `ossec.log` pre-crash tronque au restart (non rotate/preserve).
  - Sous-findings (nouvelles dettes filles) :
    - **T-WAZUH-AUDIT-LOCALFILE-DEDUP** (= T-WAZUH-AUDIT-DEDUP) : **RESOLU 2026-05-24** (T-AFK-MEGA). Le 2e bloc `<localfile>` `/var/log/nova-iam/audit.log` (sur 2) retire de l'ossec.conf de dc01 (count 2->1, 2 blocs `<ossec_config>` preserves, perms conservees). Restart wazuh-agent OK, ossec.log clean, **0 WARNING "duplicated"**. Fix live one-time (le role wazuh_agent ne gere pas ce localfile -> pas de recurrence). Backup `ossec.conf.bak-prededup-2026-05-24` sur dc01.
    - **T-WAZUH-LOGCOLLECTOR-HEALTHCHECK** : **RESOLU 2026-05-24** (T-AFK-MEGA). Decouverte : l'unit wazuh-agent est `Type=forking` + `RemainAfterExit=yes` (MainPID=0) -> `Restart=always` seul NE recupere PAS un daemon enfant mort. Solution effective = **watchdog** : `wazuh-agent-watchdog.{sh,service,timer}` (timer 30s) qui restart wazuh-agent si `wazuh-control status` voit un daemon down (+ drop-in Restart=always en filet). E2E : kill `wazuh-logcollector` -> AUTO-RECOVERED via timer ~33s. Modelise dans role `wazuh_agent` (tag `wazuh:watchdog`, vars `wazuh_agent_restart_policy`/`wazuh_agent_watchdog_enabled`/`wazuh_agent_watchdog_interval`), idempotent (0 changed au re-run). Note : 1er script bugge (`set -o pipefail` + `wazuh-control status` exit!=0 -> SIGPIPE) corrige.
- **T-AWX-IAM-SPACES-FIX** : RESOLU 2026-05-21. Repo nova-syndicate-ansible commit `86fc623` : 20 appels `cmd: samba-tool ...` -> `argv:` dans les 7 playbooks IAM. Valide E2E via AWX (grant/revoke `test.spacesfix` sur "Domain Admins" -- le groupe avec espace qui echouait avant -- jobs successful, membership verifiee, cleanup count=94). AWX project synced a 86fc623.

---

## Snapshots a nettoyer (post-validation)

Snapshots Proxmox a supprimer apres validation des modifications (T-AWX-NFT-ALLOWLIST) :
- VMID 104 (fs01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 105 (db01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 106 (app01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 109 (backup01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 110 (vpn-gw01) : `pre-awx-nftallowlist-2026-05-23`
- VMID 102 (bastion01) : `pre-awx-nftallowlist-2026-05-23` (intervention manuelle)
- VMID 106 (app01) : tout snapshot precedent (`pre-awx-nftallowlist-2026-05-21` du 12:02, etc.)

---

## Roadmap

- **Phase III** : Reporting + livrables Phase II (architecture diagram a jour, doc technique docx, screenshots) -- en cours
- **Phase IV** : VPN site-to-site IPsec + WireGuard 20 agents + MFA TOTP
- **Phase V** : Bastion zero-trust (post-WireGuard)
- **Phase VI** : Bootstrap script idempotent (template, bridges, OPNsense ISO, gateways)
- **Phase VII** : Cartographie auto (terraform-to-d2 ou similaire)
- **Phase VIII** : Tests pentest externes

---

## GitHub
matthieu-rgb/nova-syndicate-proxmox
