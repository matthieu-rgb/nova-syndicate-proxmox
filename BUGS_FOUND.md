# BUGS_FOUND.md - Phase C Verification - Session 2

Date : 2026-05-07
Session : autonome Automated DevOps pipeline
Phase : C - Verification multi-agents post-deploiement

---

## SYNTHESE

| VM          | Verdict  | Cloud-init | Common pkgs | App role  |
|-------------|----------|------------|-------------|-----------|
| dc01        | DEGRADE  | PASS       | PASS        | FAIL      |
| fs01        | DEGRADE  | PASS       | FAIL        | FAIL      |
| db01        | DEGRADE  | PASS       | FAIL        | FAIL      |
| app01       | DEGRADE  | PASS       | FAIL        | FAIL      |
| bastion01   | DEGRADE  | PASS       | FAIL        | FAIL      |
| proxy-lyon01| DEGRADE  | PASS       | FAIL        | FAIL      |
| backup01    | DEGRADE  | PASS       | FAIL        | FAIL      |

VMs non verifiables (pas de routage) :
- web01 (172.16.1.2) : UNREACHABLE - DMZ sans FW-EXT-LYON01
- mail01 (172.16.1.3) : UNREACHABLE - DMZ sans FW-EXT-LYON01
- proxy-mrs01 (192.168.40.11) : UNREACHABLE - LAN-MRS sans FW-EXT-MRS01

---

## CAUSE RACINE (BUG SYSTEMIQUE)

Pendant Phase B (ansible-playbook site.yml), la tache "Installer les paquets de base"
a bloque ~25 minutes pour 6 VMs.

Raison : au demarrage, les VMs avaient leur gateway configure sur 192.168.20.1
(FW-INT-LYON01 = non deploye). Pas de routage Internet.

- dc01 : DNS = 127.0.0.1 + 1.1.1.1 -> APT OK apres ajout NAT Proxmox
- Autres VMs : DNS = 192.168.20.10 (DC01, pas encore resolver) -> APT ECHEC silencieux

Correctif applique pendant la session : NAT temporaire sur Proxmox (masquerade).
Ce NAT est volatile (pas persiste) - disparait au reboot Proxmox.

---

## BUGS CRITIQUES

### BUG-C1 : Common packages manquants sur 6 VMs [RESOLU]
**VMs affectees** : fs01, db01, app01, bastion01, proxy-lyon01, backup01
**Symptome** : rsync, net-tools, git, python3-pip, dnsutils, gnupg non installes
**Cause** : APT impossible - DNS KO au moment de l'install (pas de FW-INT)
**Fix applique** : NAT Proxmox configure + apt-get via qm guest exec (7/7 packages sur 6 VMs)

### BUG-C2 : Samba AD DC non provisionne sur dc01
**VMs affectees** : dc01
**Symptome** : samba-ad-dc inactive, aucun domaine AD, getent passwd = users locaux seulement
**Cause** : Role ansible dc (samba_tool domain provision) non execute ou incomplet
**Fix** : ansible-playbook site.yml --limit dc01 --tags dc

### BUG-C3 : Samba fileserver non installe sur fs01
**VMs affectees** : fs01
**Symptome** : smbd inactive, nmbd inactive, /etc/samba/ absent
**Cause** : Common packages non installes -> role fileserver non execute
**Fix** : Apres BUG-C1 fixe, relancer role fileserver sur fs01

### BUG-C4 : MariaDB non installe sur db01
**VMs affectees** : db01
**Symptome** : mariadb inactive, mysql indisponible
**Cause** : Common packages non installes -> role database non execute
**Fix** : Apres BUG-C1 fixe, relancer role database sur db01

### BUG-C5 : Wazuh Manager et Grafana non actifs sur app01
**VMs affectees** : app01
**Symptome** : wazuh-manager inactive, grafana-server inactive
**Cause** : Common packages non installes -> role wazuh_manager non execute
**Fix** : Apres BUG-C1 fixe, relancer role wazuh_manager sur app01

### BUG-C6 : MFA TOTP non configure sur bastion01
**VMs affectees** : bastion01
**Symptome** : /etc/pam.d/sshd sans google-authenticator, pas de TOTP
**Cause** : Common packages non installes -> role bastion non execute
**Fix** : Apres BUG-C1 fixe, relancer role bastion sur bastion01

### BUG-C7 : Squid non installe sur proxy-lyon01
**VMs affectees** : proxy-lyon01
**Symptome** : squid inactive, port 3128 non ecoute
**Cause** : Common packages non installes -> role proxy non execute
**Fix** : Apres BUG-C1 fixe, relancer role proxy sur proxy-lyon01

### BUG-C8 : BorgBackup + rclone absents sur backup01
**VMs affectees** : backup01
**Symptome** : borg absent, rclone absent, aucun crontab
**Cause** : Role backup non implemente (Phase 8 optionnelle) + common packages KO
**Fix** : Creer role roles/backup/, puis relancer playbook sur backup01

---

## BUGS MOYENS

### BUG-M1 : NAT Proxmox volatile (non persiste) [RESOLU]
**Symptome** : iptables MASQUERADE + ip alias 192.168.20.1/15.1/50.1 perdus au reboot
**Fix applique** :
  - /etc/sysctl.d/99-nova-syndicate-nat.conf : net.ipv4.ip_forward=1
  - /etc/network/interfaces : vmbr1.15/20/50 avec static + post-up MASQUERADE

---

## ECARTS vs ARCHITECTURE CIBLE

- Tous les VMs : cloud-init conforme (IP, hostname, CPU, RAM, disk = PASS)
- Aucun ecart de configuration reseau detecte
- Ecart principal : application roles non executes (cf. CRITIQUES)

---

## DEFERRED (necessite intervention humaine)

### DEFERRED-1 : ISO OPNsense non uploade
**Impact** : VMs DMZ (web01, mail01) et LAN-MRS (proxy-mrs01) non accessibles
**Action** : Telecharger OPNsense-25.1-dvd-amd64.iso sur Proxmox, puis deployer fw_*

### DEFERRED-2 : Roles Ansible manquants (Phase 8)
**Concerne** : roles/web/ (Nginx), roles/mail/ (Postfix+Dovecot), roles/backup/ (Borg)
**Action** : Creer ces roles en Phase 8

### DEFERRED-3 : NAT Proxmox temporaire a persister OU supprimer
**Action** : Persister le NAT dans /etc/network/interfaces pour qu'il survive au reboot
  Voir section BUG-M1 pour le detail

### DEFERRED-4 : Provision Samba AD DC01 necessite input interactif
**Action** : samba-tool domain provision --use-rfc2307 est semi-interactif.
Peut aussi etre non-interactif avec les bons parametres Ansible.
Le role dc doit etre verifie et relance apres BUG-C1 fixe.

---

## PLAN DE CORRECTION (ordre)

1. Persister NAT Proxmox (/etc/network/interfaces)
2. Relancer ansible common role sur les 6 VMs affectees
3. Relancer ansible roles applicatifs (dc -> fs -> db -> app -> bastion -> proxy)
4. Telecharger ISO OPNsense + deployer firewalls
5. Creer roles/backup/ (Phase 8)

---
