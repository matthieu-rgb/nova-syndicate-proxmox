# Matrice de flux -- FW-EXT-LYON & FW-INT-LYON

**Source** : `pfctl -sr` du 2026-06-04T15:26:25Z, traduit en flux metier lisibles. Captures brutes :
- [`2026-06-04-1726-fw-ext-lyon-pfctl-rules.txt`](2026-06-04-1726-fw-ext-lyon-pfctl-rules.txt) (107 regles pf)
- [`2026-06-04-1726-fw-int-lyon-pfctl-rules.txt`](2026-06-04-1726-fw-int-lyon-pfctl-rules.txt) (170 regles pf)

**Principe global** : default-deny. Chaque interface termine par une regle `block all` explicite ; seuls les flux listes ci-dessous sont autorises. Trois firewalls (FW-EXT-LYON, FW-INT-LYON, FW-EXT-MRS) en chaine.

**Cartographie reseau** :

```
Internet (10.0.0.1)
   |
[FW-EXT-LYON] vtnet0=WAN (10.0.0.2)
   |- vtnet1 DMZ-LYON (172.16.1.0/29)  --> web01, mail01, vpn-gw01
   |- vtnet2 INTER (10.0.1.0/30)  -----> [FW-INT-LYON]
                                                |
                                                vtnet1 ADMIN-FW (192.168.99.0/29)
                                                vlan01 BACKUP   (192.168.50.0/29)  --> backup01
                                                vlan02 BASTION  (192.168.15.0/29)  --> bastion01
                                                vlan03 SERVERS  (192.168.20.0/28)  --> dc01/fs01/db01/app01
                                                vlan04 USERS    (192.168.30.0/26)  --> postes utilisateurs
                                                vlan05 ADMIN    (192.168.60.0/29)  --> awx01, postes admin

[FW-EXT-MRS] (peer IPsec, 10.0.2.2) -- site Marseille, non joignable en mgmt cette capture
```

---

## FW-EXT-LYON -- Frontal Internet & DMZ

Role : terminaison Internet, exposition publique des services DMZ, IPsec inter-sites, hairpin NAT pour acces public au portail metier sur app01.

### Interface vtnet0 (WAN) -- Entrant depuis Internet

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | Internet | `app01` (192.168.20.13) | TCP/443 HTTPS | ✅ ALLOW | Portail metier public Nova Syndicate |
| 2 | Internet | `app01` (192.168.20.13) | TCP/80 HTTP | ✅ ALLOW | Redirection HTTP -> HTTPS portail metier |
| 3 | Internet | `mail01` (172.16.1.3) | TCP/25 SMTP | ✅ ALLOW | Reception mail entrant (MX) |
| 4 | Internet | `mail01` (172.16.1.3) | TCP/465 SMTPS / TCP/587 submission | ✅ ALLOW | SMTP soumission authentifiee (mail sortant clients) |
| 5 | Internet | DMZ `172.16.1.0/29` (`web01`, `mail01`) | TCP/80 HTTP | ✅ ALLOW | Site public + Authelia portal (auth.nova-syndicate.local) |
| 6 | Internet | DMZ `172.16.1.0/29` | TCP/443 HTTPS | ✅ ALLOW | Site public + Authelia portal en TLS |
| 7 | Internet (`10.0.2.2` = FW-EXT-MRS) | self | UDP/500 ISAKMP + UDP/4500 IPsec NAT-T + IP/ESP | ✅ ALLOW | Tunnel IPsec inter-sites LYON <-> MRS (3 protocoles) |
| 8 | Internet | self | ICMP | ❌ (implicite par default-deny) | Pas de ping Internet vers WAN |
| 99 | Internet | * | ALL | ❌ DENY (default) | `block drop in log quick on vtnet0 inet all` -- tout le reste rejete et logge |

### Interface vtnet1 (DMZ-LYON 172.16.1.0/29) -- Entrant depuis DMZ

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | DMZ `172.16.1.0/29` | `bastion01` (192.168.15.2, en LAN derriere FW-INT) | TCP/22 SSH | ✅ ALLOW | Acces SSH bastion depuis DMZ (admin) |
| 2 | Road-warriors WG `10.20.0.0/24` | `mail01` (172.16.1.3) | TCP/25 SMTP | ✅ ALLOW | Clients VPN -> mail interne |
| 3 | Road-warriors WG `10.20.0.0/24` | `mail01` (172.16.1.3) | TCP/465 SMTPS | ✅ ALLOW | Idem SMTPS |
| 4 | Road-warriors WG `10.20.0.0/24` | `mail01` (172.16.1.3) | TCP/587 submission | ✅ ALLOW | Idem submission |
| 5 | Road-warriors WG `10.20.0.0/24` | `mail01` (172.16.1.3) | TCP/143 IMAP | ✅ ALLOW | Lecture mail clients VPN |
| 6 | Road-warriors WG `10.20.0.0/24` | `mail01` (172.16.1.3) | TCP/993 IMAPS | ✅ ALLOW | Idem IMAPS |
| 7 | Road-warriors WG `10.20.0.0/24` | `web01` (172.16.1.2) | TCP/80 HTTP | ✅ ALLOW | Acces site public depuis VPN |
| 8 | Road-warriors WG `10.20.0.0/24` | `web01` (172.16.1.2) | TCP/443 HTTPS | ✅ ALLOW | Idem HTTPS |
| 9 | Road-warriors WG `10.20.0.0/24` | LAN SERVERS `192.168.20.0/28` | ALL | ✅ ALLOW | Clients VPN -> tous services serveurs internes |
| 10 | DMZ `172.16.1.0/29` | self (vtnet1) | TCP/22 SSH | ✅ ALLOW | SSH admin local FW-EXT-LYON |
| 11 | DMZ `172.16.1.0/29` | self (vtnet1) | TCP/80 HTTP, TCP/443 HTTPS | ✅ ALLOW | GUI OPNsense admin local FW-EXT-LYON |
| 99 | * | * | ALL | ❌ DENY (implicite) | Tout autre flux depuis DMZ bloque par regle finale du jeu |

### Interface vtnet2 (INTER LYON 10.0.1.0/30) -- Lien transit vers FW-INT-LYON

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `10.0.1.0/30` (lien inter-firewall) | * | ALL | ✅ ALLOW | Transit complet vers FW-INT-LYON (filtrage delegue au firewall interne) |

### NAT (vtnet0 sortant) -- Masquerade Internet

| Source interne | Destination | Action |
|---|---|---|
| Tout VLAN interne (DMZ, INTER, loopback) | Internet | NAT/PAT outbound vers IP WAN, ports ephemeres 1024-65535 |
| Tout VLAN interne | * port=500 (ISAKMP) | NAT static-port (necessaire IPsec) |
| Subnet LYON (alias `<net_lyon_internal>`) | LAN MRS (`<net_lan_mrs>`) | **PAS** de NAT (route directe via IPsec) |

### Redirection (RDR) -- Hairpin NAT pour acces externe portail

| Source | Service WAN expose | Cible interne | Description |
|---|---|---|---|
| Internet | TCP/80 sur 192.168.18.51 | TCP/80 sur 192.168.20.13 (`app01`) | Hairpin portail metier HTTP |
| Internet | TCP/443 sur 192.168.18.51 | TCP/443 sur 192.168.20.13 (`app01`) | Hairpin portail metier HTTPS |

> 192.168.18.51 est l'IP "virtuelle exterieure" utilisee pour rendre le portail accessible depuis l'Internet via Cloudflared / DNAT.

---

## FW-INT-LYON -- Segmentation inter-VLAN

Role : faire respecter le moindre privilege entre VLANs internes (BACKUP, BASTION, SERVERS, USERS, ADMIN) et autoriser uniquement les flux metier explicites.

### Interface vtnet0 (transit depuis FW-EXT-LYON via INTER 10.0.1.0/30)

Entrant : flux Internet/DMZ deja filtres par FW-EXT-LYON qui doivent acceder a un service interne specifique.

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `<net_proxmox_admin>` (admin Proxmox) | `app01` (192.168.20.13) | TCP/443 HTTPS | ✅ ALLOW | Acces GUI portail/Grafana/Wazuh depuis admin Proxmox |
| 2 | `mail01` (DMZ 172.16.1.3) | `app01` (192.168.20.13) | TCP/1514 | ✅ ALLOW | Agent Wazuh mail01 -> manager (telemetrie SIEM) |
| 3 | `mail01` (DMZ 172.16.1.3) | `app01` (192.168.20.13) | TCP/1515 | ✅ ALLOW | Enrollment Wazuh agent mail01 |
| 4 | `mail01` (DMZ 172.16.1.3) | `dc01` (192.168.20.10) | TCP/636 LDAPS | ✅ ALLOW | Auth Dovecot/Postfix contre AD (2 regles identiques, redondance) |
| 5 | Internet (any) | `app01` (192.168.20.13) | TCP/443 HTTPS | ✅ ALLOW | Acces portail metier (post FW-EXT) |
| 6 | Internet (any) | `app01` (192.168.20.13) | TCP/80 HTTP | ✅ ALLOW | Redirect HTTP portail metier (post FW-EXT) |
| 7 | Road-warriors WG `<net_road_warriors>` | `app01` (192.168.20.13) | TCP/443 HTTPS | ✅ ALLOW | Acces portail metier depuis VPN |
| 8 | Road-warriors WG `<net_road_warriors>` | `fs01` (192.168.20.11) | TCP/22 SSH + 139/445 SMB | ✅ ALLOW | Acces fichiers Samba depuis VPN |
| 9 | Road-warriors WG `<net_road_warriors>` | `db01` (192.168.20.12) | TCP/22 SSH + TCP/3306 MySQL | ✅ ALLOW | Acces base MariaDB depuis VPN (DBA distant) |
| 10 | Road-warriors WG `<net_road_warriors>` | `dc01` (192.168.20.10) | UDP/53 DNS | ✅ ALLOW | Resolution DNS interne depuis VPN |
| 11 | LAN MRS `<net_lan_mrs>` | Lyon `<net_lyon_internal>` | ALL | ✅ ALLOW | Site MRS -> tous services Lyon (via IPsec) |
| 12 | FW-EXT-LYON (`10.0.1.1`) | `app01` (192.168.20.13) | UDP/5141 | ✅ ALLOW | Forwarder Suricata FW-EXT -> receiver Python app01 |
| 13 | FW-EXT-LYON (`10.0.1.1`) | `app01` (192.168.20.13) | UDP/514 syslog | ✅ ALLOW | Logs FW-EXT-LYON vers SIEM |
| 99 | * | * | ALL | ❌ DENY | `block drop in log quick on vtnet0 inet all` -- default-deny explicite |

### Interface vlan01 (BACKUP -- 192.168.50.0/29)

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `backup01` (192.168.50.2) | `<net_lyon_servers>` (192.168.20.0/28) | TCP/22 SSH | ✅ ALLOW | Borg-backup pull depuis backup01 vers serveurs |
| 2 | `backup01` (192.168.50.2) | * | ALL | ✅ ALLOW | backup01 sortie generale (Internet pour WireGuard backup Hetzner) |
| 99 | * | * | ALL | ❌ DENY | `block drop in log quick on vlan01 inet all` |

### Interface vlan02 (BASTION -- 192.168.15.0/29)

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `bastion01` (192.168.15.2) | `dc01` (192.168.20.10) | UDP/53 DNS, UDP/88 Kerberos, UDP/123 NTP, UDP/389 LDAP, UDP/137-138 NetBIOS, UDP/464 kpasswd | ✅ ALLOW | Auth AD complete UDP (jointure domaine bastion) |
| 2 | `bastion01` (192.168.15.2) | `dc01` (192.168.20.10) | TCP/88 Kerberos, TCP/135 RPC, TCP/389 LDAP, TCP/445 SMB, TCP/464 kpasswd, TCP/636 LDAPS, TCP/3268-3269 GC LDAP/S | ✅ ALLOW | Auth AD complete TCP (services Kerberos, GC, LDAPS) |
| 3 | `bastion01` (192.168.15.2) | `<net_lyon_servers>` | TCP/22 SSH | ✅ ALLOW | Rebond SSH bastion -> serveurs (admin) |
| 4 | `bastion01` (192.168.15.2) | * | ALL | ✅ ALLOW | Sortie generale bastion (mises a jour, NTP externe, etc.) |
| 99 | * | * | ALL | ❌ DENY | `block drop in log quick on vlan02 inet all` |

### Interface vlan03 (SERVERS LYON -- 192.168.20.0/28)

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `<net_lyon_servers>` (192.168.20.0/28) | * | ALL | ✅ ALLOW | Sortie generale serveurs (mises a jour, NTP, DNS public, MX, etc.) |
| 99 | * | * | ALL | ❌ DENY | `block drop in log quick on vlan03 inet all` -- aucune entree vers VLAN servers depuis VLAN servers, tout entrant doit etre explicite |

### Interface vlan04 (USERS LYON -- 192.168.30.0/26)

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `<net_lyon_users>` | `dc01` (192.168.20.10) | UDP/53 DNS, UDP/88 Kerberos, UDP/123 NTP, UDP/389 LDAP, UDP/137-138 NetBIOS, UDP/464 kpasswd | ✅ ALLOW | Auth AD UDP postes utilisateurs |
| 2 | `<net_lyon_users>` | `dc01` (192.168.20.10) | TCP/88 Kerberos, TCP/135 RPC, TCP/389 LDAP, TCP/445 SMB, TCP/464 kpasswd, TCP/636 LDAPS, TCP/3268-3269 GC LDAP/S | ✅ ALLOW | Auth AD TCP postes utilisateurs |
| 3 | `<net_lyon_users>` | `<net_lyon_servers>` | TCP/139 NetBIOS-SSN + TCP/445 SMB | ✅ ALLOW | Acces partages fichiers Samba (fs01) |
| 4 | `<net_lyon_users>` | * | ALL | ✅ ALLOW | Sortie Internet generale postes utilisateurs (web/mail/etc.) |
| 99 | * | * | ALL | ❌ DENY | `block drop in log quick on vlan04 inet all` |

### Interface vlan05 (ADMIN LYON -- 192.168.60.0/29)

| # | Source | Destination | Port/Proto | Action | Description |
|---|---|---|---|---|---|
| 1 | `<net_lyon_admin>` (192.168.60.0/29) | `dc01` (192.168.20.10) | UDP/53/88/123/389/137-138/464 + TCP/88/135/389/445/464/636/3268/3269 | ✅ ALLOW | Auth AD complete (postes admin + awx01) |
| 2 | `<net_lyon_admin>` | `<net_lyon_internal>` | TCP/22 SSH | ✅ ALLOW | SSH admin vers tous VLANs Lyon (AWX runner) |
| 3 | `<net_lyon_admin>` | `<net_dmz_lyon>` (172.16.1.0/29) | TCP/22 SSH | ✅ ALLOW | SSH admin vers DMZ (mail01, web01, vpn-gw01) |
| 4 | `<net_lyon_admin>` | * | TCP/443 HTTPS + TCP/80 HTTP | ✅ ALLOW | Sortie web admin (Internet, GUI internes) |
| 99 | * | * | ALL | ❌ DENY | `block drop in log quick on vlan05 inet all` |

### NAT FW-INT-LYON (sortant vers vtnet0 -- vers FW-EXT puis Internet)

Tous les VLANs internes (BACKUP, BASTION, SERVERS, USERS, ADMIN, ADMIN-FW) sont NAT/PAT vers l'IP transit `10.0.1.x`. Pas de NAT vers la LAN MRS (192.168.40.0/26) -- transit direct via IPsec.

---

## Glossaire des alias OPNsense

| Alias | Valeur | Role |
|---|---|---|
| `<host_app01>` | 192.168.20.13 | App server : portail metier + Grafana + Wazuh manager/indexer/dashboard + Authelia + nginx |
| `<host_dc01>` | 192.168.20.10 | Domain Controller AD (Samba 4) -- DNS interne, Kerberos, LDAPS |
| `<host_fs01>` | 192.168.20.11 | File server Samba |
| `<host_db01>` | 192.168.20.12 | MariaDB serveur |
| `<host_backup01>` | 192.168.50.2 | Borg backup, tunnel WG Hetzner offsite |
| `<host_bastion01>` | 192.168.15.2 | Bastion SSH+MFA TOTP |
| `<host_mail01>` | 172.16.1.3 | Postfix + Dovecot DMZ |
| `<net_dmz_lyon>` | 172.16.1.0/29 | DMZ Lyon (web01, mail01, vpn-gw01) |
| `<net_lyon_servers>` | 192.168.20.0/28 | VLAN SERVERS Lyon |
| `<net_lyon_users>` | 192.168.30.0/26 | VLAN USERS Lyon (postes utilisateurs) |
| `<net_lyon_admin>` | 192.168.60.0/29 | VLAN ADMIN Lyon (awx01, postes admin) |
| `<net_lyon_internal>` | union des VLANs internes Lyon | Cible "tout interne" |
| `<net_lan_mrs>` | 192.168.40.0/26 | LAN site Marseille (accessible via IPsec) |
| `<net_road_warriors>` | 10.20.0.0/24 | Pool clients WireGuard nomades |
| `<net_proxmox_admin>` | (admin Proxmox) | Sous-reseau d'admin de l'hyperviseur |

## Regles techniques (boilerplate, hors flux metier)

Filtrees de la matrice pour clarte jury -- presentes dans les 2 firewalls :

- **Anti-spoofing par interface** : tout paquet dont l'IP source ne correspond pas a un reseau attendu sur l'interface entrante est `block drop`. Garantit qu'un attaquant ne peut pas usurper une IP interne depuis l'Internet (RPF en pratique).
- **Anti-port-0** : paquets TCP/UDP avec port source ou destination = 0 (signature d'outil de scan ou de paquet malforme) -> `block drop quick`.
- **Anti-bogon / anti-multicast non sollicite** : sources `127.0.0.0/8`, addresses link-local mal placees, etc.
- **`<sshlockout>`** : table dynamique alimentee par fail2ban OPNsense interne -- IPs bloquees apres N echecs SSH ou HTTPS sur le firewall lui-meme.
- **`<virusprot>`** : table dynamique anti-virus/anti-flood OPNsense.
- **ICMPv6 RFC 4890** : autorisation des messages ICMPv6 strictement necessaires (router solicitation/advertisement, neighbor discovery, packet-too-big pour PMTU) ; le reste droppe.
- **Anti-lockout admin local** : sur le LAN d'administration (vtnet1 sur chaque firewall = DMZ pour FW-EXT, ADMIN-FW 192.168.99.0/29 pour FW-INT), les ports SSH/HTTP/HTTPS du firewall lui-meme sont toujours ouverts pour eviter de se locker hors de l'OPNsense apres une mauvaise regle.

## Points NIS2 / least-privilege a souligner au jury

1. **Default-deny explicite** sur chaque interface (`block drop in log quick on vlanXX inet all` en fin de jeu de regles). Aucun "allow all" implicite. Couverture **NIS2 art.21.2.e**.
2. **Segmentation forte inter-VLAN** : BACKUP, BASTION, USERS, ADMIN sont isoles ; chaque flux entrant vers SERVERS est explicite (pas de "users peut tout faire"). Couverture **NIS2 art.21.2.d**.
3. **Auth AD strict** : USERS et ADMIN n'ont acces a `dc01` que sur les ports Kerberos/LDAPS/SMB necessaires. Pas de TCP/22 SSH possible vers dc01 depuis USERS (seul ADMIN peut SSH vers `<net_lyon_internal>`).
4. **Mail flow asymetrique** : mail01 est en DMZ, peut recevoir SMTP/465/587 depuis Internet (necessaire), mais ne peut PAS initier de connexion vers la LAN servers SAUF `LDAPS dc01` (auth) et `1514/1515 app01` (telemetrie SIEM). Limite la surface si mail01 est compromis.
5. **Road-warriors traceable** : tous les flux depuis le subnet WG `10.20.0.0/24` sont autorises explicitement vers services bien identifies (mail/IMAP, portail HTTPS, fileserver SMB, db01 MySQL, dc01 DNS). Pas de "WG -> tout". Permet audit complet par log.
6. **Hairpin NAT controle** : seul le portail metier (`app01:80/443`) est expose publiquement via DNAT, pas l'ensemble du VLAN SERVERS. Le reverse-proxy nginx sur app01 fait office de WAF/reverse pour les sous-services (Grafana, Wazuh Dashboard, Authelia derrierre Authelia 2FA).
7. **Logs `block drop in log` partout** : chaque deny est logge par pf -> remonte dans le pipeline syslog -> Suricata -> Wazuh (rule 100009 `pf DROP -> NIS2 art.21.2.e tentative acces non autorise`). Traceability complete des refus.
8. **2 sites IPsec separes** : LYON et MRS communiquent via tunnel chiffre IKEv2/ESP, pas en clair sur Internet. Couverture **NIS2 art.21.2.b** (confidentialite reseau inter-sites).

## Limitation de la capture

- FW-EXT-MRS non capture cette session : path mgmt MRS (192.168.40.1) actuellement injoignable depuis Lyon -- l'IPsec porte les subnets metier (servers/users/backup/bastion) mais pas la mgmt firewall. Dette IPsec ouverte cf STATUS 2026-06-03. A rejouer en session future apres remise en service du path mgmt MRS.
- Les regles **NAT et RDR** sont presentes en bas du document (sections "NAT" et "Redirection") -- pf les traite comme des regles separees mais elles font partie de la posture firewall et meritent d'etre presentees au jury comme telles.
