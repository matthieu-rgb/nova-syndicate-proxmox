# T-WAZUH-SURICATA-INTEGRATION -- scripts

Reference deploy artifacts pour l'integration des 3 Suricata OPNsense vers
le wazuh-indexer (cf. ADR-0030 section "Integration Suricata 3 capteurs").

## Contenu

| Fichier | Cible | Description |
|---|---|---|
| `suricata-eve-forwarder.sh` | OPNsense FreeBSD `/usr/local/sbin/` | tail -F eve.json -> nc UDP app01:5141, injecte `sensor` |
| `suricata-eve-forwarder.rc` | OPNsense `/usr/local/etc/rc.d/suricata_eve_forwarder` | rc.d unit FreeBSD |
| `udp-log-receiver.py` | app01 `/usr/local/sbin/` | UDP receiver Python -> append `/var/log/suricata-fw.log` |
| `suricata-fw-receiver.service` | app01 `/etc/systemd/system/` | systemd unit pour le receiver Python |
| `suricata-syslog.nft` | app01 `/etc/nftables.d/` | rules nftables pour autoriser UDP 5141 + 514 depuis FW |

## Pourquoi un receiver custom et pas <remote><connection>syslog (Wazuh) ?

- Wazuh 4.11 `<remote>` UDP 514 (syslog) recoit les datagrammes mais ne
  les passe pas a l'analyse de maniere observable (debug ne montre rien).
  Pattern opaque pour le labo.
- syslog-ng OPNsense ajoute un wrapper RFC5424 + structured-data
  `[meta sequenceId="N"]` qui casse le decoder JSON.

Solution : on bypasse syslog totalement, on envoie le JSON brut via nc,
un receiver Python l'ecrit dans un fichier, et wazuh-logcollector
`<localfile log_format="json">` decode avec le decoder json + rules
86600-86699 standard.

## Procedure de deploiement (3 OPNsense + app01)

### Sur app01 (executer en root)

```bash
cp udp-log-receiver.py /usr/local/sbin/
chmod +x /usr/local/sbin/udp-log-receiver.py
cp suricata-fw-receiver.service /etc/systemd/system/
cp suricata-syslog.nft /etc/nftables.d/
touch /var/log/suricata-fw.log
chown wazuh:wazuh /var/log/suricata-fw.log
chmod 660 /var/log/suricata-fw.log

# Persistante rp_filter loose (sinon strict drop UDP de 10.0.1.1)
echo 'net.ipv4.conf.all.rp_filter=2' > /etc/sysctl.d/99-rp-filter.conf
sysctl -p /etc/sysctl.d/99-rp-filter.conf

systemctl daemon-reload
systemctl enable --now suricata-fw-receiver.service

# nft : inserer AVANT le default drop. Utiliser nft insert position <handle>
nft insert rule inet filter input position $(nft -a list chain inet filter input | awk '/policy drop|NFT-DROP/ {print $NF; exit}') \
  ip saddr {10.0.1.1/32, 192.168.99.0/24, 192.168.20.1/32, 192.168.40.0/26} udp dport 5141 accept comment '"suricata-fw-receiver"'

# Ajout <localfile> dans /var/ossec/etc/ossec.conf avant le DERNIER </ossec_config>
#   <localfile>
#     <log_format>json</log_format>
#     <location>/var/log/suricata-fw.log</location>
#   </localfile>
systemctl restart wazuh-manager
```

### Sur chaque OPNsense (depuis Proxmox via /tmp/nova_opnsense_ed25519)

```bash
cat suricata-eve-forwarder.sh | ssh root@<FW_IP> "cat > /usr/local/sbin/suricata-eve-forwarder.sh && chmod +x /usr/local/sbin/suricata-eve-forwarder.sh"
cat suricata-eve-forwarder.rc | ssh root@<FW_IP> "cat > /usr/local/etc/rc.d/suricata_eve_forwarder && chmod +x /usr/local/etc/rc.d/suricata_eve_forwarder"

# Per-FW config : NOVA_SENSOR (FW-EXT-LYON / FW-INT-LYON / FW-EXT-MRS)
# Pour MRS : ajouter aussi suricata_eve_forwarder_src=192.168.40.1 (sinon IPsec drop)
ssh root@<FW_IP> "mkdir -p /etc/rc.conf.d && cat > /etc/rc.conf.d/suricata_eve_forwarder <<EOF
suricata_eve_forwarder_sensor=FW-XXX
EOF
service suricata_eve_forwarder restart"
```

### Sur FW-INT-LYON : pf rule (via API)

Ajouter une rule pass UDP 5141 (et 514) en interface `wan`, source `10.0.1.1/32`,
dest `192.168.20.13/32`. FW-EXT-LYON traverse FW-INT pour atteindre app01.

## Test

```bash
# Sur une OPNsense, injecter une ligne dans eve.json :
TS=$(date -u +%Y-%m-%dT%H:%M:%S.000+0000)
echo "{\"timestamp\":\"$TS\",\"event_type\":\"alert\",\"src_ip\":\"1.2.3.4\",\"alert\":{\"signature\":\"TEST\",\"signature_id\":99,\"severity\":2}}" >> /var/log/suricata/eve.json

# Sur app01, verifier reception + decodage :
tail -1 /var/log/suricata-fw.log   # doit voir {"sensor":"FW-XXX", ...}
grep "TEST" /var/ossec/logs/alerts/alerts.json | tail -1  # rule 86601
```
