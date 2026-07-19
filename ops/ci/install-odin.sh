#!/usr/bin/env bash
set -euo pipefail

URUQUIM_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
URUQUIM_ODIN_PREFIX="${URUQUIM_ODIN_PREFIX:-/opt/uruquim-odin}"
URUQUIM_PIN_FILE="$URUQUIM_SOURCE_ROOT/odin-version.txt"

URUQUIM_ODIN_RELEASE="$(sed -n 's/^release=//p' "$URUQUIM_PIN_FILE")"
URUQUIM_ODIN_COMMIT="$(sed -n 's/^commit=//p' "$URUQUIM_PIN_FILE")"
URUQUIM_ODIN_ASSET="$(sed -n 's/^linux_amd64_asset=//p' "$URUQUIM_PIN_FILE")"
URUQUIM_ODIN_DIGEST="$(sed -n 's/^linux_amd64_sha256=//p' "$URUQUIM_PIN_FILE")"
URUQUIM_ODIN_URL="https://github.com/odin-lang/Odin/releases/download/$URUQUIM_ODIN_RELEASE/$URUQUIM_ODIN_ASSET"

URUQUIM_ODIN_TMP="$(mktemp -d /tmp/uruquim-odin-install.XXXXXX)"
cleanup() {
  rm -rf -- "$URUQUIM_ODIN_TMP"
}
trap cleanup EXIT

curl --retry 5 --retry-all-errors -fsSL "$URUQUIM_ODIN_URL" \
  -o "$URUQUIM_ODIN_TMP/$URUQUIM_ODIN_ASSET"
printf '%s  %s\n' "$URUQUIM_ODIN_DIGEST" \
  "$URUQUIM_ODIN_TMP/$URUQUIM_ODIN_ASSET" | sha256sum -c -

mkdir -p "$URUQUIM_ODIN_PREFIX"
tar -xzf "$URUQUIM_ODIN_TMP/$URUQUIM_ODIN_ASSET" \
  -C "$URUQUIM_ODIN_PREFIX" --strip-components=1

URUQUIM_ODIN_VERSION="$($URUQUIM_ODIN_PREFIX/odin version 2>&1)"
case "$URUQUIM_ODIN_VERSION" in
  *"$URUQUIM_ODIN_COMMIT"*) ;;
  *)
    echo "ERROR: installed compiler does not match $URUQUIM_ODIN_COMMIT" >&2
    exit 1
    ;;
esac

echo "$URUQUIM_ODIN_VERSION"
