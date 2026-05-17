#!/bin/sh
# ============================================================
# Suricata IDS detection test -- FW-EXT-LYON
# Reference : T-SURICATA-DETECTION-FIX, runbook-suricata-fw-ext-lyon.md
#
# Usage : ./suricata-test.sh [target_public_ip]
#   default target : 185.55.247.170
#
# Doit etre execute depuis un poste EXTERNE au reseau Nova
# (4G, VPS, autre site). Sinon le trafic risque de ne pas
# atteindre vtnet0 avec la bonne destination.
#
# Verifie ensuite eve.json sur FW-EXT-LYON pour le nombre
# d'alertes generees.
# ============================================================

TARGET="${1:-185.55.247.170}"
SSH_TARGET="${SSH_TARGET:-opn-fw-ext-lyon}"
EVE=/var/log/suricata/eve.json

echo "=== Suricata detection test from $(hostname) to $TARGET ==="

# Baseline alert count
baseline=$(ssh -o ConnectTimeout=5 "$SSH_TARGET" "wc -l < $EVE" 2>/dev/null | tr -d ' ')
baseline=${baseline:-0}
echo "Baseline eve.json lines : $baseline"

echo
echo "--- Test 1/3 : ICMP echo ---"
ping -c 5 -W 2 "$TARGET" 2>&1 | tail -3

echo
echo "--- Test 2/3 : SYN HTTP/HTTPS ---"
for port in 80 443 8080; do
  echo -n "  port $port : "
  curl --connect-timeout 2 -s -o /dev/null -w "%{http_code}\n" "http://$TARGET:$port" 2>&1 || echo "timeout"
done

echo
echo "--- Test 3/3 : NMAP -sS rapid scan ---"
if command -v nmap >/dev/null 2>&1; then
  if [ "$(id -u)" = "0" ]; then
    nmap -sS -p1-1000 --min-rate 2000 -T4 "$TARGET" 2>&1 | tail -5
  else
    echo "  (skipping, nmap -sS requires root)"
    nmap -sT -p1-100 -T4 "$TARGET" 2>&1 | tail -5
  fi
else
  echo "  (nmap not installed, skipping)"
fi

echo
sleep 5
final=$(ssh -o ConnectTimeout=5 "$SSH_TARGET" "wc -l < $EVE" 2>/dev/null | tr -d ' ')
final=${final:-0}
delta=$((final - baseline))
echo "=== Results ==="
echo "Final eve.json lines : $final (delta +$delta)"

if [ "$delta" -gt 0 ]; then
  echo
  echo "Top signatures triggered :"
  ssh "$SSH_TARGET" "tail -$delta $EVE" 2>/dev/null | python3 -c "
import json, sys
from collections import Counter
c = Counter()
for line in sys.stdin:
    try:
        e = json.loads(line)
        if e.get('event_type') == 'alert':
            c[e['alert']['signature']] += 1
    except: pass
for sig, n in c.most_common(10):
    print(f'  x{n:4d}  {sig}')
"
else
  echo "WARNING : no new alerts. Causes possibles :"
  echo "  - test depuis poste interne (trafic ne passe pas vtnet0)"
  echo "  - HOME_NET sur Suricata exclut $TARGET"
  echo "  - upstream NAT change la destination avant vtnet0"
  echo "  - Suricata stopped (verifier : configctl ids status)"
fi
