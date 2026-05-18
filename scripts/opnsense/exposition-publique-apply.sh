#!/bin/sh
# Apply pf rules + NAT pour exposition publique nova.0xmatthieu.dev
# T-NOVA-EXPOSITION-PUBLIQUE - 2026-05-18
# Cf. docs/adr/ADR-0024-exposition-publique-cloudflare.md
#
# Idempotent (test marker DESCR_EXPOSITION_PUB_2026_05_18).
# A executer sur FW-EXT-LYON (root@10.0.0.2 ou opn-fw-ext-lyon).
# Pour FW-INT-LYON utiliser l'API (cf. section ci-dessous).

set -e

if [ ! -f /conf/config.xml ]; then
  echo "ERREUR: pas execute sur un OPNsense (/conf/config.xml absent)" >&2
  exit 1
fi

MARK="DESCR_EXPOSITION_PUB_2026_05_18"
SNAT_MARK="OUTBOUND_NAT_EXPOSITION_PUB_2026_05_18"

if grep -q "$MARK" /conf/config.xml; then
  echo "Deja applique (marker $MARK present dans config.xml). Abort idempotent."
  exit 0
fi

TS=$(date +%s)
BACKUP="/conf/config.xml.pre-exposition-publique-$TS"
cp -p /conf/config.xml "$BACKUP"
echo "Backup config.xml -> $BACKUP"

python3 - <<PYEOF
import sys, time, uuid

CFG = "/conf/config.xml"
TS = "$TS"
MARK = "$MARK"
SNAT_MARK = "$SNAT_MARK"

with open(CFG, "r", encoding="utf-8") as f:
    xml = f.read()

# ---- Floating pass rules (3) ----
def floating_rule(action, proto, src_net, dst_net, dst_port, descr, seq=0):
    return (
        f'          <rule uuid="{uuid.uuid4()}">\\n'
        f'            <enabled>1</enabled>\\n'
        f'            <statetype>keep</statetype>\\n'
        f'            <state-policy/>\\n'
        f'            <sequence>{seq}</sequence>\\n'
        f'            <action>{action}</action>\\n'
        f'            <quick>1</quick>\\n'
        f'            <interfacenot>0</interfacenot>\\n'
        f'            <interface>wan</interface>\\n'
        f'            <direction>in</direction>\\n'
        f'            <ipprotocol>inet</ipprotocol>\\n'
        f'            <protocol>{proto}</protocol>\\n'
        f'            <source_net>{src_net}</source_net>\\n'
        f'            <source_not>0</source_not>\\n'
        f'            <source_port/>\\n'
        f'            <destination_net>{dst_net}</destination_net>\\n'
        f'            <destination_not>0</destination_not>\\n'
        f'            <destination_port>{dst_port}</destination_port>\\n'
        f'            <gateway/>\\n'
        f'            <replyto/>\\n'
        f'            <disablereplyto>0</disablereplyto>\\n'
        f'            <log>1</log>\\n'
        f'            <allowopts>0</allowopts>\\n'
        f'            <nosync>0</nosync>\\n'
        f'            <nopfsync>0</nopfsync>\\n'
        f'            <statetimeout/>\\n'
        f'            <max-src-nodes/>\\n'
        f'            <max-src-states/>\\n'
        f'            <max-src-conn/>\\n'
        f'            <max/>\\n'
        f'            <max-src-conn-rate/>\\n'
        f'            <max-src-conn-rates/>\\n'
        f'            <overload/>\\n'
        f'            <adaptivestart/>\\n'
        f'            <adaptiveend/>\\n'
        f'            <prio/>\\n'
        f'            <set-prio/>\\n'
        f'            <set-prio-low/>\\n'
        f'            <tag/>\\n'
        f'            <tagged/>\\n'
        f'            <tcpflags1/>\\n'
        f'            <tcpflags2/>\\n'
        f'            <categories/>\\n'
        f'            <sched/>\\n'
        f'            <tos/>\\n'
        f'            <shaper1/>\\n'
        f'            <shaper2/>\\n'
        f'            <description>{descr} [{MARK}]</description>\\n'
        f'          </rule>\\n'
    )

rules = (
    # Destination = 192.168.20.13 (POST-rdr). pf evalue le filter apres rdr.
    floating_rule("pass", "TCP",  "any",              "192.168.20.13", "80",  "Exposition publique HTTP -> NAT vers APP01")
    + floating_rule("pass", "TCP",  "any",            "192.168.20.13", "443", "Exposition publique HTTPS -> NAT vers APP01")
    + floating_rule("pass", "ICMP", "192.168.18.0/24","192.168.18.51", "",    "ICMP test depuis LAN Box pre-port-forward")
)

needle_flt = '<Filter version="1.0.4">\\n        <rules>\\n'
if needle_flt not in xml:
    sys.exit("ERREUR: anchor <Filter><rules> introuvable")
xml = xml.replace(needle_flt, needle_flt + rules, 1)

# ---- NAT rdr (2) ----
def nat_rdr(proto, dst_ip, dst_port, target_ip, target_port, descr):
    return (
        '    <rule>\\n'
        '      <source><any>1</any></source>\\n'
        f'      <destination><address>{dst_ip}</address><port>{dst_port}</port></destination>\\n'
        f'      <protocol>{proto}</protocol>\\n'
        f'      <target>{target_ip}</target>\\n'
        f'      <local-port>{target_port}</local-port>\\n'
        '      <interface>wan</interface>\\n'
        f'      <descr>{descr} [{MARK}]</descr>\\n'
        '      <category/>\\n'
        '      <ipprotocol>inet</ipprotocol>\\n'
        f'      <created><username>auto@portail</username><time>{TS}</time><description>T-NOVA-EXPOSITION-PUBLIQUE</description></created>\\n'
        '    </rule>\\n'
    )

nat = (
    nat_rdr("tcp", "192.168.18.51", "80",  "192.168.20.13", "80",  "RDR HTTP nova.0xmatthieu.dev -> APP01")
    + nat_rdr("tcp", "192.168.18.51", "443", "192.168.20.13", "443", "RDR HTTPS nova.0xmatthieu.dev -> APP01")
)
needle_nat = "  <nat>\\n    <outbound>\\n"
if needle_nat not in xml:
    sys.exit("ERREUR: anchor <nat><outbound> introuvable")
xml = xml.replace(needle_nat, "  <nat>\\n" + nat + "    <outbound>\\n", 1)

# ---- SNAT outbound (symmetric routing) ----
snat = (
    '      <rule>\\n'
    '        <source><network>192.168.18.0/24</network></source>\\n'
    '        <destination><network>192.168.20.0/28</network></destination>\\n'
    f'        <descr>SNAT exposition publique -- symmetric routing [{SNAT_MARK}]</descr>\\n'
    '        <category/>\\n'
    '        <interface>opt1</interface>\\n'
    '        <tag/><tagged/><poolopts/><poolopts_sourcehashkey/>\\n'
    '        <ipprotocol>inet</ipprotocol>\\n'
    '        <protocol></protocol>\\n'
    '        <target>10.0.1.1</target>\\n'
    '        <targetip_subnet>0</targetip_subnet>\\n'
    '        <sourceport/>\\n'
    '        <staticnatport>0</staticnatport>\\n'
    f'        <created><username>auto@portail</username><time>{TS}</time><description>T-NOVA-EXPOSITION-PUBLIQUE patch SNAT</description></created>\\n'
    '      </rule>\\n'
)
needle_snat = "    <outbound>\\n      <mode>hybrid</mode>\\n"
if needle_snat not in xml:
    sys.exit("ERREUR: anchor <outbound><mode>hybrid</mode> introuvable")
xml = xml.replace(needle_snat, needle_snat + snat, 1)

with open(CFG, "w", encoding="utf-8") as f:
    f.write(xml)

print(f"OK. Patched config.xml.")
PYEOF

echo "Reload filter..."
configctl filter reload
echo "Filter reloaded."
echo
echo "Verification rules actives :"
pfctl -sn | grep 192.168.18.51 || echo "  (NAT rdr absent)"
pfctl -sr | grep 192.168.20.13 || echo "  (Filter pass absent)"
echo
echo "Pour FW-INT-LYON (ajouter pass rules WAN via API):"
echo
echo "  KEY=\\\$(grep '^key=' nova-iac-secrets/apikey-fw-int-lyon.txt | cut -d= -f2)"
echo "  SECRET=\\\$(grep '^secret=' nova-iac-secrets/apikey-fw-int-lyon.txt | cut -d= -f2)"
echo "  for PORT in 80 443; do"
echo "    curl -k -s -u \\\"\\\$KEY:\\\$SECRET\\\" -X POST -H 'Content-Type: application/json' \\\\"
echo "      -d '{\\\"rule\\\":{\\\"enabled\\\":\\\"1\\\",\\\"sequence\\\":\\\"1\\\",\\\"interface\\\":\\\"wan\\\","
echo "             \\\"direction\\\":\\\"in\\\",\\\"action\\\":\\\"pass\\\",\\\"quick\\\":\\\"1\\\","
echo "             \\\"ipprotocol\\\":\\\"inet\\\",\\\"protocol\\\":\\\"TCP\\\","
echo "             \\\"source_net\\\":\\\"10.0.1.1\\\",\\\"destination_net\\\":\\\"192.168.20.13\\\","
echo "             \\\"destination_port\\\":\\\"'\\\$PORT'\\\","
echo "             \\\"log\\\":\\\"1\\\",\\\"description\\\":\\\"NAT inbound HTTP'\\\$PORT' [T-NOVA-EXPOSITION-PUBLIQUE]\\\"}}' \\\\"
echo "      https://192.168.99.1/api/firewall/filter/add_rule"
echo "  done"
echo "  curl -k -s -u \\\"\\\$KEY:\\\$SECRET\\\" -X POST -H 'Content-Type: application/json' -d '{}' \\\\"
echo "    https://192.168.99.1/api/firewall/filter/apply"
