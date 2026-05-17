#!/bin/sh
# ============================================================
# Suricata HOME_NET fix + local.rules deploy -- FW-EXT-LYON
# Reference : T-SURICATA-DETECTION-FIX, 2026-05-17
#
# A executer sur FW-EXT-LYON (ou via ssh) une seule fois.
# Idempotent : detecte si deja applique.
#
# Pre-requis :
#  - /usr/local/sbin (existant)
#  - python3 (present par defaut OPNsense)
#  - scripts/opnsense/local.rules et custom.yaml co-localises
# ============================================================

set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

# 1. Etendre HOME_NET dans /conf/config.xml si necessaire
if grep -q "<homenet>185.55.247.170/32" /conf/config.xml; then
  echo "HOME_NET already includes 185.55.247.170/32 -- skipping"
else
  cp /conf/config.xml /conf/config.xml.bak-$(date +%s)
  python3 -c "
with open('/conf/config.xml','r') as f: x = f.read()
old = '<homenet>192.168.0.0/16,10.0.0.0/8,172.16.0.0/12</homenet>'
new = '<homenet>185.55.247.170/32,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12</homenet>'
if old not in x: raise SystemExit('Pattern not found, manual review needed')
with open('/conf/config.xml','w') as f: f.write(x.replace(old, new))
print('OK extended')
"
fi

# 2. Deployer local.rules
cp -v "$HERE/local.rules" /usr/local/etc/suricata/opnsense.rules/local.rules

# 3. Deployer custom.yaml (qui include local.rules)
cp -v "$HERE/custom.yaml" /usr/local/etc/suricata/custom.yaml

# 4. Regenerer la config Suricata (template -> yaml)
configctl template reload OPNsense/IDS

# 5. Restart Suricata pour charger HOME_NET + local.rules
configctl ids restart

echo "--- Verification (apres 30s pour load) ---"
sleep 30
grep HOME_NET /usr/local/etc/suricata/suricata.yaml | head -1
ps aux | grep -v grep | grep suricata | head -1
