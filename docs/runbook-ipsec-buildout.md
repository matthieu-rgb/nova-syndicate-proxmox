# Runbook IPsec inter-sites Lyon <-> Marseille -- buildout / demo jury

**Statut** : PLAN d'execution **non execute** -- a valider avant action.
**Date** : 2026-06-03
**Ticket** : T-IPSEC-DEMO-JURY (RECO seulement a ce stade).

## TL;DR -- la situation reelle (correction du diagnostic Phase 1)

L'audit sante du 2026-06-03 disait IPsec "JAMAIS-FINALISE" et "charon Command
not found". **C'etait faux**, du a des soucis de redirection tcsh+ssh non
contournes a l'epoque. La RECO de ce soir, faite via scripts base64-encoded
pour bypasser tcsh, montre :

- **IKE SA ESTABLISHED** depuis ~7h36 entre `10.0.0.2` (FW-EXT-LYON) et
  `10.0.2.2` (FW-EXT-MRS), IKEv2, `AES_GCM_16-256/PRF_HMAC_SHA2_256/MODP_2048`.
- **4 child SAs INSTALLED en mode TUNNEL** :
  - reqid 1 SERVERS  : 192.168.20.0/28 <-> 192.168.40.0/26 -- **traffic vu** (1301 oct / 3 pkts recus, 43 s ago)
  - reqid 2 BASTION  : 192.168.15.0/29 <-> 192.168.40.0/26 -- 0 trafic exercice
  - reqid 3 USERS    : 192.168.30.0/26 <-> 192.168.40.0/26 -- 0 trafic
  - reqid 4 BACKUP   : 192.168.50.0/29 <-> 192.168.40.0/26 -- 0 trafic
- charon process running (PID 14377 cote Lyon), binaire `/usr/local/libexec/ipsec/charon`.
- Routes statiques FW-EXT-LYON vers 4 prefixes Lyon via gateway 10.0.1.2 (vtnet2).
- SPD kernel : 4 entrees `esp/tunnel/10.0.2.2-10.0.0.2/unique:{1,2,3,4}` cote Lyon, miroir cote MRS.
- PSK partagee, identique des deux cotes.

**Donc rien a "monter"** -- les 4 child SAs sont deja INSTALLED. Pour la demo
jury, il suffit de **generer du trafic** dans les 4 VLANs vers 192.168.40.0/26
pour exercer les 4 tunnels.

Le runbook ci-dessous decrit :
1. Confirmation finale RECO (a faire avant la session captures).
2. Plan de demo jury (commandes a executer en session live).
3. Points faibles a documenter en dette (persistance scripts absents).
4. Snapshots a prendre avant tout `swanctl --reload` ou modif config.

---

## 1. Contexte technique

### 1.1. Topologie

```
                          WAN-SIM (10.0.0.1 / 10.0.2.1)
                                |
        FW-EXT-LYON 10.0.0.2 <--+--> 10.0.2.2 FW-EXT-MRS
              |                                |
           172.16.1.1 (DMZ)             192.168.40.1/26 (LAN MRS)
              |
        FW-INT-LYON (10.0.1.2)
              |
   trunk VLANs 15/20/30/50 :
   - 192.168.15.0/29 BASTION
   - 192.168.20.0/28 SERVERS
   - 192.168.30.0/26 USERS  (pas de VM aujourd'hui)
   - 192.168.50.0/29 BACKUP
```

### 1.2. Parametres IKE/ESP en place

- **IKEv2**, PSK partagee 32 octets base64.
- **Phase 1 (IKE SA)** : AES_GCM_16-256 / PRF HMAC SHA-256 / MODP-2048,
  rekey 86400s, dpd 30s.
- **Phase 2 (4 child SAs)** : ESP AES_CBC-256 / HMAC_SHA2_256_128 / MODP-2048,
  rekey 3600s, `start_action=trap`.
- IKE : UDP 500 (pas de NAT-T necessaire car 10.0.0.0/8 routable bout en bout).
- ESP : protocole 50.

### 1.3. Methode d'auth -- PSK retenu (avis)

| Critere | PSK (en place) | Cert step-ca |
|---------|---------------|--------------|
| Mise en place | **deja fait** | restant : emettre 2 certs + deployer + configurer |
| Effort restant | 0 | M (3-5 j) |
| Demo jury | direct | demo "rotation cert step-ca" possible mais hors scope IPsec |
| NIS2 art.21 §2 e | conforme (32 octets aleatoires) | egalement conforme |
| Reproductibilite | terraform.tfvars sensible | role Ansible cert + step-ca + dette T-IPSEC-CERT-MIGRATION |
| Robustesse rotation | manuelle | automatable via step-ca renew |

**Avis** : **garder PSK pour la demo jury**. La cert step-ca est une evolution
post-certification, ticket `T-IPSEC-CERT-MIGRATION` a ouvrir (effort M, valeur
NIS2 marginale puisque PSK 256 bits est conforme).

---

## 2. RECO finale -- a executer juste avant la session captures

Lecture seule, ~5 minutes. Confirme que rien n'a regresse depuis aujourd'hui
16:43 (timestamp `lastused` du SPD entry servers).

### Etape RECO.1 -- FW-EXT-LYON etat live

```sh
# Via Tailscale + jump FW-INT-LYON + cle dediee (script base64 a cause de tcsh)
CMD=$(cat <<'EOF'
echo "--- IKE SA + 4 child SAs ---"
/usr/local/sbin/swanctl --list-sas
echo "--- routes 192.168 ---"
netstat -rn | grep -E "192.168.(15|20|30|40|50)"
echo "--- charon process ---"
pgrep -fl charon
EOF
)
B64=$(printf '%s' "$CMD" | base64 | tr -d '\n')
ssh -i ~/.ssh/nova_opnsense_ed25519 -o UserKnownHostsFile=/tmp/.kh -o StrictHostKeyChecking=no \
    -J opn-fw-int-lyon root@10.0.1.1 "echo $B64 | b64decode -r | /bin/sh"
```

**Attendu** : 1 IKE SA `ESTABLISHED`, 4 child SAs `INSTALLED, TUNNEL`, 4 routes.

### Etape RECO.2 -- FW-EXT-MRS etat live (via proxy-mrs01)

```sh
PVE="root@100.112.113.2"   # Tailscale IP directe (pas 192.168.18.50)
KEY_B64=$(base64 -w0 < ~/.ssh/nova_opnsense_ed25519)

# Push cle temporaire sur proxy-mrs01 (cleanup en fin)
ssh "$PVE" "qm guest exec 108 --timeout 10 -- /bin/bash -c \
  \"printf '%s' '$KEY_B64' | base64 -d > /tmp/.k && chmod 600 /tmp/.k\""

CMD=$(cat <<'EOF'
echo "--- IKE SA + 4 child SAs MRS ---"
/usr/local/sbin/swanctl --list-sas
echo "--- charon process MRS ---"
pgrep -fl charon
EOF
)
B64=$(printf '%s' "$CMD" | base64 -w0)
ssh "$PVE" "qm guest exec 108 --timeout 25 -- /bin/bash -c \
  'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/.kh \
   -i /tmp/.k root@192.168.40.1 \"echo $B64 | b64decode -r | /bin/sh\"'"

# Cleanup
ssh "$PVE" "qm guest exec 108 --timeout 5 -- /bin/bash -c 'rm -f /tmp/.k /tmp/.kh'"
```

**Attendu** : symetrique a RECO.1.

---

## 3. PLAN demo jury -- generer du trafic dans les 4 tunnels

But : exercer les 4 child SAs pour que `swanctl --list-sas` affiche des
compteurs non-nuls dans les 4 (preuve visuelle "4 SAs actives, encapsulation
ESP en cours").

**Pre-requis** : pas de VM dans 192.168.30.0/26 (USERS) ni dans 192.168.40.0/26
en interactif. Donc le trafic doit etre genere depuis les firewalls eux-memes
avec `ping -S <source>` ou depuis VMs Lyon vers `192.168.40.11` (proxy-mrs01)
qui EST joignable.

### Etape DEMO.1 -- Snapshot prealable Proxmox

**Decision** : prendre 2 snapshots ad-hoc avant la session, par prudence.

```sh
# Tunnels en place mais on ne sait jamais : un swanctl --terminate ou un reload
# foireux pourrait casser. Snapshot rapide (4-5s par VM).
ssh root@100.112.113.2 \
  'qm snapshot 201 pre-ipsec-demo-20260603 --description "Pre demo IPsec jury -- 2026-06-03"; \
   qm snapshot 203 pre-ipsec-demo-20260603 --description "Pre demo IPsec jury -- 2026-06-03"'
```

A nettoyer apres la session captures (cf STATUS.md `Snapshots a nettoyer`).

### Etape DEMO.2 -- Exercer les 4 tunnels par ping `-S`

Depuis FW-INT-LYON, lancer des pings sources par interface VLAN :

```sh
ssh opn-fw-int-lyon '
for src_dst in "192.168.20.1 192.168.40.1" "192.168.15.1 192.168.40.1" \
               "192.168.30.1 192.168.40.1" "192.168.50.1 192.168.40.1"; do
  src=$(echo $src_dst | cut -d" " -f1); dst=$(echo $src_dst | cut -d" " -f2)
  echo "--- ping -S $src $dst ---"
  ping -c 3 -W 1 -S $src $dst | grep -E "received|loss"
done
'
```

**Attendu** : ping repondu sur les 4 sources -- chaque ping declenche le child
SA correspondant (start_action=trap). FW-INT-LYON a une IP sur chaque VLAN
sub-interface, donc `-S` choisit la bonne source pour selectionner le bon
selector IPsec.

**Si servers est le seul a passer** (root cause 1 du runbook-ipsec-multi-vlan) :
relancer le fix `swanctl --load-conns` + `swanctl --initiate --child child_X`
pour les 3 manquants (cf section 4.2 du runbook-ipsec-multi-vlan, fichier
[runbook-ipsec-multi-vlan.md](runbook-ipsec-multi-vlan.md)).

### Etape DEMO.3 -- Capture visuelle pour le jury

Cote Lyon, generer la sortie qui sera projetee :

```sh
ssh -J opn-fw-int-lyon -i ~/.ssh/nova_opnsense_ed25519 root@10.0.1.1 \
  '/usr/local/sbin/swanctl --list-sas 2>&1 | head -60'
```

Attendu (post DEMO.2) : les 4 child SAs avec `bytes/packets` > 0 et timestamp
recent (< 60 s). Le compteur `bytes` augmente a chaque ping.

Cote MRS, capture symetrique pour montrer le miroir :

```sh
# Meme pattern que RECO.2, mais en capturant swanctl --list-sas | head -60
```

### Etape DEMO.4 -- tcpdump ESP au point WAN (optionnel, valeur visuelle)

Depuis FW-EXT-LYON ou FW-EXT-MRS, montrer le trafic encapsule ESP entre les
2 IP WAN :

```sh
# tcpdump sur vtnet0 (WAN side) pendant que DEMO.2 tourne
tcpdump -nn -i vtnet0 -c 20 'proto 50 and host 10.0.2.2'
```

**Attendu** : flux ESP entre `10.0.0.2 > 10.0.2.2 proto 50` toutes les ~1 s
pendant les pings. Demontre qu'aucun paquet en clair ne sort -- preuve
chiffrement NIS2.

### Etape DEMO.5 -- Verifications croisees applicatives (optionnel)

Pour aller plus loin : valider qu'une connexion applicative reelle passe via
le tunnel SERVERS. Depuis dc01 (192.168.20.10) :

```sh
ssh -J proxmox-hypervisor debian@192.168.20.10 \
  'ping -c 3 192.168.40.11; \
   curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" \
     --max-time 5 http://192.168.40.11/ || echo "no HTTP on proxy-mrs01"'
```

---

## 4. Points d'attention (a documenter en dette ou pre-action)

### 4.1. Wrapper `service ipsec onestatus` ment

Le service OPNsense `ipsec` retourne `ipsec is not running` alors que `charon`
tourne. Mecanisme suspect : marqueur `pidfile` non maintenu, ou unit RC.D
desynchronise du daemon reel. **Impact** : faux negatif healthcheck.

A documenter comme dette LOW : **T-OPNSENSE-IPSEC-SERVICE-WRAPPER**. Fix
possible : utiliser `pgrep charon` au lieu de `service ipsec onestatus` dans
les sondes du healthcheck script (cf `scripts/healthcheck.sh`).

### 4.2. Scripts persistance ABSENTS

Le runbook `runbook-ipsec-multi-vlan.md` mentionne 2 scripts de persistance
pour resister aux regenerations OPNsense de `swanctl.conf` apres modif GUI :

- `/usr/local/etc/rc.d/nova_ipsec_fix` -- **n'existe pas** aujourd'hui.
- `/usr/local/sbin/fix_ipsec_children.py` -- **n'existe pas**.

**Consequence** : si quelqu'un modifie la config IPsec via GUI OPNsense
(Tunnel Settings, Connections), le `swanctl.conf` actuel (4 children separes)
sera **ecrase par le format bundle** (1 child, 4 TS concatenes) et seul SERVERS
fonctionnera (root cause 1 du runbook-ipsec-multi-vlan).

**Recommandation** : ne PAS modifier la conf IPsec via GUI tant que les
scripts de persistance ne sont pas redeployes. Si necessaire, modifier
directement `/usr/local/etc/swanctl/swanctl.conf` + `swanctl --load-conns`
(pattern strongswan natif).

A documenter comme dette MEDIUM : **T-IPSEC-PERSISTENCE-SCRIPTS** -- replanter
les 2 scripts dans backup ou repo, prevoir un role Ansible `opnsense_ipsec`
qui les depose au boot.

### 4.3. Diagnostics tcsh OPNsense -- envelopper en base64

Toutes les commandes SSH vers OPNsense (FreeBSD, root sous tcsh) doivent
etre envoyees en base64-encoded vers `/bin/sh`, sinon les redirections
`2>&1` deviennent "Ambiguous output redirect" et les variables avec espaces
deviennent "Unmatched '"'".

Pattern stable :
```sh
CMD=$(cat <<'EOF'
... script bash/sh ...
EOF
)
B64=$(printf '%s' "$CMD" | base64 | tr -d '\n')
ssh ... opnsense "echo $B64 | b64decode -r | /bin/sh"
```

Memoire a creer : **`opnsense-tcsh-base64-pattern`** (dette tooling).

### 4.4. WAN-SIM ICMP ping vs ESP

`ping 10.0.0.2 <-> 10.0.2.2` echoue (100 % packet loss via WAN-SIM). Pourtant
ESP (proto 50) traverse correctement. WAN-SIM bloque probablement ICMP entre
les 2 segments WAN, sans impacter ESP. **Pas un bug** : c'est meme realiste
(beaucoup d'operateurs filtrent ICMP).

A noter dans la demo : on ne peut PAS utiliser `ping 10.0.2.2` pour valider
la connectivite WAN -- il faut `swanctl --list-sas` (qui confirme l'IKE SA
ESTABLISHED).

### 4.5. ADRs 0002 et 0005 desynchronises du runtime

Les ADRs decrivent un plan d'adressage `10.0.x.x` (Lyon) / `10.1.x.x` (MRS)
qui n'a jamais ete deploye. Le runtime utilise `192.168.x.x` pour les VLANs
Lyon et `192.168.40.0/26` pour MRS. Le runbook
[runbook-ipsec-multi-vlan.md](runbook-ipsec-multi-vlan.md) est aligne runtime.

A documenter comme dette LOW : **T-ADR-2-5-SYNC-RUNTIME** -- mettre a jour
les ADRs 0002 et 0005 avec les vrais prefixes, ajouter une note "actuel
runtime != plan VLSM initial".

---

## 5. Point de non-retour identifie

**Aucun point de non-retour** dans le plan de demo presente.

Toutes les actions DEMO.1 a DEMO.5 sont **lecture + generation de trafic
ICMP/HTTP non destructif**. Aucune modification de config IPsec, aucun
`swanctl --terminate` ou `--reload`, aucune ecriture sur les firewalls.

Le seul cas ou un point de non-retour apparait : si DEMO.2 echoue (tunnels
ne montent pas malgre les pings), et qu'on doit appliquer le fix manuel
`swanctl --initiate --child child_X`. Si ce fix necessite de modifier
`swanctl.conf`, alors :
- Snapshot avant : `qm snapshot 201 pre-ipsec-fix-N` (idem 203)
- Backup : `cp /usr/local/etc/swanctl/swanctl.conf .bak-pre-fix`
- Modif chirurgicale (pas via GUI)
- `swanctl --load-conns` puis `--initiate`

---

## 6. Snapshots a prendre avant la session captures

| VMID | VM | Snapshot suggere | Raison |
|------|-----|------------------|--------|
| 201 | fw-ext-lyon01 | `pre-ipsec-demo-20260603` | Filet pour la demo (cf DEMO.1) |
| 203 | fw-ext-mrs01 | `pre-ipsec-demo-20260603` | Idem |
| 202 | fw-int-lyon01 | (optionnel) `pre-ipsec-demo-20260603` | Si DEMO.2 utilise ping -S depuis FW-INT |

A supprimer apres validation jury.

---

## 7. Sequence d'execution attendue (par toi en session jury)

```
1. RECO finale (5 min)      -- valider que rien n'a regresse depuis ce soir
2. Snapshots DEMO.1 (1 min) -- 2 ou 3 snapshots Proxmox
3. DEMO.2 (2 min)           -- ping -S sur les 4 sources
4. DEMO.3 (1 min)           -- capture swanctl --list-sas Lyon + MRS
5. DEMO.4 (2 min, optionnel)-- tcpdump ESP au point WAN
6. DEMO.5 (3 min, optionnel)-- validation applicative dc01 -> proxy-mrs01
```

Total : ~10-15 minutes en session live.

---

## 8. Annexe -- PSK fait, comment voir la valeur

La PSK est stockee dans `swanctl.conf` cote charon (champ `secret =
0s...`) et probablement dans `terraform.tfvars` (variable sensible) +
backup OPNsense `/conf/config.xml` (section `<ipsec>`). Elle est partagee
entre les 2 firewalls (verifie : identique sur Lyon et MRS aujourd'hui).

Pour une demo "transparence cryptographique" jury sans leak : montrer
uniquement le hash :

```sh
ssh -J opn-fw-int-lyon -i ~/.ssh/nova_opnsense_ed25519 root@10.0.1.1 \
  'grep "secret = " /usr/local/etc/swanctl/swanctl.conf | sha256sum'
```

Memes hashes des 2 cotes = PSK partagee correctement.

---

## 9. Tickets ouverts par cette RECO

| Ticket | Severite | Description |
|--------|----------|-------------|
| **T-IPSEC-PERSISTENCE-SCRIPTS** | MEDIUM | Replanter `nova_ipsec_fix` + `fix_ipsec_children.py` ou les Ansibliser, sinon toute modif IPsec via GUI OPNsense ramene au format bundle (root cause 1). |
| **T-OPNSENSE-IPSEC-SERVICE-WRAPPER** | LOW | Le wrapper `service ipsec onestatus` ment ("not running" alors que charon tourne). Healthcheck a corriger. |
| **T-IPSEC-CERT-MIGRATION** | LOW (post-certif) | Migrer PSK -> certs step-ca (V2). PSK 256 bits suffit NIS2. |
| **T-ADR-2-5-SYNC-RUNTIME** | LOW | ADRs 0002 et 0005 utilisent un plan 10.x non deploye. Aligner sur 192.168.x runtime. |
| **T-OPNSENSE-TCSH-BASE64-PATTERN** | DOC | Documenter le pattern base64-encoded SSH vers OPNsense pour eviter "Ambiguous output redirect" tcsh. Memory Claude `opnsense-tcsh-base64-pattern`. |

---

## 10. References

- [runbook-ipsec-multi-vlan.md](runbook-ipsec-multi-vlan.md) -- root causes
  et fix 2026-05-08 (4 children separes, routes statiques).
- [runbook-ipsec-recovery.md](runbook-ipsec-recovery.md) -- script
  ipsec-recovery.sh referencee par healthcheck.
- [ADR-0005-ipsec-ikev2-site-to-site.md](adr/ADR-0005-ipsec-ikev2-site-to-site.md)
- [ADR-0002-plan-adressage-vlan.md](adr/ADR-0002-plan-adressage-vlan.md)
- [ADR-0034-ldaps-migration-strong-auth.md](adr/ADR-0034-ldaps-migration-strong-auth.md)
- [terraform/environments/opnsense/fw_ext.tf](../terraform/environments/opnsense/fw_ext.tf)
  -- regles `fwext_wan_ipsec_{ike,natt,esp}` deja IaC.
- [terraform/environments/opnsense/fw_ext_mrs.tf](../terraform/environments/opnsense/fw_ext_mrs.tf)
  -- symetrique cote MRS.
