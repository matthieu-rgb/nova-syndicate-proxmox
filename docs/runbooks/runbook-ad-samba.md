# Runbook -- Active Directory / Samba

## Perimetre

DC1 (192.168.20.10), Samba 4.17.12, domaine nova-syndicate.local.

## Operations courantes

### Verifier l'etat du domaine

```bash
ssh debian@192.168.20.10
sudo samba-tool domain info 192.168.20.10
sudo systemctl status samba-ad-dc
```

### Lister les utilisateurs AD

```bash
sudo samba-tool user list | sort
sudo samba-tool user list | wc -l  # doit etre >= 91 (85 + 6 systeme)
```

### Creer un utilisateur

```bash
sudo samba-tool user create <username> <password> \
  --given-name=<prenom> --surname=<nom> \
  --mail-address=<email> \
  --userou="OU=<site>"
```

Sites valides : Lyon, Marseille, MobileAgents.

### Reinitialiser un mot de passe

```bash
sudo samba-tool user setpassword <username>
```

### Ajouter a un groupe

```bash
sudo samba-tool group addmembers <groupe> <username>
```

Groupes existants : lyon-staff, marseille-staff, mobile-agents, finance, it-admins, managers, rh, direction.

### Desactiver / reactiver un compte

```bash
sudo samba-tool user disable <username>
sudo samba-tool user enable <username>
```

### Verifier replication (si multi-DC futur)

```bash
sudo samba-tool drs showrepl
```

## Diagnostic

### Probleme Kerberos / auth

```bash
sudo samba-tool testparm
sudo journalctl -u samba-ad-dc -n 50
```

### DNS Samba

```bash
sudo samba-tool dns query 192.168.20.10 nova-syndicate.local @ ALL
host nova-syndicate.local 192.168.20.10
```

### Rejoindre une machine au domaine (exemple Linux)

```bash
# Sur la machine cible :
sudo net ads join -U Administrator
sudo systemctl restart winbind smbd
```

## Escalade

- Config : /etc/samba/smb.conf
- Logs Samba : /var/log/samba/
- Base AD : /var/lib/samba/private/ (ne pas modifier directement)
- Playbook Ansible : playbooks/users-bulk-create.yml
