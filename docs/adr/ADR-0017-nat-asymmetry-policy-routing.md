# ADR-0017 : Resolution de l'asymetrie NAT par policy-based routing

## Status
Accepted

## Date
2026-05-11

## Contexte

Apres le deploiement de vpn-gw01 (ADR-0016), les clients WireGuard (Mac, VPS) envoyent des paquets d'initiation de handshake qui arrivent correctement sur vpn-gw01 (confirme par tcpdump). Cependant le handshake n'aboutit pas : le client ne recoit jamais la reponse.

**Anatomie du flux entrant (fonctionne) :**

```
Client Internet (port src ephemere)
    -> Box Huawei : UDP dest 51820
    -> Proxmox DNAT (iptables -t nat -A PREROUTING) : -> 172.16.1.4:51820
    -> vmbr3 -> vpn-gw01 ens18
    -> wg0 traite le handshake init
```

**Anatomie du flux sortant (problematique) :**

```
vpn-gw01 wg0 genere la reponse
    -> src 172.16.1.4:51820, dest client_ip:ephemere
    -> route par defaut de vpn-gw01 : via 172.16.1.1 (FW-EXT-LYON)
    -> FW-EXT-LYON (OPNsense) applique son auto-NAT sortant
    -> OPNsense modifie le port source : 51820 -> 44169 (port aleatoire)
    -> Proxmox recoit le paquet depuis FW-EXT-LYON avec sport 44169
    -> Proxmox conntrack cherche une entree NAT pour src=44169 : INTROUVABLE
    -> Le DNAT inverse ne peut pas etre effectue
    -> La reponse WireGuard n'atteint jamais le client
```

Le paquet de reponse passe par un chemin different de celui du paquet entrant, cassant le suivi de connexion (conntrack) de Proxmox qui avait etabli l'entree DNAT sur le port 51820.

**Preuve experimentale (tcpdump) :**

Avant fix :
```
# Sur vpn-gw01 : paquets arrivent ET repartent
tcpdump -i ens18 udp port 51820
# 14:05:12 172.16.1.5 > 172.16.1.4: UDP, length 148 (init)
# 14:05:12 172.16.1.4 > 172.16.1.5: UDP, length 92  (reponse, vers Proxmox)

# Sur le VPS client : aucun paquet recus en retour
sudo wg show wg1 | grep transfer
# transfer: 0 B received, 1.23 KiB sent
```

Apres fix :
```
sudo wg show wg1 | grep handshake
# latest handshake: 3 seconds ago
sudo wg show wg1 | grep transfer
# transfer: 12.45 KiB received, 1.23 KiB sent
```

## Decision

Mise en place d'un **policy-based routing** sur vpn-gw01, ciblant uniquement les paquets de reponse WireGuard (UDP sport 51820), les reroutant directement via Proxmox (172.16.1.5) afin que le flux de retour traverse le meme chemin que le flux entrant.

**Mecanisme (3 composants) :**

1. **Marquage des paquets** (iptables mangle) :
```bash
iptables -t mangle -A OUTPUT -p udp --sport 51820 -j MARK --set-mark 0x1
```
Seules les reponses WG (sport=51820) sont marquees. Le trafic metier des road-warriors (10.20.0.X vers fs01, db01) n'est pas marque -- il continue de passer par FW-EXT-LYON avec application des ACLs.

2. **Regle de routage** (ip rule) :
```bash
ip rule add fwmark 0x1 lookup 100
```
Les paquets marques consultent la table de routage 100 au lieu de la table principale.

3. **Table de routage dediee** (ip route) :
```bash
echo "100 wg-reply" >> /etc/iproute2/rt_tables
ip route add default via 172.16.1.5 table 100
```
Les paquets marques sortent directement via Proxmox (172.16.1.5), contournant FW-EXT-LYON.

**Pourquoi ce chemin resout le probleme :**

```
vpn-gw01 -> [fwmark 0x1] -> table 100 -> via 172.16.1.5 (Proxmox)
                                              |
                        Proxmox conntrack voit le flux de retour
                        avec sport=51820 (non modifie par OPNsense)
                        -> DNAT inverse s'applique correctement
                        -> Client recoit la reponse
```

**Persistance** : les 3 commandes sont integrees dans le script `/usr/local/sbin/wg-policy-routing.sh` appele via les directives `PostUp`/`PostDown` de wg0.conf. Le script est deploye et gere par le role Ansible `vpn_gateway` (tasks/policy_routing.yml). Idempotence garantie : les commandes `ip rule add` et `ip route add` utilisent `2>/dev/null || true` pour ne pas echouer si deja presentes.

**Separation des flux** :

| Type de trafic | Chemin |
|---|---|
| WG handshake/keepalive (sport 51820) | -> Proxmox 172.16.1.5 -> Internet |
| Trafic road-warrior (10.20.0.X -> SERVERS) | -> FW-EXT-LYON 172.16.1.1 -> FW-INT-LYON -> SERVERS |
| DNS road-warrior (10.20.0.X -> 10.20.0.1:53) | -> dnsmasq local -> DC01 192.168.20.10 |

Les ACLs FW-INT-LYON s'appliquent donc toujours au trafic metier des road-warriors. Le policy routing ne concerne que les paquets de controle WireGuard.

## Alternatives considerees

### MASQUERADE complet sur FW-EXT-LYON (modifier auto-NAT OPNsense)

**Idee** : desactiver l'auto-NAT OPNsense pour le port 51820 ou ajouter une regle de non-MASQUERADE pour ce port.

**Contre** : la configuration OPNsense est geree par Terraform (provider browningluke). Modifier le comportement NAT pour un cas specifique necessite des regles outbound NAT explicites dont la semantique browningluke est complexe. Risque de casser d'autres flux MASQUERADE. Couplage fort entre la configuration firewall Terraform et le concentrateur WireGuard. Rejete.

### SNAT explicite sur Proxmox (src -> 172.16.1.5)

**Idee** : ajouter une regle iptables POSTROUTING sur Proxmox pour SNAT les reponses WG avec l'IP Proxmox comme source.

**Contre** : masque l'IP reelle de vpn-gw01 dans le flux de retour. Couplage fort entre la configuration Proxmox et le concentrateur -- chaque modification du concentrateur impliquerait une modification du host Proxmox. La configuration Proxmox n'est pas dans le perimetre Ansible actuel (hors-role). Rejete.

### Route statique sur vpn-gw01 (via Proxmox pour toutes les destinations)

**Idee** : remplacer la route par defaut de vpn-gw01 pour pointer vers Proxmox au lieu de FW-EXT-LYON.

**Contre** : le trafic metier des road-warriors (10.20.0.X -> 192.168.20.X) doit passer par FW-EXT-LYON pour que les ACLs FW-INT-LYON s'appliquent. Une route par defaut via Proxmox court-circuiterait tous les firewalls pour le trafic metier. Violation de la defense-in-depth. Rejete.

### Modification de l'adresse d'ecoute WireGuard

**Idee** : utiliser un port autre que 51820 pour eviter les conflits de NAT.

**Contre** : ne resout pas le probleme fondamental : OPNsense applique son auto-NAT sur tous les ports sortants, pas seulement 51820. Le port aleatoire en sortie est le comportement NAT par defaut d'OPNsense (port randomization). Changer le port deplace le probleme sans le resoudre. Rejete.

## Consequences

**Positives** :

- Solution chirurgicale : seuls les paquets UDP sport=51820 empruntent le chemin alternatif. Le trafic metier, DNS, et tous les autres protocoles sont inchanges.
- Pas de modification de Terraform, OPNsense, ou Proxmox. La correction est entierement dans le role Ansible `vpn_gateway`.
- Persistance garantie via PostUp/PostDown de wg-quick. Si WireGuard redemmarre, les regles sont re-appliquees automatiquement.
- Pattern reutilisable : toute future implementation de concentrateur VPN dans une DMZ avec DNAT Proxmox devra appliquer le meme pattern.

**Negatives et risques** :

- **Monitoring requis** : les regles `ip rule` et la table 100 ne sont pas persistees via `/etc/network/interfaces` ou systemd-networkd. Elles sont reappliquees uniquement quand wg-quick demarre/redemmarre. Un reboot sans demarrage automatique de wg-quick ferait echouer les handshakes WG.
  - Mitigation : `systemctl enable wg-quick@wg0` est dans le role (tasks/wireguard.yml). Le demarrage automatique est garanti.
- **Audit** : les connexions WireGuard de retour ne passent pas par FW-EXT-LYON (OPNsense). Les logs de connexion WG sont uniquement dans `journalctl -u wg-quick@wg0` et les logs nftables de Proxmox.
- **IPSEC compatibilite** : les 4 tunnels IPsec existants ne sont pas affectes (ils utilisent UDP 500/4500, pas 51820). Verifie par observation post-fix : 4 SA INSTALLED, 7 Wazuh actifs, WG handshake OK.

**Monitoring recommande** :

```bash
# Verifier que les regles sont en place apres reboot
ip rule list | grep fwmark
ip route show table 100
iptables -t mangle -L OUTPUT | grep MARK
```

## Validation experimentale

Tests executes post-fix (2026-05-11) :

| Test | Avant fix | Apres fix |
|---|---|---|
| Handshake VPS Hetzner | Timeout infini | < 10s |
| Transfer VPS | 0 B received | Bidirectionnel OK |
| Handshake Mac | Timeout infini | < 5s |
| IPsec 4 SAs | INSTALLED | INSTALLED (inchange) |
| Wazuh 7 agents | Active | Active (inchange) |
| Playbook idempotence | N/A | changed=0 au 2e run |

## References

- `man ip-rule(8)` : documentation policy routing Linux
- `man ip-route(8)` : table de routage et metriques
- RFC 2827 : Network Ingress Filtering (contexte de l'asymetrie NAT)
- WireGuard mailing list discussion "WireGuard behind NAT" : https://lists.zx2c4.com/mailman/listinfo/wireguard
- Script de fix : `ansible/roles/vpn_gateway/templates/wg-policy-routing.sh.j2`
- Config wg0.conf : `ansible/roles/vpn_gateway/templates/wg0.conf.j2`
- Debug log complet : `docs/T-WG-HANDSHAKE-DEBUG.md` (commit 66cbc0f)
- ADR-0016 : Architecture concentrateur VPN (contexte du deploiement)
