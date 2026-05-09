# T3 -- Matrice de trafic par interface
# Date : 2026-05-09

## Perimetre : 8 interfaces avec block_all=false

Sources : pfctl -sr sur chaque FW + analysis Terraform + SSH config

---

## NOTE CRITIQUE : gestion SSH management

Toutes les connexions SSH management (Mac -> FW) passent par des interfaces LAN, jamais par les WAN.
Activer block_all sur WAN = ZERO risque de lockout SSH.

| FW | Interface mgmt | IP | Interface WAN |
|----|---------------|-----|---------------|
| FW-INT-LYON | vtnet1 (mgmt) | 192.168.99.1 | vtnet0 (10.0.1.2) |
| FW-EXT-LYON | vtnet1 (LAN/DMZ) | 172.16.1.1 | vtnet0 (10.0.0.2) |
| FW-EXT-MRS | vtnet1 (LAN) | 192.168.40.1 | vtnet0 (10.0.2.2) |
| WAN-SIM | vtnet1 (LAN) | 10.0.0.1 | vtnet0 (internet) |

---

## 1. WAN-SIM / vtnet0 (WAN internet)

**Role** : router transparent entre 10.0.0.x (Lyon) et 10.0.2.x (MRS). vtnet0 = internet reel.
**Trafic transit** : passe par vtnet1 (Lyon) et vtnet2 (MRS), PAS par vtnet0.

| Flux | Interface | Regle TF existante | Statut |
|------|-----------|---------------------|--------|
| Transit ESP Lyon<->MRS | vtnet1/vtnet2 | wansim_lan_to_any + wansim_opt1_to_any | Hors scope vtnet0 |
| Aucun trafic termine localement sur vtnet0 | - | - | - |

**Regles existantes vtnet0** :
- RFC1918 blocks + bogon blocks (OPNsense-auto)
- Aucun auto pass-all visible (pfctl confirme)

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : ZERO -- le trafic IPsec ne passe pas par vtnet0

---

## 2. FW-INT-LYON / opt1 (vlan01, BACKUP 192.168.50.0/29)

**Role** : BACKUP01 (192.168.50.2), BorgBackup + rclone B2

| Flux | Sens | Regle TF existante | Statut |
|------|------|--------------------|--------|
| BACKUP01 -> servers SSH (borg pull) | out opt1 | fwint_backup_to_servers_ssh | OK |
| BACKUP01 -> internet (rclone B2) | out opt1 | fwint_backup_to_internet | OK |
| FS1 (192.168.20.11) -> BACKUP01 SSH (push borg) | in opt3 (SERVERS) | fwint_servers_to_internet (pass-all) | OK -- arrive sur opt3 |
| DB1 (192.168.20.12) -> BACKUP01 SSH (mariabackup) | in opt3 (SERVERS) | fwint_servers_to_internet (pass-all) | OK -- arrive sur opt3 |

**Note** : Les connexions depuis SERVERS vers BACKUP arrivent sur opt3 (interface source), pas opt1.
La regle `fwint_servers_to_internet` (pass-all servers to any) couvre ces flux sur opt3.

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : FAIBLE

---

## 3. FW-INT-LYON / opt4 (vlan04, USERS 192.168.30.0/26)

**Role** : postes utilisateurs

| Flux | Regle TF existante | Statut |
|------|--------------------|--------|
| Users -> DC01 AD TCP | fwint_users_to_dc_ad_tcp | OK |
| Users -> DC01 AD UDP (DNS, Kerberos, NTP) | fwint_users_to_dc_ad_udp | OK |
| Users -> servers SMB (partages) | fwint_users_to_servers_smb | OK |
| Users -> internet (web) | fwint_users_to_internet (pass-all) | OK |

**Note** : `fwint_users_to_internet` = pass-all depuis users. Le block_all ne se declenchera jamais
tant que cette regle existe. Fermeture purement structurelle.

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : NEGLIGEABLE (pass-all actif)

---

## 4. FW-EXT-MRS / vtnet0 (WAN, 10.0.2.2)

**Role** : interface WAN vers WAN-SIM, recoit les ESP depuis FW-EXT-LYON (10.0.0.2)

| Flux | Regle TF existante | Statut |
|------|--------------------|--------|
| IKE (UDP 500) depuis 10.0.0.2 (Lyon) | fwextmrs_wan_ipsec_ike | OK |
| NAT-T (UDP 4500) depuis 10.0.0.2 | fwextmrs_wan_ipsec_natt | OK |
| ESP (proto 50) depuis 10.0.0.2 | fwextmrs_wan_ipsec_esp | OK |
| Trafic decapsule (enc0) | pass in/out on enc0 (OPNsense-auto) | OK |
| Retour internet (MRS LAN -> internet) | stateful (pass out all) | OK |
| SSH management | vtnet1 (LAN 192.168.40.1) -- hors vtnet0 | OK |

**Observation pfctl** : Aucun auto pass-all visible sur vtnet0 de FW-EXT-MRS.
Le trafic recu sur vtnet0 est uniquement IKE/ESP (traite par les regles explicites).

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : FAIBLE -- regles explicites couvrent tout

---

## 5. FW-EXT-LYON / vtnet0 (WAN, 10.0.0.2)

**Role** : interface WAN, initiateur IPsec, NAT pour VLANs internes vers internet

| Flux | Regle TF existante | Statut |
|------|--------------------|--------|
| IKE (UDP 500) depuis 10.0.2.2 (MRS) | fwext_wan_ipsec_ike | OK |
| NAT-T (UDP 4500) depuis 10.0.2.2 | fwext_wan_ipsec_natt | OK |
| ESP (proto 50) depuis 10.0.2.2 | fwext_wan_ipsec_esp | OK |
| Trafic decapsule (enc0) | pass in/out on enc0 (OPNsense-auto) | OK |
| HTTP/HTTPS -> DMZ (172.16.1.0/29) | wan_to_dmz_http + wan_to_dmz_https | OK |
| SMTP -> MAIL01 (port 25) | wan_to_mail | OK |
| SMTP submission (465, 587) -> MAIL01 | fwext_wan_to_mail_submission | OK |
| Retour internet pour VLANs (NAT) | stateful (pass out all) | OK |
| SSH management | vtnet1 (172.16.1.1) -- hors vtnet0 | OK |

**Observation pfctl** : Auto pass-all `pass in quick on vtnet0 reply-to (vtnet0 10.0.0.1) inet all`
(label 28810c42...) sera retire quand block_all=true. Les regles explicites ci-dessus
couvrent tout le trafic legitime.

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : FAIBLE -- regles explicites completes

---

## 6. FW-INT-LYON / opt3 (vlan03, SERVERS 192.168.20.0/28)

**Role** : DC01, FS01, DB01, APP01 (Wazuh manager, Prometheus, Grafana)

| Flux | Regle TF existante | Statut |
|------|--------------------|--------|
| Tous servers -> internet (apt, NTP, repos, Docker) | fwint_servers_to_internet (pass-all) | OK |
| Wazuh agents Lyon -> APP01:1514/1515 | fwint_servers_to_internet (pass-all) | OK |
| Prometheus scrape -> node_exporter :9100 | fwint_servers_to_internet (pass-all) | OK |
| DC01 -> tout (AD, DNS, Kerberos, LDAP) | fwint_servers_to_internet (pass-all) | OK |
| FS01 -> BACKUP01 SSH (borg push) | fwint_servers_to_internet (pass-all) | OK |
| DB01 -> BACKUP01 SSH (mariabackup) | fwint_servers_to_internet (pass-all) | OK |

**Note** : `fwint_servers_to_internet` = pass-all. Block_all ne se declenchera jamais.
Fermeture purement structurelle.

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : NEGLIGEABLE (pass-all actif)

---

## 7. FW-INT-LYON / opt2 (vlan02, BASTION 192.168.15.0/29)

**Role** : BASTION01 (192.168.15.2), SSH bastion, Ansible, Terraform

| Flux | Regle TF existante | Statut |
|------|--------------------|--------|
| BASTION01 -> servers SSH (admin, Ansible) | fwint_bastion_to_servers_ssh | OK |
| BASTION01 -> DC01 AD TCP | fwint_bastion_to_dc_ad_tcp | OK |
| BASTION01 -> DC01 AD UDP (DNS, Kerberos) | fwint_bastion_to_dc_ad_udp | OK |
| BASTION01 -> internet (git, terraform, ansible-galaxy) | fwint_bastion_to_internet (pass-all) | OK |
| BASTION01 -> APP01 (Wazuh agent, node_exporter) | fwint_bastion_to_internet (pass-all) | OK |

**Note** : `fwint_bastion_to_internet` = pass-all. Block_all ne se declenchera jamais.
Fermeture purement structurelle.

**Regles pass a ajouter avant fermeture** : AUCUNE

**Risque fermeture** : NEGLIGEABLE (pass-all actif)

---

## 8. FW-INT-LYON / vtnet0 (WAN, 10.0.1.2/30)

**Role** : interface transit vers FW-EXT-LYON, recoit le trafic IPsec decapsule de MRS

| Flux | Direction sur vtnet0 | Regle TF existante | Statut |
|------|---------------------|---------------------|--------|
| Sortie VLANs -> internet (NAT via FW-EXT) | out stateful | pass out all (OPNsense) | OK |
| Retour internet -> VLANs (NAT states) | in stateful | pf state table | OK |
| Retour pings IPsec (FW-INT-LYON initie) | in stateful | pf state table | OK |
| MRS (192.168.40.0/26) -> VLANs Lyon (IPsec decapsule) | in NOUVEAU | MANQUANTE | BLOCAGE |
| SSH management (Mac -> FW-INT) | vtnet1 (192.168.99.1) -- hors vtnet0 | OK | OK |

**Observation pfctl** : Auto pass-all `pass in quick on vtnet0 reply-to (vtnet0 10.0.1.1) inet all`
(label 6900a192...) sera retire quand block_all=true. AUCUNE regle explicite inbound
sur vtnet0 n'existe actuellement en Terraform.

**Impact manque** :
- Pings tests IPsec (FW-INT-LYON initie): PASSES (stateful) -- test T3 passera
- MRS Wazuh agents -> Lyon manager: BLOQUE (MRS initie, pas de state)
- MRS VMs -> Lyon VMs (connexions MRS-initiees): BLOQUE
- Validation Phase 4 check 7 (Wazuh agents actifs): ECHOUERA si non corrige

**REGLE A AJOUTER AVANT FERMETURE** :
```hcl
resource "opnsense_firewall_filter" "fwint_wan_ipsec_decapsulated" {
  provider    = opnsense.fw_int
  enabled     = true
  description = "Trafic decapsule IPsec depuis MRS vers VLANs Lyon"
  interface   = { interface = ["wan"] }
  filter = {
    action    = "pass"
    direction = "in"
    quick     = true
    protocol  = "any"
    source      = { net = "net_lan_mrs" }
    destination = { net = "any" }
  }
}
```

**Risque fermeture sans cette regle** : ELEVE (rupture trafic MRS-initie)
**Risque fermeture avec cette regle** : FAIBLE

---

## Resume par interface -- ordre Phase 3

| Ordre | Interface | FW | Regles a ajouter | Risque | Auto-pass-all retire |
|-------|-----------|-----|------------------|--------|----------------------|
| 1 | vtnet0 WAN | WAN-SIM | 0 | ZERO | NON (inexistant) |
| 2 | opt1 BACKUP | FW-INT-LYON | 0 | FAIBLE | NON (interface VLAN) |
| 3 | opt4 USERS | FW-INT-LYON | 0 | NEGLIGEABLE | NON |
| 4 | vtnet0 WAN | FW-EXT-MRS | 0 | FAIBLE | NON (inexistant) |
| 5 | vtnet0 WAN | FW-EXT-LYON | 0 | FAIBLE | OUI (retire 28810c42) |
| 6 | opt3 SERVERS | FW-INT-LYON | 0 | NEGLIGEABLE | NON |
| 7 | opt2 BASTION | FW-INT-LYON | 0 | NEGLIGEABLE | NON |
| 8 | vtnet0 WAN | FW-INT-LYON | **1 (decapsule MRS)** | FAIBLE* | OUI (retire 6900a192) |

*Faible SI la regle fwint_wan_ipsec_decapsulated est ajoutee avant fermeture.

---

## Routes PARASITES a supprimer (DT-1 -- Phase 2 ou Phase 3)

Validation faite en session 2026-05-08. Suppression safe :
- opnsense_route.wansim_to_lyon_internal_subnets
- opnsense_route.wansim_to_mrs_lan
- opnsense_route.wansim_to_lyon_transit
- opnsense_route.fwext_to_mrs_lan
- opnsense_route.fwextmrs_to_lyon

Terraform: `terraform destroy -target=opnsense_route.wansim_to_lyon_internal_subnets` x5
(ou supprimer les 5 de routes.tf et faire un apply)

Timing : a inclure dans le terraform apply de Phase 2 (avant les block_all).
