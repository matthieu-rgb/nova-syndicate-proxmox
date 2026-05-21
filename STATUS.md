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
- **T-AWX-NFT-ALLOWLIST** : nft host de chaque VM geree doit autoriser VLAN 60 -> :22 (fait sur dc01 seulement).
- **T-AWX-VAULT-INVENTORY** : `vault_default_user_password` non charge dans les jobs AWX (inventory DB-backed).
- **T-AWX-BULK-ROTATE-DRY-RUN** : variante `users_rotate_test.yml` filtre `OU=Test`.
- **T-AWX-IAM-SPACES-FIX** : bug playbooks grant/revoke sur groupes avec espace (repo nova-syndicate-ansible, session dediee).
- **T-WAZUH-LOGCOLLECTOR-DC01** : INVESTIGUEE 2026-05-21 -- root cause INDETERMINEE (voir Dettes resolues).
- **T-AWX-AUDIT-ATTRIBUTION** : audit "by root" au lieu de l'utilisateur AWX/AD.
- **T-AWX-RBAC** (Phase 8) : Teams IT-Officers/IT-Admins + LDAP team mapping + workflow onboarding.

### Dettes resolues (T-AFK-DETTES-2026-05-20)
- **T-K3S-DISABLE-TRAEFIK** : RESOLU 2026-05-21. traefik desactive sur K3s awx01 (`disable: [traefik]`, cf `files/awx/k3s-config.yaml`). ~190 MB RAM economises. nginx app01 reste le reverse proxy.
- **T-WAZUH-LOGCOLLECTOR-DC01** : INVESTIGUEE 2026-05-21, **root cause INDETERMINEE**. Remediee (restart, logcollector stable 6h+, pipeline audit valide CHECKPOINT 8).
  - Evidence : dernier evenement systemd = restart du 18/05 19:44 (changement ossec.conf, logcollector demarre OK alors). Mort ulterieure SANS trace : daemons independants du unit `active(exited)`, pas de reboot (uptime depuis 07/05), pas d'OOM, `ossec.log` pre-crash tronque au restart (non rotate/preserve).
  - Sous-findings (nouvelles dettes filles) :
    - **T-WAZUH-AUDIT-LOCALFILE-DEDUP** : `/var/log/nova-iam/audit.log` declare 2x dans ossec.conf (2 blocs `<ossec_config>`) -> WARNING "duplicated" benin. Dedupe a faire (config manuelle, pas Ansible).
    - **T-WAZUH-LOGCOLLECTOR-HEALTHCHECK** : ajouter un healthcheck (timer systemd / cron) qui restart `wazuh-agent` si un daemon (logcollector) est down -- la mort n'a pas ete auto-recuperee.

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
