# Runbook IPsec multi-VLAN Lyon <-> Marseille

## Architecture

```
FW-INT-LYON (10.0.1.2)
  VLANs:
    vlan01 192.168.50.0/29  BACKUP
    vlan02 192.168.15.0/29  BASTION
    vlan03 192.168.20.0/28  SERVERS
    vlan04 192.168.30.0/26  USERS
        |
       vtnet0 (10.0.1.x transit)
        |
FW-EXT-LYON (10.0.0.2) -- IPsec -- FW-EXT-MRS (10.0.2.2)
    vtnet2 = OPT1 (10.0.1.1)            vtnet1 = LAN (192.168.40.0/26)
```

Phase 1 IKE: `10.0.0.2 <-> 10.0.2.2`, IKEv2, AES_GCM_16-256/PRF_HMAC_SHA2_256/MODP_2048

4 Phase 2 / Child SAs:

| reqid | VLAN | Lyon local | MRS remote |
|-------|------|-----------|------------|
| 1 | SERVERS | 192.168.20.0/28 | 192.168.40.0/26 |
| 2 | BASTION | 192.168.15.0/29 | 192.168.40.0/26 |
| 3 | USERS | 192.168.30.0/26 | 192.168.40.0/26 |
| 4 | BACKUP | 192.168.50.0/29 | 192.168.40.0/26 |

---

## Diagnostic rapide

```sh
# Etat IKE SA + Child SAs (FW-EXT-LYON)
ssh opn-fw-ext-lyon 'swanctl --list-sas'

# Verifier 4 Child SAs avec compteurs non nuls :
# child_servers reqid=1, child_bastion reqid=2, child_users reqid=3, child_backup reqid=4

# Test fonctionnel depuis FW-INT-LYON
ssh opn-fw-int-lyon '
  for src in 192.168.20.1 192.168.15.1 192.168.30.1 192.168.50.1; do
    echo -n "PING from $src: "
    ping -c 1 -W 1 -S $src 192.168.40.11 | grep -E "received|loss"
  done'

# SPD kernel (doit montrer 8 entrees reqid 1..4)
ssh opn-fw-ext-lyon 'setkey -DP'

# Routes FW-EXT-LYON (doit avoir 4 routes vers 10.0.1.2)
ssh opn-fw-ext-lyon 'netstat -rn | grep 192.168'
```

---

## Root causes identifies (2026-05-08)

### Root cause 1 : OPNsense bundle tous les Phase 2 en UN seul child SA

OPNsense (legacy Tunnel Settings) genere un `swanctl.conf` avec **un seul child `con1`** contenant tous les subnets en `local_ts` concatenes :

```
children {
    con1 {
        local_ts = 192.168.20.0/28,192.168.15.0/29,192.168.30.0/26,192.168.50.0/29
        reqid = 1   # UN SEUL reqid pour les 4
    }
}
```

Consequence : lors de la negociation IKEv2, le responder (MRS) narrow les TS et n'installe **qu'un seul Child SA** (SERVERS, car premier dans la liste). Les 3 autres VLANs ont une entree SPD mais **aucun SA** -> ACQUIRE+DROP systematique.

**Commande qui tranche :**
```sh
ssh opn-fw-ext-lyon 'swanctl --list-sas'
# Affiche UN seul child (con1 reqid=1, local 192.168.20.0/28) malgre 4 Phase 2 configurees
```

### Root cause 2 : Routes statiques manquantes sur FW-EXT-LYON

FW-EXT-LYON n'avait qu'une seule route vers les VLANs de FW-INT-LYON :
```
192.168.20.0/28  10.0.1.2  UGS  vtnet2   # SERVERS - route manuelle existante
# MANQUANTES :
# 192.168.15.0/29, 192.168.30.0/26, 192.168.50.0/29
```

Consequence : quand MRS chiffrait une reponse et la renvoyait via IPsec, FW-EXT-LYON decryptait le paquet mais le routait vers la **default gateway** (internet, 10.0.0.1) au lieu de vtnet2 -> FW-INT-LYON.

**Commande qui tranche :**
```sh
ssh opn-fw-ext-lyon 'netstat -rn | grep 192.168'
# Montre seulement 192.168.20.0/28 -> 10.0.1.2
```

---

## Hypotheses ecartees

| Hypothese | Commande de falsification | Resultat |
|-----------|--------------------------|---------|
| SPD absent sur FW-INT-LYON | `ssh opn-fw-int-lyon 'setkey -DP'` | No SPD entries - FW-INT-LYON n'a pas de daemon IPsec |
| strongSwan sur FW-INT-LYON | `ssh opn-fw-int-lyon 'swanctl --list-conns'` | VICI socket absent - pas de daemon |
| pf block FW-INT-LYON | `ssh opn-fw-int-lyon 'pfctl -sr | grep "^pass out"'` | `pass out log all` existe |
| pf block FW-EXT-LYON vtnet2 | `ssh opn-fw-ext-lyon 'pfctl -sr | grep vtnet2'` | `pass in quick on vtnet2 inet all` - tout passe |
| NAT masque les VLANs | `ssh opn-fw-int-lyon 'pfctl -sn | grep 40.0'` | `no nat from 192.168.0.0/16 to 192.168.40.0/26` |
| paquet meurt sur FW-INT-LYON | `ping -S 192.168.15.1 10.0.1.1` depuis FW-INT-LYON | 2/2 paquets recus - le paquet SORT bien |

---

## Fix applique (2026-05-08)

### Fix 1 : swanctl.conf - 4 children separes

Fichiers `/usr/local/etc/swanctl/swanctl.conf` remplaces sur FW-EXT-LYON et FW-EXT-MRS.

**FW-EXT-LYON** (initiator) :
```
children {
    child_servers { local_ts = 192.168.20.0/28; remote_ts = 192.168.40.0/26; reqid = 1; }
    child_bastion { local_ts = 192.168.15.0/29; remote_ts = 192.168.40.0/26; reqid = 2; }
    child_users   { local_ts = 192.168.30.0/26; remote_ts = 192.168.40.0/26; reqid = 3; }
    child_backup  { local_ts = 192.168.50.0/29; remote_ts = 192.168.40.0/26; reqid = 4; }
}
```

**FW-EXT-MRS** (responder) : meme structure, local/remote inverses.

Rechargement sans redemarrage :
```sh
ssh opn-fw-ext-mrs 'swanctl --load-conns'
ssh opn-fw-ext-lyon 'swanctl --load-conns'
# Initiation des 3 enfants manquants depuis LYON :
ssh opn-fw-ext-lyon '
  swanctl --initiate --child child_bastion --timeout 5
  swanctl --initiate --child child_users --timeout 5
  swanctl --initiate --child child_backup --timeout 5'
```

### Fix 2 : Routes statiques FW-EXT-LYON

```sh
ssh opn-fw-ext-lyon '
  route add 192.168.15.0/29 10.0.1.2
  route add 192.168.30.0/26 10.0.1.2
  route add 192.168.50.0/29 10.0.1.2'
```

La route 192.168.20.0/28 existait deja (manuelle, inconnue de terraform).

### Fix 3 : Ghost connection 77a3ef57 supprimee

Connexion creee par le backend "Connections" moderne d'OPNsense, vide (pas d'auth, pas de children). Supprimee de `/conf/config.xml` via script Python sans redemarrage strongSwan.

---

## Persistance

### Routes (FW-EXT-LYON)

Script rc.d : `/usr/local/etc/rc.d/nova_ipsec_fix`

Au demarrage :
1. Ajoute les 4 routes (15.0/29, 20.0/28, 30.0/26, 50.0/29) via 10.0.1.2
2. Attend le socket VICI de charon
3. Appelle `/usr/local/sbin/fix_ipsec_children.py lyon`

### swanctl.conf (FW-EXT-LYON + FW-EXT-MRS)

**ATTENTION** : OPNsense regenere `swanctl.conf` a chaque modification IPsec via GUI/API.
Le fichier regenere remet le format bundle (1 child, 4 TS) -> seul SERVERS fonctionne.

Script de fix : `/usr/local/sbin/fix_ipsec_children.py [lyon|mrs]`

- Detecte si le fix est deja applique (`child_bastion` present)
- Remplace le fichier, recharge les conns, initie les 3 enfants manquants (LYON uniquement)

**Apres tout changement IPsec via GUI/API**, executer :
```sh
ssh opn-fw-ext-mrs 'python3 /usr/local/sbin/fix_ipsec_children.py mrs'
ssh opn-fw-ext-lyon 'python3 /usr/local/sbin/fix_ipsec_children.py lyon'
```

---

## Fix definitif - Terraform (TODO)

Le fix permanent necessite :

1. **Gateway OPT1 sur FW-EXT-LYON** : creer via GUI `System > Gateways > All` un gateway `FW_INT_GW`, interface `opt1`, gateway `10.0.1.2`

2. **Routes Terraform** (activer `routes.tf.bak` -> `routes.tf`) :
   ```hcl
   resource "opnsense_routes_static" "fwext_to_bastion" {
     provider    = opnsense.fw_ext
     enabled     = true
     network     = "192.168.15.0/29"
     gateway     = "FW_INT_GW"
   }
   # idem pour 20.0/28, 30.0/26, 50.0/29
   ```

3. **IPsec permanent** : migrer vers le backend moderne OPNsense (VPN > IPsec > Connections)
   avec 4 Child SA separes, ou utiliser `browningluke/opnsense` resources IPsec si disponibles en v0.16.

---

## Commandes de verification

```sh
# 4 Child SAs avec compteurs non nuls apres pings
ssh opn-fw-ext-lyon 'swanctl --list-sas'

# SPD : 8 entrees reqid 1..4
ssh opn-fw-ext-lyon 'setkey -DP | grep unique'

# Test fonctionnel 4 VLANs
ssh opn-fw-int-lyon '
  echo "SERVERS:"; ping -c 3 -W 1 -S 192.168.20.1 192.168.40.11 | tail -1
  echo "BASTION:"; ping -c 3 -W 1 -S 192.168.15.1 192.168.40.11 | tail -1
  echo "USERS:";   ping -c 3 -W 1 -S 192.168.30.1 192.168.40.11 | tail -1
  echo "BACKUP:";  ping -c 3 -W 1 -S 192.168.50.1 192.168.40.11 | tail -1'

# Routes FW-EXT-LYON
ssh opn-fw-ext-lyon 'netstat -rn | grep "192.168.*10.0.1.2"'
```

---

## Audit des routes statiques (Phase II -- 2026-05-08)

Methode : desactivation temporaire via API OPNsense (enabled=false + reconfigure),
test 4 pings depuis FW-INT-LYON vers 192.168.40.11, reactivation immediate.
Les 4 Child SAs modernes sont restes INSTALLED pendant toute la duree de l'audit.

| Route | FW | Reseau | Gateway | Verdict | Justification |
|-------|----|--------|---------|---------|---------------|
| fwext_to_bastion | FW-EXT-LYON | 192.168.15.0/29 | FW_INT_GW | **NECESSAIRE** | Non testee -- necesssite prouvee en session 2026-05-08 : sans elle, replies IPsec droppes vers default GW |
| fwext_to_servers | FW-EXT-LYON | 192.168.20.0/28 | FW_INT_GW | **NECESSAIRE** | Idem |
| fwext_to_users | FW-EXT-LYON | 192.168.30.0/26 | FW_INT_GW | **NECESSAIRE** | Idem |
| fwext_to_backup | FW-EXT-LYON | 192.168.50.0/29 | FW_INT_GW | **NECESSAIRE** | Idem |
| wansim_to_lyon_internal_subnets | WAN-SIM | 192.168.0.0/16 | FW_EXT_LYON_GW | **PARASITE** | 4/4 pings OK sans elle. WAN-SIM est transit passif : il ne route que les paquets ESP entre 10.0.0.2 et 10.0.2.2, pas les subnets dechiffres. |
| wansim_to_mrs_lan | WAN-SIM | 192.168.40.0/26 | FW_EXT_MRS_GW | **PARASITE** | Idem. Meme raisonnement. |
| wansim_to_lyon_transit | WAN-SIM | 10.0.1.0/30 | FW_EXT_LYON_GW | **PARASITE** | 4/4 pings OK. 10.0.1.0/30 est derriere FW-EXT-LYON, opaque a WAN-SIM. |
| fwext_to_mrs_lan | FW-EXT-LYON | 192.168.40.0/26 | WAN_GW | **PARASITE** | 4/4 pings OK sans elle. Le SPD strongSwan sur FW-EXT-LYON intercepte et chiffre le trafic vers 192.168.40.0/26 independamment de la table de routage. Route statique vers WAN_GW redondante. |
| fwextmrs_to_lyon | FW-EXT-MRS | 192.168.0.0/16 | WAN_GW | **PARASITE** | 4/4 pings OK. Meme logique : le SPD sur FW-EXT-MRS (responder) gere les replies via tunnel sans consulter la route statique. |

### Recommandation Phase III (T3-DURCISSEMENT)

Les 5 routes PARASITES peuvent etre supprimees lors de la session T3 :
- `wansim_to_lyon_internal_subnets`
- `wansim_to_mrs_lan`
- `wansim_to_lyon_transit`
- `fwext_to_mrs_lan`
- `fwextmrs_to_lyon`

Contrainte : ne supprimer qu'apres validation de la session T3 (durcissement block_all).
Supprimer en meme temps dans Terraform (terraform destroy sur ces 5 resources)
et dans OPNsense (reconfigure automatique).

---

## Pieges OPNsense IPsec

1. **Legacy vs Connections** : OPNsense a DEUX backends IPsec. Le melange des deux genere des connexions fantomes dans swanctl.conf.

2. **TS bundling** : Le backend legacy (Tunnel Settings) groupe TOUS les Phase 2 d'un meme Phase 1 en UN seul child avec `local_ts = A,B,C,D`. Ce comportement casse les tunnels multi-subnet via TS narrowing IKEv2.

3. **Bandeau "manual overwrites"** : indique que le config.xml contient des entrees du backend moderne ET du backend legacy. La coexistence cause des connexions fantomes sans auth dans swanctl.conf.

4. **reqid unique** : avec un seul child et reqid=1 pour 4 subnets, tous les SPD pointent vers reqid=1. La SA installee couvre seulement le subset narrow. Les autres subnets font ACQUIRE -> le responder narrow encore -> meme resultat.

5. **Routes sur FW-EXT-LYON** : les routes vers les VLANs de FW-INT-LYON doivent etre statiques sur FW-EXT-LYON. La route par defaut (WAN) ne permet pas de rejoindre les VLANs internes apres decryptage IPsec.
