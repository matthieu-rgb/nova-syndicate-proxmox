# Runbook : MFA TOTP bastion01

## Contexte

MFA TOTP (Google Authenticator / RFC 6238) sur bastion01 (192.168.15.2).
SSH login : cle publique + TOTP. sudo : mot de passe Unix + TOTP.
Gere par le role Ansible `mfa_totp`. Enrollment individuel hors-Ansible.

---

## Procedure : Enrollment nouvel admin

### Prerequis

- Le compte Linux existe sur bastion01 (cree via role `common`)
- L'admin a deja acces SSH (cle publique en place)
- App TOTP installee sur son telephone (Google Authenticator, Authy, Bitwarden)

### Etape 1 : Generer le secret TOTP

L'admin (ou un administrateur delegue) se connecte sur bastion01 et execute :

```bash
# Option A : google-authenticator interactif (recommande si TTY disponible)
google-authenticator -t -d -f -r 3 -R 30 -w 3 -e 5 \
  -l "<username>@bastion-nova-syndicate" \
  -s ~/.google_authenticator

# Option B : generation Python (non-interactif, si pas de TTY)
python3 - << 'EOF'
import base64, os, struct

raw = os.urandom(20)
secret = base64.b32encode(raw).decode().rstrip("=")
codes = [str(int.from_bytes(os.urandom(4), "big") % 100000000).zfill(8) for _ in range(5)]

content = secret + "\n" + "\" TOTP_AUTH\n\" DISALLOW_REUSE\n\" RATE_LIMIT 3 30\n\" WINDOW_SIZE 3\n"
for c in codes: content += c + "\n"

with open(os.path.expanduser("~/.google_authenticator"), "w") as f:
    f.write(content)
os.chmod(os.path.expanduser("~/.google_authenticator"), 0o400)

print("SECRET:", secret)
print("BACKUP:", codes)
print("URI:", f"otpauth://totp/<user>@bastion-nova-syndicate?secret={secret}&issuer=Nova-Syndicate")
EOF
```

### Etape 2 : Afficher le QR code et scanner

```bash
qrencode -t ANSIUTF8 "otpauth://totp/<username>@bastion-nova-syndicate?secret=<SECRET>&issuer=Nova-Syndicate"
```

Ouvrir l'app TOTP sur le telephone, scanner le QR code.
Verifier un code affiche par l'app avant de continuer.

### Etape 3 : Securiser les permissions

```bash
chmod 400 ~/.google_authenticator
ls -la ~/.google_authenticator   # doit montrer -r--------
```

### Etape 4 : Stocker le secret dans Ansible-vault

```bash
# Sur le Mac (poste admin)
cd nova-syndicate-ansible
ansible-vault edit group_vars/all/mfa_secrets.yml
```

Format YAML :
```yaml
mfa_totp_secrets:
  <username>:
    bastion01:
      secret: "<contenu_fichier_.google_authenticator>"
      enrolled_date: "YYYY-MM-DD"
      backup_codes:
        - "XXXXXXXX"
        - "XXXXXXXX"
        - "XXXXXXXX"
        - "XXXXXXXX"
        - "XXXXXXXX"
```

### Etape 5 : Tester depuis une nouvelle session SSH

```bash
# Nouveau terminal (ne pas fermer la session existante)
ssh debian@192.168.15.2
# Attendu : "Verification code:" -> entrer code TOTP -> shell
```

Tester aussi sudo :
```bash
sudo whoami
# Attendu : code TOTP + mot de passe -> "root"
```

### Etape 6 : Mettre a jour host_vars

```yaml
# host_vars/bastion01.yml
mfa_totp_users:
  - debian
  - <nouveau_username>
```

---

## Procedure : Revocation admin

### Etape 1 : Supprimer le fichier TOTP

```bash
ssh debian@192.168.15.2
sudo rm /home/<username>/.google_authenticator
```

La revocation est immediate. La prochaine connexion de cet utilisateur echouera sur le TOTP (si `nullok` est desactive) ou passera sans TOTP (si `nullok` est active).

### Etape 2 : Desactiver le compte si necessaire

```bash
sudo usermod -L <username>   # lock du password Unix
sudo usermod --expiredate 1 <username>   # expiration du compte
```

### Etape 3 : Nettoyer le vault

```bash
ansible-vault edit group_vars/all/mfa_secrets.yml
# Supprimer le bloc de l'admin revoque
```

### Etape 4 : Documenter dans audit

```bash
# Ajouter une entree dans SESSION-LOG.md ou le systeme d'audit interne
echo "$(date): Revocation TOTP <username> par <admin>" | sudo tee -a /var/log/nova-audit.log
```

---

## Procedure : Recuperation lockout

### Si TOTP rejete (code expire, clock drift)

```bash
# Verifier synchronisation NTP sur bastion01
ssh debian@192.168.15.2
sudo chronyc tracking | grep "System time"
# Si offset > 90s : resynchroniser
sudo chronyc makestep
```

### Si device perdu (telephone casse/vole)

Utiliser un backup code :
```
Verification code: 02356350  # un des 5 backup codes (usage unique)
```

Backup codes stockes dans Ansible-vault (`group_vars/all/mfa_secrets.yml`).

### Si tous les backup codes epuises ou fichier corrompu

**Via console Proxmox (hors-bande)** :
```bash
# Sur le Mac
ssh root@192.168.18.50
qm terminal 102   # console serie bastion01
# Login root (mot de passe Proxmox)
rm /home/debian/.google_authenticator
# Regenerer TOTP (voir procedure enrollment)
```

**Ou rollback snapshot Proxmox** (dernier recours) :
```bash
ssh root@192.168.18.50
qm stop 102
qm rollback 102 pre-mfa-totp-2026-05-11
qm start 102
```

> Attention : rollback supprime toutes les modifications depuis le snapshot.

### Restaurer les backups PAM si configuration cassee

```bash
# Via console Proxmox ou session root locale
sudo cp /etc/pam.d/sshd.bak-pre-mfa-2026-05-11 /etc/pam.d/sshd
sudo systemctl reload sshd
# Tester SSH depuis nouvelle session avant de fermer la session courante
```

---

## Workaround Ansible (ControlMaster pre-auth)

Ansible en mode batch ne peut pas fournir le TOTP keyboard-interactive.
Etablir un ControlMaster interactif avant de lancer ansible-playbook :

```bash
# Terminal 1 : etablir le ControlMaster (fournir TOTP)
ssh -o ControlMaster=yes \
    -o ControlPath='/tmp/ansible-cp-debian@192.168.15.2:22' \
    -o ControlPersist=600 \
    debian@192.168.15.2

# Terminal 2 : Ansible reutilise le socket existant
cd nova-syndicate-ansible
ansible-playbook playbooks/deploy_mfa.yml --limit bastion01
```

Le ControlPath correspond a celui configure dans `ansible.cfg` :
`/tmp/ansible-cp-%%r@%%h:%%p`

---

## Tests apres modification

Apres toute modification de `/etc/pam.d/sshd`, `/etc/ssh/sshd_config`, ou `/etc/pam.d/sudo` :

```bash
# 1. Valider syntaxe sshd_config avant reload
sudo sshd -t && echo "CONFIG OK"

# 2. Reload (jamais restart si sessions actives)
sudo systemctl reload sshd

# 3. Tester depuis NOUVELLE session (ne pas fermer la session courante)
ssh debian@192.168.15.2
# Si OK -> fermer la session de secours

# 4. Tester sudo dans la nouvelle session
sudo whoami
```

---

## FAQ

**Le code TOTP est rejete malgre une saisie correcte**

- Clock drift : verifier `sudo chronyc tracking`, offset doit etre < 90s
- Replay attack protection (DISALLOW_REUSE) : un code ne peut etre utilise qu'une fois, attendre le prochain code (30s)
- Rate limit : 3 echecs en 30s bloquent temporairement. Attendre 30s.

**Perte du telephone**

Utiliser un backup code (usage unique). Stocker les backup codes dans Bitwarden, 1Password, ou imprimer et conserver hors-site.

**MFA requis a chaque sudo dans la meme session**

Le `timestamp_timeout=15` permet de ne pas redemander pendant 15 minutes apres une validation reussie. Si la redemande survient, la cache a expire (> 15 min) ou la session a change.

---

## Mapping NIS2

| Article NIS2 | Controle |
|---|---|
| Art. 21.b (acces distants) | SSH = cle publique + TOTP (2 facteurs) |
| Art. 21.b (acces privilegies) | sudo = mot de passe + TOTP (2 facteurs) |
| Art. 21.e (MFA systemes critiques) | Bastion = porte d'entree unique, MFA obligatoire |
| Art. 21.i (journalisation) | /var/log/auth.log (tentatives SSH et sudo) |

---

## Dette T-ANSIBLE-SERVICE-ACCOUNT

Ansible en mode batch ne peut pas s'authentifier avec TOTP (keyboard-interactive non automatisable).

**Solution definitive** : compte service `ansible` avec PAM conditionnel :
```
# /etc/pam.d/sshd et /etc/pam.d/sudo
auth [success=1 default=ignore] pam_succeed_if.so user = ansible
auth required pam_google_authenticator.so nullok
```
Le compte `ansible` bypass le TOTP, les admins humains le conservent.
Effort estime : 2h. Planifie pour Phase III.

---

## References

- ADR-0018 : Decision MFA TOTP bastion (ce document est complementaire)
- ADR-0014 : Bastion Teleport MFA Phase III (remplacement futur)
- Role Ansible : `ansible/roles/mfa_totp/`
- Vault secrets : `ansible/group_vars/all/mfa_secrets.yml` (chiffre)
- libpam-google-authenticator : https://github.com/google/google-authenticator-libpam
- RFC 6238 : TOTP Time-Based One-Time Password
