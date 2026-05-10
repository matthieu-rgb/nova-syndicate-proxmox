# ADR-0007 : Tailscale pour l'acces administratif personnel uniquement

## Status
Accepted

## Date
2026-05-10

## Contexte

L'administration de l'infrastructure Nova Syndicate depuis le poste de travail principal (Mac M4 Pro) requiert un acces securise aux VMs internes. Le poste de travail n'est pas dans le meme reseau que Proxmox (ou peut etre sur un reseau externe lors de deplacement). Les options generiques sont :
- Ouvrir des ports SSH/8006 directement sur l'IP publique du serveur Proxmox
- Utiliser un VPN traditionnel (OpenVPN, WireGuard road-warrior, IPsec)
- Utiliser un service de tunneling base sur une overlay network

La contrainte principale est que la solution doit fonctionner immediatement, depuis n'importe quel reseau (domicile, mobilite), sans gestion manuelle de ports NAT ni dependance a une adresse IP fixe. Le lab est heberge derriere une box Internet standard avec NAT (pas d'IP fixe garantie).

Un second besoin emerge : le lab est en cours de construction et des acces d'urgence "hors bande" sont necessaires quand le reseau de production est casse (mauvaise config OPNsense, tunnel IPsec down). Dans ce cas, les VPNs geres par OPNsense sont inutilisables (le firewall est la source du probleme). Il faut une couche d'acces independante d'OPNsense.

**La contrainte de securite specifique** : Tailscale SSH bypass a ete identifie comme un risque. La fonctionnalite "Tailscale SSH" permet d'acceder aux machines sans passer par les cles SSH configurees localement, via le daemon Tailscale. Si le daemon est compromis ou mal configure, cela cree un vecteur d'acces SSH qui bypasse `sshd_config` (notamment `ForceCommand`, `AllowUsers`, `Match`). Ce risque est documente dans la task T-TAILSCALE-SSH-HARDEN et a ete traite dans le commit `68066ea`.

## Decision

Adoption de **Tailscale** pour l'**acces administratif personnel uniquement**, avec les contraintes suivantes :

1. **Scope limite** : Tailscale est installe uniquement sur :
   - Le poste de travail Mac M4 Pro (noeud client)
   - Le noeud Proxmox VE (pour l'acces a l'interface web 8006 et aux consoles VM)
   - Eventuellement bastion01 pour l'acces SSH de secours

   Tailscale n'est **pas** installe sur les VMs de production (dc01, fs01, db01, app01, etc.). L'acces aux VMs de production passe par bastion01 via SSH ProxyJump.

2. **Tailscale SSH desactive** : la fonctionnalite Tailscale SSH (`tailscale ssh`) est explicitement desactivee sur tous les noeuds. L'acces SSH passe exclusivement par `sshd` local avec les cles authorisees dans `~/.ssh/authorized_keys`. Tailscale sert uniquement de couche reseau (overlay network L3), pas d'authentification SSH.

   Configuration appliquee : `tailscale up --ssh=false` ou equivalent dans la configuration ACL Tailnet.

3. **Tailscale comme acces "hors bande"** : quand OPNsense est mal configure, la connectivite Tailscale reste disponible car elle utilise le serveur DERP Tailscale (relay) en cas d'indisponibilite du chemin direct. Cela permet un acces console Proxmox pour corriger la configuration.

4. **Non utilise pour la gestion de production** : les playbooks Ansible, les `terraform apply`, et les deploiements sont executes depuis le poste de travail via bastion01 (SSH ProxyJump). Tailscale est l'acces de secours, pas le chemin nominal.

**Justification du choix Tailscale vs alternatives** :
Tailscale est une solution zero-config pour le cas d'usage specifique identifie : acces depuis n'importe quel reseau, derriere NAT, sans gestion de ports. Le plan personnel Tailscale est gratuit pour usage personnel (jusqu'a 100 appareils). L'overhead de configuration est quasi-nul comparativement aux alternatives.

## Alternatives considerees

### WireGuard road-warrior manuel

**Pour** :
- Pas de dependance a un service tiers (Tailscale coordonne par les serveurs tailscale.com).
- Controle total de la configuration et des cles.
- WireGuard est deja utilise dans le projet pour le tunnel backup (coherence).

**Contre** :
- Necessite une IP publique fixe ou un DNS dynamique pour le serveur WireGuard (OPNsense). Le lab est derriere une box avec NAT et IP dynamique potentielle.
- Necessite d'ouvrir un port UDP (51820) sur la box Internet vers OPNsense FW-EXT. Cela augmente la surface d'attaque exposee sur Internet.
- Si OPNsense est la cause du probleme (ce qui arrive en lab), le tunnel WireGuard gere par OPNsense est aussi down. Pas de valeur comme acces "hors bande".
- La gestion des pairs road-warrior (ajout/suppression de cles, distribution des configs) est manuelle. Pas problematique avec un seul utilisateur, mais moins ergonomique que Tailscale.

### OpenVPN remote access

**Pour** :
- Standard documente, clients disponibles sur toutes les plateformes (iOS, Android, macOS, Windows).
- OpenVPN Access Server (gratuit jusqu'a 2 connexions concurrentes) simplifie la gestion.

**Contre** :
- Memes problematiques que WireGuard road-warrior : dependance a OPNsense pour le tunnel, pas d'acces hors-bande.
- Configuration plus lourde (PKI, certificats client, OVPN file).
- OpenVPN Access Server necessite une VM dediee ou un service supplementaire.
- Performance inferieure a WireGuard et Tailscale (single-threaded userspace).

### Teleport pour l'administration personnelle

**Pour** :
- Teleport est prevu comme solution de bastion avec MFA et enregistrement de session (T-BASTION-TELEPORT). Utiliser Teleport pour l'acces personnel aussi centraliserait la gestion des acces.
- MFA natif, audit complet des sessions.

**Contre** :
- Teleport n'est pas encore deploye (tache future T-BASTION-TELEPORT). Utiliser Teleport pour l'acces personnel avant qu'il soit deploye en production creerait une dependance circulaire.
- Teleport requiert une infrastructure de coordination (serveur Teleport ou Teleport Cloud). Pour un acces "personnel" depuis le Mac, c'est une couche de complexite disproportionnee.
- Teleport est prevu comme solution de gestion des acces **a** l'infrastructure, pas comme solution d'acces personnel ad hoc.
- Voir ADR-0014 pour la decision sur Teleport.

### Forwarding de ports direct (SSH sur port public)

**Pour** :
- Zero configuration cote infrastructure.
- Compatible avec n'importe quel client SSH.

**Contre** :
- Exposer le port SSH du noeud Proxmox ou du bastion directement sur Internet est inacceptable. Les scanners automatiques tentent des authentifications en continu sur le port 22 (et les ports alternatifs connus).
- Meme avec fail2ban et des cles SSH uniquement, l'exposition directe augmente le risque d'exploitation de vulnerabilites zero-day sur sshd.
- Pas d'acces hors-bande si le serveur est inaccessible via son IP publique.

## Consequences

**Positives :**
- L'acces administratif personnel est disponible depuis n'importe quel reseau, sans configuration de ports NAT.
- La couche Tailscale est independante d'OPNsense : si le firewall est mal configure, l'acces Proxmox reste disponible via Tailscale pour corriger le probleme.
- Pas de port SSH expose sur Internet. La surface d'attaque externe est reduite.
- La desactivation de Tailscale SSH (`--ssh=false`) elimine le vecteur d'acces bypass de `sshd_config`. Ce point est verifie et documente dans le commit `68066ea`.
- Tailscale fonctionne sur le Mac M4 Pro sans configuration supplementaire (client natif macOS disponible).

**Negatives et risques residuels :**
- **Dependance a Tailscale Inc.** : si les serveurs de coordination Tailscale sont indisponibles (panne, cession d'activite), le reseau Tailscale ne peut plus etablir de nouvelles connexions. Les connexions directes (Direct Connections) existantes continuent via WireGuard, mais les nouvelles connexions ou reconnexions via DERP relay echouent. La disponibilite de l'acces admin depend d'un service tiers.
- **Controle des mises a jour** : le daemon Tailscale met a jour automatiquement sur macOS via le Mac App Store. Une mise a jour de Tailscale pourrait modifier le comportement de `--ssh`. Necessite une surveillance des changelogs Tailscale.
- **Perimetre creep** : la facilite d'utilisation de Tailscale peut inciter a installer le daemon sur des VMs de production "pour simplifier l'acces", ce qui etend le perimetre au-dela du scope defini. Cette derive doit etre activement resistee.
- **Audit limite** : Tailscale genere des logs d'acces dans le tableau de bord admin Tailscale, mais ces logs ne sont pas integres dans Wazuh (sauf via syslog personnalise). Les acces admin via Tailscale ne sont pas traces dans le SIEM. Dette d'audit.
- **T-TAILSCALE-SSH-HARDEN** : bien que la tache soit marquee "done" (commit `68066ea`), la desactivation de Tailscale SSH necessite d'etre verifiee a chaque mise a jour majeure du daemon. Ce point est une dette de maintenance permanente.

## References

- Tailscale documentation - SSH : https://tailscale.com/kb/1193/tailscale-ssh/
- Commit hardening Tailscale SSH bypass : git commit `68066ea`
- Tailscale ACLs et politiques : https://tailscale.com/kb/1018/acls/
- ADR-0006 (WireGuard backup) : `docs/adr/ADR-0006-wireguard-backup-vpn.md`
- ADR-0014 (Bastion Teleport) : `docs/adr/ADR-0014-bastion-teleport-mfa.md`
- Task T-TAILSCALE-SSH-HARDEN : `docs/PHASE-II-KANBAN.md`
