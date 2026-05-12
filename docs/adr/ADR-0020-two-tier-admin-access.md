# ADR-0020 : Modele d'acces administratif two-tier

## Status
Accepted

## Date
2026-05-11

## Contexte

Un audit architectural a revele que le fichier `~/.ssh/config` du poste admin (Mac M4 Pro)
configurait ProxyJump via l'hyperviseur Proxmox (192.168.18.50) plutot que via bastion01
(192.168.15.2) pour les VMs metier. Cette configuration permettait de contourner le MFA
TOTP deploye sur bastion01 (ADR-0018) pour atteindre les VMs metier directement.

**Root cause du bypass :**

L'hyperviseur Proxmox possede des interfaces kernel directement sur tous les VLANs internes
via les bridges VLAN (vmbr1.15, vmbr1.20, vmbr1.30, vmbr1.50). Le kernel Linux route le
trafic SSH de 192.168.18.0/24 (reseau admin) vers 192.168.20.0/28 (SERVERS) directement
via vmbr1.20, sans que ce trafic ne traverse FW-INT-LYON.

```
# Route kernel Proxmox - bypass FW-INT-LYON
192.168.20.0/28 dev vmbr1.20 proto kernel scope link src 192.168.20.5
```

Validation du bypass (avant correctif) :
```
ssh -o ProxyJump=none -o ConnectTimeout=3 debian@192.168.20.12 hostname
# Resultat : db01  (bypass confirme, sans TOTP)
```

FW-INT-LYON n'a aucune interface sur 192.168.18.0/24. Des regles sur FW-INT-LYON seules
ne suffisent pas pour proteger ce chemin.

**Exigences contradictoires du break-glass :**

Si bastion01 est indisponible (crash VM, probleme systemd, corruption config PAM),
l'impossibilite d'acceder a l'infrastructure via Proxmox creerait un SPOF dur. Le break-glass
via Proxmox direct est necessaire pour maintenir la capacite d'intervention d'urgence.

## Decision

Adoption d'un **modele d'acces two-tier** avec enforcement a deux niveaux.

### Tier 1 -- Acces operationnel (normal)

| Attribut | Valeur |
|---|---|
| Workflow | Mac -> bastion01 (MFA TOTP) -> VM cible |
| Protocole | SSH ProxyJump pubkey + TOTP keyboard-interactive |
| Acces | Sysadmins operationnels |
| Audit | syslog bastion01 + Wazuh SIEM (auth.log) |

Enforcement multi-couche :
- **Couche 1 (client)** : `~/.ssh/config` ProxyJump force vers bastion01
- **Couche 2 (hyperviseur)** : iptables FORWARD chain sur Proxmox
  - DROP SSH TCP 22 de 192.168.18.0/24 vers tous les VLANs internes
  - Persistant via `/etc/network/interfaces` post-up
- **Couche 3 (firewall)** : FW-INT-LYON (defense-in-depth, belt-and-suspenders)
  - Regles existantes : `fwint_bastion_to_servers_ssh` (allow) + block_all
  - Nouvelles regles : alias `net_proxmox_admin` + DROP sur vtnet0 si trafic passe par FW-INT

La couche 2 (Proxmox iptables) est le **verrou effectif** pour le chemin de bypass identifie.

### Tier 2 -- Hyperviseur admin break-glass

| Attribut | Valeur |
|---|---|
| Workflow | Mac -> Proxmox direct (SSH 192.168.18.50) |
| Protocole | SSH pubkey root (depuis subnet admin) |
| Acces | Administrateur senior uniquement (1-2 personnes max) |
| Usage | Urgence si bastion KO, snapshots, rollback VM, console serie |
| Audit | /var/log/pveproxy/access.log + systemd journal Proxmox |

Tier 2 ne passe PAS par bastion (justification : le bastion est precisement ce qu'on doit
pouvoir reparer/restaurer depuis ce tier). L'acces est restreint au subnet admin 192.168.18.0/24
uniquement via FW-EXT-LYON WAN block_all (acces LAN physique ou VPN Tailscale requis).

### Schema

```
          Mac
           |
    +------+------+
    |             |
[Tier 1]      [Tier 2]
bastion01      Proxmox
(MFA TOTP)  (SSH pubkey)
    |             |
    |    [iptables FORWARD]
    |      BLOCK 18.0/24->VLANs
    |             |
 [FW-INT-LYON]   |
  (belt)         |
    |             |
   VMs          VMs
  metier       metier
```

### Implementation Tier 1 -- Proxmox iptables (couche primaire)

```bash
# Appliquer immediatement
iptables -I FORWARD 1 -s 192.168.18.0/24 -d 192.168.20.0/28 -p tcp --dport 22 -j LOG \
  --log-prefix "ADR-0020-BLOCK: " --log-level 4
iptables -I FORWARD 2 -s 192.168.18.0/24 -d 192.168.20.0/28 -p tcp --dport 22 -j DROP
iptables -I FORWARD 3 -s 192.168.18.0/24 -d 192.168.15.0/29 -p tcp --dport 22 -j DROP
iptables -I FORWARD 4 -s 192.168.18.0/24 -d 192.168.30.0/26 -p tcp --dport 22 -j DROP
iptables -I FORWARD 5 -s 192.168.18.0/24 -d 192.168.50.0/29 -p tcp --dport 22 -j DROP

# Persister via /etc/network/interfaces post-up sur vmbr0
```

### Implementation Tier 1 -- SSH config client (couche 0)

```
# ~/.ssh/config (Mac) - ProxyJump enforce
Host 192.168.15.* 192.168.20.* 192.168.30.* 192.168.50.*
    ProxyJump debian@192.168.15.2
    IdentityFile ~/.ssh/id_ed25519

Host bastion01 192.168.15.2
    HostName 192.168.15.2
    User debian
    IdentityFile ~/.ssh/id_ed25519
    ControlMaster auto
    ControlPath /tmp/ssh-ctrl-%r@%h:%p
    ControlPersist 3600
```

## Alternatives considerees

### Single-tier via bastion uniquement

**Pour** : plus simple, un seul chemin, audit centralise.

**Contre** : SPOF dur si bastion KO (crash VM, bug libpam, update sshd_config cassee). Sans
break-glass, le seul recours est la console physique du serveur. En homelab sans KVM
physique, c'est la console serie Proxmox (qm terminal). Rejete car risque de lockout
complet sur intervention d'urgence.

### Direct access partout (statu ante)

**Pour** : simplicite maximale.

**Contre** : SSH direct depuis le Mac aux VMs sans TOTP. Non conforme NIS2 art. 21.b.
Les logs SSH sont disperses sur chaque VM sans centralisation. Impossible de detecter
une compromission du poste admin rapidement. Rejete.

### Bastion HA actif/passif

**Pour** : elimine le SPOF Tier 1, toujours un bastion disponible.

**Contre** : complexite disproportionnee (keepalived, IP virtuelle, replication config,
test de bascule). Pour une infrastructure 85 employes avec un seul hyperviseur, le ROI
est negatif. La console Proxmox (Tier 2) est suffisante comme fallback. Reporte Phase IV.

### VPN full-mesh (WireGuard) comme seul vecteur admin

**Pour** : pas de bastion SSH, chaque admin a un tunnel WireGuard vers chaque VM.

**Contre** : gestion des cles par VM, pas de MFA natif, audit fragmente. Complexite
operationnelle superieure au modele bastion. Rejete.

## Consequences

**Positives :**
- NIS2 art. 21.b : MFA 2 facteurs sur l'acces operationnel (pubkey SSH + TOTP)
- Audit Tier 1 centralise sur bastion01 (auth.log -> Wazuh)
- Break-glass formalise et documente (NIS2 art. 21.f : procedure de gestion d'incidents)
- Defense-in-depth : 3 couches pour bloquer le bypass (client config, iptables, FW-INT)
- Pattern standard enterprise PME tech (cf. ANSSI guide bastion PA-066)

**Negatives et risques acceptes :**
- **Surface secondaire Tier 2** : Proxmox direct = acces root sans TOTP depuis subnet admin.
  Mitigation : acces physique/VPN requis pour atteindre 192.168.18.0/24, IP restriction,
  audit /var/log/pveproxy/access.log.
- **Cumul de pouvoirs senior** : un seul admin a acces Tier 2.
  Mitigation : audit Proxmox complet, procedure d'utilisation documentee (runbook).
- **Bastion SPOF Tier 1** : si bastion01 KO, acces operationnel bloque.
  Mitigation : Tier 2 break-glass disponible pour reparer bastion.
- **Proxmox iptables hors IaC** : regles appliquees manuellement + post-up.
  Mitigation : dokumentees dans runbook + ADR, Phase IV role Ansible proxmox_host.

## Validation experimentale (2026-05-11)

| Test | Avant | Apres |
|---|---|---|
| `ssh -o ProxyJump=none debian@192.168.20.12` | Succes (bypass) | Timeout (DROP) |
| `ssh debian@192.168.20.12` (via bastion) | Succes (bypass sans TOTP) | Succes (TOTP demand) |
| `ssh root@192.168.18.50` (Proxmox break-glass) | Succes | Succes (inchange) |
| IPsec 4 SAs INSTALLED | OK | OK (invariant) |
| Wazuh 7 agents actifs | OK | OK (invariant) |

## References

- NIS2 art. 21.b : gestion des acces et authentification multifacteur
- NIS2 art. 21.f : gestion des incidents et continuite operationnelle
- ANSSI guide bastion (PA-066/2024)
- ADR-0018 : MFA TOTP bastion01 SSH + sudo
- Runbook : `docs/runbook-admin-access.md`
- Dette : T-PROXMOX-HOST-IAC (role Ansible proxmox_host, Phase IV)
