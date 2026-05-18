#!/bin/bash
# Test detection multi-capteurs Suricata
# T-SURICATA-MULTI-CAPTEURS - 2026-05-18
# Cf. ADR-0025-suricata-defense-in-depth.md

set -u

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
pass() { printf "${GREEN}[OK]${NC}   %s\n" "$1"; PASSED=$((PASSED+1)); }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; WARNINGS=$((WARNINGS+1)); }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; FAILED=$((FAILED+1)); }
PASSED=0; WARNINGS=0; FAILED=0

SECRETS="${SECRETS:-$HOME/Documents/Nova-syndicate-Code/nova-iac-secrets}"

check_ssh() {
  local host="$1"
  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" "pgrep suricata" >/dev/null 2>&1; then
    pass "$host Suricata running"
    local rss=$(ssh "$host" "ps aux | grep suricata | grep -v grep | head -1 | awk '{print \$6}'")
    [ -n "$rss" ] && printf "       RAM: ${rss}KB\n"
    local sz=$(ssh "$host" "stat -f%z /var/log/suricata/eve.json 2>/dev/null || echo 0")
    printf "       eve.json: ${sz}B\n"
    local alerts=$(ssh "$host" "grep -c '\"event_type\":\"alert\"' /var/log/suricata/eve.json 2>/dev/null || echo 0")
    printf "       Alerts cumulees: ${alerts}\n"
  else
    fail "$host Suricata down ou SSH inaccessible"
  fi
}

check_api() {
  local label="$1"; local ip="$2"; local keyfile="$3"
  if [ ! -f "$keyfile" ]; then
    warn "$label: keyfile manquant ($keyfile)"
    return
  fi
  local key=$(grep '^key=' "$keyfile" | cut -d= -f2)
  local secret=$(grep '^secret=' "$keyfile" | cut -d= -f2)
  local proxmox=${PROXMOX:-root@100.112.113.2}
  local status=$(ssh "$proxmox" "curl -k -s -m 5 -u '$key:$secret' https://$ip/api/ids/service/status" 2>/dev/null)
  if echo "$status" | grep -q running; then
    pass "$label Suricata running (via API)"
    local mem=$(ssh "$proxmox" "curl -k -s -m 5 -u '$key:$secret' https://$ip/api/diagnostics/system/system_resources" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['memory']['used_frmt'])" 2>/dev/null)
    [ -n "$mem" ] && printf "       RAM used: ${mem}MB\n"
  else
    fail "$label Suricata KO via API ($status)"
  fi
}

echo "=== Suricata multi-capteurs status ==="
check_ssh opn-fw-ext-lyon
check_api "opn-fw-int-lyon" "192.168.99.1" "$SECRETS/apikey-fw-int-lyon.txt"
check_ssh opn-fw-ext-mrs

echo
echo "=== Resume ==="
printf "  ${GREEN}Passed${NC}:   %d\n" "$PASSED"
printf "  ${YELLOW}Warning${NC}:  %d\n" "$WARNINGS"
printf "  ${RED}Failed${NC}:   %d\n" "$FAILED"

[ "$FAILED" = "0" ] && exit 0 || exit 1
