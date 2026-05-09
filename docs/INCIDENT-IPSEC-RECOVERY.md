# INCIDENT -- IPsec Recovery Post-Reboot

## Date / Contexte

2026-05-09, ~18:52 Europe/Paris.
Reboot des 3 firewalls OPNsense (opn-fw-ext-lyon, opn-fw-ext-mrs, opn-fw-int-lyon)
pour appliquer changements NUMA/Memory hotplug dans Proxmox.

## Symptome initial

Apres reboot, 4 tunnels IPsec DOWN.
```
swanctl --list-sas  ->  0 IKE_SAs, 0 CHILD_SAs
```

## Diagnostic

### 1. Mode swanctl confirme (les 2 FW externes)

```xml
<Swanctl version="1.0.0"></Swanctl>
<enable_legacy_sect>1</enable_legacy_sect>
```

Mode swanctl actif. Legacy section presente mais sans fichiers .conf.

### 2. Conf sur disque presente, non chargee

Fichier `/usr/local/etc/swanctl/swanctl.conf` present et correct sur les 2 FW.
Repertoire `conf.d/` vide. `strongswan.opnsense.d/` vide (README seulement).

### 3. sequence au boot (logs charon)

| Heure | Evenement |
|-------|-----------|
| 18:52-53 | charon demarre, charge vici connection, installe 4 child SA policies (`start_action = trap`) |
| 18:58:19 | `configctl ipsec reload` s'execute -- "updated vici connection" -- AUCUNE initiation IKE |
| Apres | 0 IKE_SA, policies SPD presentes, tunnels morts |

### 4. Cause racine

`start_action = trap` dans swanctl.conf :
- charon installe les policies SPD (kernel routing entries)
- BUT ne demarre PAS l'IKE_SA automatiquement
- Le tunnel ne monte que si du trafic traverse les policies (acquire)

`configctl ipsec reload` appelle `swanctl --load-conns` qui met a jour la config
mais ne trigger PAS `swanctl --initiate`. Resultat : policies chargees, IKE jamais lance.

### 5. Terraform : aucune divergence

```
No changes. Your infrastructure matches the configuration.
```

T3 block_all intact sur les 3 FW. Probleme = runtime IPsec uniquement, pas config Terraform.

## Procedure de recuperation

### Etape 1 : Charger les connexions dans charon

```bash
ssh opn-fw-ext-lyon 'swanctl --load-conns'
ssh opn-fw-ext-lyon 'swanctl --load-creds'
```

Connexion chargee : `78112723-0176-40d8-905f-1c187aaf58b3`

### Etape 2 : Initier IKE_SA

```bash
ssh opn-fw-ext-lyon 'swanctl --initiate --ike 78112723-0176-40d8-905f-1c187aaf58b3'
```

Resultat : IKE_SA ESTABLISHED en ~2s.

### Etape 3 : Initier les 4 CHILD_SA

```bash
ssh opn-fw-ext-lyon 'swanctl --initiate --child 4bbf5017-9416-4332-8551-a0d9e77990f8'
ssh opn-fw-ext-lyon 'swanctl --initiate --child 1856ee5d-842a-4008-a917-bafbfcf50072'
ssh opn-fw-ext-lyon 'swanctl --initiate --child 1a71c717-2f3e-4006-99b4-5f786880c64b'
ssh opn-fw-ext-lyon 'swanctl --initiate --child 120d04c8-4353-4854-a95f-df0b1459b9d9'
```

4/4 CHILD_SA INSTALLED. Verification :
```
swanctl --list-sas | grep -c INSTALLED  ->  4 (ext-lyon)
swanctl --list-sas | grep -c INSTALLED  ->  4 (ext-mrs)
```

### Etape 4 : Test cross-site

```
dc01 -> proxy-mrs01 (192.168.40.11) : 3/3 paquets, 0% loss
proxy-mrs01 -> dc01 (192.168.20.10) : 3/3 paquets, 0% loss
```

## Effet secondaire decouvert : Wazuh 1514 bloque

### Symptome

Apres recovery IPsec, Wazuh montrait 5/7 agents Active.
backup01 (192.168.50.2) et bastion01 (192.168.15.2) : Disconnected.

### Cause

T-NFT-PROMETHEUS (session precedente) avait applique le role hardening sur app01.
Le template nftables ne contient pas de regle pour le port Wazuh (1514).
Les 5 agents deja connectes ont survecu grace a `ct state established,related accept`
(connexions etablies avant le hardening).
Le reboot de fwint-lyon a flush le conntrack -> backup01 et bastion01 ont perdu
leur connexion etablie -> tentative de reconnexion bloquee par nftables app01.

### Fix tactique applique

```bash
ssh debian@192.168.20.13 'sudo nft insert rule inet filter input position 6 \
  ip saddr { 192.168.15.0/24, 192.168.50.0/24 } tcp dport 1514 accept'
```

Resultat : 7/7 agents Active. Regle temporaire (disparait au prochain `nftables reload`).

### Dette Ansible -- T-WAZUH-NFT

Ajouter dans `host_vars/app01.yml` :

```yaml
hardening_extra_nft_rules:
  - "ip saddr 192.168.10.0/24 tcp dport 1514 accept"
  - "ip saddr 192.168.15.0/24 tcp dport 1514 accept"
  - "ip saddr 192.168.18.0/24 tcp dport 1514 accept"
  - "ip saddr 192.168.20.0/24 tcp dport 1514 accept"
  - "ip saddr 192.168.50.0/24 tcp dport 1514 accept"
```

Puis relancer hardening sur app01 :
```bash
ansible-playbook -i inventory/hosts.yml site.yml --tags role:hardening --limit app01
```

## Recommandation -- T-IPSEC-PERSIST-CHECK

`start_action = trap` signifie que les tunnels NE montent PAS automatiquement au boot.
Ils montent uniquement quand du trafic traverse les policies SPD (trigger ACQUIRE).

Deux options :

**Option A (OPNsense GUI)** -- Changer `start_action = start` dans la config tunnel.
Cela force charon a initier l'IKE des le chargement de la connexion.
Verification : OPNsense VPN > IPsec > Connections > Mode initiation.

**Option B (script post-boot)** -- Ajouter un script `/usr/local/etc/rc.d/ipsec-initiate.sh`
qui attend que charon soit pret puis appelle `swanctl --initiate --ike <uuid>` :

```bash
#!/bin/sh
# Force IPsec initiation post-boot (start_action=trap workaround)
sleep 30
swanctl --initiate --ike 78112723-0176-40d8-905f-1c187aaf58b3 --child 4bbf5017-9416-4332-8551-a0d9e77990f8
```

Option A est preferable si supportee par l'UI OPNsense sans modifier config.xml manuellement.

## Etat final post-recovery

| Check | Resultat |
|-------|----------|
| IPsec : 4 CHILD_SAs INSTALLED | OK |
| Terraform : No changes | OK |
| SSH : dc01, fs01, db01, app01, bastion01 | OK |
| SSH backup01 (ProxyJump direct Mac) | ECHEC pre-existant (via dc01 : OK) |
| AD : 91 users, 8 groupes | OK |
| SMB : 5 shares | OK |
| MariaDB : nova_logistique + nova_rh | OK |
| Wazuh : 7/7 agents Active | OK (apres fix nft 1514) |
| Prometheus + Grafana : active | OK |
| Borg : 3 repos (configs, databases, filesystem) | OK |
| T3 block_all : 16+12+12 regles | OK |
