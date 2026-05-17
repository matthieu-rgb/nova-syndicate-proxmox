#!/bin/sh
# ============================================================
# IPsec auto-recovery -- FW-EXT-LYON
# Reference : T-IPSEC-STABILITY
# Goal : Garantir que tous les child SAs IPsec restent UP.
#
# Logic :
#  1. Enumere les child SAs definis dans la config strongSwan (swanctl --list-conns).
#  2. Compare avec les child SAs INSTALLED (swanctl --list-sas).
#  3. Initie ceux qui manquent.
#  4. Si IKE_SA absente, tente configctl ipsec reload puis re-initie.
#  5. Log dans /var/log/ipsec-recovery.log + syslog si echec.
#
# Install :
#   chmod +x /usr/local/sbin/ipsec-recovery.sh
#   echo "*/5 * * * * root /usr/local/sbin/ipsec-recovery.sh >/dev/null 2>&1" >> /etc/crontab
#   service cron restart
# ============================================================

LOG=/var/log/ipsec-recovery.log
SWANCTL=/usr/local/sbin/swanctl
CONFIGCTL=/usr/local/sbin/configctl
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() {
  echo "[$TS] $*" >> "$LOG"
}

alert() {
  log "ALERT: $*"
  logger -t ipsec-recovery -p user.error "$*"
}

if [ ! -x "$SWANCTL" ]; then
  alert "swanctl introuvable a $SWANCTL"
  exit 1
fi

defined_children=$("$SWANCTL" --list-conns 2>/dev/null \
  | awk '/^  [0-9a-f-]+: TUNNEL/ {gsub(":",""); print $1}')

installed_children=$("$SWANCTL" --list-sas 2>/dev/null \
  | awk '/INSTALLED, TUNNEL/ {gsub(":",""); print $1}')

ike_count=$("$SWANCTL" --list-sas 2>/dev/null | grep -c ESTABLISHED)
defined_count=$(echo "$defined_children" | grep -c .)
installed_count=$(echo "$installed_children" | grep -c .)

log "Check : IKE=$ike_count, child INSTALLED=$installed_count/$defined_count"

if [ "$installed_count" -ge "$defined_count" ] && [ "$ike_count" -ge 1 ]; then
  exit 0
fi

if [ "$ike_count" -lt 1 ]; then
  log "IKE_SA absente, reload strongSwan"
  "$CONFIGCTL" ipsec reload >> "$LOG" 2>&1
  sleep 5
fi

tmp_defined=$(mktemp)
tmp_installed=$(mktemp)
trap 'rm -f "$tmp_defined" "$tmp_installed"' EXIT
echo "$defined_children" | sort -u > "$tmp_defined"
echo "$installed_children" | sort -u > "$tmp_installed"

comm -23 "$tmp_defined" "$tmp_installed" | while IFS= read -r child; do
  [ -z "$child" ] && continue
  log "Initiation child $child"
  "$SWANCTL" --initiate --child "$child" >> "$LOG" 2>&1
done

sleep 3
final=$("$SWANCTL" --list-sas 2>/dev/null | grep -c "INSTALLED, TUNNEL")
log "Post-recovery : child INSTALLED=$final/$defined_count"

if [ "$final" -lt "$defined_count" ]; then
  alert "Recovery partial : $final/$defined_count child SAs INSTALLED"
  exit 2
fi

exit 0
