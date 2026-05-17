# Runbook -- IPsec auto-recovery sur FW-EXT-LYON

Reference : ADR-0022, T-IPSEC-STABILITY, incident 2026-05-17

## Objet

Garantir que les 4 child SAs IPsec Lyon <-> MRS restent INSTALLED en permanence,
meme apres :
- reboot FW-EXT-LYON
- rollback Proxmox vers un snapshot anterieur
- crash strongSwan
- expiration d'un child SA en mode "trap"

## Architecture

```
+--------------+         IKE_SA           +--------------+
| FW-EXT-LYON  | <----------------------> | FW-EXT-MRS   |
| 10.0.0.2     |   78112723-...           | 10.0.2.2     |
+------+-------+                          +--------------+
       | 4 child SAs (TUNNEL, AES_CBC_256 + HMAC_SHA2_256 + MODP_2048)
       |
       +-- 4bbf5017-...  192.168.20.0/28 <-> 192.168.40.0/26  (SERVERS)
       +-- 1856ee5d-...  192.168.15.0/29 <-> 192.168.40.0/26  (BASTION)
       +-- 1a71c717-...  192.168.30.0/26 <-> 192.168.40.0/26  (USERS)
       +-- 120d04c8-...  192.168.50.0/29 <-> 192.168.40.0/26  (BACKUP)
```

## Script

Emplacement sur FW-EXT-LYON : `/usr/local/sbin/ipsec-recovery.sh`
Source versionnee : `scripts/opnsense/ipsec-recovery.sh`

## Declencheurs

Dans /etc/crontab sur FW-EXT-LYON :

```
*/5 * * * * root /usr/local/sbin/ipsec-recovery.sh >/dev/null 2>&1
@reboot root sleep 45 && /usr/local/sbin/ipsec-recovery.sh >/dev/null 2>&1
```

## Verification rapide

```sh
# Sur FW-EXT-LYON
swanctl --list-sas | grep -c "INSTALLED, TUNNEL"   # attendu : 4
tail -5 /var/log/ipsec-recovery.log

# Depuis MRS
ssh opn-fw-ext-mrs 'ping -c 2 -S 192.168.40.1 192.168.20.1'   # OK = 0.5ms
```

## Test de recovery (drill)

```sh
# 1. Casser deux child SAs
ssh opn-fw-ext-lyon 'swanctl --terminate --child 1856ee5d-842a-4008-a917-bafbfcf50072'
ssh opn-fw-ext-lyon 'swanctl --terminate --child 120d04c8-4353-4854-a95f-df0b1459b9d9'

# 2. Verifier le drop a 2/4
ssh opn-fw-ext-lyon 'swanctl --list-sas | grep -c "INSTALLED, TUNNEL"'

# 3. Declencher la recovery
ssh opn-fw-ext-lyon '/usr/local/sbin/ipsec-recovery.sh; echo EXIT=$?'

# 4. Verifier retour a 4/4
ssh opn-fw-ext-lyon 'swanctl --list-sas | grep -c "INSTALLED, TUNNEL"'
```

Resultat attendu : EXIT=0, 4/4 SAs, log montre "Post-recovery : child INSTALLED=4/4".

## Diagnostic en cas d'alerte

Si `logger` ecrit `ALERT: Recovery partial : X/4 child SAs INSTALLED` :

1. Verifier IKE_SA cote Lyon : `swanctl --list-sas | grep ESTABLISHED`
   - Si absente : probleme reseau WAN ou PSK/cert mismatch. Test : `ping 10.0.2.2`.
2. Verifier cote MRS : `ssh opn-fw-ext-mrs 'swanctl --list-sas'`
3. Tail strongSwan : `tail -30 /var/log/ipsec`
4. Verifier la config inchangee : `grep -A 5 "<ipsec>" /conf/config.xml | head -10`
5. Si config IPsec vide : restaurer un snapshot connu (cf. `incidents/2026-05-17-ipsec-restoration-fw-ext-lyon.md`).

## Limites connues

- Le script suppose que les child SAs sont definis dans la config strongSwan
  (visibles dans `swanctl --list-conns`). Si la config IPsec entiere est wipee
  (cas du 2026-05-17), le script ne peut rien faire et alerte simplement.
- L'UUID des child SAs est determine par OPNsense au moment de la creation
  -- si la config IPsec est recreee, les UUIDs changent et le script enumere
  automatiquement les nouveaux.

## Dettes liees

- **T-IPSEC-CONFIG-AS-CODE** : passer la config Phase 1 + Phase 2 en Ansible
  ou Terraform via API OPNsense (`/api/ipsec/connections/*`). Aujourd'hui
  c'est uniquement dans /conf/config.xml.
- **T-DPD-RESTART-ACTION** : etudier l'option `dpd action = restart` sur les
  child SAs pour rendre le script inutile.
