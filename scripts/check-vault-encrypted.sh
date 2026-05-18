#!/usr/bin/env bash
# check-vault-encrypted.sh -- Defense in depth contre re-leak vault.yml plaintext.
# Called by pre-commit hook on every staged file matching vault\.yml$.
# T-VAULT-PLAINTEXT-FIX-2026-05-18 / DETTE-011

set -eu

VAULT_HEADER='$ANSIBLE_VAULT;1.1'
RC=0

for file in "$@"; do
  if [ ! -f "$file" ]; then
    continue
  fi
  HEAD=$(head -c 18 "$file")
  if [ "$HEAD" != "$VAULT_HEADER" ]; then
    echo "ERROR: $file is NOT ansible-vault encrypted." >&2
    echo "       Expected header: $VAULT_HEADER" >&2
    echo "       Got:             $HEAD" >&2
    echo "" >&2
    echo "       Fix: ansible-vault encrypt --vault-password-file ~/.ansible/nova_vault_pass $file" >&2
    RC=1
  fi
done

exit "$RC"
