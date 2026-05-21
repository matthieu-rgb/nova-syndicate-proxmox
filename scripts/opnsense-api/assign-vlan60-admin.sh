#!/usr/bin/env bash
#
# assign-vlan60-admin.sh  --  T-AWX-DEPLOY / Pre-Phase 0 step A4
#
# Objet : assigner le VLAN 60 (vlan05, tag 60 sur vtnet1) comme interface
#         logique OPT5 "ADMIN" sur FW-INT-LYON, IP 192.168.60.1/29.
#
# IMPORTANT -- pourquoi ce script ne fait PAS tout en API :
#   OPNsense 25.1 N'EXPOSE PAS d'endpoint REST pour l'assignation
#   d'interface ni la config IP. Probe effectue le 2026-05-20 :
#     GET /api/interfaces/overview/setInterface       -> 404
#     GET /api/interfaces/setting                     -> 404
#     GET /api/interfaces/reconfigure                 -> 404
#     GET /api/interfaces/assign_settings/searchItem  -> 404
#     GET /api/interfaces/vlan_settings/reconfigure   -> 200  (VLAN uniquement)
#   => l'assignation OPT5 + IP se fait MANUELLEMENT via Web UI
#      (interfaces_assign.php + config.xml, pas d'API MVC).
#   Cf commentaire fw_int_vlans.tf et provider browningluke 0.16.
#
# Sequence reelle du deploiement VLAN 60 :
#   1. [Terraform] creation du VLAN tag 60 sur vtnet1   -> opnsense_interfaces_vlan.fwint_vlan60_admin
#      (+ aliases net_lyon_admin 192.168.60.0/29, host_awx01 192.168.60.2)
#   2. [Manuel Web UI] assignation OPT5 = vlan05, enable, IP 192.168.60.1/29, name ADMIN  <-- ce script documente + verifie
#   3. [Terraform] regles firewall ADMIN (etape A5)
#
# Acces API/GUI depuis le Mac : tunnel SSH via Proxmox (le Mac ne joint pas .99.1 en direct).
#   ssh -f -N -M -S /tmp/fw-int-tunnel.sock -L 19443:192.168.99.1:443 proxmox-hypervisor
#   API + GUI alors sur https://127.0.0.1:19443
#
set -euo pipefail

TUNNEL_URL="https://127.0.0.1:19443"
SECRETS="${HOME}/Documents/Nova-syndicate-Code/nova-iac-secrets/apikey-fw-int-lyon.txt"
SOCK="/tmp/fw-int-tunnel.sock"

err() { echo "ERROR: $*" >&2; exit 1; }

load_creds() {
  [ -f "$SECRETS" ] || err "secrets introuvables: $SECRETS"
  KEY=$(grep '^key='    "$SECRETS" | cut -d= -f2)
  SECRET=$(grep '^secret=' "$SECRETS" | cut -d= -f2)
  [ -n "$KEY" ] && [ -n "$SECRET" ] || err "key/secret vides"
}

api() { # api <path>
  curl -k -m 12 -s -u "${KEY}:${SECRET}" "${TUNNEL_URL}/api/$1"
}

ensure_tunnel() {
  if curl -k -m 6 -s -o /dev/null -w '%{http_code}' "${TUNNEL_URL}/" | grep -q 200; then
    echo "[ok] tunnel deja actif (${TUNNEL_URL})"
  else
    echo "[..] ouverture tunnel SSH via Proxmox"
    ssh -f -N -M -S "$SOCK" -L 19443:192.168.99.1:443 proxmox-hypervisor
    sleep 1
    curl -k -m 6 -s -o /dev/null -w '%{http_code}' "${TUNNEL_URL}/" | grep -q 200 \
      || err "tunnel KO"
    echo "[ok] tunnel ouvert"
  fi
}

step_verify_vlan() {
  echo "=== 1. VLAN tag 60 present (cree par Terraform) ? ==="
  api "interfaces/vlan_settings/searchItem" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);r=[x for x in d['rows'] if str(x.get('tag'))=='60'];print(r if r else 'ABSENT -- relancer terraform apply (etape A3)')"
}

print_manual_steps() {
  cat <<'STEPS'

=== 2. ETAPE MANUELLE Web UI (pas d'API possible) ===
Ouvrir le GUI via le tunnel : https://127.0.0.1:19443
(si "Potential DNS Rebind attack detected" :
   System > Settings > Administration > cocher "Disable DNS Rebinding Check", Save,
 ou acceder via le hostname configure du firewall.)

a) Interfaces > Assignments
   - "New interface" : choisir  vlan05  (descr "VLAN 60 - Admin", tag 60 sur vtnet1)
   - cliquer "+"  -> devient OPT5
   - renommer la description : ADMIN
   - Save
b) Interfaces > [ADMIN] (opt5)
   - Enable interface : coche
   - IPv4 Configuration Type : Static IPv4
   - IPv4 address : 192.168.60.1 / 29
   - Upstream gateway : None
   - Save
c) cliquer "Apply changes"

STEPS
}

step_verify_assignment() {
  echo "=== 3. VERIFICATION post-assignation ==="
  api "interfaces/overview/interfacesInfo" | python3 -c "
import sys,json
d=json.load(sys.stdin)
ok=False
for r in d['rows']:
    if r.get('device')=='vlan05' or (r.get('description','').upper()=='ADMIN'):
        print('  identifier :', r.get('identifier'))
        print('  device     :', r.get('device'))
        print('  descr      :', r.get('description'))
        print('  enabled    :', r.get('enabled'))
        print('  addr       :', r.get('addr4', r.get('ipv4')))
        ok=True
print('  => OPT5/ADMIN '+('OK' if ok else 'PAS ENCORE ASSIGNE'))
"
}

main() {
  load_creds
  ensure_tunnel
  step_verify_vlan
  print_manual_steps
  step_verify_assignment
  echo
  echo "Si OPT5/ADMIN OK avec 192.168.60.1/29 -> passer a l'etape A5 (regles firewall Terraform)."
}

main "$@"
