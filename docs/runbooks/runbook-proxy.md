# Runbook : proxy (Squid HTTP Proxy)

## 1. Perimetre

Le role `proxy` deploie et configure Squid sur proxy-lyon01 (192.168.20.14, VLAN SERVERS) en tant que proxy HTTP/HTTPS transparent pour les VMs des VLAN SERVERS et USERS. Squid ecoute sur le port 3128 et relaie les requetes HTTP/HTTPS sortantes des clients autorises vers Internet via la gateway OPNsense FW-INT-LYON (192.168.20.1).

Le proxy remplit trois fonctions dans l'architecture Nova Syndicate : centraliser et loguer le trafic web sortant (traçabilite NIS2 Art. 21.f), permettre le filtrage des destinations non autorisees (`squid_denied_sites`), et fournir un cache HTTP pour les mises a jour apt (optimisation bande passante). L'objectif a terme (tache T-SQUID en attente) est de rendre le proxy obligatoire et de bloquer l'acces direct a Internet depuis les VMs internes. Dans l'etat actuel, le proxy est configure et operationnel mais pas encore rendu mandatory (les VMs peuvent encore sortir directement via OPNsense).

proxy-lyon01 est une VM dediee au proxy, separee des serveurs applicatifs, ce qui permet d'appliquer des regles de filtrage sans impacter les services metier. Le profil memoire Squid est dimensionne pour le parc actuel (9 VMs + postes VLAN USERS, environ 50 clients simultanes maximum).

## 2. Prerequis

### Dependances de roles

- `common` et `hardening` doivent etre executes avant `proxy`.
- Aucun autre role metier n'est requis avant le deploiement du proxy.

### Reseau

- proxy-lyon01 : IP statique 192.168.20.14/28, gateway 192.168.20.1 (OPNsense FW-INT-LYON).
- Squid ecoute sur TCP 3128.
- proxy-lyon01 doit avoir un acces sortant vers Internet via la gateway (pour relayer les requetes).
- Les VMs clients doivent pouvoir joindre 192.168.20.14:3128.
- nftables sur proxy-lyon01 : port 3128 ouvert pour les reseaux autorises (configurable via `squid_allowed_networks`).

### Packages

`squid`

### Configuration HTTP_PROXY sur les VMs clients (pour utiliser le proxy)

```bash
# A ajouter dans /etc/environment sur les VMs clientes
http_proxy="http://192.168.20.14:3128/"
https_proxy="http://192.168.20.14:3128/"
no_proxy="localhost,127.0.0.1,192.168.20.0/28,192.168.15.0/29,192.168.50.0/29"
```

Via Ansible, ajouter dans `group_vars/all/vars.yml` :
```yaml
http_proxy: "http://192.168.20.14:3128/"
https_proxy: "http://192.168.20.14:3128/"
```

### Acces

- SSH via bastion : `ssh -J debian@192.168.15.2 debian@192.168.20.14`

## 3. Installation

### Verification pre-deploiement

```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

# Verifier la connectivite de proxy-lyon01
ansible proxies -i inventory/hosts.yml -m ping \
  --private-key ~/.ssh/nova_ansible_ed25519 -u debian

# Verifier que proxy-lyon01 a un acces Internet sortant
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "curl -s --max-time 5 https://debian.org | head -1"
```

### Dry-run

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l proxies \
  --tags proxy \
  --check \
  --diff \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement complet

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l proxies \
  --tags proxy \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Deploiement cible (reconfigurer squid.conf uniquement)

```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l proxies \
  --tags proxy,config \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian \
  --ask-vault-pass
```

### Ordre des tasks internes

1. Installation de squid
2. Deploiement squid.conf.j2 (ACL, ports, reseaux autorises, sites bloques)
3. Start + enable squid
4. (Handler : restart squid si squid.conf change)

## 4. Configuration

### Variables par defaut (defaults/main.yml)

```yaml
squid_port: 3128
squid_allowed_networks:
  - 192.168.20.0/28
  - 192.168.30.0/26
squid_denied_sites: []
```

### Variables du groupe (group_vars/proxies/vars.yml)

```yaml
squid_port: 3128
squid_allowed_networks:
  - 192.168.20.0/28    # VLAN SERVERS
  - 192.168.30.0/26    # VLAN USERS
squid_denied_sites:
  - .torrent-site.example.com
  - .malware-domain.example.com
squid_cache_mem: "256 MB"
squid_max_object_size: "50 MB"
squid_access_log: "/var/log/squid/access.log"
```

### squid.conf cle (template)

```
http_port 3128

# ACL reseaux autorises
acl localnet src 192.168.20.0/28
acl localnet src 192.168.30.0/26

# ACL sites bloques
acl blocked_sites dstdomain .torrent-site.example.com

# Autoriser les reseaux definis
http_access deny blocked_sites
http_access allow localnet
http_access deny all

# Cache
cache_mem 256 MB
maximum_object_size 50 MB

# Logs
access_log /var/log/squid/access.log squid

# DNS interne
dns_nameservers 192.168.20.10 1.1.1.1
```

### Etat actuel vs objectif T-SQUID

**Etat actuel :** Le proxy est configure mais non obligatoire. Les VM peuvent sortir directement via OPNsense. Les regles `squid_denied_sites` sont vides (pas de filtrage actif).

**Objectif T-SQUID :** Ajouter des regles OPNsense bloquant le trafic HTTP/HTTPS direct depuis les VLAN SERVERS et USERS, forçant le passage par le proxy. Configurer les variables d'environnement proxy sur toutes les VMs via Ansible.

## 5. Validation post-deploiement

### Verifier que Squid est actif

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl is-active squid && \
   sudo ss -tlnp | grep 3128"
```

### Tester le proxy depuis une VM cliente (ex. db01)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "curl -s --proxy http://192.168.20.14:3128 \
   https://debian.org | head -1"
```

Resultat attendu : code 200 ou contenu HTML.

### Verifier les logs d'acces Squid

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo tail -20 /var/log/squid/access.log"
```

### Verifier le filtrage des sites bloques

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "curl -sv --proxy http://192.168.20.14:3128 \
   http://blocked-domain.example.com 2>&1 | grep -E 'HTTP|Access Denied'"
```

Resultat attendu : `403 Forbidden` ou `Access Denied`.

### Verifier la resolution DNS via le proxy

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo squidclient -h 192.168.20.14 mgr:dns | head -20"
```

### Tester le cache HTTP

```bash
# Premier acces (MISS)
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "curl -sv --proxy http://192.168.20.14:3128 http://cdn.debian.net/ 2>&1 | grep -i 'X-Cache'"

# Second acces (HIT attendu pour les ressources cacheables)
ssh -J debian@192.168.15.2 debian@192.168.20.12 \
  "curl -sv --proxy http://192.168.20.14:3128 http://cdn.debian.net/ 2>&1 | grep -i 'X-Cache'"
```

## 6. Operations courantes

### Redemarrer Squid (apres modification de config)

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl restart squid && \
   sudo systemctl is-active squid"
```

### Ajouter un site a bloquer

1. Ajouter le domaine dans `squid_denied_sites` dans `group_vars/proxies/vars.yml`.
2. Rejouer le role :
```bash
ansible-playbook -i inventory/hosts.yml site.yml \
  -l proxies \
  --tags proxy,config \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian
```

### Consulter les sites les plus accedes

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo awk '{print \$7}' /var/log/squid/access.log | \
   sort | uniq -c | sort -rn | head -20"
```

### Consulter les IP les plus actives

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo awk '{print \$3}' /var/log/squid/access.log | \
   sort | uniq -c | sort -rn | head -10"
```

### Vider le cache Squid

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo systemctl stop squid && \
   sudo squid -z && \
   sudo systemctl start squid"
```

### Verifier les statistiques Squid

```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo squidclient -h 127.0.0.1 mgr:info | \
   grep -E 'Request|Cache hits|Memory'"
```

### Rotation des logs Squid

Squid integre logrotate via le paquet Debian. Pour forcer une rotation :
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo logrotate -f /etc/logrotate.d/squid"
```

## 7. Troubleshooting

### Incident 1 : Squid ne demarre pas (port 3128 deja utilise)

**Symptome :** `systemctl start squid` echoue avec `bind: address already in use`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo ss -tlnp | grep 3128 && \
   sudo fuser 3128/tcp"
```

**Fix :**
```bash
# Identifier et tuer le processus qui utilise 3128
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo kill -9 \$(sudo fuser 3128/tcp 2>/dev/null | tr -s ' ') && \
   sudo systemctl start squid"
```

### Incident 2 : Requetes refusees pour un reseau qui devrait etre autorise

**Symptome :** Une VM dans `squid_allowed_networks` recoit `403 Forbidden`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo squid -k parse 2>&1 | grep -E 'ERROR|WARNING'"

# Verifier les ACL dans squid.conf
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo grep -A 5 'acl localnet' /etc/squid/squid.conf"
```

**Fix :** Verifier que l'IP de la VM est bien dans un subnet couvert par `squid_allowed_networks`. Si non, ajouter le sous-reseau et rejouer le role. Redemarrer Squid apres la modification.

### Incident 3 : Logs Squid saturent le disque

**Symptome :** `df -h /var/log/` montre 100% d'utilisation. `/var/log/squid/access.log` est tres volumineux.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo du -sh /var/log/squid/ && \
   sudo ls -lh /var/log/squid/"
```

**Fix :**
```bash
# Forcer la rotation logrotate
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo logrotate -f /etc/logrotate.d/squid"

# Si le fichier access.log est ouvert par Squid, utiliser squid -k rotate
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo squid -k rotate"
```

Ajuster la configuration logrotate pour conserver moins de fichiers ou compresser plus agressivement.

### Incident 4 : Le proxy ne resout pas les noms de domaine internes

**Symptome :** `curl --proxy http://192.168.20.14:3128 http://dc01.nova-syndicate.local` retourne `DNS lookup failure`.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo squidclient mgr:dns | head -20 && \
   sudo dig dc01.nova-syndicate.local @192.168.20.10"
```

**Fix :** Verifier que `dns_nameservers 192.168.20.10 1.1.1.1` est bien dans squid.conf. Si proxy-lyon01 pointe vers un autre resolver, corriger et rejouer le role. Verifier aussi que nftables sur proxy-lyon01 autorise les requetes DNS sortantes vers 192.168.20.10.

### Incident 5 : Toutes les connexions sont bloquees par nftables sur proxy-lyon01

**Symptome :** Le port 3128 n'est pas accessible depuis les VM clientes. `nc -zv 192.168.20.14 3128` echoue.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "sudo nft list ruleset | grep -E '3128|accept'"
```

**Fix :** Verifier que `hardening_extra_nft_rules` inclut une regle ouvrant le port 3128 depuis les VLAN autorises dans `group_vars/proxies/vars.yml`. Rejouer le role hardening si la regle est absente.

### Incident 6 : Squid utilise trop de memoire

**Symptome :** La VM proxy-lyon01 a peu de RAM libre. `squid_cache_mem` est trop eleve pour le dimensionnement de la VM.

**Diagnostic :**
```bash
ssh -J debian@192.168.15.2 debian@192.168.20.14 \
  "free -h && \
   sudo squidclient mgr:mem | grep 'Total in use'"
```

**Fix :** Reduire `squid_cache_mem` dans `group_vars/proxies/vars.yml` (ex. passer de 256 MB a 128 MB) et rejouer le role.

## 8. Disaster Recovery

### Contexte DR

Squid est un composant de filtrage et de traçabilite. Sa perte n'interrompt pas les services metier (dans l'etat actuel ou les VMs peuvent sortir directement). En mode T-SQUID (proxy obligatoire), la perte du proxy bloque tout acces Internet des VMs. RTO cible : 30 minutes. RPO : N/A (pas de donnees persistantes, configuration as-code).

### Procedure de restauration

**Etape 1 (urgence si proxy obligatoire est active) : Desactiver temporairement les regles OPNsense forçant le proxy**

Via l'interface OPNsense FW-INT-LYON ou le Terraform OPNsense, desactiver la regle qui bloque le trafic direct. Cela restaure l'acces Internet direct pendant la reconstruction du proxy.

**Etape 2 : Provisionner une nouvelle VM proxy-lyon01 si necessaire**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/
terraform apply -target=proxmox_vm_qemu.proxy_lyon01
```

La nouvelle VM doit recevoir l'IP 192.168.20.14.

**Etape 3 : Deployer le role proxy**
```bash
cd /Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-ansible/

ansible-playbook -i inventory/hosts.yml site.yml \
  -l proxies \
  --tags common,hardening,proxy \
  --private-key ~/.ssh/nova_ansible_ed25519 \
  -u debian --ask-vault-pass
```

**Etape 4 : Valider le proxy**

Reprendre les tests de la section 5.

**Etape 5 : Reactivation du proxy obligatoire (si applicable)**

Reenactiver les regles OPNsense forçant le passage par le proxy.

**RTO :** 30 minutes (provisioning VM + deploiement + validation).
**RPO :** N/A -- configuration as-code, logs non critiques pour le DR.

## 9. Securite et conformite

### NIS2 Article 21

**Art. 21.2.b -- Gestion des risques :**
Le proxy centralise les sorties HTTP/HTTPS, permettant de bloquer les destinations malveillantes connues via `squid_denied_sites`. En mode proxy obligatoire (T-SQUID), il elimine les flux sortants non supervises. La liste de sites bloques doit etre maintenue a jour via les threat feeds.

**Art. 21.2.c -- Gestion des incidents :**
Les logs d'acces Squid (`access.log`) constituent une source d'evidence pour l'investigation d'incidents (exfiltration de donnees, connexions C2, beaconing). Ces logs sont collectes par Wazuh agent sur proxy-lyon01 et centralises sur app01 (192.168.20.13). Une alerte Wazuh sur des volumes anormaux de donnees sortantes ou des connexions vers des domaines suspects doit etre configuree.

**Art. 21.2.e -- Continuite d'activite :**
Dans l'etat actuel (proxy non obligatoire), la perte du proxy n'impacte pas la continuite. En mode T-SQUID, la procedure DR doit garantir le RTO de 30 min ou prevoir un mecanisme de bypass d'urgence.

**Art. 21.2.f -- Audit et traçabilite :**
Les logs Squid enregistrent : timestamp, IP source, URL demandee, code reponse, volume transfere, statut cache. Ces informations constituent un journal des acces web, requis pour la traçabilite des utilisateurs et la detection des comportements anormaux.

### RGPD

Les logs Squid enregistrent les URL accedees par les postes du VLAN USERS, ce qui peut constituer un traitement de donnees personnelles (navigation des employes). Mesures requises :
- Informer les utilisateurs de l'existence du proxy et du logging (mention dans la charte informatique).
- Limiter la retention des logs (recommande : 30 jours pour les logs acces, 90 jours pour les alertes).
- Restreindre l'acces aux logs aux seuls administrateurs autorises.

## 10. References

### Internes au projet

- `roles/proxy/defaults/main.yml` -- variables du role
- `roles/proxy/templates/squid.conf.j2` -- template de configuration
- `group_vars/proxies/vars.yml` -- variables du groupe
- Runbook hardening : `docs/runbooks/runbook-hardening.md`
- Runbook Wazuh : `docs/runbooks/runbook-wazuh.md`
- Tache T-SQUID : deploiement proxy obligatoire (en attente)

### Documentation upstream

- Squid documentation : http://www.squid-cache.org/Doc/
- Squid ACL configuration : https://wiki.squid-cache.org/SquidFaq/SquidAcl
- Squid cache management : http://www.squid-cache.org/Doc/config/cache_dir/
- NIS2 Directive : https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:32022L2555
