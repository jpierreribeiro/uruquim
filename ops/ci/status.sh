#!/usr/bin/env bash
set -euo pipefail

URUQUIM_CI_STATE_DIR="${URUQUIM_CI_STATE_DIR:-/var/lib/uruquim-ci}"
URUQUIM_CI_STATUS="$URUQUIM_CI_STATE_DIR/status"

if test ! -f "$URUQUIM_CI_STATUS"; then
  echo "No VPS verification result has been recorded yet."
  exit 1
fi

printf '%s\n' "Uruquim VPS verification status"
sed 's/^/  /' "$URUQUIM_CI_STATUS"
printf '\nRecent output:\n'
tail -n 20 "$URUQUIM_CI_STATE_DIR/latest.log"
