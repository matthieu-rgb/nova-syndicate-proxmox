# Evidence -- Fix healthcheck.sh PVE 9.x (D.7 maintenance corrective)

**Date** : 2026-06-02
**Ticket** : T-HEALTHCHECK-PVE9-FIX (dette file ramenee par AFK 2026-06-02)
**Fichier modifie** : `scripts/healthcheck.sh`

## Symptome

Apres upgrade Proxmox 8.x -> 9.1, le script `healthcheck.sh` reportait
trois faux negatifs critiques alors que les services etaient operationnels :

| Section | Avant fix | Realite verifiee |
|---------|-----------|------------------|
| 4. Active Directory | `[FAIL] Samba AD inactive on DC01` | `systemctl is-active samba-ad-dc` = `active` |
| 4. AD users | `[WARN] AD users: 0 (attendu >= 80)` | `samba-tool user list \| wc -l` = `94` |
| 6. Database | `[FAIL] MariaDB DB01 inactive` | `systemctl is-active mariadb` = `active` |
| 7. Wazuh SIEM | `[WARN] Wazuh agents Active: 8 (attendu 7)` | 8 agents Active (invariant a maj depuis enrollment mail01) |

## Cause racine

PVE 9.x serialise differemment la sortie `qm guest exec` : le champ
`out-data` se termine systematiquement par `\n` echappe avant la quote
fermante.

```
"out-data" : "active\n"
```

Le pattern de detection precedent `grep -q '"active"'` cherchait `"active"`
avec quote-fermante directement apres `e`, donc ne matchait pas la
sequence reelle `"active\n"`.

Meme mecanisme pour le compteur `USER_COUNT` : pattern over-escape
`'"[0-9]+\\\\n"'` (4 backslashes shell -> 2 backslashes regex ERE ->
recherche de `\\n` litteral, alors que le buffer contient seulement `\n`).

## Fix

Introduction d'un helper `qm_exec_out()` en tete de script qui parse la
reponse JSON de maniere robuste (jq prioritaire, fallback awk/sed
deterministe). Toutes les sections qui parsaient `out-data` a la main
ont ete refactorisees pour utiliser le helper :

- Section 4 -- detection `is-active samba-ad-dc`
- Section 4 -- compteur `samba-tool user list`
- Section 6 -- detection `is-active mariadb`
- Section 7 -- compteur agents Wazuh

Invariant Wazuh aligne sur l'etat post-enrollment mail01 :
`7 -> 8` (les 7 historiques + 000 app01 self-managed + 007 mail01).

## Verification

Output complet AVANT (extrait) :

```
=== 4. ACTIVE DIRECTORY (DC01) ===
[FAIL]    Samba AD inactive on DC01
[WARN]    AD users: 0 (attendu >= 80)

=== 6. DATABASE (DB01) ===
[FAIL]    MariaDB DB01 inactive

=== 7. WAZUH SIEM ===
[WARN]    Wazuh agents Active: 8 (attendu 7)

RESUME
  Passed:   13
  Warning:  8
  Failed:   3
```

Output APRES :

```
=== 4. ACTIVE DIRECTORY (DC01) ===
[OK]      Samba AD active on DC01
[OK]      AD users: 94

=== 6. DATABASE (DB01) ===
[OK]      MariaDB DB01 active

=== 7. WAZUH SIEM ===
[OK]      Wazuh agents Active: 8

RESUME
  Passed:   17
  Warning:  6
  Failed:   1
```

Le seul `[FAIL]` residuel (`IPsec FW-EXT-LYON: 0 SAs`) est une **dette
fonctionnelle documentee** (Phase IV roadmap : tunnel IPsec Lyon-MRS non
configure, daemon strongSwan pas demarre, configuration heritee de GNS3
obsolete). Pas un bug du healthcheck.

Les `[WARN]` residuels :
- Suricata SSH KO sur opn-fw-* x3 : dettes connues T-TF-WANSIM-CONNECTIVITY
  / T-TF-FWEXTMRS-CONNECTIVITY / T-TF-FWEXTLYON-CONNECTIVITY (providers
  injoignables depuis le Mac, hors session supervisee).
- Suricata 0 alerts FW-EXT-LYON : decoulant du KO precedent.
- ipsec-recovery.sh manquant : meme dette Phase IV.
- Borg repo info indisponible : `BORG_PASSPHRASE` non set en mode non-interactif
  (dette d'instrumentation a part : passer la passphrase via `--pass-fd` ou
  variable d'env injectee, ou exposer un endpoint `borg info --json` sur
  socket local). **Hors scope** du fix PVE 9.x.

## Methode de maintenance corrective (D.7)

1. **Detection** : healthcheck en CI nightly rapporte 3 FAIL persistants
   alors que les services repondent normalement par sondes manuelles.
2. **Reproduction** : execution locale du script, comparaison avec sondes
   directes via `qm guest exec` cote Proxmox host.
3. **Isolation** : inspection brute de la sortie JSON ->
   identification du `\n` echappe trailer.
4. **Hypothese** : changement de framing entre PVE 8.x et 9.x sur
   `qm guest exec` apres upgrade hote (recherche docs Proxmox release notes
   confirmerait ; non bloquant pour le fix).
5. **Fix** : abstraction `qm_exec_out()` + jq prioritaire pour decoupler le
   script de toute future evolution de la representation JSON.
6. **Regression-proofing** : fallback awk/sed sans dependance jq, pour
   garantir l'execution en environnement minimaliste.
7. **Validation** : re-execution comparative + capture avant/apres
   (ce document).
8. **Commit** : message conventionnel avec tag ticket, runbook pointe.

Cycle PDCA complet documente, traceable via git history sur ce fichier
et `scripts/healthcheck.sh`.
