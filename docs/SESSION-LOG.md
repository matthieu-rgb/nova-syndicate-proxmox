# Session Log -- T-MIGRATION IPsec legacy -> modern Connections backend
# Date: 2026-05-08

## Contexte

Migration IPsec OPNsense legacy "Tunnel Settings" -> backend moderne "Connections"
sur FW-EXT-LYON et FW-EXT-MRS.

Root cause initial : OPNsense legacy groupait tous les Phase 2 en un seul child SA
avec TS bundled -> IKEv2 TS narrowing -> seul VLAN SERVERS fonctionnait.

Fix Phase I (precedente session) : swanctl.conf edite manuellement, 4 children
separes avec reqids 1-4. Scripts fix_ipsec_children.py + rc.d pour persistance.

T-MIGRATION : eliminer les workarounds, utiliser le backend moderne qui genere
nativement 4 children separes.

---

## Phase 0 -- Snapshots pre-migration

Repertoire : backups/pre-migration-20260508-1956/

Fichiers snapshotes :
- config.xml.fw-ext-lyon (63K)
- config.xml.fw-ext-mrs (54K)
- config.xml.fw-int-lyon (74K)
- swanctl.conf.fw-ext-lyon (2.1K)
- swanctl.conf.fw-ext-mrs (2.1K)
- nova_ipsec_fix.fw-ext-lyon (922B)
- nova_ipsec_fix_mrs.fw-ext-mrs (549B)
- fix_ipsec_children.py.fw-ext-lyon (5.9K)
- fix_ipsec_children.py.fw-ext-mrs (5.9K)

Rollback script : scripts/rollback-ipsec-migration.sh (executable, non lance)

---

## Phase 1 -- Migration FW-EXT-MRS (responder)

### swanctl --list-sas PRE-migration FW-EXT-MRS (capture avant Phase 1)

```
con1: #2, ESTABLISHED, IKEv2
  con1: #8,  reqid 1, INSTALLED, TUNNEL  local=192.168.40.0/26 remote=192.168.20.0/28
  con1: #13, reqid 1, INSTALLED, TUNNEL  local=192.168.40.0/26 remote=192.168.50.0/29
  con1: #14, reqid 1, INSTALLED, TUNNEL  local=192.168.40.0/26 remote=192.168.15.0/29
  con1: #15, reqid 1, INSTALLED, TUNNEL  local=192.168.40.0/26 remote=192.168.30.0/26
```

Note: reqid=1 pour tous -- artefact du bundle legacy. Trafic fonctionnel malgre tout.

### Actions Phase 1

1. PSK cree via API moderne (UUID: c01c9acf-0ac9-4683-a60e-dc1348bdb469)
2. Connection moderne creee (UUID: cbe685dd-489c-497f-a629-7cf407dd4362)
3. Local auth: 10.0.2.2 psk (UUID: b95817e6-86e2-424c-b010-72d7f431a9f2)
4. Remote auth: 10.0.0.2 psk (UUID: c3c94174-8be6-4d49-ba15-17fa73de9777)
5. 4 children crees:
   - child_servers  reqid=1  local=192.168.40.0/26 remote=192.168.20.0/28 (4b43c523)
   - child_bastion  reqid=2  local=192.168.40.0/26 remote=192.168.15.0/29 (fbcde098)
   - child_users    reqid=3  local=192.168.40.0/26 remote=192.168.30.0/26 (83231d8e)
   - child_backup   reqid=4  local=192.168.40.0/26 remote=192.168.50.0/29 (bf600d43)
6. Legacy Phase 1 "nova-site2site" disabled dans config.xml
7. Connection moderne toggled enabled
8. Reconfigure: status ok
9. nova_ipsec_fix_mrs_enable="NO" dans /etc/rc.conf

### swanctl --list-sas POST-migration FW-EXT-MRS

```
con1: #2, ESTABLISHED, IKEv2
  con1: #8,  reqid 1, INSTALLED  local=192.168.40.0/26 remote=192.168.20.0/28
  con1: #13, reqid 1, INSTALLED  local=192.168.40.0/26 remote=192.168.50.0/29
  con1: #14, reqid 1, INSTALLED  local=192.168.40.0/26 remote=192.168.15.0/29
  con1: #15, reqid 1, INSTALLED  local=192.168.40.0/26 remote=192.168.30.0/26
```

SAs pre-migration restees actives. reqid=1 sur tous = artefact SA legacy,
sera corrige au prochain rekey. Trafic 4 VLANs 100%.

### Verification pings Phase 1

Depuis FW-INT-LYON (ping -S <vlan_gw> 192.168.40.11) :
- SERVERS 192.168.20.1 -> 192.168.40.11 : 3/3 (0% loss)
- BASTION 192.168.15.1 -> 192.168.40.11 : 3/3 (0% loss)
- USERS   192.168.30.1 -> 192.168.40.11 : 3/3 (0% loss)
- BACKUP  192.168.50.1 -> 192.168.40.11 : 3/3 (0% loss)

CHECKPOINT 2 valide.

---

## Phase 2 -- Migration FW-EXT-LYON (initiator)

### Verification pre-migration

PSK LYON = PSK MRS = X33JHSMi51jMthduUwOE1DfM8NdXW1Aq/sDZetkCjsU= (identiques)
IKE proposal : aes256gcm16-sha256-modp2048 (identique)
ESP proposal : aes256-sha256-modp2048 (identique)

### swanctl --list-sas PRE-migration FW-EXT-LYON

```
con1: #2, ESTABLISHED, IKEv2, 4bf55cf446203320_i f1c38ef415728a1b_r*
  local  '10.0.0.2' @ 10.0.0.2[4500]
  remote '10.0.2.2' @ 10.0.2.2[4500]
  AES_GCM_16-256/PRF_HMAC_SHA2_256/MODP_2048
  established 492s ago, rekeying in 13253s
  con1:        #10, reqid 1, INSTALLED  local=192.168.20.0/28 remote=192.168.40.0/26  (2725s)
  child_backup: #15, reqid 4, INSTALLED  local=192.168.50.0/29 remote=192.168.40.0/26  (2611s)
  child_bastion:#16, reqid 2, INSTALLED  local=192.168.15.0/29 remote=192.168.40.0/26  (2611s)
  child_users:  #17, reqid 3, INSTALLED  local=192.168.30.0/26 remote=192.168.40.0/26  (2611s)
```

### Actions Phase 2

1. PSK cree (UUID: 20fcbc95-50e5-478c-b094-912066626f21) -- identique MRS, verifie
2. Connection moderne creee (UUID: 78112723-0176-40d8-905f-1c187aaf58b3)
3. Local auth: 10.0.0.2 psk (UUID: e4427e91-80c6-49c4-ba55-ad4941d3eddf)
4. Remote auth: 10.0.2.2 psk (UUID: 0d8404d5-f948-42cc-8673-33b43f461142)
5. 4 children crees:
   - 4bbf5017  reqid=1  local=192.168.20.0/28 remote=192.168.40.0/26 (child_servers)
   - 1856ee5d  reqid=2  local=192.168.15.0/29 remote=192.168.40.0/26 (child_bastion)
   - 1a71c717  reqid=3  local=192.168.30.0/26 remote=192.168.40.0/26 (child_users)
   - 120d04c8  reqid=4  local=192.168.50.0/29 remote=192.168.40.0/26 (child_backup)
6. Legacy Phase 1 "nova-site2site" disabled dans config.xml
7. Connection moderne enabled + reconfigure: ok
8. Initiation UUID children: 4 x "initiate completed successfully"
   Note: premiere initiation (child_servers) = nouvel IKE SA #3 (78112723...) etabli
   Enfants suivants (#23/#24/#25) = CREATE_CHILD_SA dans nouvel IKE SA
9. nova_ipsec_fix_enable="NO" dans /etc/rc.conf

### swanctl --list-sas POST-migration FW-EXT-LYON

```
78112723: #3, ESTABLISHED, IKEv2 (UUID connection)
  4bbf5017: #22, reqid 1, INSTALLED  local=192.168.20.0/28 remote=192.168.40.0/26  (rekey 3357s)
  1856ee5d: #23, reqid 2, INSTALLED  local=192.168.15.0/29 remote=192.168.40.0/26  (rekey 3541s)
  1a71c717: #24, reqid 3, INSTALLED  local=192.168.30.0/26 remote=192.168.40.0/26  (rekey 3411s)
  120d04c8: #25, reqid 4, INSTALLED  local=192.168.50.0/29 remote=192.168.40.0/26  (rekey 3326s)
con1: #2, ESTABLISHED, IKEv2 (IKE SA legacy -- expire naturellement)
  #10 reqid 1, #15 reqid 4, #16 reqid 2, #17 reqid 3 (expire < 760s, no rekey)
```

Ancien IKE SA #2 (con1) expire naturellement. Nouveaux SAs #22-25 operationnels.

### Verification pings Phase 2

Depuis FW-INT-LYON :
- SERVERS 192.168.20.1 -> 192.168.40.11 : 3/3 (0% loss)
- BASTION 192.168.15.1 -> 192.168.40.11 : 3/3 (0% loss)
- USERS   192.168.30.1 -> 192.168.40.11 : 3/3 (0% loss)
- BACKUP  192.168.50.1 -> 192.168.40.11 : 3/3 (0% loss)

CHECKPOINT 3 atteint.

---

## Phase 3 -- Cleanup legacy entries

### swanctl --list-sas PRE-cleanup FW-EXT-LYON

```
78112723: #3, ESTABLISHED (198s), rekeying in 85317s
  4bbf5017: #22, reqid 1 INSTALLED  192.168.20.0/28===192.168.40.0/26  (rekey 3171s)
  1856ee5d: #23, reqid 2 INSTALLED  192.168.15.0/29===192.168.40.0/26  (rekey 3355s)
  1a71c717: #24, reqid 3 INSTALLED  192.168.30.0/26===192.168.40.0/26  (rekey 3225s)
  120d04c8: #25, reqid 4 INSTALLED  192.168.50.0/29===192.168.40.0/26  (rekey 3140s)
con1: #2, ESTABLISHED (907s, orphan -- config supprimee)
  #26 reqid 1 INSTALLED (rekey 3056s)  -- rekey naturel de #10 apres expiry
  #27 reqid 4 INSTALLED (rekey 3059s)  -- rekey de child_backup
  #28 reqid 3 INSTALLED (rekey 2935s)  -- rekey de child_users
  #29 reqid 2 INSTALLED (rekey 3090s)  -- rekey de child_bastion
```

### swanctl --list-conns PRE-cleanup FW-EXT-LYON

```
78112723: IKEv2, rekeying 86400s, dpd 30s
  local PSK 10.0.0.2 / remote PSK 10.0.2.2
  4bbf5017: TUNNEL 192.168.20.0/28 -> 192.168.40.0/26
  1856ee5d: TUNNEL 192.168.15.0/29 -> 192.168.40.0/26
  1a71c717: TUNNEL 192.168.30.0/26 -> 192.168.40.0/26
  120d04c8: TUNNEL 192.168.50.0/29 -> 192.168.40.0/26
```
Note: con1 ABSENT de list-conns (swanctl.conf moderne uniquement).

### swanctl --list-sas PRE-cleanup FW-EXT-MRS

```
cbe685dd: #3, ESTABLISHED (198s)
  4b43c523: #20, reqid 1 INSTALLED  192.168.40.0/26===192.168.20.0/28  (rekey 3240s)
  fbcde098: #21, reqid 2 INSTALLED  192.168.40.0/26===192.168.15.0/29  (rekey 3108s)
  83231d8e: #22, reqid 3 INSTALLED  192.168.40.0/26===192.168.30.0/26  (rekey 3225s)
  bf600d43: #23, reqid 4 INSTALLED  192.168.40.0/26===192.168.50.0/29  (rekey 3236s)
con1: #2, ESTABLISHED (908s, orphan)
  #24 reqid 1, #25 reqid 1, #26 reqid 1, #27 reqid 1 (rekeyes legacy, expire ~3500s)
```

### swanctl --list-conns PRE-cleanup FW-EXT-MRS

```
cbe685dd: IKEv2, rekeying 86400s, dpd 30s
  local PSK 10.0.2.2 / remote PSK 10.0.0.2
  4b43c523: TUNNEL 192.168.40.0/26 -> 192.168.20.0/28
  fbcde098: TUNNEL 192.168.40.0/26 -> 192.168.15.0/29
  83231d8e: TUNNEL 192.168.40.0/26 -> 192.168.30.0/26
  bf600d43: TUNNEL 192.168.40.0/26 -> 192.168.50.0/29
```

### Legacy UUIDs identifies

FW-EXT-LYON:
- Phase1: ikeid=1, descr=nova-site2site (disabled)
- Phase2: uniqid=69fdeb6be45da (servers), 69fdf89d82177 (bastion), 69fdf922cb8cf (users), 69fdf955d6b1d (backup)

FW-EXT-MRS:
- Phase1: ikeid=1, descr=nova-site2site (disabled)
- Phase2: uniqid=69fdedc1ed601 (servers), 69fdf9a62ddb6 (bastion), 69fdfb85e9b0f (users), 69fdfbbc1631b (backup)

### Actions Phase 3

- delPhase1/1 sur LYON: {"status":"ok","phase1count":1,"phase2count":4}
- delPhase1/1 sur MRS:  {"status":"ok","phase1count":1,"phase2count":4}
- Reconfigure les deux FW: ok
- fix_ipsec_children.py supprime (LYON + MRS)
- nova_ipsec_fix rc.d supprime (LYON + MRS)
- rc.conf nettoye (LYON + MRS) : aucune reference nova_ipsec restante
- config.xml verifie: Phase1=0, Phase2=0 sur LYON (config propre)

### Verifications post-cleanup

1. swanctl --list-conns : UNIQUEMENT connexion moderne UUID (pas de con1, pas de ghost)
2. config.xml: sections <ipsec><phase1> et <ipsec><phase2> vides -- bandeau "manual overwrites" disparu
3. /usr/local/etc/rc.d/ : aucun script nova_ipsec -- CONFIRME
4. /etc/rc.conf : aucune reference nova_ipsec -- CONFIRME
5. /usr/local/sbin/ : aucun fix_ipsec_children.py -- CONFIRME

### Test stabilite GUI

setConnection (description change) + reconfigure:
- Resultat: {'result': 'saved'} + {'status': 'ok'}
- 8 Child SAs INSTALLED apres Apply (4 modernes + 4 orphelins legacy expirant)
- PASS: GUI change ne casse plus les tunnels
- DETTE TECHNIQUE ELIMINEE

### Pings finaux Phase 3

Depuis FW-INT-LYON:
- SERVERS 192.168.20.1 -> 192.168.40.11 : 3/3
- BASTION 192.168.15.1 -> 192.168.40.11 : 3/3
- USERS   192.168.30.1 -> 192.168.40.11 : 3/3
- BACKUP  192.168.50.1 -> 192.168.40.11 : 3/3

---

## Phase 4 (AVORTEE) + Rollback Option A -- 2026-05-08

### Phase 4 -- Tentative Terraform alignment (avortee)

terraform apply Phase 4 : 9 routes ajoutees + 8 block_all enabled=true.
Resultat : 4/4 pings -> 100% packet loss. Cause : block_all rules
(notamment fwint_wan_block_all) bloquent trafic retour IPsec sur WAN FW-INT.
Les routes orphelines (dont fwext_to_mrs_lan 192.168.40.0/26 via WAN) persistent.

### Rollback Option A applique

Methode :
1. Snapshot pre-rollback dans backups/rollback-phase4-20260508/
2. Edit fw_*.tf : 8 block_all enabled=true -> false
3. routes.tf archive /tmp/routes.tf.removed-20260508-2103, supprime du repo
4. tfstate restore depuis terraform.tfstate.backup (supprime 9 routes du state)
5. terraform plan : 0 add, 8 change, 0 destroy (confirmed)
6. terraform apply : block_all desactives sur 4 FW

### swanctl --list-sas post-rollback (FW-EXT-LYON)

```
78112723: #3, ESTABLISHED 2876s ago, rekeying in 82639s
  local 10.0.0.2 @ 10.0.0.2[500] / remote 10.0.2.2 @ 10.0.2.2[500]
  AES_GCM_16-256/PRF_HMAC_SHA2_256/MODP_2048
  4bbf5017: #22, reqid 1 INSTALLED  192.168.20.0/28<->192.168.40.0/26  (in 252B/3pkts, out 468B/3pkts)
  1856ee5d: #23, reqid 2 INSTALLED  192.168.15.0/29<->192.168.40.0/26  (in 252B/3pkts, out 468B/3pkts)
  1a71c717: #24, reqid 3 INSTALLED  192.168.30.0/26<->192.168.40.0/26  (in 252B/3pkts, out 468B/3pkts)
  120d04c8: #25, reqid 4 INSTALLED  192.168.50.0/29<->192.168.40.0/26  (in 252B/3pkts, out 468B/3pkts)
con1: #2, ESTABLISHED 3585s ago (orphan legacy, expire naturellement ~82800s)
  #26-29 reqid 1-4 INSTALLED (rekeyes legacy, aucun trafic entrant)
```

4 UUID children modernes INSTALLED, compteurs non nuls. IKE SA moderne actif.

### Routes FW-EXT-LYON post-rollback (netstat -rn)

```
192.168.15.0/29    10.0.1.2    UGS  vtnet2   (VLAN BASTION, rc.d ou TF Phase4-orphan)
192.168.20.0/28    10.0.1.2    UGS  vtnet2   (VLAN SERVERS)
192.168.30.0/26    10.0.1.2    UGS  vtnet2   (VLAN USERS)
192.168.40.0/26    10.0.0.1    UGS  vtnet0   (MRS LAN -- orphan Phase4, non managee TF)
192.168.50.0/29    10.0.1.2    UGS  vtnet2   (VLAN BACKUP)
```

9 routes orphelines restent dans OPNsense (non managees Terraform).

### terraform state list + plan post-rollback

- state list : 0 opnsense_route.* (backup state restaure)
- terraform plan : "No changes. Your infrastructure matches the configuration."

### Pings finaux post-rollback

Depuis FW-INT-LYON (ping -c 2 -W 1 -S <vlan_gw> 192.168.40.11) :
- BASTION  192.168.15.1 -> 192.168.40.11 : 2/2 (0% loss)
- SERVERS  192.168.20.1 -> 192.168.40.11 : 2/2 (0% loss)
- USERS    192.168.30.1 -> 192.168.40.11 : 2/2 (0% loss)
- BACKUP   192.168.50.1 -> 192.168.40.11 : 2/2 (0% loss)

ROLLBACK VALIDE. Tunnels UP.
