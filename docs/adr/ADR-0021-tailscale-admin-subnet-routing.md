# ADR-0021 : Tailscale subnet routing pour acces admin hors LAN

## Status
Accepted

## Date
2026-05-12

## Contexte

Le modele two-tier d'ADR-0020 impose le passage par bastion01 (MFA TOTP) depuis le subnet
admin 192.168.18.0/24. En pratique le poste admin (Mac M4 Pro) n'est pas toujours sur
ce subnet :

- Deplacements, teletravail
- Sessions AFK longues (deploys nocturnes, nuit, weekend)
- Pas de tunnel IPsec/WireGuard utilisateur deja monte sur le Mac

L'alternative "monter un VPN avant chaque session" ajoute de la friction et un point de
defaillance supplementaire (handshake WG, peering IPsec, DNS split-horizon).

Sans route admin alternative, en cas de panne hors LAN :
- impossible de declencher un rollback Proxmox depuis l'exterieur
- impossible de relancer un deploy Ansible
- impossible d'investiguer un incident en cours

## Decision

**Tailscale en mode subnet router** sur l'hyperviseur Proxmox (100.112.113.2) advertise
les subnets internes au tailnet personnel. Le Mac, deja membre du tailnet, accepte les
routes et atteint les VMs internes sans VPN dedie.

### Subnets advertises (Proxmox subnet router)

| CIDR | Usage | VMs |
|---|---|---|
| 192.168.15.0/29 | Bastion | bastion01 |
| 192.168.20.0/28 | Servers | dc01, fs01, db01, app01, proxy-lyon01 |
| 172.16.1.0/29 | DMZ | web01, mail01, vpn-gw01 |
| 192.168.40.0/26 | MRS | proxy-mrs01 |
| 192.168.50.0/29 | Backup | backup01 |

Config Tailscale Proxmox (extrait) :
```bash
tailscale up --advertise-routes=192.168.15.0/29,192.168.20.0/28,172.16.1.0/29,192.168.40.0/26,192.168.50.0/29
```
Routes approuvees cote admin console (https://login.tailscale.com/admin/machines).
Cote Mac : `tailscale up --accept-routes` + `Settings > Tailscale > Use Tailscale subnet routes`.

### Enforcement de la securite two-tier sur le chemin Tailscale

Le passage par Tailscale **ne court-circuite PAS** le modele two-tier d'ADR-0020 :

1. **Couche client (Mac)** -- `~/.ssh/config` impose toujours ProxyJump bastion pour
   les hosts `192.168.20.*`, `192.168.30.*`, `192.168.40.*`, `192.168.50.*`, `172.16.1.*`.
   Ansible utilise le meme ProxyCommand explicite (`ansible@192.168.15.2`).

2. **Couche bastion (PAM)** -- ADR-0018 force MFA TOTP keyboard-interactive sur tout
   utilisateur SSH bastion, exception `Match User ansible` avec bypass depuis subnets
   de confiance (incluant 100.64.0.0/10 Tailscale CGNAT).

3. **Couche hyperviseur (iptables)** -- ADR-0020 DROP SSH 22 de 192.168.18.0/24 vers
   les VLANs internes via Proxmox FORWARD chain. Note : Tailscale traffic n'arrive
   PAS depuis 192.168.18.0/24 ; il est SNAT-e par le subnet router sur l'interface
   du VLAN destination (cf. consequences ci-dessous).

4. **Couche FW-INT-LYON** -- ACL `fwint_bastion_to_servers_ssh` allow + block_all default.

### Tier 2 break-glass via Tailscale

Tier 2 (acces hyperviseur Proxmox direct, ADR-0020) est preserve via le tailnet : le
Mac peut joindre 100.112.113.2 (CGNAT Tailscale du Proxmox) directement, sans dependance
LAN admin. Cela permet :
- `qm rollback <VMID> <snapshot>` en cas de deploy KO en AFK
- `qm guest exec <VMID> --` pour debug VM SSH-inaccessible
- `qm listsnapshot <VMID>` pour inventaire avant intervention

Acces root@100.112.113.2 reste restreint au subnet admin + au tailnet personnel
(ACLs Tailscale + sshd_config sur Proxmox).

## Alternatives considerees

### A. Routes statiques LaunchDaemon macOS

Idee : `route -n add -net 192.168.20.0/28 -gateway <Proxmox-WireGuard-IP>` au boot Mac
via LaunchDaemon plist. Necessite un tunnel WG/IPsec monte avant les routes (sinon les
routes pointent dans le vide).

Rejete :
- Necessite encore un VPN actif (revient au probleme initial)
- Pas de NAT traversal hors LAN admin
- Pas de DNS magique inter-noeuds (Tailscale MagicDNS = bonus)

### B. Tailscale sans SNAT (no-SNAT mode)

Idee : `--snat-subnet-routes=false` cote Proxmox -> source IP preservee (= Tailscale
CGNAT 100.x.x.x du Mac). Les hosts cibles voient l'origine reelle, audit precis.

Rejete pour l'instant :
- Necessite que CHAQUE host destination route 100.64.0.0/10 vers son default gw qui
  doit re-router vers Proxmox -- modifications routing sur toutes les VMs
- hardening_allowed_ssh_nets devrait inclure 100.64.0.0/10 sur tous les hosts -> elargit
  la surface SSH bien au-dela du necessaire
- Tailscale advisory recommande d'enable no-SNAT seulement quand le routing est valide
  end-to-end

Conserve comme dette **T-TAILSCALE-NO-SNAT** -- a etudier dans une iteration ulterieure
quand l'environnement supportera le routing return-path proprement (probablement via
ajustement des routes Proxmox + acceptance des sources 100.64.0.0/10 dans les FW VM).

### C. Reverse proxy SSH via web (gateway like Teleport / Boundary)

Idee : portail web qui broker la session SSH (Teleport, HashiCorp Boundary, Pomerium).

Rejete pour Phase II :
- Complexite d'integration (encore un service critique a deployer)
- Out of scope de l'audit NIS2 actuel
- Pourra etre reevalue Phase III si l'equipe admin grossit (multi-tenant ACLs)

## Consequences

### Positives

- **Acces admin partout** : Mac peut faire snapshot/deploy/rollback depuis n'importe ou
  (LAN, teletravail, deplacement) tant que le tailnet est UP
- **Pas de friction VPN** : Tailscale daemon toujours UP sur Mac, pas de "monter le VPN"
  manuel par session
- **Break-glass Proxmox preserve** : Tier 2 fonctionne meme si bastion KO
- **AFK Ansible operationnel** : sessions de deploy nocturnes possibles sans presence
  physique sur LAN admin (valide cette nuit : 4/4 VMs hardening deploye)

### Negatives / Dettes

- **T-TAILSCALE-NO-SNAT** : SNAT active masque l'origine reelle Mac dans les logs des
  VMs cibles (Wazuh, auditd). Audit precis remonte au subnet router (Proxmox) seulement.
  Mitigation actuelle : auth bastion (ADR-0018) trace l'origine via auth.log + Wazuh,
  l'audit final est correle par username + horodatage.

- **T-TAILSCALE-PROXMOX-SPOF** : Proxmox = subnet router unique. Si Tailscale down sur
  Proxmox, plus de chemin Tailscale interne (Mac retombe sur LAN admin uniquement).
  Mitigation : Proxmox Tailscale est systemd-managed avec restart automatique, et
  Tailscale a un fallback DERP relay. Acceptable pour break-glass.

- **T-TAILSCALE-CGNAT-ACL** : `hardening_allowed_ssh_nets` n'inclut pas 100.64.0.0/10
  (Tailscale CGNAT) pour les VMs internes -> pas de bypass direct sans passer par le
  subnet router. C'est volontaire (force ProxyJump bastion) mais signifie que si Tailscale
  no-SNAT est active un jour (T-TAILSCALE-NO-SNAT), il faudra revoir les ACL VM.

- **T-AUTHELIA-CERT-SAN** : cert `app01.crt` ne couvre pas `auth.nova-syndicate.local`
  ni `grafana.nova-syndicate.local` -> warning browser. Pas lie directement a Tailscale
  mais surface pendant les tests AFK depuis Mac.

### Audit / Conformite NIS2

- Auth bastion (ADR-0018) reste le pivot d'audit (Wazuh agent + auth.log)
- Source IP des audits VM = Proxmox subnet router (IP interne du VLAN destination)
- Correlation user -> session -> action assuree par bastion auth events
- Acceptable pour NIS2 art.21.2.b/i (gestion identites + logging) tant que l'audit
  bastion est preserve

## References

- ADR-0007 : Tailscale admin perso (decision originelle d'utiliser Tailscale)
- ADR-0018 : MFA TOTP bastion (couche enforcement)
- ADR-0020 : Two-tier admin access (modele d'enforcement multi-couche)
- Tailscale subnet router docs : https://tailscale.com/kb/1019/subnets/
