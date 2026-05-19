#!/bin/sh
# T-WAZUH-SURICATA-INTEGRATION
# Source de verite : ce repo, deployer sur les 3 OPNsense
# (/usr/local/sbin/suricata-eve-forwarder.sh)
#
# Suricata EVE -> Wazuh local UDP receiver (raw JSON, no syslog wrapper).
# Pourquoi pas via syslog-ng OPNsense :
#   - le destination network() wrappe en RFC5424 + structured-data [meta seqId="N"]
#     ce qui casse le decoder json de Wazuh (predecoder n'extrait pas le body).
#
# Pourquoi pas via le toggle "syslog_eve" OPNsense :
#   - le toggle ne genere aucun output syslog visible meme apres restart Suricata.
#
# On tail directement eve.json et on envoie chaque ligne JSON brut en datagramme
# UDP, taggee par capteur (header injecte au debut de l'objet JSON).

EVE=/var/log/suricata/eve.json
WAZUH_IP="${WAZUH_IP:-192.168.20.13}"
WAZUH_PORT="${WAZUH_PORT:-5141}"
PIDFILE=/var/run/suricata-eve-forwarder.pid

# Si NC_SRC est defini, force nc a utiliser cette IP comme source. Necessaire
# pour FW-EXT-MRS ou la policy IPsec ne couvre que 192.168.40.0/26 -- le kernel
# choisirait sinon 10.0.2.2 (WAN) qui n'est PAS dans la policy.
NC_SRC_OPT=""
[ -n "${NC_SRC:-}" ] && NC_SRC_OPT="-s $NC_SRC"

case "$1" in
  start)
    [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null && {
      echo "already running pid=$(cat $PIDFILE)"; exit 0;
    }
    HOSTNAME="${NOVA_SENSOR:-$(hostname -s)}"
    nohup /bin/sh -c "tail -F '$EVE' 2>/dev/null | while IFS= read -r line; do
      [ -z \"\$line\" ] && continue
      out=\$(echo \"\$line\" | sed -e \"s/^{/{\\\"sensor\\\":\\\"$HOSTNAME\\\",/\")
      echo \"\$out\" | nc -u -w 0 -N $NC_SRC_OPT $WAZUH_IP $WAZUH_PORT 2>/dev/null
    done" >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "started pid=$(cat $PIDFILE)"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      pkill -P "$PID" 2>/dev/null
      kill "$PID" 2>/dev/null
      rm -f "$PIDFILE"
      echo "stopped"
    fi
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
      echo "running pid=$(cat $PIDFILE)"
    else
      echo "not running"
    fi
    ;;
  *)
    echo "usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
