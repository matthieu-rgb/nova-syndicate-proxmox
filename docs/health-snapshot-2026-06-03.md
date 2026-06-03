# Nova Syndicate -- Etat de sante infrastructure (2026-06-03)

Capture factuelle post-menage des services failed, avant session de captures
jury. Base pour une slide de presentation "etat de l'infrastructure aujourd'hui".

Methode : sondes lecture seule via `qm guest exec` (Proxmox host Tailscale)
ou SSH ProxyJump. Aucun service redemarré pour cette capture.

---

## 1. Sante des VMs Linux -- 13/13 services failed = 0

| VMID | VM | Role | `systemctl --failed` | Snapshot rollback |
|------|-----|------|----------------------|-------------------|
| 100 | web01 | Nginx DMZ | 0 | -- |
| 101 | mail01 | Postfix + Dovecot + OpenDKIM DMZ | 0 | -- |
| 102 | bastion01 | SSH Bastion + MFA TOTP + Teleport | 0 | -- |
| 103 | dc01 | Samba AD-DC + DNS + Kerberos | 0 | dc01-pre-menage-failed-services-20260603 |
| 104 | fs01 | Samba File Server + winbind | 0 | -- |
| 105 | db01 | MariaDB | 0 | -- |
| 106 | app01 | Wazuh manager + indexer + dashboard + Grafana + Authelia + nginx + nova-portail + Vault | 0 | -- |
| 107 | proxy-lyon01 | Squid Forward Proxy Lyon | 0 | -- |
| 108 | proxy-mrs01 | Squid Forward Proxy MRS | 0 | -- |
| 109 | backup01 | BorgBackup + rclone B2 + WireGuard -> Hetzner | 0 | -- |
| 110 | vpn-gw01 | WireGuard road warriors + IPsec local | 0 | vpn-gw01-pre-dnsmasq-ordering-20260603 |
| 111 | awx01 | AWX (K3s + Operator) | 0 | -- |
| 112 | pki01 | step-ca PKI interne | 0 | -- |

Verification : `for vmid in {100..112}; do qm guest exec $vmid -- systemctl --failed --no-legend | wc -l; done`
retourne `0` x 13.

---

## 2. Services metier actifs

### 2.1. Active Directory (dc01)

| Sonde | Resultat |
|-------|----------|
| `systemctl is-active samba-ad-dc` | `active` |
| `ss -tlnp` ports AD (389, 636, 88, 53, 464) | 10 listeners (IPv4 + IPv6) |
| `samba-tool user list \| wc -l` | 95 (= 94 users + ligne finale) |
| `testparm -s --parameter-name="ldap server require strong auth"` | `Yes` (refus simple bind cleartext 389) |
| `dc01-pre-strong-auth` snapshot existant | Phase 7a (2026-06-02 17:38) |

### 2.2. Wazuh SIEM (app01) -- 8/8 agents Active

```
000,app01 (server),127.0.0.1,Active/Local,
001,backup01,any,Active,
002,proxy-lyon01,any,Active,
003,dc01,any,Active,
004,fs01,any,Active,
005,db01,any,Active,
006,bastion01,any,Active,
007,mail01,any,Active,
```

Stack app01 : `wazuh-manager` + `wazuh-indexer` + `filebeat` + `authelia`
(HTTP 200 `/api/health`) + `grafana-server` + `nginx` + `nova-portail` +
`prometheus` -- tous `active`.

### 2.3. Mail (mail01) -- DMZ, LDAPS step-ca

| Sonde | Resultat |
|-------|----------|
| `systemctl is-active postfix dovecot opendkim` | active x 3 |
| `doveadm auth test svc-mail-ldap@nova-syndicate.local` | auth succeeded (LDAPS dc01:636, trust step-ca) |
| ADR de cloture | [ADR-0034](adr/ADR-0034-ldaps-migration-strong-auth.md) |

### 2.4. File server (fs01) -- AD ADS member

| Sonde | Resultat |
|-------|----------|
| `systemctl is-active smbd winbind` | active x 2 |
| Ports SMB (139, 445) | 4 listeners |
| `wbinfo -u \| wc -l` | 94 users AD listed |
| `wbinfo -t` | trust secret OK |
| `wbinfo -a svc-mail-ldap%...` | plaintext + challenge/response succeeded |

### 2.5. Database (db01)

| Sonde | Resultat |
|-------|----------|
| `systemctl is-active mariadb` | active |
| LISTEN | 192.168.20.13:3306 |

### 2.6. Web public + portail metier (web01 + app01)

| Sonde | Resultat |
|-------|----------|
| nginx web01 actif | 2 listeners (80, 443) |
| Public `nova.0xmatthieu.dev` | 200 (via Cloudflare) |
| Interne `www.nova-syndicate.local/` | 200 |
| Interne `portail.nova-syndicate.local/health` | 200 |
| Interne `portail.nova-syndicate.local/` | 302 (redirige vers Authelia) |
| Authelia `http://127.0.0.1:9091/api/health` | 200 |

---

## 3. Backup -- DRP runtime operationnel

### 3.1. WireGuard backup01 (10.30.0.2) -> Hetzner (10.30.0.1)

```
interface: wg0
  public key: +Q5HPOp8fzmRmDIcIzwemRNXfqdT4ddj2Tblo0jAu2U=
  listening port: 33355

peer: tNuP7iBH2lYL5KozXewSlcP2/aSzCgI+ubNWNj21uCg=
  endpoint: 46.62.138.33:51820
  allowed ips: 10.30.0.1/32
  latest handshake: 1 minute, 39 seconds ago
  transfer: 603.54 KiB received, 3.37 MiB sent
  persistent keepalive: every 25 seconds
```

Ping vers Hetzner : 37 ms.

### 3.2. Archives Borg distantes (Hetzner)

Test `borg-cloud-sync.sh --dry-run` (lecture seule, 2026-06-03 12:57) liste
les **5 archives existantes** sur le VPS :

```
backup01-2026-05-27-2330
backup01-2026-05-28-2330
backup01-2026-05-29-2330
backup01-2026-06-01-2330
backup01-2026-06-02-2330   <- hier soir 23h30
```

Hiatus 2026-05-30 et 2026-05-31 (probablement KO ponctuel, non investigue).

### 3.3. Planification (cron, pas systemd timer)

```
/etc/cron.d/borg-cloud-backup :
30 23 * * * root /usr/local/bin/borg-cloud-sync.sh >> /var/log/borg-cloud-sync.log 2>&1
```

Dette `T-IAC-BORG-ROLE` (audit IaC §4.6) reste ouverte UNIQUEMENT pour le passage
en role Ansible (idempotence + reproductibilite). Le DRP runtime ne depend pas
de cette dette.

---

## 4. Reseau peripherique

### 4.1. Firewalls OPNsense -- 4/4 VMs runtime, 0/1 tunnel inter-sites

| Firewall | VMID | Acces capture | Statut |
|----------|------|---------------|--------|
| WAN-SIMULATOR | 200 | non joignable depuis Mac (T-TF-WANSIM-CONNECTIVITY) | `running` Proxmox |
| FW-EXT-LYON | 201 | atteint via `-J opn-fw-int-lyon root@10.0.1.1` (link 10.0.1.0/30) | `running` Proxmox + FreeBSD 14.2 |
| FW-INT-LYON | 202 | atteint direct via Tailscale `opn-fw-int-lyon` | `running` Proxmox + FreeBSD 14.2 + 6 sous-interfaces VLAN |
| FW-EXT-MRS | 203 | non sonde (chaine SSH cassee dans cette session, dette T-TF-FWEXTMRS-CONNECTIVITY) | `running` Proxmox |

**Pare-feu Lyon-MRS (IPsec)** : strongSwan `charon: Command not found` sur
FW-EXT-LYON, ping FW-EXT-LYON -> 192.168.40.0/26 = 100 % packet loss.
JAMAIS-FINALISE (Phase IV roadmap). STATUS Phase II §4 corrige : "package
non installe" (plus precis que "daemon non demarre").

### 4.2. WireGuard road warriors (vpn-gw01)

```
interface: wg0
  public key: 9ExSPQD6PWsFChdoX3SDEkY8ZppRnvXmH78SKM0vvy4=
  listening port: 51820

peer: XTG8TL36x4fG2xyjp1jLZYjmvkvDfI/ZSbNMjY6MuUA=
  allowed ips: 10.20.0.10/32
  persistent keepalive: every 25 seconds
  latest handshake: 0 (never)
  transfer: 0 0 / 0 0

peer: fPVzZDtvUydP4gi+4yNulEwuG9+JFtVjdZtYAKbvx3o=
  allowed ips: 10.20.0.20/32
  latest handshake: 0 (never)
  transfer: 0 0 / 0 0
```

Service actif (`wg-quick@wg0` enabled + bind 51820), config 2 peers, mais
**0 handshake, 0 trafic** -- aucun client n'a jamais connecte. Phase IV
roadmap "WireGuard 20 agents" jamais aboutie ; les 2 peers configures
sont des reliquats pour future demo.

### 4.3. dnsmasq vpn-gw01 -- bind 10.20.0.1 (DNS pour les peers WG)

Post-fix (drop-in `After=wg-quick@wg0`) :

```
LISTEN 0      32         10.20.0.1:53     0.0.0.0:*    users:(("dnsmasq", ...
```

Survit au reboot via `/etc/systemd/system/dnsmasq.service.d/wait-wg0.conf`.

---

## 5. PKI interne -- step-ca operationnelle

| Element | Etat |
|---------|------|
| pki01 (VMID 112, 192.168.60.4) | running |
| step-ca service | active |
| Root CA + Intermediate CA | issued, present sur pki01 (`/home/step/.step/certs/`) |
| Cert dc01:636 (LDAPS) | emis par Nova Intermediate CA, validite 2026-06-01 -> 2027-06-01 |
| Clients utilisant LDAPS step-ca | mail01 (Dovecot), app01 (Authelia) |
| Trust bundle distribution | role Ansible `pki_client` (commit `fc05d17` 2026-06-02) |
| ADR | [ADR-0034](adr/ADR-0034-ldaps-migration-strong-auth.md) |

---

## 6. Indicateurs synthese

| Pilier | Indicateur | Valeur | Cible |
|--------|------------|--------|-------|
| Disponibilite VMs | running / total | 17 / 17 (16 prod + 1 template) | 100 % |
| Services failed | total | 0 | 0 |
| SIEM | agents Active | 8 / 8 | 8 |
| AD | users LDAP | 94 | invariant |
| PKI interne | trust anchor | step-ca (Nova Root + Intermediate) | step-ca only |
| Cert LDAPS | jours restants | 363 | > 30 |
| Backups offsite | derniere archive Hetzner | 2026-06-02 23:30 | < 24 h |
| WireGuard offsite | derniere handshake | < 2 min | < 5 min |
| Couverture IaC en volume | mesure | ~75 % | -- |
| Couverture IaC en sequencabilite | mesure | ~30 % | -- |

NIS2 art.21 §2 piliers :
- **e (chiffrement)** : LDAPS strict step-ca + GSSAPI sealed sur 389 + cert wildcard interne. Conforme.
- **i (continuite/incidents)** : DRP runtime (Borg + Hetzner) + Wazuh SIEM 8/8 + ADR-0034 (rotation cert). Conforme.
- **j (MFA)** : MFA TOTP bastion + AWX LDAP + Authelia. Partiellement conforme (couverture road warriors a finaliser, Phase IV).

---

## 7. Annexes

### Tickets ouverts non bloquants (post-certif)

Categorie A (corrections) : T-IAC-SITE-YML-ETAPE-7, T-IAC-WIREGUARD-DRIFT,
T-IAC-CLEAN-LEGACY-TF, T-DHCP-USERS-VLAN.

Categorie B (evolutions) : T-IAC-BRIDGES-PROXMOX-HOST, T-IAC-TEMPLATE-9000-BUILD,
T-IAC-AWX01-K3S-AWX, T-IAC-AUTHELIA-ROLE, T-IAC-BORG-ROLE,
T-IAC-APP01-STACKS-NOT-CODED.

Phase IV roadmap : tunnel IPsec Lyon-MRS, WireGuard 20 agents, MFA TOTP final.

### Snapshots Proxmox a nettoyer (apres validation captures)

- VMID 101 mail01 : `mail01-pre-ldaps-mail` (2026-06-02 09:14)
- VMID 103 dc01 : `dc01-pre-mail-ldaps`, `dc01-pre-strong-auth`,
  `dc01-pre-iac-reformat-smbconf`, **`dc01-pre-menage-failed-services-20260603`** (3 juin 12:52)
- VMID 110 vpn-gw01 : **`vpn-gw01-pre-dnsmasq-ordering-20260603`** (3 juin 12:52)
- Snapshots residuels sessions plus anciennes : voir STATUS.md sections respectives.

### References

- [STATUS.md](../STATUS.md) session 2026-06-03
- [Audit IaC](iac-coverage-audit-2026-06-02.md)
- [Runbook LDAPS](runbook-ldaps-migration.md)
- [Rapport LDAPS Phase 6.3 + 6.6 + 7a](ldaps-migration-report.md)
- [ADR-0034 LDAPS + strong auth](adr/ADR-0034-ldaps-migration-strong-auth.md)
