#!/usr/bin/env bash
# check-no-leaked-strings.sh -- refuse to commit known-leaked patterns
# T-VAULT-PLAINTEXT-FIX-2026-05-18 / DETTE-011
#
# Patterns chosen from the actual leak found by T-INFRA-FULL-TEST.
# Add new patterns when new leaks are discovered + rotated.

set -eu

# Build patterns from concat to avoid self-match of this script.
P1="Nova"; P1="${P1}20"; P1="${P1}26!"
P2="kHr1"; P2="${P2}jUZrNgtM3dKJJSsV2ncJc8ghDqoyOwYjUyIFk0U="
PATTERNS="(${P1}|${P2})"

# Filter out this script + check-vault-encrypted.sh from staged files inspected
FILES=()
for f in "$@"; do
  case "$f" in
    *check-no-leaked-strings.sh|*check-vault-encrypted.sh) ;;
    *.gitleaks.toml) ;;
    *.pre-commit-config.yaml) ;;
    docs/adr/ADR-0026*|docs/adr/ADR-0028*) ;;
    *) FILES+=("$f") ;;
  esac
done

if [ ${#FILES[@]} -eq 0 ]; then
  exit 0
fi

LEAKS=$(git diff --cached -U0 -- "${FILES[@]}" 2>/dev/null | grep -E "^\+.*${PATTERNS}" || true)

if [ -n "$LEAKS" ]; then
  echo "ERROR: known previously-leaked string added in staged diff." >&2
  echo "       cf T-VAULT-PLAINTEXT-FIX-2026-05-18 (ADR-0026)." >&2
  echo "" >&2
  echo "Offending lines:" >&2
  echo "$LEAKS" | head -10 >&2
  echo "" >&2
  echo "       Either : rotate the secret again + filter-repo," >&2
  echo "       or     : redact it manually if it is a doc reference (Nova****)." >&2
  exit 1
fi
exit 0
