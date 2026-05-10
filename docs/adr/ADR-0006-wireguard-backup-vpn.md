# ADR-0006 : WireGuard pour le tunnel backup cloud et les acces road-warrior

## Status
Accepted

## Date
2026-05-10

## Contexte

Nova Syndicate requiert deux types de connectivite VPN distincts de la liaison site-to-site IPsec IKEv2 :

**Besoin 1 - Tunnel backup cloud** : `backup01` (10.0.50.1, VLAN BACKUP) doit transporter des archives Borg chiffrees vers un VPS Hetzner (Helsinki, 5 EUR/mois). Ce trafic est :
- Unidirectionnel (backup01 -> VPS), initie par le client Borg
- Periodique (cron quotidien)
- Un seul pair connu a l'avance (le VPS Hetzner a une IP publique fixe)
- Pas besoin de negociation de politiques de securite complexes (une seule relation de confiance)

**Besoin 2 - Acces road-warrior futur** : les utilisateurs mobiles (typiquement le poste de travail Mac M4 Pro) pourront avoir besoin d'acceder aux VLANs internes depuis l'exterieur sans passer par Tailscale (qui est reserve a l'administration personnelle, voir ADR-0007).

Les contraintes specifiques :
- Le VPS Hetzner tourne sous Ubuntu 22.04 avec wireguard-tools installe manuellement.
- La configuration du serveur WireGuard sur le VPS est geree via Ansible (role `wireguard_server`).
- OPNsense FW-INT-LYON doit autoriser le trafic du VLAN BACKUP vers l'endpoint WireGuard.
- Pas besoin d'interoperabilite avec des equipements tiers non-WireGuard pour ces usages.

Le contexte de securite est different de la liaison site-to-site : pour le backup, la confidentialite est deja assuree par le chiffrement Borg (repokey-blake2) dans le payload. WireGuard ajoute une couche de protection du canal de transport (metadata, timing).

## Decision

Adoption de **WireGuard** (module kernel Linux, daemon `wg-quick`) pour :
1. Le tunnel backup entre `backup01` et le VPS Hetzner (actif, deploye)
2. Le futur usage road-warrior depuis le poste de travail (planifie, non deploye)

**Architecture du tunnel backup :**

```
backup01 (10.0.50.1) -- VLAN BACKUP --> FW-INT-LYON --> FW-EXT-LYON --> [Internet]
                                                                              |
                                                          VPS Hetzner Helsinki (IP publique fixe)
                                                          WireGuard server : 51820/UDP
                                                          WireGuard subnet : 10.200.0.0/24
                                                          VPS peer : 10.200.0.1
                                                          backup01 peer : 10.200.0.2
```

**Parametres cryptographiques WireGuard :**
- Algorithme de cle : Curve25519 (ECDH)
- Algorithme de chiffrement : ChaCha20-Poly1305 (AEAD)
- Fonction de hachage : BLAKE2s (pour le hachage des cles)
- Pas de negociation de parametres : WireGuard utilise des algorithmes fixes, pas de negotiation.

**Justification du choix WireGuard pour ce cas d'usage :**

La caracteristique determinante pour le tunnel backup est la **simplicite de configuration** et la **robustesse** face aux reconnexions. Un tunnel WireGuard est stateless du point de vue de l'operateur : si le daemon OPNsense redemarrage ou si le VPS est redemarree, la connexion se retablit automatiquement sans intervention humaine. Cette propriete est critique pour des sauvegardes autonomes.

Contrairement a IPsec IKEv2 (choisi pour le site-to-site, ADR-0005), WireGuard n'a pas de phase de negociation IKE. La connexion est etablie des qu'un premier paquet arrive d'un pair connu. Ce comportement "zero setup time" est ideal pour des cron jobs de sauvegarde.

Le code base WireGuard (~4000 lignes) est inferieur de deux ordres de grandeur a strongSwan (~300 000 lignes). La surface d'attaque est structurellement plus faible. Pour un tunnel qui transporte des donnees vers un VPS public, cette consideration est pertinente.

**Configuration OPNsense WireGuard** : le plugin WireGuard d'OPNsense est gere via le provider Terraform `browningluke/opnsense` (resources `opnsense_wireguard_server`, `opnsense_wireguard_peer`). La cle privee OPNsense et la cle publique du VPS sont des variables sensibles dans Terraform.

**Configuration VPS** : le serveur WireGuard sur le VPS est configure par le role Ansible `wireguard_server` (voir `ansible/roles/wireguard_server/`). Le fichier `wg0.conf` est genere depuis un template Jinja2 avec les cles stockees dans Ansible Vault.

## Alternatives considerees

### IPsec IKEv2 pour le tunnel backup (coherence avec le site-to-site)

**Pour** :
- Coherence technique : un seul protocole VPN pour toutes les liaisons.
- strongSwan est deja configure sur OPNsense pour le site-to-site, pas de nouveau composant.
- IPsec supporte les certificats, offrant une meilleure authentification qu'une PSK WireGuard.

**Contre** :
- La configuration d'un tunnel IPsec IKEv2 pour un unique pair (VPS Hetzner) vers un VPS Ubuntu 22.04 est disproportionnement complexe : PKI ou PSK, phase 1, phase 2, propositions cryptographiques, etc.
- strongSwan sur Ubuntu 22.04 (cote VPS) necessite une configuration et une maintenance supplementaire. WireGuard est installe en une commande sur Ubuntu et la configuration tient en 10 lignes.
- Si le VPS Hetzner est reconstructu (destroy + create Terraform), la configuration IPsec doit etre reconfiguree des deux cotes simultanement. Avec WireGuard, il suffit de regenerer les cles et de mettre a jour la configuration OPNsense.
- Le cas d'usage road-warrior futur est nativement supporte par WireGuard (chaque peer a sa propre cle, ajout/suppression simple). Avec IPsec IKEv2, un road-warrior necessite IKEv2 en mode Remote Access, plus complexe a configurer.

### OpenVPN pour le tunnel backup

**Pour** :
- Tres documente, clients disponibles sur toutes les plateformes.
- Compatible avec les clients OpenVPN existants (OVPN files).

**Contre** :
- OpenVPN est single-threaded (daemon userspace) : performance moindre pour les transferts de sauvegarde volumineuses.
- Configuration plus complexe que WireGuard pour un simple tunnel point-a-point (ca, cert, cle serveur, cle client, parametres tls-auth).
- Pas de mode "kernel" sur Linux : tout le trafic passe par userspace, overhead plus eleve.
- OpenVPN n'a pas de propriete de "silent reconnect" aussi propre que WireGuard. Les reconnexions apres interruption reseau sont plus lentes.
- Le provider `browningluke/opnsense` ne couvre pas OpenVPN dans les versions utilisees.

### Acces direct SFTP/SCP vers VPS (sans tunnel VPN)

**Pour** :
- Extreme simplicite : Borg over SSH sans couche VPN supplementaire.
- Borg supporte nativement SSH comme transport (`borg init user@host:/path`).
- Le chiffrement SSH (ED25519 + ChaCha20 ou AES-CTR) protege le canal.

**Contre** :
- Le port SSH du VPS serait expose publiquement pour accepter les connexions de `backup01`. Cela augmente la surface d'attaque du VPS.
- Sans WireGuard, l'acces road-warrior futur necessite une solution distincte.
- Le trafic de backup serait identifiable sur le reseau comme du SSH, revealant la nature des operations.
- WireGuard tunnel + Borg over SSH dans le tunnel = double isolation. Le choix retenu maintient Borg over SSH **dans** le tunnel WireGuard, ce qui est redondant mais coherent avec la politique "defense en profondeur".

Note technique : dans l'implementation actuelle, Borg utilise SSH comme transport (`BORG_RSH="ssh -i /root/.ssh/borg_backup"`). Le tunnel WireGuard assure la couche reseau entre backup01 et le VPS. Le SSH Borg est donc un second chiffrement sur le tunnel WireGuard, ce qui est volontairement redondant.

### Tailscale pour le tunnel backup

**Pour** :
- Tailscale utilise WireGuard en sous-couche, meme securite.
- Zero configuration reseau : pas besoin de gerer les cles manuellement, Tailscale s'en charge.
- Accessible depuis n'importe ou sans gestion de l'IP publique du VPS.

**Contre** :
- Tailscale depend d'un plan de controle centralise (les serveurs de coordination Tailscale). Si tailscale.com est indisponible, la connexion ne peut pas s'etablir.
- Pour un tunnel de sauvegarde automatise, cette dependance a un tiers est inacceptable en termes de fiabilite.
- Le VPS Hetzner hebergeant le depot Borg ne doit pas etre enregistre dans le reseau Tailscale de l'admin personnel (separation des usages, voir ADR-0007).
- Tailscale etendu a des systemes automatises (cron, backup) sort du perimetre defini pour son usage dans Nova Syndicate.

## Consequences

**Positives :**
- Le tunnel WireGuard backup01 <-> VPS est auto-reconnectant : les sauvegardes Borg reprennent apres toute interruption reseau sans intervention humaine.
- La configuration est minimaliste : deux fichiers de 15 lignes chacun (`/etc/wireguard/wg0.conf` sur le VPS, configuration OPNsense via Terraform). Facile a auditer.
- L'ajout d'un peer road-warrior futur necessite uniquement d'ajouter un bloc `[Peer]` dans la configuration et un `terraform apply` sur OPNsense.
- WireGuard utilise des algorithmes modernes (Curve25519, ChaCha20, BLAKE2) sans possibilite de downgrade cryptographique.
- Le runbook de deploiement est documente dans `docs/runbooks/runbook-wireguard-vps.md`.

**Negatives et risques residuels :**
- **Gestion manuelle des cles** : contrairement a Tailscale ou IPsec avec PKI, la rotation des cles WireGuard est manuelle. Si la cle privee de backup01 est comprommise, la cle doit etre regeneree et la cle publique mise a jour sur le VPS et dans Terraform. Pas de rotation automatique.
- **Pas d'authentification forte** : WireGuard utilise uniquement les cles Curve25519 pour l'authentification. Pas de MFA, pas de certificats avec CRL. La securite repose sur la protection des cles privees (stockees dans Ansible Vault et dans `/etc/wireguard/` avec permissions 600).
- **Endpoint fixe requis cote serveur** : le VPS Hetzner doit avoir une IP publique fixe (ce qui est le cas pour CX22). Si l'IP change (destruction/creation du VPS), toutes les configurations clients doivent etre mises a jour.
- **WireGuard n'est pas un standard interoperable** : si un partenaire future requiert une connexion VPN, il faudra utiliser IPsec IKEv2 et non WireGuard.
- **Logging limite** : WireGuard ne produit pas de logs detailles sur les connexions (par design : stealth). Le monitoring de l'etat du tunnel repose sur `wg show` et sur le succes/echec des jobs Borg.

## References

- WireGuard website and whitepaper : https://www.wireguard.com/
- WireGuard RFC-like documentation : https://www.wireguard.com/papers/wireguard.pdf
- Runbook WireGuard VPS : `docs/runbooks/runbook-wireguard-vps.md`
- Ansible role wireguard_server : `ansible/roles/wireguard_server/`
- Log deploiement WireGuard VPS : `docs/T-WG-SERVER-VPS-BACKUP-LOG.md`
- ADR-0005 (IPsec IKEv2 site-to-site) : `docs/adr/ADR-0005-ipsec-ikev2-site-to-site.md`
- ADR-0007 (Tailscale admin) : `docs/adr/ADR-0007-tailscale-admin-perso.md`
- ADR-0008 (Borg backup) : `docs/adr/ADR-0008-borg-repokey-append-only.md`
