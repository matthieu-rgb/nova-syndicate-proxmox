# Nova Syndicate -- STATUS

Derniere mise a jour : 3 juin 2026 (menage services failed + Borg cron confirme)

## Session 2026-06-03 -- audit sante + menage services failed -- 13/13 VMs propres

Audit complet runtime + remise en marche avant session captures jury.
Diagnostic lecture seule puis reparations ciblees apres validation.

### Resultat ménage (13/13 VMs avec 0 service failed)

| Action | Cibles | Effet |
|--------|--------|-------|
| `systemctl disable --now openipmi` + reset-failed | 10 VMs (web01, mail01, bastion01, dc01, fs01, db01, app01, proxy-lyon01, proxy-mrs01, backup01) | LSB OpenIPMI driver desactive (hardware inexistant sur VM, BENIN). 3 VMs sans le paquet (vpn-gw01, awx01, pki01). |
| `systemctl disable --now isc-dhcp-server` + reset-failed | dc01 | Service ne pouvait pas servir (subnet declare 192.168.30.0/26 VLAN Users mais dc01 = eth0 192.168.20.10/28 VLAN 20). JAMAIS-FINALISE. -> dette **T-DHCP-USERS-VLAN** ouverte. |
| `systemctl reset-failed cloud-final` | pki01 | Echec one-shot APT update au 1er install (1er juin, DNS template 9000 KO). step-ca tourne. Etat failed historique nettoye. |
| drop-in `/etc/systemd/system/dnsmasq.service.d/wait-wg0.conf` (`After=wg-quick@wg0.service` + `Requires=`) + restart | vpn-gw01 | Race condition systemd resolue : dnsmasq tente de bind 10.20.0.1 avant wg0 up. Persiste au reboot. -> dette **T-DNSMASQ-WG0-ORDERING** marquee RESOLUE. |

Verification finale : `systemctl --failed --no-legend | wc -l` retourne `0` sur les 13 VMs Linux.

### Borg backups -- correction de diagnostic

Diagnostic initial Phase 1 erronne ("borgbackup-nova.timer inactive"). En realite :
- **Le timer systemd N'EXISTE PAS**. La planification est via cron classique :
  `/etc/cron.d/borg-cloud-backup : 30 23 * * * root /usr/local/bin/borg-cloud-sync.sh ...`
- **Le backup CLOUD vers Hetzner FONCTIONNE deja** (preuve dry-run 2026-06-03 12:57) :
  - Tunnel WireGuard backup01 (10.30.0.2) -> Hetzner (10.30.0.1) actif (handshake 1 min 39 s avant le check).
  - 5 archives sur le VPS, dont **backup01-2026-06-02-2330** (hier soir).
  - Ping 37 ms, transfer 603 KiB recus + 3.37 MiB envoyes (compteur live).

**Dette T-IAC-BORG-ROLE** (audit catégorie B EVOLUTIONS) reste valide UNIQUEMENT pour la dimension "role Ansible reproductible". Le DRP runtime est operationnel des aujourd'hui.

### Precisions IPsec Phase II §4 -- "daemon non demarre" -> "package non installe"

Diagnostic SSH FW-EXT-LYON via `-J opn-fw-int-lyon root@10.0.1.1` confirme :
- `charon: Command not found` (binaire absent du PATH).
- `pgrep charon` = vide.
- `swanctl --list-sas` et `--list-conns` = vides.
- `last reboot` depuis 2026-05-07 -- aucune trace de demarrage strongswan.
- ping FW-EXT-LYON -> 10.0.2.2 (WAN MRS) ou 192.168.40.1 (LAN MRS) : 100 % packet loss.

**STATUS Phase II §4 ("strongSwan present mais daemon non demarre") etait imprecis** :
le binaire `charon` n'est meme pas installe. C'est plus profond qu'un service down.
Effort de remise en service Phase IV = install pkg + cert step-ca + swanctl.conf x 2 firewalls.

FW-EXT-MRS non sonde directement (reseau coupe, chaine SSH cassee). Posture presumee identique.

### Services metier critiques au jour de cette session

13/13 services actifs (cf [docs/health-snapshot-2026-06-03.md](docs/health-snapshot-2026-06-03.md)
pour le detail visuel). Aucune regression metier detectee.

### Snapshots Proxmox a nettoyer (apres validation finale par l'operateur)

Snapshots filets pris avant le menage du 3 juin :
- VMID 103 (dc01) : `dc01-pre-menage-failed-services-20260603` (2026-06-03 12:52:22)
- VMID 110 (vpn-gw01) : `vpn-gw01-pre-dnsmasq-ordering-20260603` (2026-06-03 12:52:22)

A supprimer apres :
1. Confirmation que les changements (openipmi/isc-dhcp/dnsmasq drop-in) tiennent au reboot.
2. Aucune regression detectee lors de la session captures jury.

Snapshots residuels des sessions precedentes a nettoyer egalement (cf STATUS sections 2026-06-02 et plus anciennes) :
- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (2026-06-02 09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps`, `dc01-pre-strong-auth`, `dc01-pre-iac-reformat-smbconf`
- 5 snapshots dc01 cumules en moins de 24 h, a nettoyer en lot.

## Session 2026-06-02 -- audit IaC READ-ONLY -- tickets ouverts

Audit lecture seule de la couverture IaC vs runtime reel : 17 VMs + 4 OPNsense,
3 dirs Terraform, 20 roles Ansible, 34 ADRs. Livrable :
[docs/iac-coverage-audit-2026-06-02.md](docs/iac-coverage-audit-2026-06-02.md).

Couverture mesuree : **~75 % en volume / ~30 % en sequencabilite** (chaine
rebuild enchainable). 8 ruptures identifiees dont 5 manuels irreductibles
(install PVE, OPNsense ISO+1er boot, OPNsense API keys, step-ca Root CA init,
Vault un-sealing). Posture realiste = "une commande par phase" atteignable en
4-6 semaines de chantiers M.

Tickets ouverts a partir de l'audit, scindes en deux categories :

### Categorie A -- CORRECTIONS (bugs reels a fixer)

| Ticket | Severite | Description | Reference |
|--------|----------|-------------|-----------|
| **T-IAC-SITE-YML-ETAPE-7** | LOW | `nova-syndicate-ansible/site.yml` ligne 59 : ETAPE 7 ("VPN WireGuard + IPsec") cible `hosts: domain_controllers` au lieu de `vpn_gateways`. Probable copier-coller. Aucun apply recent n'a tourne cette etape (sinon dc01 aurait recu une config WireGuard). Trivial a corriger : changer une ligne + verifier en `--check`. | Audit §3.2 (anomalie ETAPE 7) |
| **T-IAC-WIREGUARD-DRIFT** | MEDIUM | Source de verite WireGuard ambigue : 3 fichiers candidats hors `nova-syndicate-proxmox` -- `nova-syndicate-ansible/terraform/environments/lyon/wireguard.tf` (910 oct, contenu), `nova-syndicate-ansible/terraform/environments/lyon/ireguard.tf` (0 oct, **typo**), `terraform/environments/lyon/wireguard.tf` (888 oct, top-level). Aucun fichier dans le repo proxmox. Decision a prendre : consolider dans `nova-syndicate-proxmox/terraform/environments/opnsense/` ou ailleurs, supprimer les duplicats et la typo. | Audit §7.1 (decouverte 2) |
| **T-IAC-CLEAN-LEGACY-TF** | LOW | Deux dirs `terraform/environments/lyon/` (sous `nova-syndicate-ansible/` et top-level) sont des orphelins Phase II pre-renommage en `opnsense/`. Pas de tfstate visible dans les deux. Recouvre partiellement T-IAC-WIREGUARD-DRIFT : nettoyer les 2 dirs ferme aussi le drift WireGuard si la source est migree avant. | Audit §3.1 (Repos legacy) |

### Categorie B -- EVOLUTIONS post-certification (chantiers de couverture, non bloquants)

Aucun de ces tickets n'est requis pour la certification. Ils ferment la dette
"reproductibilite IaC" identifiee par l'audit. Ordre suggere = ordre du tableau.

| Ticket | Effort | Valeur | Description | Reference |
|--------|--------|--------|-------------|-----------|
| **T-IAC-BRIDGES-PROXMOX-HOST** | S (~1 jour) | ELEVEE | Scripter `/etc/network/interfaces` Proxmox host (bridges vmbr0..5 + sub-VLAN .15/.20/.50/.60) via un mini-role Ansible ciblant un group `proxmox` (`ansible_user=root`). Ferme dette Phase II §5 partiellement. Risque bas (rollback `/etc/network/interfaces`). | Audit §4.1, §6.1 #1 |
| **T-IAC-TEMPLATE-9000-BUILD** | M (~3-5 jours) | ELEVEE | Scripter la creation du template Debian 12 cloud-init VMID 9000 : download cloud image -> `qm create` -> `qm importdisk` -> `qm set --ide2 cloudinit` -> customisation (fix systemd-resolved DNS cf memory `nova-cloud-init-template-dns-issue`, `qm set --sshkeys`) -> `qm template`. Cle de voute Phase VI : sans ce script, terraform apply ne tourne pas. | Audit §4.2, §6.1 #2 |
| **T-IAC-AWX01-K3S-AWX** | M (~5-10 jours) | MOYENNE | 3 sous-roles Ansible : (1) `k3s_server` (binaire + config `disable: [traefik]`, files presents dans `nova-syndicate-ansible/files/awx/k3s-config.yaml`) ; (2) `awx_operator` (helm + CR YAML) ; (3) `awx_objects` (Org + Credentials + Project + Inventory + JT + Teams + AUTH_LDAP_TEAM_MAP via API REST, cf ADR-0031/0033). Risque : objets crees a chaud, prevoir tests en sandbox. | Audit §4.9, §6.1 #3 |
| **T-IAC-AUTHELIA-ROLE** | M (~3-5 jours) | MOYENNE | Role Ansible `authelia` (install + `configuration.yml` template + secrets vault + LDAP backend ldaps://dc01:636). Touche tout l'acces SSO (Grafana, futur Wazuh dashboard, portail metier). Faible risque, gros gain narratif NIS2. | Audit §4.5, §6.1 #4 |
| **T-IAC-BORG-ROLE** | S-M (~3-5 jours) | MOYENNE | Roles `borg_repo` (backup01 cote serveur, init repo append-only) + `borg_client` (cles, exclusions, scheduling). Reference ADR-0008 (`repokey-append-only`) + ADR-0009 (3-2-1-1-0). Sans ca, le DRP est partiellement manuel. | Audit §4.6, §6.1 #5 |
| **T-IAC-APP01-STACKS-NOT-CODED** | M (par stack, MEDIUM agrege) | HIGH (NIS2 reproductibilite) | Meta-ticket : Authelia (cf T-IAC-AUTHELIA-ROLE), Grafana, Vault, nginx reverse-proxy = pas de role Ansible. ADRs 0019 (Authelia), 0030 (Grafana), 0026 (Vault plaintext fix lab) existent mais le code IaC manque. Dette importante en termes de NIS2 "reproductibilite". A decomposer en 3 sous-tickets Grafana/Vault/nginx une fois T-IAC-AUTHELIA-ROLE clos (modele de reference). | Audit §4.5, §7.1 #4 |

Chantiers explicitement **ECARTES** (effort eleve, gain nul ou anti-pattern,
detail audit §6.2) :
- step-ca Root CA init (decision humaine NIS2, irreductible)
- OPNsense ISO bootstrap + 4 API keys (limite produit, pas de cloud-init OPNsense)
- Install PVE sur le fer (pre-requis physique)
- Vault APP01 un-sealing automatique (anti-pattern securite tant que `tls_disable=true` reste choix lab)

## Session 2026-06-02 -- complement (Phase 7a) -- Strong auth applique, listener 389 conserve

Pre-check tcpdump cote serveur dc01 (eth0 any, `tcp port 389 or udp port 389`,
fenetre 90 s avec triggers : Authelia restart, mail01 doveadm, fs01 wbinfo,
samba-tool user list) : **28 paquets capturees, source unique 192.168.20.11
(fs01)** = `winbindd` (PID 12858, FD 24, ESTAB 39546->389) + CLDAP UDP.

Analyse ASN.1 du premier payload : `searchRequest base="" filter=objectclass=*
attr=currentTime` -- requete **anonyme au RootDSE** (decouverte AD standard).
Apres : bind GSSAPI/Kerberos avec `client ldap sasl wrapping = seal` (chiffrement
+ integrite). Pas un cleartext simple bind.

**Decision retenue** : decoupler Phase 7 en deux. **7a applique** (refus simple
bind cleartext) ; **7b refusee** (fermeture listener 389) car casserait winbind
fs01 jusqu'a migration sssd-ad ou Samba membre 636.

| Action | Statut | Detail |
|--------|--------|--------|
| Pre-check tcpdump cote dc01 | **DONE** | pcap archive : `docs/evidence/389-incoming-pre-strong-auth-2026-06-02.pcap` (20855 octets). |
| Snapshot `dc01-pre-strong-auth` | **DONE** | 2026-06-02 17:38:01 (VMID 103). |
| Default Samba 4.15+ deja a `Yes` -- `testparm` confirme | **DONE** | Pin explicite necessaire pour survivre aux upgrades futurs. |
| `inventory/group_vars/domain_controllers/vars.yml` : `samba_ldap_require_strong_auth: false -> true` | **DONE** | Aligne IaC (template `dc/templates/smb.conf.j2` avait deja le toggle conditionnel). |
| Edition live `/etc/samba/smb.conf` + `ldap server require strong auth = yes` sous `[global]` | **DONE** | Backup `smb.conf.bak-prestrongauth-2026-06-02`. |
| `systemctl restart samba-ad-dc` | **DONE** | `active` apres 6 s. `testparm` post-restart : `Yes`. Listeners 389 + 636 toujours presents (decision 7b assume). |
| Cross-checks 8/8 | **DONE** | fs01 wbinfo -u (94 users), wbinfo -t (trust OK), getent passwd fabien.bonnet/marine.fleury (resolu), **wbinfo -a "svc-mail-ldap%..." = plaintext + challenge/response succeeded** ; Authelia HTTP 200 ; mail01 doveadm auth succeeded ; Wazuh 8 Active ; samba-tool user list 95 lignes. |
| Phase 7b -- desactivation listener 389 | **REFUSEE (posture finale assumee)** | 389 reste ouvert, durci par strong-auth. Seuls binds GSSAPI-sealed l'empruntent (= winbind fs01). Detail ADR-0034. |

Findings clos cette session **definitivement** :
- **P-001** (bind LDAP anonyme HIGH) : **RESOLU** via `ldap server require strong auth = yes` pinne dans smb.conf. Refus simple bind cleartext applique cote dc01. Verifie effectif par testparm + cross-checks. Les binds GSSAPI-sealed (winbind) et LDAPS (Authelia + Dovecot) restent autorises.
- **P-002** (mkcert non-PKI LOW) : **RESOLU** via step-ca. mail01 et Authelia chaines sur Nova Root + Intermediate CA.
- **T-LDAPS-MIGRATION** : **CLOS**.

Nouvelle dette filiale :
- **T-FS01-LDAPS-OR-SSSD** (LOW, decision d'archi differee, hors scope certification) -- pour permettre une eventuelle fermeture future du listener 389 sur dc01 (Phase 7b), il faudrait au prealable basculer fs01 vers un client AD nativement LDAPS-capable. Trois options documentees, **aucune tranchee** :
  1. **Migration winbind -> sssd-ad** : sssd supporte nativement `ldap_uri = ldaps://dc01.nova-syndicate.local`. Refonte complete du daemon d'auth + PAM + NSS sur fs01. Effort eleve, gain principal = chemin LDAPS pur.
  2. **Reconfiguration Samba membre pour LDAPS 636** : ajuster `client ldap sasl wrapping`, `ldap server`, et resolution SRV `_ldap._tcp.NOVA-SYNDICATE.LOCAL.` pour forcer 636. Non trivial (Samba historique est cable 389+SASL), risque de regression silencieuse sur SMB join/trust.
  3. **nft allowlist 389 sur dc01** : conserver le listener 389 mais filtrer en host nft pour n'accepter que `192.168.20.11/32` (fs01) + IPs admin legit. Conserve la posture actuelle avec un perimetre reseau plus etroit. Compatible avec Phase 7a (strong auth) deja en place.

Posture finale assumee Phase 7 (a documenter dans ADR-0034) : **389 reste
ouvert, hardened par strong-auth + chiffrement GSSAPI cote winbind + listeners
distincts 389/636**. Surface d'attaque reduite a "simple bind cleartext refuse"
+ "anonymous bind limite au RootDSE". Mitigation conforme NIS2 art.21 §2 (e+i).

Snapshots Proxmox a nettoyer post-validation finale :
- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps` (09:14:04), `dc01-pre-strong-auth` (17:38:01)

ADR de cloture : [ADR-0034](docs/adr/ADR-0034-ldaps-migration-strong-auth.md).

**Drift IaC ouvert (non commit ce soir)** : `nova-syndicate-ansible/inventory/group_vars/domain_controllers/vars.yml` doit passer `samba_ldap_require_strong_auth` a `true` pour aligner l'IaC avec l'etat live dc01. Non commit cette session : la branche actuellement checked-out (`fix/wazuh-agent-pin-411-adr0013`) contient 6 autres fichiers M WIP non lies a Phase 7a + 3 dossiers untracked (`group_vars/pki/`, `roles/pki_client/`, `roles/pki_server/`). A normaliser au prochain merge sur `main` (toggle + bloc `samba_ldaps_*` keys + commentaires Phase 7a).

## Session 2026-06-02 (T-LDAPS-MIGRATION) -- Bascule trust anchor Dovecot vers step-ca

Migration LDAPS de Dovecot (mail01) de l'ancienne CA mkcert vers la chaine
PKI interne step-ca. Plan d'execution autoritatif :
[runbook-ldaps-migration.md](docs/runbook-ldaps-migration.md) (versionne
explicitement pour survivre a `/clear`). Rapport detaille :
[ldaps-migration-report.md](docs/ldaps-migration-report.md).

| Etape | Statut | Detail |
|-------|--------|--------|
| 6.3 (10 etapes) | **RESOLU** | Snapshots OK ; CA bundle deploye sur mail01 (nova-root + intermediate via `qm guest exec`) ; `update-ca-certificates` 2 added ; handshake `Verify return code: 0 (ok)` ; sed chirurgical 2 cles (`tls_require_cert demand->hard`, `tls_ca_cert_file nova-CA.crt -> ca-certificates.crt`) ; `doveadm auth test svc-mail-ldap` **AUTH SUCCEEDED** (etat AVANT : `temp_fail`, cause `Can't connect to server: ldaps://dc01:636` confirme dans dovecot.log) ; cross-checks tous verts. |
| 6.6 | **RESOLU** | tcpdump 25 s `dst dc01:389` sur mail01 + 10 binds auth generes -> **0 packets captured**. Aucun fallback LDAP cleartext applicatif. |
| Phase 7 | **STOP OBLIGATOIRE** | Desactivation listener 389 sur dc01 + `--ldap-require-strong-auth=yes` : validation manuelle requise (point de non-retour cross-clients). Snapshot dedie `dc01-pre-disable-389` a prevoir au moment de l'apply. |

Findings clos cette session :
- **P-001** (bind LDAP anonyme HIGH) : cote mail01 = plus de path 389 utilise ; cote AD = attend Phase 7.
- **P-002** (mkcert non-PKI LOW) : step-ca operationnelle, trust anchor effectif sur mail01 + Authelia.
- **T-PKI-INTERNE-CA** : root + intermediate dans system trust mail01 ; cert dc01:636 (validite 2026-06-01 -> 2027-06-01) valide.
- **T-LDAPS-MIGRATION** : RESOLU.
- **T-CLOUD-INIT-DNS** : RESOLU (pre-existant a cette session ; `/etc/hosts` statique mail01, `manage_etc_hosts: false`).

Ecart vs plan reconstruit (transparence) : l'etat de depart etait deja `uris = ldaps://...`, le delta reel = trust anchor + `tls_require_cert`. Bloc `tls = yes` du runbook **omis volontairement** (redondant/conflictuel avec `ldaps://`). Edit chirurgical sed 2 lignes, autres cles preservees. Detail dans rapport, section "Ecart vs plan reconstruit".

Snapshots Proxmox pre-changement (a nettoyer apres validation Phase 7) :
- VMID 101 (mail01) : `mail01-pre-ldaps-mail` (2026-06-02 09:14:04)
- VMID 103 (dc01) : `dc01-pre-mail-ldaps` (2026-06-02 09:14:04)

Backups configs locales mail01 (rollback de proximite, sans toucher au snapshot LVM) :
- `/etc/dovecot/conf.d/auth-ldap.conf.ext.bak-preldaps-2026-06-02`
- `/etc/dovecot/dovecot-ldap.conf.ext.bak-preldaps-2026-06-02`
- `/etc/dovecot/conf.d/10-auth.conf.bak-preldaps-2026-06-02`

Dettes decouvertes en passant :
- **T-ANSIBLE-MUX-CORRUPTION** : ControlMaster bastion-nova absent au demarrage de session (socket inexistant). Mitigation = execution via `proxmox-hypervisor` (Tailscale, pas de MFA), pattern documente en section "Voies d'acces" du runbook.
- **TCP/53 DMZ follow-up (LOW)** : `manage_etc_hosts: false` + entree `/etc/hosts` mail01 marche, mais a repliquer si autre VM DMZ doit resoudre dc01. Alternative = regle FW-INT DMZ -> dc01:53, decision a documenter.

NIS2 recalcule : auth LDAPS effectivement chainee PKI interne, `tls_require_cert = hard`, plus de mkcert dans le path d'auth -> renforce le pilier confidentialite/integrite des credentials. Wazuh = 8/8 Active (mise a jour : 8 et non 7 -- 000 app01 self-managed etait deja compte).

## Session 2026-05-27 (T-AGENTS-KEY-DEPLOY) -- PoC agents : phases intra-VM debloquees

Deploiement d'une cle SSH dediee `nova-agents` (privee sur awx01 uniquement, JAMAIS
dans le coffre AWX) pour debloquer les phases intra-VM des agents d'audit
(network-mapper A3/A4, rules-auditor Phase B), via `ProxyJump=proxmox-hypervisor`.

| Ticket | Statut | Detail |
|--------|--------|--------|
| T-AGENTS-KEY-DEPLOY | **RESOLU (partiel 4/9)** | cle deployee sur les 4 SERVERS (dc01/fs01/db01/app01) ; `authorized_keys` `from=192.168.60.0/29` + `restrict` ; sudoers NOPASSWD scoped nft. E2E OK (4 hostnames + 4 nft rulesets). |
| T-AGENTS-RULES-AUDITOR-VM-ACCESS | **RESOLU (ferme)** | Phase B nft live debloquee pour les 4 SERVERS. Reliquat -> dettes filles. |

Exclusions justifiees (security-by-design) :
- **bastion01** : exclu - le MFA TOTP reste l'autorite d'acces, aucun bypass cle (defense-in-depth NIS2).
- **DMZ (web01/mail01/vpn-gw01) + backup01** : non routables depuis le management Proxmox (seul VLAN 20 accessible) -> differe.

Donnees intra-VM (4 SERVERS) : Debian 12 ; nft host input policy = **drop** (default-deny) sur les 4 ; dc01 AD = nova-syndicate.local, **94 users** ; services confirmes (samba-ad-dc, smbd/nmbd, mariadb, nginx/authelia/grafana/wazuh/suricata). NIS2 recalcule : segmentation **9.5** (host default-deny confirme), least-privilege **6** (R-006), global **7.9**.

Nouvelles dettes (low prio) :
- **T-AGENTS-DMZ-AUDIT** -- audit intra-VM DMZ via session bastion+TOTP supervisee.
- **T-AGENTS-BACKUP-AUDIT** -- idem backup01.
- **R-006 (debian NOPASSWD:ALL sur SERVERS)** -- la cle agents est root-capable de fait (mitige par source-lock VLAN60 + restrict) ; envisager un user d'audit dedie a privileges scopes.

## Session supervisee 2026-05-25 (T-FW-PERIMETER-CLOSE) -- 4 dettes RESOLU

Cloture des 3 dettes perimetre OPNsense heritees de l'AFK (toutes sur FW-INT-LYON)
+ 1 dette fille decouverte en passant.

| Dette | Resolution | Verif E2E |
|-------|------------|-----------|
| T-FW-VLAN60-DMZ-VPNGW-OPEN | regle FW-INT `opt5` : `net_lyon_admin -> net_dmz_lyon:22` (+ alias `net_dmz_lyon`) | awx01 -> `172.16.1.4:22` = **OPEN** |
| T-FW-DMZ-WAZUH-OPEN | 2 regles FW-INT `wan` : `host_mail01 -> host_app01:1514` + `:1515` (pattern LDAP existant) | enrollment mail01 OK |
| T-MAIL-WAZUH-ENROLL | rôle ansible `wazuh_agent` rejoue sur mail01 (auto-enroll via 1515 desormais ouvert) | `agent_control -ls` = `007,mail01,any,Active` |
| T-MAIL-LDAP (dette fille) | drift detecte au plan : regle `fwint_mail01_to_dc01_ldaps` + alias `host_mail01` codes mais jamais appliques -> crees ; alias preexistant importe dans le state | state FW-INT : **0 drift** |

Notes techniques :
- Modeling Terraform : reutilisation des aliases existants (`net_lyon_admin`, `net_dmz_lyon`, `net_lyon_servers`, `host_app01`). Least-privilege NIS2 : wazuh cible `host_app01` (192.168.20.13) et non tout le /28 ; source `host_mail01` seul ; `log=true`.
- `host_mail01` existait dans OPNsense mais absent du state -> `terraform import` (UUID `cc3810e5-...`) + alignement description (in-place).
- **Hypothese NAT validee** : la regle FW-INT seule suffit pour VLAN60->DMZ (double-firewall transparent en NAT auto) -> AUCUNE regle FW-EXT necessaire.
- Fix rôle ansible `wazuh_agent` : garde `agent-auth` corrigee (le paquet livre un `client.keys` VIDE -> ancienne garde `creates:` skippait l'enrollment a tort ; nouvelle garde teste le contenu reel).
- Connectivite ce jour : seul FW-INT-LYON (192.168.99.1, via Tailscale) joignable depuis le Mac -> plan/apply **cibles FW-INT** ; 3 autres providers en dette (voir ci-dessous).

## AFK 2026-05-24 (T-AFK-MEGA) -- Recap

### Resolues cette session (7 taches traitees, 6 DONE + 1 ABORTED justifie)
- **T1 T-AWX-KEY-DEPLOY** -- cle pub `awx-runner` deployee sur 5 VMs (+ dc01 = 6/6) via playbook idempotent. CI green.
- **T2 T-APP01-SWAP-ADD** -- 2 GB swap app01 + role `swap_file` (gate `enable_swap`). OOM mitige. CI green.
- **T3 T-AWX-VPNGW-NFT-MODEL** -- `/60` applique sur vpn-gw01 sans wiper mangle/MSS/ct-state (flush chirurgical `hardening_nft_filter_only` + fix handler restart->reload). T-AWX-NFT-ALLOWLIST host 6/6. CI green. *Nouvelle dette perimetre : T-FW-VLAN60-DMZ-VPNGW-OPEN.*
- **T4 T-MAIL-TLS-WILDCARD** -- mail01 sert le cert wildcard mkcert (STARTTLS 587/143 verify=0). Role `mail_server` + `mail_tls_use_wildcard`. CI green.
- **T5 T-MAIL-WAZUH-ENROLL** -- **ABORTED** (R4) : path DMZ->SERVERS:1514/1515 bloque au perimetre. *Nouvelle dette : T-FW-DMZ-WAZUH-OPEN* (+ T-MAIL-WAZUH-ENROLL reste ouverte).
- **T6 T-BASTION-TAILSCALE-CLEANUP** -- **SKIP** (sudo MFA bastion01, session supervisee).
- **T7 T-WAZUH-AUDIT-DEDUP + T-WAZUH-LOGCOLLECTOR-HEALTHCHECK** -- dedup nova-iam audit.log sur dc01 + watchdog timer (Restart=always insuffisant car unit fire-and-forget). E2E auto-recovery OK. CI green.
- **T8 T-AWX-RBAC (Phase 8)** -- 4 groupes AD + 4 Teams AWX + `AUTH_LDAP_TEAM_MAP` (via API, no downtime) + perms. E2E dual-role OK. ADR-0033. CI green.

### Dettes ouvertes apres ce AFK
- **T-BASTION-TAILSCALE-CLEANUP** -- sudo MFA bastion01, session supervisee.
- **T-WIREGUARD-POC** -- 1 agent demo + test client (non adresse en AFK).
- **T-SPLIT-MONITORING-VM** -- **URGENT** : sortir wazuh-indexer + stack lourde d'app01 (OOM confirme).
- **T-SQUID-PROXY** -- proxy filtrant non deploye.
- **T-GRAFANA-AUTHELIA-SSO** -- SSO Grafana via Authelia.
- **T-AWX-VAULT-INVENTORY** -- inventaire AWX peuple + `vault_default_user_password` dans les jobs (+ inventaire Nova-MRS).
- **T-AWX-TEMPLATES-IAC** -- Config-as-Code AWX (Teams/TEAM_MAP/JT non versionnes).
- **T-SSH-CONFIG-DEDUP** -- doublon `~/.ssh/config` Mac.
- **MFA TOTP bastion** -- finalisation.
- ~~**T-FW-VLAN60-DMZ-VPNGW-OPEN**~~ -- **RESOLU 2026-05-25** (regle FW-INT opt5 ; E2E `OPEN`).
- ~~**T-FW-DMZ-WAZUH-OPEN**~~ -- **RESOLU 2026-05-25** (2 regles FW-INT wan, 1514/1515).
- ~~**T-MAIL-WAZUH-ENROLL**~~ -- **RESOLU 2026-05-25** (mail01 agent `Active` sur manager ; note T5 "install incomplete" obsolete : /var/ossec present, seul l'enrollment manquait).
- ~~**T-MAIL-LDAP**~~ -- **RESOLU 2026-05-25** (dette fille : drift regle LDAP `mail01->dc01:636` + alias host_mail01, appliques + importes).
- **T-TF-WANSIM-CONNECTIVITY** (NOUVELLE) -- provider WAN-SIM (10.0.0.1) injoignable depuis le Mac -> plan/apply impossibles sur ce FW.
- **T-TF-FWEXTMRS-CONNECTIVITY** (NOUVELLE) -- provider FW-EXT-MRS (192.168.40.1) injoignable depuis le Mac.
- **T-TF-FWEXTLYON-CONNECTIVITY** (NOUVELLE) -- provider FW-EXT-LYON (172.16.1.1) injoignable depuis le Mac -> bloque toute future regle FW-EXT (ex. fallback DMZ->SERVERS si l'hypothese NAT cessait de tenir).

### Snapshots Proxmox a nettoyer (apres validation)
- VMID 106 (app01) : `pre-app01-swap-add-2026-05-24`
- VMID 110 (vpn-gw01) : `pre-awx-vpngw-nft-2026-05-24`
- VMID 101 (mail01) : `pre-mail-tls-wildcard-2026-05-24`
- VMID 103 (dc01) : `pre-wazuh-audit-dedup-2026-05-24`, `pre-awx-rbac-2026-05-24`
- VMID 111 (awx01) : `pre-awx-rbac-2026-05-24`
- dc01 : fichier `/var/ossec/etc/ossec.conf.bak-prededup-2026-05-24`

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
- **T-AWX-RBAC** (Phase 8) : **RESOLU 2026-05-24** (T-AFK-MEGA, ADR-0033). 4 groupes AD (IT-Officers-Lyon/MRS, IT-Managers, IT-Auditors, dans CN=Users) + 4 Teams AWX (org Nova Syndicate) + `AUTH_LDAP_TEAM_MAP` via API (pas de CR/downtime, LDAP hors CR) + permissions (Officers: exec create/enable ; Managers: exec tous iam-* + admin inv Nova-Lyon ; Auditors: org auditor read-only). **E2E** : user jetable `rbac.test` dual-role -> Teams {IT-Officers, Auditors}, create/enable EXECUTE + reste read-only (conforme), supprime apres test. Snapshots `pre-awx-rbac-2026-05-24` (VMID 103+111). Workflow Onboarding (bonus) reporte. TEAM_MAP a sauvegarder en IaC (-> T-AWX-TEMPLATES-IAC).

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
