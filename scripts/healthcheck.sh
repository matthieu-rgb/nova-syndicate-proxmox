#!/usr/bin/env bash
# healthcheck.sh -- Nova Syndicate full infrastructure check
# T-HEALTHCHECK-INFRA / 2026-05-18
#
# Usage:
#   bash scripts/healthcheck.sh [--verbose]
#
# Exit codes:
#   0 -- all critical checks pass
#   1 -- one or more checks failed
#
# Complementaire a scripts/health-check.sh (qui est CI-ready, set -e).
# Ce script-ci est tolerant (continue meme si une section echoue) et
# affiche un resume color-coded pour ops courantes.

set -u

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0; WARNING=0; FAILED=0

pass()    { printf "${GREEN}[OK]${NC}      %s\n" "$1"; PASSED=$((PASSED+1)); }
warn()    { printf "${YELLOW}[WARN]${NC}    %s\n" "$1"; WARNING=$((WARNING+1)); }
fail()    { printf "${RED}[FAIL]${NC}    %s\n" "$1"; FAILED=$((FAILED+1)); }
info()    { printf "${BLUE}[INFO]${NC}    %s\n" "$1"; }
section() { printf "\n${BLUE}=== %s ===${NC}\n" "$1"; }

PROXMOX="root@100.112.113.2"
SSH_O="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"
START=$(date +%s)

# qm_exec_out -- run a command inside a VM via qm guest exec and return the
# raw out-data string. Robust to PVE 9.x output framing (the out-data value
# contains a literal "\n" trailer which broke grep patterns like '"active"').
# Usage: qm_exec_out <vmid> <command-string>
qm_exec_out() {
  local vmid="$1"; shift
  local raw
  raw=$(ssh $SSH_O "$PROXMOX" "qm guest exec $vmid -- bash -c \"$*\"" 2>/dev/null)
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r '."out-data" // empty' 2>/dev/null | tr -d '\n'
  else
    # Fallback : extract content between "out-data" : " and the closing "
    printf '%s' "$raw" | awk -F'"out-data" : "' 'NF>1{ print $2 }' | sed 's/\\n//g; s/",$//; s/"$//'
  fi
}

printf "==========================================\n"
printf "  Healthcheck Nova Syndicate\n"
printf "  Date : %s\n" "$(date)"
printf "==========================================\n"

# ============ 1. PROXMOX ============
section "1. PROXMOX"

if ssh $SSH_O "$PROXMOX" "uname -n" >/dev/null 2>&1; then
  pass "Proxmox accessible (Tailscale)"
else
  fail "Proxmox unreachable via Tailscale"
fi

VM_COUNT=$(ssh $SSH_O "$PROXMOX" "qm list | awk 'NR>1 && \$3==\"running\"' | wc -l" 2>/dev/null || echo 0)
VM_COUNT=$(echo "$VM_COUNT" | tr -d ' ')
if [ "${VM_COUNT:-0}" -ge 10 ]; then
  pass "VMs running: $VM_COUNT (attendu >= 10)"
else
  warn "VMs running: $VM_COUNT (attendu >= 10)"
fi

# ============ 2. IPSEC INTER-SITES ============
section "2. IPSEC INTER-SITES"

SAS=$(ssh $SSH_O opn-fw-ext-lyon "swanctl --list-sas 2>/dev/null | grep -c 'INSTALLED, TUNNEL'" 2>/dev/null || echo 0)
SAS=$(echo "$SAS" | tr -d ' ')
if [ "${SAS:-0}" = "4" ]; then
  pass "IPsec FW-EXT-LYON: 4 SAs INSTALLED"
else
  fail "IPsec FW-EXT-LYON: $SAS SAs (attendu 4)"
fi

if ssh $SSH_O opn-fw-ext-lyon "[ -x /usr/local/sbin/ipsec-recovery.sh ]" 2>/dev/null; then
  pass "Script auto-recovery present + executable"
else
  warn "Script auto-recovery /usr/local/sbin/ipsec-recovery.sh manquant"
fi

# ============ 3. SURICATA IDS ============
section "3. SURICATA IDS"

for fw in opn-fw-ext-lyon opn-fw-int-lyon opn-fw-ext-mrs; do
  if ssh $SSH_O "$fw" "pgrep suricata >/dev/null 2>&1" 2>/dev/null; then
    pass "Suricata running: $fw"
  else
    warn "Suricata down ou inaccessible: $fw"
  fi
done

ALERTS=$(ssh $SSH_O opn-fw-ext-lyon "grep -c '\"event_type\":\"alert\"' /var/log/suricata/eve.json 2>/dev/null" 2>/dev/null || echo 0)
ALERTS=$(echo "$ALERTS" | tr -d ' ')
if [ "${ALERTS:-0}" -gt 0 ]; then
  pass "Suricata FW-EXT-LYON alerts cumulees: $ALERTS"
else
  warn "Suricata FW-EXT-LYON: 0 alert (jamais sollicite?)"
fi

# ============ 4. ACTIVE DIRECTORY ============
section "4. ACTIVE DIRECTORY (DC01)"

if [ "$(qm_exec_out 103 'systemctl is-active samba-ad-dc 2>/dev/null')" = "active" ]; then
  pass "Samba AD active on DC01"
else
  fail "Samba AD inactive on DC01"
fi

USER_COUNT=$(qm_exec_out 103 'samba-tool user list 2>/dev/null | wc -l')
USER_COUNT=${USER_COUNT:-0}
if [ "$USER_COUNT" -ge 80 ]; then
  pass "AD users: $USER_COUNT"
else
  warn "AD users: $USER_COUNT (attendu >= 80)"
fi

# ============ 5. SERVICES APPLICATIFS (APP01) ============
section "5. SERVICES APP01"

for svc in nginx authelia nova-portail grafana-server prometheus wazuh-manager; do
  STATUS=$(ssh $SSH_O "$PROXMOX" "qm guest exec 106 -- bash -c \"systemctl is-active $svc 2>/dev/null\"" 2>/dev/null \
    | grep -oE 'active|inactive|failed' | head -1)
  if [ "$STATUS" = "active" ]; then
    pass "$svc: active"
  else
    fail "$svc: ${STATUS:-unknown}"
  fi
done

# ============ 6. DATABASE (DB01) ============
section "6. DATABASE (DB01)"

if [ "$(qm_exec_out 105 'systemctl is-active mariadb 2>/dev/null')" = "active" ]; then
  pass "MariaDB DB01 active"
else
  fail "MariaDB DB01 inactive"
fi

# Skip count tarifs : depend de creds, on garde simple
# Voir scripts/test-nova-portail.sh pour les checks fonctionnels.

# ============ 7. WAZUH SIEM ============
section "7. WAZUH SIEM"

AGENTS=$(qm_exec_out 106 'sudo /var/ossec/bin/agent_control -l 2>/dev/null | grep -c Active')
AGENTS=${AGENTS:-0}
# Invariant maj 2026-06-02 T-LDAPS-MIGRATION : mail01 enroll +
# decompte inclut le manager 000 -> 8 agents au total.
if [ "$AGENTS" = "8" ]; then
  pass "Wazuh agents Active: 8"
elif [ "$AGENTS" -gt 0 ]; then
  warn "Wazuh agents Active: $AGENTS (attendu 8)"
else
  fail "Wazuh: 0 agents Active ou inaccessible"
fi

# ============ 8. WEB FRONTENDS ============
section "8. WEB FRONTENDS"

PROBE_INT() {
  local host="$1"; local path="${2:-/}"; local expected="$3"
  local code
  code=$(ssh $SSH_O "$PROXMOX" "curl -k --max-time 5 -s -o /dev/null -w '%{http_code}' --resolve $host:443:192.168.20.13 https://$host$path" 2>/dev/null || echo 000)
  if [ "$code" = "$expected" ]; then
    pass "Interne $host$path: $code"
  else
    fail "Interne $host$path: $code (attendu $expected)"
  fi
}

PROBE_INT www.nova-syndicate.local "/" 200
PROBE_INT portail.nova-syndicate.local "/" 302
PROBE_INT portail.nova-syndicate.local "/health" 200

# Site public (Internet) -- optionnel, peut etre offline si Cloudflare/Box pas configures
if command -v dig >/dev/null && dig +short nova.0xmatthieu.dev | head -1 | grep -qE '^[0-9]'; then
  EXT_CODE=$(curl --max-time 8 -s -o /dev/null -w '%{http_code}' https://nova.0xmatthieu.dev 2>/dev/null || echo 000)
  if [ "$EXT_CODE" = "200" ]; then
    pass "Public nova.0xmatthieu.dev: 200 (via Cloudflare)"
  else
    warn "Public nova.0xmatthieu.dev: $EXT_CODE (Box port-forward / Cloudflare a verifier)"
  fi
else
  info "nova.0xmatthieu.dev non resolu (skip test externe)"
fi

# ============ 9. BACKUP ============
section "9. BACKUP"

if ssh $SSH_O "$PROXMOX" 'qm guest exec 109 -- bash -c "sudo -u borg borg info /srv/borg-repo 2>&1"' 2>/dev/null | grep -q "Repository"; then
  pass "Borg repo accessible"
else
  warn "Borg repo info indisponible (check manuel: ssh backup01)"
fi

# ============ 10. CERTIFICATS ============
section "10. CERTIFICATS"

CERT_END=$(ssh $SSH_O "$PROXMOX" "echo | openssl s_client -servername www.nova-syndicate.local -connect 192.168.20.13:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2" 2>/dev/null)
if [ -n "$CERT_END" ]; then
  pass "Cert wildcard interne expire: $CERT_END"
else
  warn "Cert interne info indisponible"
fi

CERT_PUB=$(ssh $SSH_O "$PROXMOX" "echo | openssl s_client -servername nova.0xmatthieu.dev -connect 192.168.18.51:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2" 2>/dev/null)
if [ -n "$CERT_PUB" ]; then
  pass "Cert origin public expire: $CERT_PUB"
else
  info "Cert origin public non deploye (exposition publique inactive ?)"
fi

# ============ RESUME ============
END=$(date +%s)
DURATION=$((END - START))

printf "\n==========================================\n"
printf "  RESUME\n"
printf "==========================================\n"
printf "  ${GREEN}Passed${NC}:   %d\n" "$PASSED"
printf "  ${YELLOW}Warning${NC}:  %d\n" "$WARNING"
printf "  ${RED}Failed${NC}:   %d\n" "$FAILED"
printf "  Duration: %ds\n" "$DURATION"
printf "==========================================\n"

[ "$FAILED" = 0 ] && exit 0 || exit 1
