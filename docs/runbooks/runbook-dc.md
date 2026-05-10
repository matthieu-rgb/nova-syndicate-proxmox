# Runbook : dc (Samba Active Directory Domain Controller)

## 1. Perimetre

Le role `dc` provisionne et gere le controleur de domaine Active Directory du projet Nova Syndicate. Il s'appuie sur Samba 4 en mode "active directory domain controller" sur la VM dc01 (192.168.20.10, VLAN SERVERS). Le domaine provisionne est `nova-syndicate.local`, realm Kerberos `NOVA-SYNDICATE.LOCAL`. Le DNS interne est assure par Samba (backend SAMBA_INTERNAL), et le serveur DHCP (isc-dhcp-server) distribue les adresses sur le VLAN USERS (192.168.30.0/26, plage 192.168.30.100-200).

Le role couvre l'ensemble du cycle de vie AD : provisioning initial du domaine, configuration DNS, configuration DHCP pour le VLAN USERS, creation des unites organisationnelles (OU), groupes et comptes utilisateurs de service, et planification des sauvegardes AD (samba-tool ntds backup). dc01 est l'unique DC du projet (single DC, pas de replication). La haute disponibilite AD n'est pas implementee dans la phase actuelle du projet.

Toutes les VMs du VLAN SERVERS qui joignent le domaine (fs01 en particulier via le role fileserver) dependent de dc01. La disponibilite de dc01 est critique pour l'authentification Kerberos, la resolution DNS interne, et la distribution DHCP sur le VLAN USERS.

## 2. Prerequis

### Dependances de roles

- `common` doit etre execute avant `dc`.
- `hardening` doit etre execute avant `dc` (les regles nftables AD doivent etre en place).
- Le role `dc` doit etre execute avant `fileserver` (fs01 rejoint le domaine apres que dc01 existe).

### Reseau

- dc01 doit avoir une IP statique : 192.168.20.10/28, gateway 192.168.20.1 (OPNsense FW-INT-LYON).
- Les ports AD doivent etre ouverts par nftables (configures via `hardening_extra_nft_rules` dans group_vars/domain_controllers) :
  - TCP : 53, 88, 135, 139, 389, 445, 464, 636, 3268, 3269
  - UDP : 53, 67, 68, 88, 123, 137, 138, 389, 464
- dc01 est le DNS primaire pour tout le parc (nova_dns_primary: 192.168.20.10).

### Packages deployes par le role

`samba`, `smbclient`, `winbind`, `krb5-user`, `isc-dhcp-server`, `dnsutils`, `acl`

### Acces

- SSH via bastion : `ssh -J debian@192.168.15.2 debian@192.168.20.10`

## 3. Installation

### ATTENTION : le provisioning Samba est destructif

`samba-tool domain provision` efface et reinitialise l'annuaire. Ne l'executer que sur un DC vierge ou en cas de DR complete. Le role est protege par un test `stat` sur `/etc/samba/smb.conf` : si le fichier existe, la task de provisioning est skippee.

### Verification pre-deploiement

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Verifier que dc01 est accessible et que samba n'est pas deja provisionne
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "test -f /etc/samba/smb.conf && echo 'DEJA PROVISIONNE - NE PAS REJOUER PROVISION' || echo 'OK a provisionner'"
```

### Dry-run

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l domain_controllers \
  --tags dc \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement initial (premier provisioning)

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l domain_controllers \
  --tags dc \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Rejouer uniquement les users/groupes AD (apres le provisioning initial)

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l domain_controllers \
  --tags dc,users \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes

1. `tasks/samba_provision.yml` -- provisioning AD (si /etc/samba/smb.conf absent)
2. `tasks/dns.yml` -- zones DNS supplementaires
3. `tasks/dhcp.yml` -- configuration isc-dhcp-server VLAN 30
4. `tasks/users_groups.yml` -- OU, groupes, comptes de service
5. `tasks/backup.yml` -- script de sauvegarde AD + cron

## 4. Configuration

### Variables principales (group_vars/domain_controllers/vars.yml)

```yaml
samba_server_role: "active directory domain controller"
samba_dns_backend: "SAMBA_INTERNAL"
dhcp_range_start: "192.168.30.100"
dhcp_range_end: "192.168.30.200"
dhcp_subnet: "192.168.30.0"
krb5_ticket_lifetime: "10h"
krb5_renew_lifetime: "7d"
hardening_extra_nft_rules:
  - "tcp dport { 53, 88, 135, 139, 389, 445, 464, 636, 3268, 3269 } accept"
  - "udp dport { 53, 67, 68, 88, 123, 137, 138, 389, 464 } accept"
```

### Variables Vault (group_vars/domain_controllers/vault.yml)

Les variables suivantes sont chiffrees dans le vault Ansible :
```yaml
vault_samba_admin_password: "..."    # Mot de passe Administrator AD
vault_krb5_admin_password: "..."    # Mot de passe Kerberos admin
```

### Parametres Kerberos (/etc/krb5.conf)

```ini
[libdefaults]
  default_realm = NOVA-SYNDICATE.LOCAL
  dns_lookup_realm = false
  dns_lookup_kdc = true
  ticket_lifetime = 10h
  renew_lifetime = 7d
```

### DHCP (VLAN USERS)

- Subnet : 192.168.30.0/255.255.255.192
- Range : 192.168.30.100 -- 192.168.30.200
- Router (option 3) : 192.168.30.1 (gateway VLAN 30 sur OPNsense)
- DNS (option 6) : 192.168.20.10 (dc01)
- Domain (option 15) : nova-syndicate.local

## 5. Validation post-deploiement

### Verifier le service Samba AD

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl is-active samba-ad-dc && \
   sudo samba-tool domain info 192.168.20.10"
```

### Verifier la resolution DNS interne

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "host -t A nova-syndicate.local 192.168.20.10 && \
   host -t SRV _kerberos._tcp.nova-syndicate.local 192.168.20.10"
```

### Tester l'authentification Kerberos

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo kinit Administrator@NOVA-SYNDICATE.LOCAL && \
   sudo klist && sudo kdestroy"
```

### Verifier la liste des utilisateurs AD

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool user list"
```

### Verifier le DHCP

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl is-active isc-dhcp-server && \
   sudo cat /var/lib/dhcp/dhcpd.leases | grep -c 'lease '"
```

### Verifier les niveaux fonctionnels AD

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool domain level show"
```

## 6. Operations courantes

### Creer un utilisateur AD

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool user create jdupont 'MotDePasse!123' \
   --given-name='Jean' --surname='Dupont' \
   --mail-address='jdupont@nova-syndicate.local' \
   --department='Logistique'"
```

### Ajouter un utilisateur a un groupe

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool group addmembers GRP_LOGISTIQUE jdupont"
```

### Reinitialiser un mot de passe utilisateur

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool user setpassword jdupont --newpassword='NouveauMotDePasse!456'"
```

### Desactiver un compte utilisateur

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool user disable jdupont"
```

### Redemarrer Samba AD

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl restart samba-ad-dc && \
   sudo systemctl is-active samba-ad-dc"
```

### Lancer une sauvegarde AD manuelle

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo /usr/local/bin/samba-ad-backup.sh"

# Verifier le resultat
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "ls -lh /var/backups/samba-ad/"
```

### Consulter les logs Samba

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo journalctl -u samba-ad-dc --since '1 hour ago' | tail -50"
```

## 7. Troubleshooting

### Incident 1 : samba-ad-dc ne demarre pas apres reboot

**Symptome :** `systemctl status samba-ad-dc` retourne `failed` ou `activating` sans passer a `active`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo journalctl -u samba-ad-dc -n 50 --no-pager"

# Verifier les permissions sur le repertoire Samba
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "ls -la /var/lib/samba/private/"
```

**Fix :**
```bash
# Correction permissions frequente
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo chown -R root:root /var/lib/samba/private/ && \
   sudo chmod 700 /var/lib/samba/private/ && \
   sudo systemctl start samba-ad-dc"
```

### Incident 2 : Resolution DNS interne en echec depuis les clients

**Symptome :** Les VMs du VLAN SERVERS ne resolvent pas `nova-syndicate.local` ou `dc01.nova-syndicate.local`.

**Diagnostic :**
```bash
# Tester depuis fs01
ssh -J debian@192.168.15.2 debian@192.168.20.11 \
  "dig dc01.nova-syndicate.local @192.168.20.10 +short && \
   cat /etc/resolv.conf"
```

**Fix :**
```bash
# Verifier que le service DNS Samba ecoute sur 192.168.20.10
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo ss -tlunp | grep ':53'"

# Redemarrer Samba si le DNS ne repond pas
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl restart samba-ad-dc"

# Verifier resolv.conf sur les clients (doit pointer vers 192.168.20.10)
ansible servers -i inventory/hosts.yml -m command \
  -a "cat /etc/resolv.conf" \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian
```

### Incident 3 : Tickets Kerberos expires, authentification echouee

**Symptome :** `kinit` echoue avec `KDC_ERR_PREAUTH_FAILED` ou les services integres au domaine (fs01) rejettent les authentifications.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool dns query 192.168.20.10 nova-syndicate.local @ ALL"

# Verifier la synchronisation NTP (critique pour Kerberos)
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "chronyc tracking | grep 'System time'"
```

**Fix :** Kerberos est extremement sensible au drift NTP (tolerance 5 minutes). Si l'offset NTP est superieur a 5 minutes, forcer `chronyc makestep` sur dc01 ET sur les clients, puis retenter `kinit`.

### Incident 4 : DHCP ne distribue plus d'adresses sur le VLAN USERS

**Symptome :** Les postes du VLAN 30 n'obtiennent plus d'adresse IP.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl status isc-dhcp-server && \
   sudo journalctl -u isc-dhcp-server -n 30 --no-pager"

# Verifier la plage DHCP
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo cat /etc/dhcp/dhcpd.conf | grep -E 'range|subnet'"
```

**Fix :**
```bash
# Redemarrer isc-dhcp-server
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo systemctl restart isc-dhcp-server && \
   sudo systemctl is-active isc-dhcp-server"
```

Si la plage est epuisee (192.168.30.100-200 = 101 adresses), verifier les baux actifs dans `/var/lib/dhcp/dhcpd.leases` et identifier les baux fantomes (machines disparues).

### Incident 5 : Mot de passe Administrator AD perdu

**Symptome :** Impossible de s'authentifier en tant qu'Administrator sur le domaine.

**Diagnostic :** Verifier d'abord si le vault Ansible contient le mot de passe correct : `ansible-vault view group_vars/domain_controllers/vault.yml`.

**Fix (reinitialisation offline) :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10

# Arreter Samba
sudo systemctl stop samba-ad-dc

# Reinitialiser le mot de passe Administrator en mode offline
sudo samba-tool user setpassword Administrator \
  --newpassword='NouveauAdmin!2024' \
  -H /var/lib/samba/private/sam.ldb

# Redemarrer
sudo systemctl start samba-ad-dc

# Mettre a jour vault_samba_admin_password dans le vault Ansible
```

### Incident 6 : Replication SYSVOL corrompue (si futur DC secondaire)

**Symptome :** `samba-tool ntacl sysvolcheck` retourne des erreurs.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool ntacl sysvolcheck 2>&1 | tail -20"
```

**Fix :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10 \
  "sudo samba-tool ntacl sysvolreset"
```

## 8. Disaster Recovery

### Contexte DR

dc01 est le DC unique et critique. Sa perte impacte : authentification de toutes les VMs jointes au domaine, DNS interne, DHCP VLAN USERS. RTO cible : 2 heures. RPO : 24 heures (sauvegarde quotidienne via Borg).

### Procedure de restauration complete

**Etape 1 : Provisionner une nouvelle VM dc01 dans Proxmox**

Via Terraform :
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/
terraform apply -target=proxmox_vm_qemu.dc01
```

La nouvelle VM doit avoir l'IP 192.168.20.10, VLAN 20.

**Etape 2 : Deployer les roles de base**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  -l domain_controllers \
  --tags common,hardening \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**Etape 3 : Recuperer la sauvegarde AD depuis backup01**
```bash
ssh -J debian@192.168.15.2 debian@192.168.50.2

# Lister les archives Borg disponibles
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg list /var/backups/borg/configs

# Extraire la sauvegarde AD la plus recente
sudo BORG_PASSPHRASE=$(cat /etc/borg/passphrase) \
  borg extract /var/backups/borg/configs::nova-configs-<DATE> \
  var/backups/samba-ad/

# Copier vers dc01
scp -J debian@192.168.15.2 \
  /var/backups/samba-ad/samba-backup-<DATE>.tar.gz \
  debian@192.168.20.10:/tmp/
```

**Etape 4 : Restaurer l'AD sur dc01**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.10

sudo systemctl stop samba-ad-dc

# Extraire la sauvegarde
sudo tar -xzf /tmp/samba-backup-<DATE>.tar.gz -C /

# Restaurer avec samba-tool
sudo samba-tool domain backup restore \
  --backup-file=/tmp/samba-backup-<DATE>.tar.gz \
  --newservername=dc01 \
  --targetdir=/var/lib/samba-restore/

sudo systemctl start samba-ad-dc
```

**Etape 5 : Valider le domaine restaure**

Reprendre les tests de la section 5. Verifier en particulier la resolution DNS et les tickets Kerberos.

**Etape 6 : Rejoindre fs01 au domaine si necessaire**
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l fileservers \
  --tags fileserver,domain_join \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**RTO :** 2 heures (provisioning VM + restore AD + validation).
**RPO :** 24 heures (sauvegarde Borg quotidienne via cron sur dc01).

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
Le controleur de domaine est le systeme d'authentification central. Sa compromission entraine la compromission totale du domaine (DCSync, pass-the-hash, Kerberoasting). Les mesures appliquees : mot de passe Administrator complexe (vault), tickets Kerberos TTL limites a 10h, acces SSH restreint au bastion, ports AD fermes aux reseaux non autorises via nftables.

**Art. 21.2.c -- Gestion des incidents :**
Les evenements d'authentification AD sont collectes par Wazuh (agent sur dc01) et centralises sur app01 (192.168.20.13). Les regles NIS2 personnalisees dans Wazuh alertent sur les operations AD sensibles (creation de compte, modification de groupe privilegie, echec d'authentification repetitif).

**Art. 21.2.e -- Continuite d'activite :**
Sauvegarde quotidienne du domaine via `samba-tool ntds backup` + Borg vers backup01 + sync cloud VPS Hetzner. RTO 2h, RPO 24h documentes dans la procedure DR.

**Art. 21.2.f -- Audit :**
Les logs Samba (niveau 3) incluent les operations LDAP, les authentifications Kerberos et les modifications d'annuaire. Collecte via Wazuh agent, retention 90 jours sur app01.

### Comptes privilegies AD

- `Administrator` : compte de service AD, mot de passe dans vault Ansible, utilise uniquement pour les operations de provisioning et DR.
- Aucun compte utilisateur humain ne doit avoir des droits "Domain Admin" en fonctionnement normal.
- Les comptes de service (app_logistique, app_rh) ont des droits minimaux (acces base de donnees uniquement, pas de droits AD).

## 10. References

### Internes au projet

- `roles/dc/defaults/main.yml` -- packages et variables du role
- `roles/dc/tasks/samba_provision.yml` -- provisioning AD
- `roles/dc/tasks/dhcp.yml` -- configuration DHCP
- `group_vars/domain_controllers/vars.yml` -- variables du groupe
- `docs/adressage_vlsm.md` -- plan d'adressage VLSM
- Runbook fileserver : `docs/runbooks/runbook-fileserver.md`
- Runbook Wazuh : `docs/runbooks/runbook-wazuh.md`

### Documentation upstream

- Samba Wiki -- AD DC : https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller
- samba-tool documentation : https://www.samba.org/samba/docs/current/man-html/samba-tool.8.html
- ISC DHCP Server : https://kb.isc.org/docs/isc-dhcp-44-manual-pages-dhcpd
- MIT Kerberos documentation : https://web.mit.edu/kerberos/krb5-latest/doc/
