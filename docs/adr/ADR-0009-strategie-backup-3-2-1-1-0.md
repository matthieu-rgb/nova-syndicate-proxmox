# ADR-0009 : Strategie de sauvegarde 3-2-1-1-0

## Status
Accepted

## Date
2026-05-10

## Contexte

La definition d'une strategie de sauvegarde pour Nova Syndicate ne peut pas se resumer au choix technique de l'outil (BorgBackup, voir ADR-0008). La strategie porte sur le schema global : combien de copies, sur quels supports, ou sont-elles stockees, quelles proprietes de resilience offrent-elles, et comment la capacite de restauration est-elle validee.

Le cadre reglementaire de reference est la **directive NIS2 (UE 2022/2555)**, Article 21, qui impose aux entites essentielles et importantes des mesures de gestion des risques comprenant explicitement :
- La continuite des activites (21.c)
- La securite des reseaux et des systemes d'information (21.e)
- Des politiques et procedures d'utilisation de la cryptographie (21.h)

Bien que Nova Syndicate soit un lab de formation et non une entite NIS2, le portfolio destine au stage Thales Luxembourg doit demontrer la comprehension et l'application de ces exigences.

Les contraintes supplementaires sont :
- **Budget** : le stockage hors-site doit etre economique. Un VPS Hetzner CX22 (5 EUR/mois, 40 GB) est l'option retenue.
- **Automatisation** : les sauvegardes doivent etre entierement automatiques. Aucune intervention manuelle pour les sauvegardes quotidiennes.
- **Testabilite** : la strategie n'a de valeur que si la restauration a ete testee. Une tache de drill de restauration (T-RESTORE-DRILL) est integree dans la roadmap.
- **Resistance au ransomware** : le scenario de compromission du client de sauvegarde (backup01) ne doit pas permettre la destruction des archives.

La regle classique **3-2-1** (3 copies, 2 supports differents, 1 hors-site) a ete etendue avec deux criteres supplementaires pour repondre aux menaces modernes.

## Decision

Adoption de la strategie **3-2-1-1-0** telle que definie ci-dessous :

### Decomposition de la regle

**3 - Trois copies des donnees**

| Copie | Localisation | Support | Outil |
|-------|-------------|---------|-------|
| Copie 1 | backup01 local (10.0.50.1) | Disque virtuel Proxmox | Borg depot local (`/var/backup/nova-syndicate/`) |
| Copie 2 | Proxmox snapshots | Volume LVM Proxmox | Snapshots QEMU des VMs critiques |
| Copie 3 | VPS Hetzner Helsinki | SSD distante | Borg depot distant (via WireGuard, push depuis backup01) |

**2 - Deux types de supports differents**

Les copies 1 et 2 sont sur les memes disques physiques du serveur Proxmox (stockage local). Elles comptent comme un seul support du point de vue de la regle "2 supports". Le VPS Hetzner represente le second support (stockage SSD distant, infrastructure independante).

Interpretation large de la regle 2 : les copies 1 et 2 sont sur des couches logiques differentes (Borg vs QEMU snapshots) meme si le support physique sous-jacent est le meme. En production reelle, la copie 2 serait sur un NAS supplementaire.

**1 - Une copie hors-site**

La copie 3 sur le VPS Hetzner Helsinki est la copie hors-site. Elle est geographiquement distante (Finlande), sur une infrastructure tierce (Hetzner), et connectee uniquement via WireGuard.

**1 - Une copie immuable (le "+1")**

Le mode append-only de Borg sur le VPS (voir ADR-0008) garantit que la copie distante est immuable du point de vue du client `backup01`. Meme si backup01 est compromis par un ransomware, les archives sur le VPS ne peuvent pas etre supprimees par le client. La suppression requiert un acces administrateur direct au VPS via un canal independant (SSH avec mot de passe, pas de cle depuis backup01).

Ce critere correspond a la notion de "WORM storage" (Write Once, Read Many) ou "immutable backup" des frameworks securite modernes (NIST SP 800-209).

**0 - Zero erreur non detectee (le "+0")**

Le critere "0" signifie que la validite des archives est verifiee et que la restauration a ete testee. Cela implique :
- `borg check` hebdomadaire (verification des checksums des chunks)
- Tache T-RESTORE-DRILL : restauration complete d'au moins un service (fs01 ou db01) depuis les archives Borg, validation du service restaure

Ce critere distingue une strategie de sauvegarde theorique (les archives existent) d'une strategie de continuite reelle (les archives sont restaurables).

### Planification des sauvegardes

```
Quotidienne (02h00) : borg create sur tous les noeuds critiques
Hebdomadaire (dimanche 03h00) : borg check + rapport integrite
Mensuelle : pruning des archives > 30 jours (action manuelle sur VPS)
Annuelle : drill de restauration complet (T-RESTORE-DRILL)
```

### Politique de retention Borg

```
--keep-daily 7
--keep-weekly 4
--keep-monthly 3
```

Cette politique conserve 7 sauvegardes quotidiennes, 4 hebdomadaires et 3 mensuelles, soit environ 3 mois de couverture. En contexte NIS2 production, la retention minimale recommandee est 90 jours pour les logs et 12 mois pour les configurations critiques.

## Alternatives considerees

### Strategie 3-2-1 classique (sans les criteres immuabilite et test)

**Pour** :
- Regle simple, bien etablie depuis des decennies.
- Adequate pour la majorite des cas d'usage SMB.
- Moins de contraintes operationnelles (pas de mode append-only, pas de drill obligatoire).

**Contre** :
- La regle 3-2-1 ne traite pas explicitement le scenario ransomware : un client compromis peut effacer les archives sur les destinations ou il a acces en ecriture.
- Sans validation par drill, la strategie 3-2-1 n'offre aucune garantie que les archives sont effectivement restaurables. Des archives corrompues ou des problemes de compatibilite de version peuvent etre decouverts seulement au moment ou la restauration est critique.
- NIS2 Art. 21.c ne se satisfait pas d'un plan de continuite non-teste. Un auditeur demandera la preuve de la derniere restauration reussie.
- Pour un portfolio destine a Thales Luxembourg (contexte defense/securite), la 3-2-1 sans immutabilite est insuffisante.

### Cloud-only (Backblaze B2 ou AWS S3)

**Pour** :
- Backblaze B2 offre Object Lock (immutabilite native) pour les sauvegardes WORM.
- Pas de gestion de VPS.
- Scalabilite illimitee.
- Backblaze B2 est moins cher que S3 : 0.006 USD/GB/mois vs 0.023 USD/GB/mois pour S3 Standard.

**Contre** :
- Les donnees de l'AD, de la base de donnees et des logs SIEM quittent l'infrastructure. Meme avec le chiffrement Borg, les metadonnees (taille, frequence) sont visibles par le fournisseur cloud.
- Depend de la connectivite Internet. Si la connexion est hors service lors d'un incident, la restauration depuis le cloud est impossible.
- Le modele de cout peut devenir impredictible en cas de restauration d'urgence (egress fees chez certains fournisseurs).
- RGPD : les donnees d'un AD d'entreprise contiennent des donnees personnelles. Stocker dans un cloud US (AWS, Backblaze sont des societes americaines soumises au CLOUD Act) cree des questions de conformite pour une entite NIS2 europeenne.
- Hetzner Helsinki est en UE, soumis au RGPD, et les donnees ne quittent pas l'espace europeen.

### Sauvegarde sur bande magnetique

**Pour** :
- Cout par GB tres bas pour les grands volumes.
- Bandes physiquement deconnectees du reseau = immune au ransomware.
- Standard industriel pour l'archivage longue duree.

**Contre** :
- Inrealiste pour un lab de formation : lecteur de bandes LTO-8 = 2000-3000 EUR, bandes LTO-8 = 20-30 EUR l'unite.
- Pas de valeur pedagogique directe pour le titre AIS ou le portfolio securite informatique.
- Temps de restauration eleve (acces sequentiel).
- Pas de mecanisme automatise de verification d'integrite equivalent a `borg check`.

## Consequences

**Positives :**
- La strategie 3-2-1-1-0 est defensible face a un auditeur NIS2 : copies multiples, support distinct (lab : deux couches logiques, production idealement deux physiques), hors-site, immuable, teste.
- Le drill de restauration T-RESTORE-DRILL documente dans `docs/T-RESTORE-DRILL-LOG.md` constitue la preuve de la restaurabilite des archives.
- Le mode append-only protege les archives distantes meme en cas de compromission complete de backup01 (ransomware, acces non autorise).
- La strategie est entierement automatisee : les sauvegardes quotidiennes ne necessitent pas d'intervention humaine.

**Negatives et risques residuels :**
- **Pruning manuel** : la consequence du mode append-only est que le pruning (suppression des archives trop anciennes) necessite une action manuelle sur le VPS. Si non effectue, le VPS se remplit progressivement. Alerte a implementer (monitoring espace disque VPS).
- **Copie 1 et 2 sur le meme support physique** : dans le lab, les copies 1 (Borg local) et 2 (snapshots Proxmox) sont sur le meme disque physique du serveur. Une defaillance du disque detruit les deux copies simultanement. Solution acceptable pour un lab, insuffisante en production.
- **Dependance a un seul VPS pour l'hors-site** : une seule destination distante. Si le VPS Hetzner est irrecuperable (destruction accidentelle, defaillance Hetzner), l'hors-site est perdu. Un second depot distant (second VPS ou cloud objet) renforcerait la resilience.
- **Retention limitee** : 3 mois de retention en lab. Pour NIS2 en production, la retention des logs de securite est recommandee a 12 mois minimum (ENISA guidelines). Dette documentee.
- **Chiffrement de la cle Vault** : la passphrase Borg est dans Ansible Vault. La recuperation de la passphrase en cas de perte du mot de passe Vault necessite un processus de recovery documente separement (hors du depot Git). Ce processus existe mais sa robustesse n'a pas ete testee en conditions de stress.

## References

- NIST SP 800-209 - Security Guidelines for Storage Infrastructure : https://csrc.nist.gov/publications/detail/sp/800-209/final
- Directive NIS2 Article 21 : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX%3A32022L2555
- BorgBackup pruning documentation : https://borgbackup.readthedocs.io/en/stable/usage/prune.html
- Log T-RESTORE-DRILL : `docs/T-RESTORE-DRILL-LOG.md`
- Log deploiement cloud backup : `docs/T-CLOUD-BACKUP-DEPLOY-LOG.md`
- Runbook Borg cloud : `docs/runbooks/runbook-borg-cloud.md`
- ADR-0008 (Borg repokey) : `docs/adr/ADR-0008-borg-repokey-append-only.md`
- ADR-0010 (VPS Hetzner) : `docs/adr/ADR-0010-vps-hetzner-hors-site.md`
