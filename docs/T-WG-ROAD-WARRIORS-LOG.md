# T-WG-ROAD-WARRIORS -- Journal de bord

Objectif : Concentrateur WireGuard road-warriors sur vpn-gw01 (172.16.1.4/29, DMZ)

Subnet road-warriors : 10.20.0.0/24
VMID : 110
Contraintes absolues confirmees :
  - Aucun commit Claude/Anthropic
  - Aucune modif VMs hors scope
  - Tunnel WG backup 10.30.0.0/24 preserve
  - Aucun reboot Proxmox sans validation
  - Stop + log si erreur/doute

Invariants :
  - 4 IPsec INSTALLED
  - 7 Wazuh agents Active
  - WG backup 10.30.0.0/24 UP
  - 11/11 Ansible ping (apres ajout vpn-gw01)
  - terraform plan OPNsense = No changes (hors road-warriors)

---

## 2026-05-11 -- GATE 1

### Etape 1.1 -- Clone template Proxmox (qm clone 9000 110 --name vpn-gw01)
Timestamp : 2026-05-11 ~10h00
Action : qm clone 9000 110 --name vpn-gw01 --full
Resultat : DONE
Fichiers modifies : -

### Etape 1.2-1.4 -- Config + boot + ping
Timestamp : 2026-05-11 ~10h10
Action : qm set 110 (cores/mem/net0/ipconfig0/ciuser/sshkeys), qm start 110, ping
Resultat : DONE. Ping 4/4, rtt ~0.06ms

### Etape 1.5-1.7 -- Ansible inventory + ping
Timestamp : 2026-05-11 ~10h15
Action : host_vars/vpn-gw01.yml, inventory/hosts.yml (vpn_gateways group), ansible ping
Resultat : DONE. pong via ProxyJump
Fichiers modifies : host_vars/vpn-gw01.yml (NEW), inventory/hosts.yml

### Etape 1.8 -- Dry-run hardening
Timestamp : 2026-05-11 ~10h20
Action : --check --diff (playbooks/deploy_vpn_gw.yml NEW)
Resultat : PARTIAL. Faux positif check-mode SSH key (attendu). Erreur ansible.builtin.timezone
  -> Fix : remplacer par timedatectl command dans ntp.yml
  -> Fix ansible.cfg : roles_path = roles

### Etape 1.9 -- Apply hardening reel
Timestamp : 2026-05-11 ~10h40 (apres fix DNS Tailscale par Matthieu)
Action : ansible-playbook deploy_vpn_gw.yml --limit vpn-gw01
Resultat : DONE. ok=49 changed=21 failed=0
  Problemes rencontres :
  - apt bloque 38min (DNS Tailscale, resolu par Matthieu via console Proxmox)
  - ansible.builtin.timezone n'existe pas -> fix timedatectl
  - ProxyJump -> ProxyCommand (Ansible mux compat)
  - nftables SSH bloque : FW-EXT-LYON masquerade source 10.0.1.2
    -> fix : 10.0.0.0/8 ajoute a hardening_allowed_ssh_nets
  - Route retour mgmt : 192.168.0.0/16 via 172.16.1.5 (Proxmox vmbr3)
    -> ajoutee a chaud, NON PERSISTEE (dette T-WG-PERSIST-ROUTE)
Fichiers modifies : host_vars/vpn-gw01.yml, inventory/hosts.yml, playbooks/deploy_vpn_gw.yml
  ansible.cfg, roles/common/tasks/ntp.yml

Commit GATE 1 : 8c71b54, 3b06f09

---

## 2026-05-11 -- GATE 2

### Etape 2.1 -- Install WireGuard + dnsmasq + qrencode
Timestamp : 2026-05-11 ~11h15
Action : apt install wireguard wireguard-tools dnsmasq qrencode
Resultat : DONE

### Etape 2.2 -- ip_forward
Timestamp : 2026-05-11 ~11h20
Action : /etc/sysctl.d/99-wireguard.conf, sysctl -p
Resultat : DONE. net.ipv4.ip_forward = 1

### Etape 2.3 -- Cles serveur
Timestamp : 2026-05-11 ~11h20
Action : wg genkey | tee server-private.key | wg pubkey | tee server-public.key
Resultat : DONE.
  Server pubkey : zT9LykWNnobMSYxHV5dSavQpzyLMJ3GUBExCacniszI=

### Etape 2.4-2.5 -- wg0.conf + dnsmasq
Timestamp : 2026-05-11 ~11h22
Action : /etc/wireguard/wg0.conf, /etc/dnsmasq.d/road-warriors.conf
Resultat : DONE. chmod 600 OK.
  PostUp : ip_forward + routes 192.168.20.0/24 via FW-EXT-LYON + 192.168.0.0/16 via Proxmox

### Etape 2.6-2.7 -- Demarrage services + verification
Timestamp : 2026-05-11 ~11h23
Action : systemctl enable --now wg-quick@wg0, systemctl restart dnsmasq
Resultat : DONE
  wg show : interface wg0 UP, port 51820, pubkey OK
  dnsmasq : active (running), :53 sur 10.20.0.1
  ss : UDP 0.0.0.0:51820 LISTEN, TCP/UDP 10.20.0.1:53 LISTEN

GATE 2 COMPLETE. Pret pour GATE 3 (DNAT Proxmox).

---

## 2026-05-11 -- GATE 3

### Etape 3.1 -- iptables DNAT + FORWARD
Timestamp : 2026-05-11 ~11h30
Action :
  iptables -t nat -A PREROUTING -i vmbr0 -p udp --dport 51820 -j DNAT --to-destination 172.16.1.4:51820
  iptables -A FORWARD -i vmbr0 -o vmbr3 -d 172.16.1.4 -p udp --dport 51820 -j ACCEPT
  iptables -A FORWARD -i vmbr3 -o vmbr0 -s 172.16.1.4 -p udp --sport 51820 -j ACCEPT
Resultat : DONE. Regles num 1/2/3 en place.

### Etape 3.2 -- Persistance iptables-persistent
Timestamp : 2026-05-11 ~11h31
Action : apt install iptables-persistent + netfilter-persistent save
Resultat : DONE. /etc/iptables/rules.v4 sauvegarde.

### Etape 3.3-3.4 -- Test VPS + tcpdump vpn-gw01
Timestamp : 2026-05-11 ~11h32
Action : echo TEST | nc -u nova-vpn.0xmatthieu.dev 51820 depuis VPS
         tcpdump -i eth0 udp port 51820 sur vpn-gw01
Resultat : DONE. Paquet vu : 46.62.138.33:44478 → 172.16.1.4:51820 (1 paquet capturé)
  Invariant : tunnel backup BACKUP01 UP (handshake 4s, endpoint VPS 46.62.138.33 non affecte)

GATE 3 COMPLETE. Pret pour GATE 4 (ACLs OPNsense via Terraform).

---

## 2026-05-11 -- GATE 4

### Etape 4.1-4.3 -- Analyse + creation fichier Terraform
Timestamp : 2026-05-11 ~11h50
Action : lecture routes.tf, fw_int.tf, fw_ext.tf, aliases.tf.
  Pattern confirme. Gateway VPN_GW01 creee via API (provider v0.16 ne supporte pas).
  Nouveau fichier : terraform/environments/opnsense/fw-int-lyon-road-warriors.tf
Fichiers crees : fw-int-lyon-road-warriors.tf (226 lignes)

### Etape 4.4 -- terraform plan (CHECKPOINT 4A)
Timestamp : 2026-05-11 ~12h00
Action : terraform plan
Resultat : 15 to add, 0 to change, 0 to destroy
  Route FW-EXT-LYON : 10.20.0.0/24 via VPN_GW01 (172.16.1.4)
  7 rules FW-EXT-LYON lan (web01, mail01, servers transit)
  5 aliases FW-INT-LYON (net_road_warriors, host_fs01, host_db01, ports_*)
  3 rules FW-INT-LYON wan seq=1 (fs01, db01, dc01:53)

Pre-apply check routing retour : FW-INT-LYON WAN_GW = 10.0.1.1 (FW-EXT, defaultgw=true).
Aucune route statique sur FW-INT. Default suffit : fs01→FW-INT→FW-EXT→VPN_GW01→vpn-gw01.

### Etape 4.5 -- terraform apply (GATE 4B)
Timestamp : 2026-05-11 ~12h10
Action : terraform apply -auto-approve
Resultat : DONE. 15 resources added (2 passes : 12 + 3), 0 changed, 0 destroyed.

Post-apply :
  terraform plan : "No changes" OK
  ansible all ping : 11/11 SUCCESS (dont vpn-gw01)
  Route FW-EXT-LYON : 10.20.0.0/24 via VPN_GW01 - 172.16.1.4 CONFIRME via API
  WG backup : handshake 58s, INTACT

Commit GATE 4 : dfdceeb

GATE 4 COMPLETE. Pret pour GATE 5 (peer Mac + test end-to-end 4G).
