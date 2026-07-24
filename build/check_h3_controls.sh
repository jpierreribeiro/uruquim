#!/usr/bin/env bash
# H-3 — web.Server_Stats / web.stats(), under control.
#
# The ledger amendment is already pinned by the freeze/public-api/docs gates.
# This gate pins the things those cannot see: that the counters are actually
# WIRED (a Server_Stats that never increments is a decorative struct), that
# redaction holds by construction (no string field), and that the accessor is
# proven on real traffic rather than a package-internal read.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_OBS="$URUQUIM_ROOT/web/observability.odin"
URUQUIM_SERVER="$URUQUIM_ROOT/vendor/odin-http/server.odin"
URUQUIM_RESP="$URUQUIM_ROOT/vendor/odin-http/response.odin"
URUQUIM_SUITE="$URUQUIM_ROOT/tests/h3-server-stats/server_stats_test.odin"

fail() {
  echo "H3-CONTROL-FAIL: $*" >&2
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
URUQUIM_TMP="$(mktemp -d -t uruquim-h3-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

test -f "$URUQUIM_SUITE" || fail "tests/h3-server-stats/server_stats_test.odin is missing"

# --- 1. Redaction by construction: no field of Server_Stats is a string -------
# Extract the struct body and refuse any `string` type in it. The two-instance
# trap in reverse: a string field would be a channel for a request-derived byte.
URUQUIM_STRUCT="$(sed -n '/^Server_Stats :: struct {/,/^}/p' "$URUQUIM_OBS")"
test -n "$URUQUIM_STRUCT" || fail "Server_Stats struct not found in web/observability.odin"
if grep -qE ':\s*string' <<<"$URUQUIM_STRUCT"; then
  fail "Server_Stats has a string field. Every field must be an integer so redaction holds by construction — a string is a path for a request byte to reach an observer (WP20 §3.1)."
fi

# --- 2. The counters are wired (patch 28), not decorative ---------------------
grep -q 'responses_sent:' "$URUQUIM_SERVER" ||
  fail "the backend Server struct no longer declares the write-side counters (patch 28)"
grep -q 'atomic_add(&conn.server.responses_sent' "$URUQUIM_RESP" ||
  fail "on_response_sent no longer increments responses_sent; the counter is decorative"
grep -q 'atomic_add(&conn.server.response_bytes' "$URUQUIM_RESP" ||
  fail "on_response_sent no longer increments response_bytes"
grep -q 'atomic_add(&conn.server.send_errors' "$URUQUIM_RESP" ||
  fail "on_response_sent no longer counts send errors"
grep -q 'atomic_add(&s.write_deadline_aborts' "$URUQUIM_SERVER" ||
  fail "the sweep's write-deadline abort no longer increments write_deadline_aborts"

# --- 3. The accessor is proven on real traffic --------------------------------
grep -q '^h3_stats_count_real_responses_and_are_zero_without_a_server ::' "$URUQUIM_SUITE" ||
  fail "the H-3 behavioural test is gone"
grep -q 's.response_bytes > i64(served \* len(BODY))' "$URUQUIM_SUITE" ||
  fail "the assertion that response_bytes exceeds the body bytes (proving the counter moves and includes headers) is gone"
grep -q 'pre.responses_sent, 0' "$URUQUIM_SUITE" ||
  fail "the no-server-returns-zero assertion is gone; the accessor must be safe before any server runs"

env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/h3-server-stats" \
  "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
  "-out:$URUQUIM_TMP/h3"

echo "h3: Server_Stats has no string field (redaction by construction)"
echo "h3: all four backend send counters are wired (patch 28), not decorative"
echo "h3: web.stats() counts real responses and is zero before any server runs"
echo "PASS: H-3 write-observability controls"
