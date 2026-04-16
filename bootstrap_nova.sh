#!/bin/bash
# =============================================================================
# Nova Syndicate -- Script de bootstrap complet
# A executer depuis BASTION1 apres chaque reboot du lab
# Usage : bash bootstrap_nova.sh
# =============================================================================

set -e

ANSIBLE_DIR="$HOME/nova-syndicate-ansible"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }
step() { echo -e "\n${YELLOW}==== $1 ====${NC}"; }

# =============================================================================
# ETAPE 1 -- Configurer BASTION1 lui-meme
# =============================================================================
step "1/6 Configuration reseau BASTION1"

# Verifier si l'IP est deja configuree
if ip addr show ens4 | grep -q "192.168.15.2"; then
    ok "BASTION1 deja configure (192.168.15.2)"
else
    sudo ip link set ens4 up
    sudo ip addr add 192.168.15.2/29 dev ens4
    sudo ip route add default via 192.168.15.1 2>/dev/null || true
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null
    ok "BASTION1 configure"
fi

# Corriger sshd si necessaire
if sudo grep -q "AuthenticationMethods publickey,keyboard-interactive" /etc/ssh/sshd_config 2>/dev/null; then
    sudo sed -i 's/AuthenticationMethods publickey,keyboard-interactive/AuthenticationMethods publickey/' /etc/ssh/sshd_config
    sudo systemctl restart sshd
    ok "sshd corrige (MFA desactive pour Ansible)"
fi

# =============================================================================
# ETAPE 2 -- Configurer les VMs via Ansible
# =============================================================================
step "2/6 Bootstrap VMs via Ansible"

cd "$ANSIBLE_DIR"

# Playbook de bootstrap reseau
cat > /tmp/bootstrap_network.yml << 'EOF'
---
- name: Bootstrap reseau sur toutes les VMs
  hosts: all
  gather_facts: false
  become: true
  tasks:
    - name: Flush nftables
      command: nft flush ruleset
      ignore_errors: true

    - name: Configurer sshd AllowUsers
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^AllowUsers'
        line: 'AllowUsers ansible debian'
      notify: restart sshd

    - name: Corriger AuthenticationMethods
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^AuthenticationMethods'
        line: 'AuthenticationMethods publickey'
      notify: restart sshd

  handlers:
    - name: restart sshd
      service:
        name: sshd
        state: restarted

- name: Configurer IPs statiques
  hosts: domain_controllers
  gather_facts: false
  become: true
  tasks:
    - name: Configurer IP DC1
      shell: |
        ip link set ens4 up
        ip addr add 192.168.20.10/28 dev ens4 2>/dev/null || true
        ip route del default 2>/dev/null || true
        ip route add default via 192.168.20.1
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        ip route add 192.168.40.0/26 via 192.168.20.1 2>/dev/null || true
        ip route add 10.10.0.0/24 via 192.168.20.1 2>/dev/null || true
      ignore_errors: true

- name: Configurer FS1
  hosts: fileservers
  gather_facts: false
  become: true
  tasks:
    - name: Configurer IP FS1
      shell: |
        ip link set ens4 up
        ip addr add 192.168.20.11/28 dev ens4 2>/dev/null || true
        ip route del default 2>/dev/null || true
        ip route add default via 192.168.20.1
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
      ignore_errors: true

- name: Configurer DB1
  hosts: databases
  gather_facts: false
  become: true
  tasks:
    - name: Configurer IP DB1
      shell: |
        ip link set ens4 up
        ip addr add 192.168.20.12/28 dev ens4 2>/dev/null || true
        ip route del default 2>/dev/null || true
        ip route add default via 192.168.20.1
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
      ignore_errors: true

- name: Configurer APP1
  hosts: app_servers
  gather_facts: false
  become: true
  tasks:
    - name: Configurer IP APP1
      shell: |
        ip link set ens4 up
        ip addr add 192.168.20.13/28 dev ens4 2>/dev/null || true
        ip route del default 2>/dev/null || true
        ip route add default via 192.168.20.1
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
      ignore_errors: true

- name: Configurer BACKUP1
  hosts: backups
  gather_facts: false
  become: true
  tasks:
    - name: Configurer IP BACKUP1
      shell: |
        ip link set ens4 up
        ip addr add 192.168.50.2/29 dev ens4 2>/dev/null || true
        ip route del default 2>/dev/null || true
        ip route add default via 192.168.50.1
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
      ignore_errors: true
EOF

ansible-playbook /tmp/bootstrap_network.yml --become -b || warn "Certaines VMs non accessibles -- normal si FW-INT pas encore configure"

# =============================================================================
# ETAPE 3 -- Verifier la connectivite
# =============================================================================
step "3/6 Test connectivite Ansible"

ansible all -m ping 2>/dev/null && ok "Toutes les VMs repondent" || warn "Certaines VMs ne repondent pas"

# =============================================================================
# ETAPE 4 -- Samba AD
# =============================================================================
step "4/6 Demarrage services critiques"

ansible dc01 -m shell -a "systemctl start samba-ad-dc 2>/dev/null || true" --become 2>/dev/null && ok "Samba AD demarre" || warn "Samba AD non demarre"

# =============================================================================
# ETAPE 5 -- Afficher les commandes OPNsense
# =============================================================================
step "5/6 Commandes a copier-coller sur OPNsense"

cat << 'OPNSENSE'
=============================================================================
FW-EXT-LYON1 (option 8 shell) -- copier tout d'un coup :
=============================================================================
ifconfig vtnet0 inet 10.0.0.2/30 && route add default 10.0.0.1 && ifconfig vtnet3 inet 10.20.0.1/24 && printf 'no nat on vtnet2 from 10.10.0.0/24 to 192.168.20.0/28\nnat on vtnet0 inet from 10.20.0.0/24 to any -> (vtnet0)\nnat on vtnet0 inet from 10.0.1.0/24 to any -> (vtnet0)\nnat on vtnet0 inet from 192.168.0.0/16 to any -> (vtnet0)\npass all\n' > /tmp/nat_ext.rules && pfctl -e && pfctl -f /tmp/nat_ext.rules && route add -net 192.168.20.0/28 10.0.1.2 && route add -net 192.168.15.0/29 10.0.1.2 && service strongswan onestart && swanctl --load-all

=============================================================================
FW-INT-LYON1 (option 8 shell) -- copier ligne par ligne :
=============================================================================
ifconfig vtnet0 inet 10.0.1.2/24 && route add default 10.0.1.1
ifconfig vlan01 inet 192.168.15.1/29
ifconfig vlan02 inet 192.168.20.1/28
ifconfig vlan03 inet 192.168.30.1/26
ifconfig vlan04 inet 192.168.50.1/29

Puis creer nat5.rules :
printf 'no nat on vtnet0 from 10.10.0.0/24 to 192.168.20.0/28\nno nat on vtnet0 from 192.168.15.0/29 to 192.168.20.0/28\nno nat on vtnet0 from 192.168.20.0/28 to 192.168.40.0/26\nnat on vtnet0 inet from 192.168.15.0/29 to any -> (vtnet0)\nnat on vtnet0 inet from 192.168.20.0/28 to any -> (vtnet0)\npass in on vlan01 all\npass in on vlan02 all\npass in on vtnet0 all\npass out on vlan02 all\npass out on vtnet0 all\n' > /tmp/nat5.rules && pfctl -e && pfctl -f /tmp/nat5.rules

=============================================================================
FW-EXT-MRS1 (option 8 shell) :
=============================================================================
ifconfig vtnet0 inet 10.1.0.2/30 && route add default 10.1.0.1 && ifconfig vtnet1 inet 192.168.40.1/26 && pfctl -d && service strongswan onestart && swanctl --load-all

=============================================================================
Initier le tunnel IPsec depuis FW-EXT-LYON1 :
=============================================================================
swanctl --initiate --child child-lyon

OPNSENSE

# =============================================================================
# ETAPE 6 -- Resume final
# =============================================================================
step "6/6 Resume"

echo ""
echo "Connectivite Ansible :"
ansible all -m ping 2>/dev/null | grep -E "SUCCESS|UNREACHABLE|FAILED" | while read line; do
    if echo "$line" | grep -q "SUCCESS"; then
        ok "$line"
    else
        err "$line"
    fi
done

echo ""
echo "Prochaines etapes manuelles :"
echo "  1. Copier-coller les commandes OPNsense ci-dessus"
echo "  2. Initier le tunnel IPsec : swanctl --initiate --child child-lyon"
echo "  3. Configurer WireGuard si besoin : wg show sur FW-EXT-LYON1"
echo ""
ok "Bootstrap termine !"
