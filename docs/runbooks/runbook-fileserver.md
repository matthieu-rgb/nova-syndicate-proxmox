# Runbook -- Fileserver (FS1 / Samba)

## Perimetre

FS1 (192.168.20.11), Samba 4.17.x, membre de nova-syndicate.local, partages CIFS/SMB.

## Partages existants

| Nom | Chemin | Visible | Groupe proprietaire |
|-----|--------|---------|---------------------|
| lyon | /srv/samba/lyon | oui | lyon-staff |
| marseille | /srv/samba/marseille | oui | marseille-staff |
| commun | /srv/samba/commun | oui | domain users |
| finance | /srv/samba/finance | non | finance |
| it-restricted | /srv/samba/it-restricted | non | it-admins |

## Operations courantes

### Verifier les partages actifs

```bash
ssh debian@192.168.20.11
sudo smbstatus --shares
```

### Tester un acces partage depuis le reseau

```bash
# Depuis bastion ou toute machine du reseau
smbclient //192.168.20.11/lyon -U 'nova-syndicate.local\<username>'
```

### Ajouter un partage

1. Modifier /etc/samba/smb.conf (section [nouveau-partage])
2. Creer le repertoire et chgrp vers le bon groupe AD
3. `sudo systemctl reload smbd`

### Verifier membership groupe (winbind)

```bash
sudo id 'nova-syndicate\<username>'
sudo wbinfo -u | grep <username>
```

### Relancer winbind (prudence : peut bloquer sudo)

```bash
# Verifier d'abord que la session sudo est active
sudo systemctl restart winbind
sudo systemctl status winbind
```

## Diagnostic

### Winbind ne repond pas

```bash
sudo wbinfo --ping-dc
sudo wbinfo -t   # test trust secret
sudo net ads testjoin
```

### Probleme de permissions

```bash
ls -la /srv/samba/<partage>/
sudo getfacl /srv/samba/<partage>/
# Verifier que le groupe AD est proprietaire
```

### Re-joindre le domaine si kicked out

```bash
sudo net ads leave -U Administrator
sudo net ads join -U Administrator
sudo systemctl restart winbind smbd nmbd
```

## Notes techniques

- full_audit VFS desactive (opnames mkdir/rename invalides Samba 4.17). TODO : valider opnames corrects et re-activer pour NIS2.
- idmap : backend RID, range 10000-99999
- Config : /etc/samba/smb.conf
- Playbook Ansible : playbooks/fileserver.yml
