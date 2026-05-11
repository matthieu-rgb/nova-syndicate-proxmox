# T-WG-HANDSHAKE-DEBUG -- Investigation WireGuard handshake drop

Date : 2026-05-11
Tunnel : vpn-gw01 172.16.1.4, wg0, UDP 51820
Subnet road-warriors : 10.20.0.0/24

## Symptome

vpn-gw01 reçoit les handshake init (tcpdump In OK).
vpn-gw01 emet des réponses (tcpdump Out 92 bytes).
Peers (Mac 185.55.247.170, VPS 46.62.138.33) ne reçoivent jamais la réponse.
wg show : latest handshake absent, transfer 0 B received.

## Hypothèse principale

Réponse src=172.16.1.4:51820 ne passe pas le NAT retour.
Proxmox DNAT entrant OK mais pas de MASQUERADE POSTROUTING pour DMZ sortant.
Paquet src RFC1918 non transformé en IP publique.

## Chemin réseau

Internet → Box Huawei (port-forward 51820 → 192.168.18.50)
Proxmox iptables DNAT : vmbr0 UDP 51820 → 172.16.1.4
vpn-gw01 répond : src=172.16.1.4:51820 → dst=PEER_ENDPOINT
Chemin retour : vpn-gw01 eth0 → FW-EXT-LYON lan → FW-EXT-LYON wan → WAN-SIM → Proxmox vmbr0 → Internet

## Investigation

### ETAPE 1.1 -- tcpdump eth0 vpn-gw01 vers VPS 46.62.138.33

Résultat : Out confirmé eth0, src=172.16.1.4:51820, dst=46.62.138.33:45469.
Paquet quitte bien vpn-gw01. Problème en aval.

### ETAPE 2.1 -- NAT Proxmox (iptables -t nat -L -n -v)

PREROUTING : DNAT udp 51820 → 172.16.1.4 (pkts=6 confirmé) OK.
POSTROUTING : MASQUERADE pour 192.168.15.0/29, 192.168.20.0/28, 192.168.50.0/29.
MANQUE : 172.16.1.0/29 (DMZ, subnet de vpn-gw01) et 10.0.0.0/29 (WAN-SIM).

### ETAPE 1.3 -- tcpdump Proxmox vmbr0 pendant handshake

```
46.62.138.33.45469 > 192.168.18.50.51820: UDP, length 148  (init VPS, DNAT entrant)
10.0.0.2.44169    > 46.62.138.33.45469: UDP, length 92     (réponse via FW-EXT-LYON, port MASQUERADE'd!)
192.168.18.47.48901 > 46.62.138.33.45469: UDP, length 92   (double-capture bridge)
```

## Root cause identifié

Chemin retour : vpn-gw01 (172.16.1.4) → FW-EXT-LYON (default GW 172.16.1.1) → WAN 10.0.0.2 → vmbr0.
OPNsense FW-EXT-LYON auto-NAT outbound : src=172.16.1.4:51820 → src=10.0.0.2:44169 (port changé).
Réponse n'arrive JAMAIS par Proxmox conntrack (qui avait fait le DNAT entrant).
Conntrack ne peut pas faire le reverse-SNAT. Réponse src=10.0.0.2 ou src=172.16.1.4 non routée par Box Huawei.

Le FORWARD rule Proxmox (-i vmbr3 -o vmbr0 -s 172.16.1.4 -p udp --sport 51820) était correct
mais jamais invoqué : trafic passait par FW-EXT-LYON, pas par Proxmox routing.

## Fix appliqué

### Policy routing sur vpn-gw01 (wg0.conf PostUp/PostDown)

Forcer les paquets WireGuard sortants (UDP sport 51820) à passer par Proxmox (172.16.1.5)
au lieu de FW-EXT-LYON (172.16.1.1), pour que conntrack Proxmox reverse le DNAT.

```
PostUp = ip route add default via 172.16.1.5 table 100 || true
PostUp = iptables -t mangle -A OUTPUT -p udp --sport 51820 -j MARK --set-mark 0x1
PostUp = ip rule add fwmark 0x1 lookup 100 priority 100 || true
PostDown = ip rule del fwmark 0x1 lookup 100 priority 100 || true
PostDown = iptables -t mangle -D OUTPUT -p udp --sport 51820 -j MARK --set-mark 0x1
PostDown = ip route del default via 172.16.1.5 table 100 || true
```

### Résultat après fix

tcpdump vmbr0 :
```
46.62.138.33.45469 > 192.168.18.50.51820: UDP, length 192   (init)
192.168.18.50.51820 > 46.62.138.33.45469: UDP, length 32    (réponse, src correct!)
```

Conntrack Proxmox reverse-SNAT automatique : src=172.16.1.4:51820 → src=192.168.18.50:51820.
Box Huawei reçoit de 192.168.18.50:51820, SNAT vers public IP:51820, VPS reçoit réponse OK.

wg show vpn-gw01 après fix :
- VPS (fPVzZDtv...): latest handshake 8s, transfer OK
- Mac (XTG8TL36...): latest handshake 9s, transfer OK

## Décision finale

Root cause : asymétrie NAT. Le DNAT Proxmox était effectué sur vmbr0 mais la réponse passait
par FW-EXT-LYON (WAN différent) → conntrack ne voyait pas le retour.
Fix : policy routing ciblé (mangle mark + ip rule + table 100) sur vpn-gw01. Aucune modification
Proxmox, OPNsense, ou Box Huawei nécessaire.
Persiste via wg0.conf PostUp/PostDown.
