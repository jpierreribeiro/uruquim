#!/usr/bin/env bash
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! git -C "$URUQUIM_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: install-hooks must run inside the cloned Uruquim repository" >&2
  exit 1
fi

git -C "$URUQUIM_ROOT" config core.hooksPath .githooks
echo "Installed Uruquim hooks: core.hooksPath=.githooks"
