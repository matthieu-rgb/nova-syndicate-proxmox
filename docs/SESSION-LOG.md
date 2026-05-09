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

---

## T-IMPORT -- Reintegration 9 routes orphelines (2026-05-08)

### UUID mapping routes OPNsense -> ressources Terraform

| Ressource Terraform | FW | UUID OPNsense | Reseau |
|---------------------|----|---------------|--------|
| opnsense_route.fwext_to_bastion | FW-EXT-LYON | 9d625e6a-4642-434c-a898-bb8b910e6afc | 192.168.15.0/29 |
| opnsense_route.fwext_to_servers | FW-EXT-LYON | 9a55165b-684e-41cd-9505-21764cbd5489 | 192.168.20.0/28 |
| opnsense_route.fwext_to_users | FW-EXT-LYON | 69e1dd92-b929-43ad-96f2-2c27810fd030 | 192.168.30.0/26 |
| opnsense_route.fwext_to_backup | FW-EXT-LYON | ffa56a3d-90bb-4ee8-a2aa-b6177f2c0fc8 | 192.168.50.0/29 |
| opnsense_route.fwext_to_mrs_lan | FW-EXT-LYON | 6a3ba959-f852-4647-9b9a-d2ce55a8e8d6 | 192.168.40.0/26 |
| opnsense_route.fwextmrs_to_lyon | FW-EXT-MRS | 6fd5ee61-bba3-4a82-9599-e7cdf7681ddb | 192.168.0.0/16 |
| opnsense_route.wansim_to_mrs_lan | WAN-SIM | 2bdb3470-30b8-4033-9d0b-8de61890127c | 192.168.40.0/26 |
| opnsense_route.wansim_to_lyon_transit | WAN-SIM | 884b73c4-734f-45e5-bf5b-14805bd9ce03 | 10.0.1.0/30 |
| opnsense_route.wansim_to_lyon_internal_subnets | WAN-SIM | d6760959-7a0f-4ac4-a0ff-3bcb4e4bcf7b | 192.168.0.0/16 |

### terraform import : 9/9 succes

```
terraform import 'opnsense_route.fwext_to_bastion' '9d625e6a-4642-434c-a898-bb8b910e6afc'
terraform import 'opnsense_route.fwext_to_servers' '9a55165b-684e-41cd-9505-21764cbd5489'
terraform import 'opnsense_route.fwext_to_users' '69e1dd92-b929-43ad-96f2-2c27810fd030'
terraform import 'opnsense_route.fwext_to_backup' 'ffa56a3d-90bb-4ee8-a2aa-b6177f2c0fc8'
terraform import 'opnsense_route.fwext_to_mrs_lan' '6a3ba959-f852-4647-9b9a-d2ce55a8e8d6'
terraform import 'opnsense_route.fwextmrs_to_lyon' '6fd5ee61-bba3-4a82-9599-e7cdf7681ddb'
terraform import 'opnsense_route.wansim_to_mrs_lan' '2bdb3470-30b8-4033-9d0b-8de61890127c'
terraform import 'opnsense_route.wansim_to_lyon_transit' '884b73c4-734f-45e5-bf5b-14805bd9ce03'
terraform import 'opnsense_route.wansim_to_lyon_internal_subnets' 'd6760959-7a0f-4ac4-a0ff-3bcb4e4bcf7b'
```

terraform plan post-import : "No changes. Your infrastructure matches the configuration."

### Pings post-import

Depuis FW-INT-LYON :
- SERVERS 192.168.20.1 -> 192.168.40.11 : 2/2 (0% loss)
- BASTION 192.168.15.1 -> 192.168.40.11 : 2/2 (0% loss)
- USERS   192.168.30.1 -> 192.168.40.11 : 2/2 (0% loss)
- BACKUP  192.168.50.1 -> 192.168.40.11 : 2/2 (0% loss)

### Audit des routes suspectes (Etape 5)

Methode : disable API + reconfigure, 3 pings x 4 VLANs, reactivation immediate.
4 Child SAs modernes restes INSTALLED pendant tout l'audit.

| Route | Verdict | Pings sans elle |
|-------|---------|----------------|
| wansim_to_lyon_internal_subnets | PARASITE | 4/4 OK |
| wansim_to_mrs_lan | PARASITE | 4/4 OK |
| wansim_to_lyon_transit | PARASITE | 4/4 OK |
| fwext_to_mrs_lan | PARASITE | 4/4 OK -- SPD strongSwan gere independamment |
| fwextmrs_to_lyon | PARASITE | 4/4 OK -- idem cote responder MRS |

5 routes PARASITES identifiees. A supprimer lors de T3-DURCISSEMENT.
4 routes NECESSAIRES conservees (fwext_to_{bastion,servers,users,backup}).
Ref detaillee : docs/runbook-ipsec-multi-vlan.md section "Audit des routes statiques"

---

## T2 -- Internet BASTION (2026-05-08)

### Diagnostic initial

Phase 1 a revele que T2 etait deja accompli sans intervention :
- `fwint_bastion_to_internet` (enabled=true) en state depuis Phase II IaC apply
- `fwint_servers_to_internet`, `fwint_users_to_internet`, `fwint_backup_to_internet`
  aussi enabled=true -- tous les VLANs avaient internet

### Perimetre recalibre

L'objectif T2 "donner internet a BASTION uniquement" etait sur-simplifie.
Apres analyse :
- BASTION internet : OK (curl github.com -> HTTP/2 200, DNS OK, git OK)
- SERVERS/USERS/BACKUP internet "raw" : conserve (besoins legaux apt/NTP/web/rclone)
- Filtrage granulaire par VLAN : reporte en T-SQUID (proxy Squid forward)

### Tests de non-regression post-T2

- terraform plan : "No changes"
- swanctl --list-sas : 4 Child SA modernes INSTALLED (reqids 1-4)
- 4 pings IPsec cross-site : 2/2 (0% loss) sur SERVERS/BASTION/USERS/BACKUP

### Etat final Phase II

| Tache | Statut |
|-------|--------|
| T-MIGRATION IPsec | CLOSED |
| T-IMPORT 9 routes | CLOSED |
| T2 Internet BASTION | CLOSED |
| T3 Durcissement block_all | OPEN |
| T-SQUID Proxy VLAN | OPEN (nouvelle) |
| DT-2 block_all=false | OPEN (scope T3) |
| DT-3 con1 legacy expire | SURVEILLANCE |
| DT-4 IPsec state TF | OPEN (hors scope) |

---

## T3 -- Durcissement Firewall block_all (2026-05-09)

### Phase 1 -- Cartographie trafic

Ref : docs/T3-traffic-matrix.md
Resultat : 1 seule regle manquante identifiee (fwint_wan_ipsec_decapsulated sur FW-INT vtnet0).
Toutes les autres interfaces disposent deja des regles pass necessaires.

### Apply A -- Suppression 5 routes parasites (2026-05-09)

Commande :
```
terraform apply -target=opnsense_route.wansim_to_lyon_internal_subnets \
  -target=opnsense_route.wansim_to_lyon_transit \
  -target=opnsense_route.wansim_to_mrs_lan \
  -target=opnsense_route.fwext_to_mrs_lan \
  -target=opnsense_route.fwextmrs_to_lyon
```

Resultat : 0 added, 0 changed, 5 destroyed

Routes supprimees :
- wansim_to_lyon_internal_subnets [d6760959] -- 192.168.0.0/16
- wansim_to_lyon_transit           [884b73c4] -- 10.0.1.0/30
- wansim_to_mrs_lan                [2bdb3470] -- 192.168.40.0/26
- fwext_to_mrs_lan                 [6a3ba959] -- 192.168.40.0/26
- fwextmrs_to_lyon                 [6fd5ee61] -- 192.168.0.0/16

Tests post-Apply A :
- 4 pings IPsec cross-site : 2/2 (0% loss) sur BASTION/SERVERS/USERS/BACKUP
- swanctl --list-sas : 8 INSTALLED (4 modernes UUID + 4 legacy expirant)
- Wazuh agents : 7 Active (000-006)
- SSH 6 hotes : OK
- AD, FS, DB, Monitoring, BorgBackup : OK
- terraform plan : 2 creates pending (Apply B -- normal, non-regression)

### Apply B -- Alias net_lyon_internal + regle decapsulated (2026-05-09)

Ressources creees :
- opnsense_firewall_alias.fwint_network["net_lyon_internal"] [e35c88d6]
  content = [192.168.15.0/29, 192.168.20.0/28, 192.168.30.0/26, 192.168.50.0/29]
- opnsense_firewall_filter.fwint_wan_ipsec_decapsulated [ff99886c]
  pass in quick on vtnet0 inet from net_lan_mrs to net_lyon_internal

Verification pfctl : regle visible avant auto-pass-all (position correcte) :
  pass in quick on vtnet0 inet from <net_lan_mrs> to <net_lyon_internal>
  flags S/SA keep state label "ff99886c-0cd1-4167-9447-c91d2ce9c263"

Tests post-Apply B :
- 4 pings IPsec (FW-INT-LYON initie) : 0% loss ✓
- swanctl --list-sas : 8 INSTALLED (4 modernes + 4 legacy) ✓
- Wazuh agents : 7 Active ✓
- health-check.sh : 0 critiques / 0 warnings ✓
- terraform plan : No changes ✓
- BONUS (MRS initie -> Lyon) :
  192.168.40.11 -> DC1 (192.168.20.10) : 2/2 (0% loss) ✓
  192.168.40.11 -> APP1 (192.168.20.13) : 2/2 (0% loss) ✓

Regle fwint_wan_ipsec_decapsulated validee fonctionnellement.
Trafic MRS-initie traverse FW-INT-LYON vtnet0 sans blocage.
Block_all sur vtnet0 peut etre active en Phase 3 sans risque.

### Phase 3 -- Fermeture progressive (2026-05-09)

| Interface | FW | Statut | Commit |
|-----------|-----|--------|--------|
| vtnet0 WAN | WAN-SIM | CLOSED | d5c4991 |
| opt1 BACKUP | FW-INT-LYON | CLOSED | d5c4991 |
| opt4 USERS | FW-INT-LYON | CLOSED | c4fbf10 |
| vtnet0 WAN | FW-EXT-MRS | CLOSED | 364c044 |
| vtnet0 WAN | FW-EXT-LYON | CLOSED | d838416 |
| opt3 SERVERS | FW-INT-LYON | CLOSED | pending |
| opt2 BASTION | FW-INT-LYON | pending | - |
| vtnet0 WAN | FW-INT-LYON | pending | - |

Note T3 : interfaces USERS/SERVERS/BACKUP fermées avec block_all placeholder
(pass-all *_to_internet positionné avant block => block dead code).
Hardening réel différé en T-SQUID. Voir PHASE-II-KANBAN.md section
"Dette T3 -- Pass-all à remplacer".

#### Interface 1/8 correction : commit WAN-SIM = commit initial de session,
BACKUP = d5c4991 (même session), USERS = c4fbf10, EXT-MRS = 364c044,
EXT-LYON = d838416.

#### Interface 2/8 -- FW-INT-LYON opt1 BACKUP (2026-05-09)

Ressource : opnsense_firewall_filter.fwint_backup_block_all [ac3427cc]
Ordering confirmé post -replace : pass SSH + pass-all AVANT block.
Tests : BACKUP01 ping DC1/FS1/APP1 0%, curl 200, Wazuh active, 7/7, 0/0.

#### Interface 3/8 -- FW-INT-LYON opt4 USERS (2026-05-09)

Ressource : opnsense_firewall_filter.fwint_users_block_all [17883b5f]
Note : fwint_users_to_internet (435d8df8) pass-all positionné avant block.
Block dead code. Flux testés depuis 192.168.30.1 vers DC1/FS1/APP1 : 0%.

#### Interface 4/8 -- FW-EXT-MRS vtnet0 (2026-05-09)

Ressource : opnsense_firewall_filter.fwextmrs_wan_block_all [e16e4a40]
IPsec : ESP + NAT-T/4500 + IKE/500 AVANT block. 8 SA INSTALLED. 0/0.

#### Interface 5/8 -- FW-EXT-LYON vtnet0 (2026-05-09)

Ressource : opnsense_firewall_filter.wan_block_all [fa96cb54 après -replace]
INCIDENT : premier apply positionne block à ligne 5 (entre SMTP/25 et IPsec).
IPsec IKE/ESP dead code -- tunnels tenus par état pf seulement.
Fix : terraform apply -replace immédiat -> block repositionné ligne 13.
Ordering final : SMTP+HTTP+HTTPS+NAT-T+IKE+ESP -> block -> reply-to auto.
Tests post-fix : 8 SA, 3x curl 200, 4 pings 0%, 7/7, 0/0.

#### Interface 6/8 -- FW-INT-LYON opt3 SERVERS (2026-05-09)

Ressource : opnsense_firewall_filter.fwint_servers_block_all [b19da746]
Seule règle pass : fwint_servers_to_internet pass-all (7c8e2113).
Block placeholder (dead code). Option A retenue (cohérence avec USERS).
Tests : MariaDB OK, SMB FS01 OK, cross-site DC01->MRS 0%, Prometheus 2 up,
Wazuh 7/7, SSH 3/3, health-check 0/0.

#### Interface 1/8 -- WAN-SIM vtnet0 (2026-05-09 14:56)

Ressource : opnsense_firewall_filter.wansim_wan_block_all [e480ceaa]
enabled false -> true

pfctl confirme : block drop in log quick on vtnet0 inet all label "e480ceaa-..."
Tests : 4 pings 0% loss, 8 SAs INSTALLED, SSH INT/EXT/MRS OK, 7 Wazuh Active
health-check : 0/0

## TODO post-T3 — Fail2ban + Host keys

- DC1, FS1, APP1, BACKUP01 ont banni BASTION01 via fail2ban suite 
  aux tests SSH automatisés. À débannir : 
  for ip in 192.168.20.10 192.168.20.11 192.168.20.13 192.168.50.2; do
    ssh debian@$ip "sudo fail2ban-client set sshd unbanip 192.168.15.2"
  done

- DB1 host key a changé (probablement après réinstall) : 
  ssh debian@192.168.15.2 "ssh-keygen -R 192.168.20.12"

- Whitelist fail2ban à ajouter pour subnet BASTION (à traiter en 
  T-FAIL2BAN-TUNING).

## TODO post-T3 — Suite cleanup BASTION jumpbox

Découverte pendant cleanup fail2ban T3 : la clé SSH publique 
debian@BASTION01 n'est pas déployée dans les authorized_keys des 
serveurs internes. BASTION01 ne fonctionne pas réellement comme 
jumpbox.

Symptôme : debian@BASTION01 → debian@<DC1|FS1|DB1|APP1|BACKUP01> = 
Permission denied (publickey,keyboard-interactive).

Action différée (T-BASTION-JUMPBOX) :
1. Récupérer la clé publique : 
   ssh debian@192.168.15.2 "cat ~/.ssh/id_ed25519.pub" 
   (ou id_rsa.pub selon ce qui est configuré)
   Si pas de clé : générer une (ssh-keygen -t ed25519)
2. Déployer sur les 5 hôtes via Ansible :
   ansible-playbook playbooks/deploy-bastion-pubkey.yml
3. Hardening sshd des serveurs internes : 
   AllowUsers debian@192.168.15.0/29 dans sshd_config
4. Test : depuis BASTION, ssh chaque host = OK sans password

Effort estimé : 60 min
Dépendance recommandée : T-MFA-BASTION (TOTP) avant ce déploiement
