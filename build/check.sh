#!/usr/bin/env bash
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_PIN_FILE="$URUQUIM_ROOT/odin-version.txt"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

test -f "$URUQUIM_PIN_FILE" || fail "missing odin-version.txt"
URUQUIM_EXPECTED_COMMIT="$(sed -n 's/^commit=//p' "$URUQUIM_PIN_FILE")"
test -n "$URUQUIM_EXPECTED_COMMIT" || fail "missing commit pin"

if test -n "${URUQUIM_ODIN_BIN:-}"; then
  URUQUIM_COMPILER="$URUQUIM_ODIN_BIN"
elif command -v odin >/dev/null 2>&1; then
  URUQUIM_COMPILER="$(command -v odin)"
elif test -x /tmp/uruquim-odin-toolchain/odin; then
  URUQUIM_COMPILER=/tmp/uruquim-odin-toolchain/odin
else
  fail "odin not found; install the pinned distribution or set URUQUIM_ODIN_BIN"
fi

URUQUIM_COMPILER="$(readlink -f "$URUQUIM_COMPILER")" ||
  fail "cannot resolve compiler path: $URUQUIM_COMPILER"
test -x "$URUQUIM_COMPILER" || fail "compiler is not executable: $URUQUIM_COMPILER"
URUQUIM_COMPILER_DIR="$(cd "$(dirname "$URUQUIM_COMPILER")" && pwd)"
if ! URUQUIM_VERSION="$(ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
  "$URUQUIM_COMPILER" version 2>&1)"; then
  fail "compiler version check failed: $URUQUIM_VERSION"
fi
case "$URUQUIM_VERSION" in
  *"$URUQUIM_EXPECTED_COMMIT"*) ;;
  *) fail "compiler mismatch: expected commit $URUQUIM_EXPECTED_COMMIT, got: $URUQUIM_VERSION" ;;
esac

test -d "$URUQUIM_COMPILER_DIR/core/net" || fail "pinned core:net package missing"
test -d "$URUQUIM_COMPILER_DIR/core/nbio" || fail "pinned core:nbio package missing"
test -d "$URUQUIM_COMPILER_DIR/core/encoding/json" ||
  fail "pinned core:encoding/json package missing"
command -v clang >/dev/null 2>&1 ||
  fail "clang not found; Odin needs it to link runnable checks"

bash -n "$URUQUIM_ROOT/build/check.sh"
bash -n "$URUQUIM_ROOT/build/check_test.sh"
bash -n "$URUQUIM_ROOT/build/check_public_api.sh"
bash -n "$URUQUIM_ROOT/build/install-hooks.sh"
bash -n "$URUQUIM_ROOT/experiments/run_checks.sh"
bash -n "$URUQUIM_ROOT/.githooks/pre-push"
bash -n "$URUQUIM_ROOT/ops/ci/run.sh"
bash -n "$URUQUIM_ROOT/ops/ci/status.sh"
bash -n "$URUQUIM_ROOT/ops/ci/install-odin.sh"

echo "toolchain version: $URUQUIM_VERSION"
echo "toolchain commit: $URUQUIM_EXPECTED_COMMIT"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  bash "$URUQUIM_ROOT/experiments/run_checks.sh"

# WP1 — the public package must compile and its compile contract must hold.
# `web` is a library package, so -no-entry-point is required: without it the
# pinned compiler reports "Undefined entry point procedure 'main'".
echo "--- WP1 public API package (odin check) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_ROOT/web" \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point

echo "--- WP1 public API compile contract (odin test) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp1-public-api" \
  "-collection:uruquim=$URUQUIM_ROOT"

echo "--- WP1 public API anti-accretion contract ---"
bash "$URUQUIM_ROOT/build/check_public_api.sh"
