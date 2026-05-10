# T-CLOUD-BACKUP-PREP -- Log de session

Date : 2026-05-10

## Objectif

Borg server sur VPS Hetzner, accessible UNIQUEMENT via tunnel WireGuard
(10.30.0.1), append-only, repo /srv/borg-repo/nova-syndicate/.

## Architecture cible

```
VPS Hetzner (10.30.0.1 via wg0)
  borguser : /home/borguser
  /srv/borg-repo/nova-syndicate/  (quota monitoring 15 GB)
  SSH borguser : from="10.30.0.2" uniquement

BACKUP01 (10.30.0.2 via wg0)
  /root/.ssh/id_ed25519_borg-cloud  (cle SSH dediee)
  /etc/borg/passphrase (600 root, passphrase chiffrement)
```

## Etat initial (CHECKPOINT 1)

### VPS Hetzner

- Disk / : 75G total / 30G used / 43G free (OK pour 15 GB Borg)
- /srv : vide
- borgbackup : non installe
- borguser : non cree
- WireGuard handshake : 57s (TUNNEL UP)
- IPsec : 4/4 INSTALLED
- Wazuh : 7/7 Active
- Tailscaled + Docker : actifs (inchanges)

### BACKUP01

- borg : installe (/usr/bin/borg, version 1.2.4)
- /root/.ssh/id_ed25519_borg-cloud : absent (a creer)
- /etc/borg/ : absent (a creer)
- WireGuard handshake : 1 min (TUNNEL UP)

## Installation -- COMPLETE 2026-05-10

### Phase 2 -- VPS setup

- borgbackup 1.2.8 installe
- borguser : uid=1001, /home/borguser
- /srv/borg-repo/nova-syndicate/ : 700 borguser:borguser
- borg-disk-monitor.sh : cron 23h00 daily, alerte si > 15 GB
- UFW backup 2 : user.rules.bak2-20260510-...
- UFW : SSH TCP 22 sur wg0 ajoutee (borguser via tunnel uniquement)

### Phase 3 -- Restriction SSH borguser

- /etc/ssh/sshd_config.d/50-borguser.conf cree
- ForceCommand : borg serve --append-only --restrict-to-path /srv/borg-repo/nova-syndicate/
- PermitTTY no, AllowTcpForwarding no, X11Forwarding no
- ssh.service reloade (ubuntu : ssh.service, pas sshd.service)

### Phase 4 -- Cle SSH Borg BACKUP01

- /root/.ssh/id_ed25519_borg-cloud genere sur BACKUP01
- Fingerprint : SHA256:pJiEFkqc3U8eHjhF/zCSkzwWFx1h7c2ruHFbi/3hFxU
- authorized_keys borguser : from="10.30.0.2", command=, no-port-forwarding, no-X11, no-pty

### Phase 5 -- Tests SSH

| Test | Source | Resultat |
|---|---|---|
| SSH borguser via wg0 | BACKUP01 (10.30.0.2) | Borg 1.2.8 response -- OK |
| SSH borguser via localhost | VPS (127.0.0.1) | Permission denied -- from= bloque |
| SSH via Tailscale SSH | Mac | Tailscale SSH daemon bypasse sshd -- DETTE T-TAILSCALE-SSH-HARDEN |

### Phase 6 -- Repo Borg + premier backup

- Passphrase : stockee dans /etc/borg/passphrase (600 root) sur BACKUP01
  ATTENTION : a migrer dans Ansible vault (T-VAULT-INTEGRATE)
- Encryption : repokey-blake2
- Init : OK, cle stockee dans le repo
- Premier backup test-2026-05-10-1740 : /etc/hostname, 0.09s, 108K sur VPS
- borg list : archive visible

### Dette technique identifiee

- T-TAILSCALE-SSH-HARDEN : Tailscale SSH daemon intercepte les connexions
  borguser@tailscale -- ForceCommand ne s'applique pas.
  Fix : soit desactiver Tailscale SSH, soit exclure borguser des ACL Tailscale.
- T-VAULT-INTEGRATE : migrer /etc/borg/passphrase vers Ansible vault.
- T-BORG-KEY-EXPORT : exporter la cle Borg (borg key export) et la sauvegarder
  hors du repo (gestionnaire de mots de passe).

