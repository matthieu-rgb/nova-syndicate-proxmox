#!/usr/bin/env bash
# health-check.sh — Nova Syndicate invariant checks
# Arrete si un check critique echoue (tunnels IPsec ou terraform plan)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/environments/opnsense"
LOG="$REPO_ROOT/docs/NIGHT-LOG.md"
INCIDENT="$REPO_ROOT/docs/NIGHT-INCIDENT.md"
SSH_KEY=~/.ssh/id_ansible
SSH_OPTS="-i $SSH_KEY -o ConnectTimeout=5 -o StrictHostKeyChecking=no"

FAILED=0
WARNINGS=0

log() { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { log "CRITICAL: $*"; FAILED=1; }
warn() { log "WARN: $*"; WARNINGS=$((WARNINGS+1)); }

log "=== HEALTH CHECK START $(date '+%Y-%m-%d %H:%M:%S') ==="

# --- 1. Tunnels IPsec (4 modernes UUID 78112723) ---
log "Check IPsec tunnels..."
IPSEC_OUT=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no opn-fw-ext-lyon \
    'swanctl --list-sas' 2>/dev/null || echo "SSH_FAILED")

if echo "$IPSEC_OUT" | grep -q "SSH_FAILED"; then
    fail "Cannot reach opn-fw-ext-lyon via SSH"
elif ! echo "$IPSEC_OUT" | grep -q "78112723"; then
    fail "Modern IKE SA 78112723 not found — tunnels may be down"
else
    MODERN_CHILDREN=$(echo "$IPSEC_OUT" | grep -c "INSTALLED" || true)
    MODERN_SA=$(echo "$IPSEC_OUT" | grep -E "4bbf5017|1856ee5d|1a71c717|120d04c8" | grep -c "INSTALLED" || true)
    if [ "$MODERN_SA" -lt 4 ]; then
        fail "Only $MODERN_SA/4 modern Child SAs INSTALLED (expected 4bbf5017, 1856ee5d, 1a71c717, 120d04c8)"
    else
        log "IPsec OK — 4 modern Child SAs INSTALLED under 78112723"
    fi
fi

# --- 2. Terraform plan = No changes ---
log "Check terraform plan..."
TF_OUT=$(cd "$TF_DIR" && terraform plan -no-color 2>&1)
if echo "$TF_OUT" | grep -q "No changes"; then
    log "Terraform OK — No changes"
else
    TF_TAIL=$(echo "$TF_OUT" | tail -5)
    fail "Terraform plan shows changes or error: $TF_TAIL"
fi

# --- 3. SSH vers les 6 hotes ---
log "Check SSH connectivity..."
CHECK_SSH() {
    local label="$1" ip="$2"
    if ssh $SSH_OPTS "debian@$ip" 'echo OK' &>/dev/null; then
        log "SSH $label ($ip) OK"
    else
        fail "SSH $label ($ip) FAILED"
    fi
}
CHECK_SSH dc01     192.168.20.10
CHECK_SSH fs01     192.168.20.11
CHECK_SSH db01     192.168.20.12
CHECK_SSH app01    192.168.20.13
CHECK_SSH bastion01 192.168.15.2
CHECK_SSH backup01 192.168.50.2

# --- 4. Checks T1-T6 ---

# T1: AD users >= 91 (85 + 6 systeme)
log "Check AD users (T1)..."
USERS_OUT=$(ssh $SSH_OPTS debian@192.168.20.10 \
    'sudo samba-tool user list 2>/dev/null | wc -l' 2>/dev/null || echo "0")
if [ "$USERS_OUT" -ge 91 ]; then
    log "AD users: $USERS_OUT OK (>=91)"
else
    warn "AD users: $USERS_OUT (expected >=91)"
fi

# T1: Groupes AD (8 groupes metier)
GROUPS_OK=$(ssh $SSH_OPTS debian@192.168.20.10 \
    'for g in lyon-staff marseille-staff mobile-agents finance it-admins managers rh direction; do sudo samba-tool group show "$g" &>/dev/null && echo OK; done | wc -l' 2>/dev/null || echo "0")
if [ "$GROUPS_OK" -ge 8 ]; then
    log "AD groupes: $GROUPS_OK/8 OK"
else
    warn "AD groupes: $GROUPS_OK/8 presents"
fi

# T2: FS1 partages Samba (5 shares)
log "Check FS1 shares (T2)..."
SHARES_OUT=$(ssh $SSH_OPTS debian@192.168.20.11 \
    'sudo smbstatus --shares 2>/dev/null | grep -c "\." || echo 0' 2>/dev/null || echo "0")
# Verifier via config smb.conf (shares definis, y compris hidden)
SHARES_LIST=$(ssh $SSH_OPTS debian@192.168.20.11 \
    'grep -c "^\[" /etc/samba/smb.conf 2>/dev/null || echo 0' 2>/dev/null || echo "0")
# Sections = [global] + 5 shares = 6 minimum
log "FS1 smb.conf sections: $SHARES_LIST"
if [ "$SHARES_LIST" -ge 6 ]; then
    log "FS1 shares: OK (${SHARES_LIST} sections dont global + 5 partages)"
else
    warn "FS1 shares: $SHARES_LIST sections dans smb.conf (expected >=6)"
fi

# T3: MariaDB + bases
log "Check MariaDB (T3)..."
DB_STATUS=$(ssh $SSH_OPTS debian@192.168.20.12 \
    "sudo mysql -e 'SHOW DATABASES;' 2>/dev/null" 2>/dev/null || echo "FAILED")
if echo "$DB_STATUS" | grep -q "nova_logistique"; then
    log "MariaDB: nova_logistique OK"
else
    warn "MariaDB: nova_logistique not found"
fi
if echo "$DB_STATUS" | grep -q "nova_rh"; then
    log "MariaDB: nova_rh OK"
else
    warn "MariaDB: nova_rh not found"
fi

# T4: Wazuh manager + agents
log "Check Wazuh (T4)..."
WAZUH_STATUS=$(ssh $SSH_OPTS debian@192.168.20.13 \
    'systemctl is-active wazuh-manager 2>/dev/null' 2>/dev/null || echo "unknown")
if [ "$WAZUH_STATUS" = "active" ]; then
    log "Wazuh manager: active"
else
    warn "Wazuh manager: $WAZUH_STATUS"
fi
WAZUH_AGENTS=$(ssh $SSH_OPTS debian@192.168.20.13 \
    'sudo /var/ossec/bin/agent_control -l 2>/dev/null | grep -c "Active" || echo 0' 2>/dev/null || echo "0")
if [ "$WAZUH_AGENTS" -ge 5 ]; then
    log "Wazuh agents actifs: $WAZUH_AGENTS OK (>=5)"
else
    warn "Wazuh agents actifs: $WAZUH_AGENTS (expected >=5)"
fi

# T5: Prometheus + Grafana
log "Check monitoring (T5)..."
PROM_STATUS=$(ssh $SSH_OPTS debian@192.168.20.13 \
    'systemctl is-active prometheus 2>/dev/null' 2>/dev/null || echo "unknown")
GRAF_STATUS=$(ssh $SSH_OPTS debian@192.168.20.13 \
    'systemctl is-active grafana-server 2>/dev/null' 2>/dev/null || echo "unknown")
[ "$PROM_STATUS" = "active" ] && log "Prometheus: active" || warn "Prometheus: $PROM_STATUS"
[ "$GRAF_STATUS" = "active" ] && log "Grafana: active" || warn "Grafana: $GRAF_STATUS"

# T6: BorgBackup repos
log "Check BorgBackup repos (T6)..."
BORG_REPOS=$(ssh $SSH_OPTS debian@192.168.50.2 \
    'sudo ls /var/backups/borg/ 2>/dev/null | wc -l' 2>/dev/null || echo "0")
if [ "$BORG_REPOS" -ge 3 ]; then
    log "Borg repos: $BORG_REPOS OK (>=3)"
else
    warn "Borg repos: $BORG_REPOS (expected 3)"
fi
BORG_SCRIPTS=$(ssh $SSH_OPTS debian@192.168.50.2 \
    'sudo find /opt/nova-backup -name "*.sh" 2>/dev/null | wc -l' 2>/dev/null || echo "0")
if [ "$BORG_SCRIPTS" -ge 3 ]; then
    log "Borg scripts: $BORG_SCRIPTS OK (>=3)"
else
    warn "Borg scripts: $BORG_SCRIPTS (expected >=3)"
fi

# --- Resultat final ---
echo ""
log "=== HEALTH CHECK COMPLETE ==="
log "Critical failures: $FAILED"
log "Warnings: $WARNINGS"

if [ "$FAILED" -gt 0 ]; then
    log "STOP — Critical failure detected. Writing NIGHT-INCIDENT.md..."
    cat > "$INCIDENT" <<INCIDENT_EOF
# NIGHT-INCIDENT -- $(date '+%Y-%m-%d %H:%M:%S')

## Detecte par

health-check.sh

## Symptome

$IPSEC_OUT

Terraform output:
$TF_OUT

## Actions requises au matin

1. Verifier swanctl --list-sas sur opn-fw-ext-lyon
2. Si tunnels down: executer rollback-ipsec-migration.sh
3. Si terraform plan montre changes: inspecter le diff avant tout apply

## Aucune action autonome prise (regle invariant)
INCIDENT_EOF
    echo ">> INCIDENT FILE WRITTEN: $INCIDENT"
    exit 1
fi

log "All critical checks PASSED"
exit 0
