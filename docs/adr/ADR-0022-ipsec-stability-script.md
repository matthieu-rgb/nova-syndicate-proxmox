# ADR-0022 -- IPsec auto-recovery script sur FW-EXT-LYON

- Statut : Accepte
- Date : 2026-05-17
- Reference : T-IPSEC-STABILITY, incident 2026-05-17

## Contexte

Le 2026-05-17, suite a un rollback Proxmox vers `pre-suricata-2026-05-12`,
la section IPsec de /conf/config.xml etait videe et `/usr/local/etc/strongswan.opnsense.d/`
ne contenait que le README -- 0 SA INSTALLED.

Restauration via rollback vers `post-incident-recovery-2026-05-09` (snapshot
explicitement decrit "IPsec 4 SAs"). Apres reboot, OPNsense ne ré-initie pas
automatiquement les child SAs en mode `dpd action=none` -- seul le SA portant
du trafic actif reste UP. Sur 4 child SAs definis (192.168.15.0/29,
192.168.20.0/28, 192.168.30.0/26, 192.168.50.0/29 vers 192.168.40.0/26),
on retombe a 1/4 INSTALLED si seulement la VLAN servers genere du trafic.

L'invariant operationnel est **4 child SAs INSTALLED en permanence**, sinon
les pings cross-site ad-hoc depuis bastion/users/backup echouent jusqu'a
generation du premier paquet.

## Decision

Mise en place d'un script `/usr/local/sbin/ipsec-recovery.sh` qui :

1. Enumere les child SAs definis (swanctl --list-conns).
2. Compare avec les child SAs INSTALLED (swanctl --list-sas).
3. Initie chaque enfant manquant via `swanctl --initiate --child <uuid>`.
4. Si l'IKE_SA elle-meme est down, declenche `configctl ipsec reload`.
5. Loggue dans /var/log/ipsec-recovery.log + alerte syslog si recovery partielle.

Le script est invoque :
- A chaque reboot via `@reboot` dans /etc/crontab (avec `sleep 45` pour laisser
  strongSwan completer son boot).
- Toutes les 5 minutes via cron.

## Consequences

Positives :
- Plus de "0/4 SAs apres reboot" silencieux.
- Recovery automatique en moins de 5 minutes sans intervention humaine.
- Source de verite shellscript versionne dans le repo (reproductible).

Negatives :
- Le script masque la cause racine du "trap mode" : si OPNsense devait passer
  les child SAs en mode `start` natif, le script deviendrait inutile sans qu'on
  ne s'en rende compte. Mitigation : conserver le log pour audit.
- Le snapshot Proxmox reste la seule sauvegarde de la config IPsec
  (rule, gateway, child SAs). Dette **T-IPSEC-CONFIG-AS-CODE** : passer la config
  IPsec en Ansible/Terraform avec import via API OPNsense.

## Alternatives considerees

- **DPD action=restart** : modifier le profil de chaque child pour que strongSwan
  re-initie lui-meme apres timeout. Pas applique car la config IPsec n'est pas
  encore IaC -- toute modif manuelle dans la WebUI risque d'etre perdue au
  prochain incident.
- **Service strongSwan auto-restart** : insuffisant car le probleme n'est pas le
  daemon mais l'absence de child SAs INSTALLED, qui necessite une action explicite.

## Implementation

- Script : `scripts/opnsense/ipsec-recovery.sh`
- Runbook : `docs/runbook-ipsec-recovery.md`
- Cron : 2 lignes ajoutees dans /etc/crontab sur FW-EXT-LYON.

## Mesure de succes

- Recovery testee : `swanctl --terminate --child <uuid>` x2 -> appel manuel
  du script -> 4/4 SAs en moins de 10 secondes.
- A surveiller : `tail -f /var/log/ipsec-recovery.log` apres prochain reboot,
  doit montrer "Check : IKE=1, child INSTALLED=4/4" sans alert.
