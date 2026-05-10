# T-RESTORE-DRILL -- Log de validation restore
# Date : 2026-05-10

## Objectif

Valider que le repo Borg distant (VPS Hetzner via WireGuard) permet un
restore fonctionnel. Prouver la mecanique avant incident reel.

## Archive testee

```
backup01-2026-05-10-2110
Fingerprint: bfb53f16ecf3b84023769da0d5e6484d25479b7eb1ccd0982a876134623c7361
836 fichiers
14.92 MB original / 13.32 MB compresse
Duration backup : 10.31s
```

## Conditions du test

- Machine : BACKUP01 (192.168.50.2)
- Tunnel WireGuard : UP, handshake 2 min 4 sec avant test
- Methode : restore in-place dans /tmp/restore-test/ (pas de VM bac-a-sable)
- Cleanup : /tmp/restore-test/ + /tmp/restore-partial/ supprimes apres

## Resultats Phase 2 -- Restore complet

| Metrique | Valeur |
|----------|--------|
| Duree restore | 14.6s |
| Volume | 14.92 MB (836 fichiers) |
| Erreurs | 0 |
| Structure | etc/ + var/ presents |

## Resultats Phase 3 -- Validation integrite

| Source | Fichiers source | Fichiers restaures | Match |
|--------|-----------------|-------------------|-------|
| /var/backups/borg | 48 | 48 | OK |
| /var/backups/from-db1 | 12 | 12 | OK |

Checksums MD5 (5 fichiers testes) :
```
OK: /var/backups/borg/filesystem/hints.9
OK: /var/backups/borg/filesystem/data/0/0
OK: /var/backups/borg/filesystem/data/0/5
OK: /var/backups/from-db1/all-databases-20260508-2130.sql.gz
OK: /var/backups/from-db1/all-databases-20260508-2100.sql.gz
```

/etc/hostname : source=backup01 / restore=backup01. Match.

Permissions preservees (verifie sur etc/borg/passphrase : 600 root:root).

## Resultats Phase 4 -- Restore partiel

Restore de `etc/borg` uniquement : OK. Seul `etc/borg/passphrase` restaure.
Aucun fichier hors scope ecrit. Isolation parfaite.

## Conclusion

**3-2-1-1-0 valide :**
- 3 copies : source BACKUP01 + backup local Borg + backup cloud VPS
- 2 supports differents : disque local + VPS distant
- 1 copie hors-site : VPS Hetzner via WireGuard
- 1 copie offline-like : append-only mode (archives non effacables par client)
- 0 erreur : checksums OK, fichiers complets, permissions preservees

**Metriques a retenir pour le DR :**
- Temps restore 836 fichiers / 14.92 MB : **14.6 secondes**
- Debit effectif : ~1 MB/s via WireGuard 10.30.0.0/24 (normal pour VPS Hetzner)

## Limites du test

- Pas de VM bac-a-sable : restore in-place sur BACKUP01 (machine source)
- Pas de test restore-from-scratch (reconstruire BACKUP01 from zero)
- Pas de test SQL restore (dezippé + importé en MySQL) -> a faire T-SQL-RESTORE-DRILL
- Le mode append-only empeche prune depuis client -> voir runbook pour la procedure

## Prochaine etape

T-BORG-KEY-EXPORT : exporter la cle repo + stocker dans password manager.
