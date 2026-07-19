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

# WP2 — the request/response model.
#
# `Response`, `response_commit`, `method_from_token` and `Header_Pair` are
# package-private, and on the pinned toolchain an `@(test)` procedure must be
# compiled as part of the package it tests. Compiling those tests inside `web/`
# would link `core:testing` into every application binary (+41,592 bytes,
# measured on 819fdc7), so the shipped package contains no test file at all.
#
# Instead the gate assembles a THROWAWAY package: the real sources from `web/`
# plus `tests/wp2-internal/`, copied into a fresh `mktemp -d` directory. The
# tests therefore run against the genuine sources, not a stand-in. The
# directory is removed afterwards, including when the test run fails — the trap
# fires on the `set -e` exit. `build/check_public_api.sh` permanently forbids
# `*_test.odin` and `core:testing` under `web/`, so this cannot regress.
echo "--- WP2 request/response model, internal behavior (throwaway package) ---"
URUQUIM_TMP_PKG="$(mktemp -d -t uruquim-wp2-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP_PKG"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_TMP_PKG/"
cp "$URUQUIM_ROOT"/tests/wp2-internal/*.odin "$URUQUIM_TMP_PKG/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_TMP_PKG" \
  "-collection:uruquim=$URUQUIM_ROOT"
rm -rf "$URUQUIM_TMP_PKG"
trap - EXIT
test ! -d "$URUQUIM_TMP_PKG" ||
  fail "the throwaway internal-test package was not removed"
echo "PASS: internal tests ran against the real sources; throwaway package removed"

echo "--- WP2 public surface contract (odin test) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp2-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT"

# WP2 compile probes. A negative probe must fail to compile AND fail for the
# stated reason: an unrelated compile error must never be read as proof that a
# symbol is unreachable.
URUQUIM_PROBES="$URUQUIM_ROOT/tests/wp2-public-surface/probes"

uruquim_negative_probe() { # file expected-diagnostic label
  local file="$1" expected="$2" label="$3"
  local output
  echo "--- WP2 probe: $label (expected compile failure) ---"
  # The compile is EXPECTED to fail, so it is run as the condition of an `if`:
  # under `set -e` a bare assignment from a failing command would abort here.
  if output="$(env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
    PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
    "$URUQUIM_COMPILER" check "$URUQUIM_PROBES/$file" -file \
    "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point 2>&1)"; then
    echo "$output" >&2
    fail "probe '$label' compiled; the symbol it must not reach is reachable"
  fi
  if ! grep -qF "$expected" <<<"$output"; then
    echo "$output" >&2
    fail "probe '$label' failed for the wrong reason; expected: $expected"
  fi
  echo "PASS: $label"
}

uruquim_negative_probe header_pair_not_exported.odin \
  "'Header_Pair' is not exported by 'web'" \
  "Header_Pair is not nameable from outside the package"

uruquim_negative_probe header_view_internal_not_exported.odin \
  "'Header_View_Internal' is not exported by 'web'" \
  "Header_View_Internal is not nameable from outside the package"

uruquim_negative_probe context_has_no_response.odin \
  "has no field 'response'" \
  "Context exposes no public response field"

# The matching POSITIVE probe records an accepted fact rather than a feature:
# `Header_View` is encapsulated BY CONTRACT, not opaque. If this ever stopped
# compiling, the documentation would be claiming a barrier Odin does not give.
echo "--- WP2 probe: internal slot stays reachable (expected compile success) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_PROBES/internal_slot_is_reachable.odin" -file \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point ||
  fail "the encapsulation-by-contract probe stopped compiling; ADR-008's scope statement would be wrong"
echo "PASS: encapsulation is by contract, not a barrier (ADR-008 scope confirmed)"

echo "--- Phase-1 public API anti-accretion contract ---"
bash "$URUQUIM_ROOT/build/check_public_api.sh"
