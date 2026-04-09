# Plan d Adressage VLSM - Nova Syndicate

## Liens de transit point a point (/30 = 2 hotes utiles)

| Lien                        | Reseau       | A (.1)         | B (.2)          |
|-----------------------------|--------------|----------------|-----------------|
| RTR-LYON1 -> FW-EXT-LYON1   | 10.0.0.0/30  | RTR-LYON1 fa0/1 | FW-EXT em0      |
| FW-EXT-LYON1 -> FW-INT-LYON1| 10.0.1.0/30  | FW-EXT em2     | FW-INT em0      |
| RTR-MRS1 -> FW-EXT-MRS1     | 10.0.2.0/30  | RTR-MRS1 fa0/1 | FW-EXT-MRS1 em0 |

## VLANs internes Lyon (/29 a /26)

| VLAN | Nom     | Reseau           | Gateway       | Hotes | Equipements                   |
|------|---------|------------------|---------------|-------|-------------------------------|
| -    | DMZ     | 172.16.1.0/29    | 172.16.1.1    | 6     | WEB01 .10, MAIL01 .11         |
| 15   | Bastion | 192.168.15.0/29  | 192.168.15.1  | 6     | BASTION01 .10                 |
| 20   | Servers | 192.168.20.0/28  | 192.168.20.1  | 14    | DC01 .10, FS01 .11, DB01 .12, APP01 .13 |
| 30   | Users   | 192.168.30.0/26  | 192.168.30.1  | 62    | Postes Lyon DHCP .20 -> .62   |
| 40   | VPN     | 192.168.40.0/27  | 192.168.40.1  | 30    | Agents WireGuard .100 -> .119 |
| 50   | Backup  | 192.168.50.0/29  | 192.168.50.1  | 6     | BACKUP01 .10                  |

## Marseille

| Reseau          | Gateway       | Hotes | Usage                             |
|-----------------|---------------|-------|-----------------------------------|
| 192.168.31.0/26 | 192.168.31.1  | 62    | Postes MRS DHCP .20 -> .62        |

## Interfaces OPNsense

### FW-EXT-LYON1

| Interface | Nom GNS3 | Role              | IP               |
|-----------|----------|-------------------|------------------|
| em0       | Ethernet0 | WAN (vers RTR)   | 10.0.0.2/30      |
| em1       | Ethernet1 | DMZ              | 172.16.1.1/29    |
| em2       | Ethernet2 | vers FW-INT      | 10.0.1.1/30      |
| em3       | Ethernet3 | WireGuard agents | 192.168.40.1/27  |

### FW-INT-LYON1

| Interface | Nom GNS3 | Role              | IP               |
|-----------|----------|-------------------|------------------|
| em0       | Ethernet0 | depuis FW-EXT    | 10.0.1.2/30      |
| em1       | Ethernet1 | Trunk VLANs LAN  | -                |

### FW-EXT-MRS1

| Interface | Nom GNS3 | Role              | IP               |
|-----------|----------|-------------------|------------------|
| em0       | Ethernet0 | WAN (vers RTR)   | 10.0.2.2/30      |
| em1       | Ethernet1 | LAN Marseille    | 192.168.31.1/26  |
