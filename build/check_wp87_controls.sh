#!/usr/bin/env bash
# WP87 — the stream/body lifecycle corpus is committed RED, under control.
#
# Three claims, each executable:
#   1. the buffered oracle is GREEN — so the RED below cannot be blamed on the
#      tree, and G7-10's byte pins exist before any streaming code does;
#   2. both lifecycle corpora fail COMPLETELY, and for the sentinel's reason
#      (`Unimplemented`), not for a compile error, a partial pass or an
#      unrelated fault — the WP67 vacuity lesson;
#   3. the pre-registered contract cases are all present by name, so a later
#      edit cannot quietly drop one and call the survivor set "the corpus".
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP87-CONTROL-FAIL: $*" >&2
  exit 1
}

if test -n "${URUQUIM_COMPILER:-}"; then
  URUQUIM_ODIN="$URUQUIM_COMPILER"
elif test -n "${URUQUIM_ODIN_BIN:-}"; then
  URUQUIM_ODIN="$URUQUIM_ODIN_BIN"
elif command -v odin >/dev/null 2>&1; then
  URUQUIM_ODIN="$(command -v odin)"
elif test -x /tmp/uruquim-odin-toolchain/odin; then
  URUQUIM_ODIN=/tmp/uruquim-odin-toolchain/odin
else
  fail "odin compiler not found"
fi

URUQUIM_ODIN="$(readlink -f "$URUQUIM_ODIN")"
URUQUIM_ODIN_ROOT="$(cd "$(dirname "$URUQUIM_ODIN")" && pwd)"
URUQUIM_TMP="$(mktemp -d -t uruquim-wp87-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

run_green() { # package, output binary
  env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
    "$1" "-collection:uruquim=$URUQUIM_ROOT" "-out:$URUQUIM_TMP/$2"
}

run_expected_red() { # package, output binary, then diagnostic tokens...
  local package="$1" binary="$2"
  shift 2
  local output
  if output="$(env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
      "$package" "-collection:uruquim=$URUQUIM_ROOT" \
      "-out:$URUQUIM_TMP/$binary" 2>&1)"; then
    fail "$package unexpectedly passed before WP88/WP89/WP94 exist"
  fi
  for token in "$@"; do
    grep -qF "$token" <<<"$output" || {
      echo "$output" >&2
      fail "$package failed for the wrong reason; missing diagnostic token: $token"
    }
  done
}

# Claim 1 — the oracle: buffered behaviour is pinned and green today.
run_green "$URUQUIM_ROOT/tests/wp87-buffered-oracle" oracle-green

# Claim 2/3, response side — STAGE ADVANCED BY WP88/WP89 (2026-07-23): the
# registry and cross-lane delivery are implemented, so the stream corpus is
# now required GREEN, unedited — the RED-under-control promise kept. The
# corpus completeness (every pre-registered case present by name) moves to
# check_wp88_controls.sh, next to the generation-check mutation control.
run_green "$URUQUIM_ROOT/tests/wp87-stream-lifecycle" stream-green

# The inbound-body corpus: same discipline.
run_expected_red \
  "$URUQUIM_ROOT/tests/wp87-body-lifecycle" body-red \
  "All tests failed." \
  "Unimplemented" \
  "wp87_admission_refuses_before_reading_any_byte" \
  "wp87_spool_file_is_generated_private_and_inside_the_designated_dir" \
  "wp87_large_body_bytes_never_coexist_in_memory" \
  "wp87_per_upload_quota_breach_is_typed_and_cleans" \
  "wp87_disconnect_cancel_is_exactly_once" \
  "wp87_ready_hands_exactly_one_owned_body" \
  "wp87_persist_is_the_only_path_that_leaves_a_file"

# STAGED: WP90b wired the STREAM package into the transport adapter — that
# was the guard's stated lifetime. What remains guarded: the INGEST sentinel
# stays unlinked until WP94, and `package web` itself (the public core) still
# imports neither — only the transport boundary may.
if grep -rn 'internal/ingest' "$URUQUIM_ROOT/web" \
  --include='*.odin' -l | grep -v 'web/internal/ingest' >/dev/null; then
  fail "web imports the WP87 ingest sentinel before WP94 implements it (G7-8)"
fi
if grep -n 'internal/stream\|internal/ingest' "$URUQUIM_ROOT/web"/*.odin >/dev/null 2>&1; then
  fail "package web imports a private lifecycle package directly; only the transport boundary may (ADR-009)"
fi

echo "wp87: buffered oracle green — G7-10 byte pins exist before streaming code"
echo "wp87: stream corpus GREEN unedited (WP88/WP89 implemented the sentinel)"
echo "wp87: body corpus RED, complete, for the sentinel's reason (7 cases)"
echo "wp87: ingest sentinel unlinked until WP94; package web imports no private lifecycle package"
echo "PASS: WP87 lifecycle corpus controls"
