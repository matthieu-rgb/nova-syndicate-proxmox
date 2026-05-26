# Skill : Drawio Nova Syndicate

## Mission

Generer des diagrammes draw.io XML production-grade representant l'architecture
Nova Syndicate, sans aucune reference aux artefacts de virtualisation (Proxmox,
VMID, lab, simulator). Les diagrammes doivent etre directement lisibles et
exploitables dans un rapport d'audit.

## Topologie cible (representation logique)

### SITE LYON (gauche)

- WAN-LYON : reseau externe (haut, exterieur)
- DMZ : 172.16.1.0/29
- BASTION : 192.168.15.0/29
- SERVERS : 192.168.20.0/28
- USERS : 192.168.30.0/26
- BACKUP : 192.168.50.0/29
- MGMT : 192.168.99.0/29
- ADMIN-AWX : 192.168.60.0/29

### SITE MARSEILLE (droite)

- WAN-MRS : reseau externe (haut, exterieur)
- MRS-LAN : 192.168.40.0/26

### CLOUD

- Tailscale : mgmt break-glass
- Internet : positionne entre les 2 WAN (WAN-LYON et WAN-MRS)

### ROAD WARRIORS

- Nuage "20 agents mobiles" -> vpn-gw01 (DMZ)

## Charte graphique

| Zone | Couleur fond | Couleur bordure |
|---|---|---|
| WAN (Lyon/MRS) | gris fonce #C0C0C0 | noir #000000 |
| DMZ | orange clair #FFE6CC | orange #D79B00 |
| BASTION | bleu clair #DAE8FC | bleu #6C8EBF |
| SERVERS | vert clair #D5E8D4 | vert #82B366 |
| USERS | gris clair #F5F5F5 | gris #666666 |
| BACKUP | violet #E1D5E7 | violet #9673A6 |
| MGMT | jaune #FFF2CC | jaune #D6B656 |
| ADMIN-AWX | rose #F8CECC | rouge #B85450 |
| MRS-LAN | bleu turquoise #B0E3E6 | turquoise #0E8088 |
| Firewall (forme) | rouge fonce #F08080 | noir #000000 |
| Tailscale cloud | bleu clair gradient | bleu #6C8EBF |
| Tunnels IPsec | pointilles bleus #0066CC | - |
| Tunnels WG | pointilles verts #009933 | - |
| Mgmt links (Tailscale) | gris pointille #999999 | - |

## Format XML draw.io

### Structure de base d'un fichier .drawio

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="app.diagrams.net" modified="2026-05-25T10:00:00.000Z" agent="agent-nova" version="22.0.0">
  <diagram name="Nova Syndicate Architecture" id="nova-archi-v5">
    <mxGraphModel dx="2000" dy="1500" grid="1" gridSize="10" guides="1" tooltips="1"
                  connect="1" arrows="1" fold="1" page="1" pageScale="1"
                  pageWidth="1654" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- VOS CELLULES ICI -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

### Templates de cellules

#### Zone container (swim lane)

```xml
<mxCell id="zone_servers" value="ZONE SERVERS&#xa;192.168.20.0/28"
        style="rounded=1;whiteSpace=wrap;html=1;fillColor=#D5E8D4;strokeColor=#82B366;
               fontSize=14;fontStyle=1;align=center;verticalAlign=top;
               container=1;collapsible=0;"
        vertex="1" parent="1">
  <mxGeometry x="200" y="400" width="400" height="200" as="geometry"/>
</mxCell>
```

#### Serveur / VM individuelle

```xml
<mxCell id="srv_dc01" value="dc01&#xa;Samba AD&#xa;192.168.20.10"
        style="shape=mscae/server;html=1;labelPosition=right;align=left;verticalAlign=middle;
               fontSize=11;"
        vertex="1" parent="zone_servers">
  <mxGeometry x="20" y="40" width="40" height="50" as="geometry"/>
</mxCell>
```

#### Firewall

```xml
<mxCell id="fw_int_lyon" value="FW-INT-LYON&#xa;OPNsense 25.1&#xa;192.168.99.1"
        style="shape=mscae/firewall;fillColor=#F08080;strokeColor=#000000;html=1;
               labelPosition=right;align=left;verticalAlign=middle;fontSize=11;"
        vertex="1" parent="1">
  <mxGeometry x="800" y="500" width="40" height="50" as="geometry"/>
</mxCell>
```

#### Lien reseau (avec label)

```xml
<mxCell id="link_dc01_fwint" value="VLAN 20"
        style="endArrow=classic;html=1;rounded=0;exitX=1;exitY=0.5;entryX=0;entryY=0.5;
               labelBackgroundColor=#FFFFFF;fontSize=10;"
        edge="1" parent="1" source="srv_dc01" target="fw_int_lyon">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

#### Tunnel IPsec (pointille bleu)

```xml
<mxCell id="ipsec_lyon_mrs" value="IPsec site-to-site&#xa;4 tunnels"
        style="endArrow=classic;startArrow=classic;html=1;rounded=0;
               dashed=1;dashPattern=8 4;strokeColor=#0066CC;strokeWidth=2;
               labelBackgroundColor=#FFFFFF;fontSize=10;"
        edge="1" parent="1" source="fw_ext_lyon" target="fw_ext_mrs">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

#### Tunnel WireGuard (pointille vert)

```xml
<mxCell id="wg_remote" value="WireGuard&#xa;Road warriors"
        style="endArrow=classic;html=1;rounded=0;
               dashed=1;dashPattern=4 4;strokeColor=#009933;strokeWidth=2;
               labelBackgroundColor=#FFFFFF;fontSize=10;"
        edge="1" parent="1" source="vpn_gw01" target="cloud_road_warriors">
  <mxGeometry relative="1" as="geometry"/>
</mxCell>
```

#### Cloud generique (Internet, Tailscale, etc.)

```xml
<mxCell id="cloud_tailscale" value="Tailscale&#xa;(break-glass admin)"
        style="ellipse;shape=cloud;whiteSpace=wrap;html=1;fillColor=#DAE8FC;
               strokeColor=#6C8EBF;fontSize=12;"
        vertex="1" parent="1">
  <mxGeometry x="1200" y="100" width="160" height="100" as="geometry"/>
</mxCell>
```

## Layout type A4 paysage

- Largeur : 1654 (A4 paysage 300dpi)
- Hauteur : 1169
- Marges : 50px
- Grid : 10px
- Police : Helvetica 11pt par defaut, 14pt pour zone titles, 10pt pour labels de liens

## Regles d'or

1. ZERO reference aux artefacts de virtualisation (pas de "Proxmox", "VMID", "lab", "simulator")
2. 2 WAN distincts (WAN-LYON et WAN-MRS), pas de WAN-SIM unifie
3. Tailscale = nuage externe + tunnel mgmt pointille gris vers Hyperviseur Nova
4. WireGuard road warriors = nuage ou icone collective "20 agents mobiles" + tunnel
   pointille vers vpn-gw01 (DMZ)
5. Standard keyboard chars uniquement dans le XML (pas de caracteres speciaux
   Unicode dans les labels)
6. Tous les firewall sont rouge fonce (#F08080) pour les distinguer visuellement
7. Zones avec swim lanes (container=1) pour une lecture immediate
8. Labels de liens : VLAN ID + protocole quand pertinent
9. Aucune IP n'apparait isolee - toujours dans le label d'une VM ou d'un firewall

## Topologie reference (etat actuel Nova)

VMs / hosts par zone :

DMZ (172.16.1.0/29) :
- web01 : 172.16.1.2 (nginx public)
- mail01 : 172.16.1.3 (Postfix, Dovecot, DKIM)
- vpn-gw01 : 172.16.1.4 (WireGuard road warriors)

BASTION (192.168.15.0/29) :
- bastion01 : 192.168.15.2 (SSH jump host avec MFA TOTP)

SERVERS (192.168.20.0/28) :
- dc01 : 192.168.20.10 (Samba AD)
- fs01 : 192.168.20.11 (NFS/Samba)
- db01 : 192.168.20.12 (MariaDB)
- app01 : 192.168.20.13 (nginx RP, Authelia, Grafana, Wazuh manager+indexer, Filebeat)

BACKUP (192.168.50.0/29) :
- backup01 : 192.168.50.2 (Borg)

ADMIN AWX (192.168.60.0/29) :
- awx01 : 192.168.60.2 (K3s + AWX Operator)

FIREWALLS :
- FW-EXT-LYON (perimetre Lyon) - entre WAN-LYON et DMZ
- FW-INT-LYON (interne Lyon) - entre DMZ et SERVERS/USERS/etc
- FW-EXT-MRS (perimetre MRS) - entre WAN-MRS et MRS-LAN
- (WAN-SIM existe en lab mais N'APPARAIT PAS dans le diagramme)

TUNNELS :
- IPsec site-to-site : FW-EXT-LYON <-> FW-EXT-MRS (4 tunnels)
- WireGuard : vpn-gw01 -> 20 road warriors (nuage)
- Tailscale : Hyperviseur Nova <-> Mac admin (mgmt break-glass)
