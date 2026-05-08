#!/bin/sh
# rollback-ipsec-migration.sh
# Restaure l'etat pre-migration IPsec (swanctl.conf + rc.d + fix scripts)
# sur FW-EXT-LYON et FW-EXT-MRS.
#
# Usage : sh scripts/rollback-ipsec-migration.sh
# Prerequis : acces SSH aux deux firewalls (opn-fw-ext-lyon, opn-fw-ext-mrs)
# Effet : restaure les fichiers snapshotes, recharge strongSwan sans redemarrage

set -e

SNAP="/Users/matthieu/Documents/Nova-syndicate-Code/nova-syndicate-proxmox/backups/pre-migration-20260508-1956"

echo "=== ROLLBACK IPsec migration -- debut ==="
echo "Snapshot source : $SNAP"
echo ""

# ------------------------------------------------------------------
# FW-EXT-LYON
# ------------------------------------------------------------------
echo "[1/6] FW-EXT-LYON : restauration swanctl.conf"
scp "$SNAP/swanctl.conf.fw-ext-lyon" opn-fw-ext-lyon:/usr/local/etc/swanctl/swanctl.conf

echo "[2/6] FW-EXT-LYON : restauration rc.d nova_ipsec_fix"
scp "$SNAP/nova_ipsec_fix.fw-ext-lyon" opn-fw-ext-lyon:/usr/local/etc/rc.d/nova_ipsec_fix
ssh opn-fw-ext-lyon 'chmod 755 /usr/local/etc/rc.d/nova_ipsec_fix'

echo "[3/6] FW-EXT-LYON : restauration fix_ipsec_children.py"
scp "$SNAP/fix_ipsec_children.py.fw-ext-lyon" opn-fw-ext-lyon:/usr/local/sbin/fix_ipsec_children.py
ssh opn-fw-ext-lyon 'chmod 755 /usr/local/sbin/fix_ipsec_children.py'

echo "[4/6] FW-EXT-LYON : reload swanctl + re-initiation children manquants"
ssh opn-fw-ext-lyon 'swanctl --load-conns && sleep 1 && swanctl --initiate --child child_bastion --timeout 5; swanctl --initiate --child child_users --timeout 5; swanctl --initiate --child child_backup --timeout 5'

# ------------------------------------------------------------------
# FW-EXT-MRS
# ------------------------------------------------------------------
echo "[5/7] FW-EXT-MRS : restauration swanctl.conf"
scp "$SNAP/swanctl.conf.fw-ext-mrs" opn-fw-ext-mrs:/usr/local/etc/swanctl/swanctl.conf

echo "[6/7] FW-EXT-MRS : restauration rc.d nova_ipsec_fix_mrs"
scp "$SNAP/nova_ipsec_fix_mrs.fw-ext-mrs" opn-fw-ext-mrs:/usr/local/etc/rc.d/nova_ipsec_fix_mrs
ssh opn-fw-ext-mrs 'chmod 755 /usr/local/etc/rc.d/nova_ipsec_fix_mrs'

echo "[7/7] FW-EXT-MRS : restauration fix_ipsec_children.py + reload"
scp "$SNAP/fix_ipsec_children.py.fw-ext-mrs" opn-fw-ext-mrs:/usr/local/sbin/fix_ipsec_children.py
ssh opn-fw-ext-mrs 'chmod 755 /usr/local/sbin/fix_ipsec_children.py && swanctl --load-conns'

# ------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------
echo ""
echo "=== Verification post-rollback ==="
echo "--- FW-EXT-LYON : Child SAs ---"
ssh opn-fw-ext-lyon 'swanctl --list-sas 2>/dev/null | grep -E "child_|reqid|INSTALLED"'
echo "--- FW-EXT-MRS : Child SAs ---"
ssh opn-fw-ext-mrs 'swanctl --list-sas 2>/dev/null | grep -E "child_|reqid|INSTALLED"'

echo ""
echo "=== ROLLBACK termine. Verifier 4 Child SAs INSTALLED sur chaque FW ==="
