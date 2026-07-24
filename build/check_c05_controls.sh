#!/usr/bin/env bash
# C-05 — combined saturation and the write-observability gap, under control.
#
# Four executable claims:
#
#   1. THE INSTRUMENT SURVIVES. The lab's whole value is that it tells the
#      refusal kinds APART — a 503 (the Handler lane) from a connected-then-EOF
#      (the admission budget) from a failed connect (the backlog). Collapse
#      those into "error" and the suite can no longer name a binding constraint,
#      which is the one thing it exists to do;
#   2. THE F-C05-1 FIX cannot be silently reverted: the accept-cancel wait stays
#      bounded, and it still refuses to reattach on expiry;
#   3. the measurement and the specification survive in the record — perimeter 7
#      was DEFERRED on condition that its API is specified and handed forward;
#   4. the lab is green, which now also means the server still shuts down.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_DOC="$URUQUIM_ROOT/planning/closure-saturation-and-write-observability.md"
URUQUIM_SUITE="$URUQUIM_ROOT/tests/c05-saturation/saturation_test.odin"
URUQUIM_SERVER="$URUQUIM_ROOT/vendor/odin-http/server.odin"

fail() {
  echo "C05-CONTROL-FAIL: $*" >&2
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
URUQUIM_TMP="$(mktemp -d -t uruquim-c05-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

test -f "$URUQUIM_DOC" || fail "planning/closure-saturation-and-write-observability.md is missing"
test -f "$URUQUIM_SUITE" || fail "tests/c05-saturation/saturation_test.odin is missing"

# --- 1. The instrument -------------------------------------------------------
for URUQUIM_KIND in Served Lane_Refused Admission_Refused Connect_Failed Timed_Out Malformed; do
  grep -q "$URUQUIM_KIND" "$URUQUIM_SUITE" ||
    fail "$(printf 'the saturation lab lost the outcome %s.\nThe six outcomes are the instrument: an admission refusal ACCEPTS the connection and then closes it unwritten, so a client that counts only "errors" cannot tell it from a backlog drop. Collapse them and the suite can no longer name which resource bound first.' "$URUQUIM_KIND")"
done
grep -q 'FIRST BINDING CONSTRAINT' "$URUQUIM_SUITE" ||
  fail "the lab no longer reports which resource bound first — that report IS the deliverable of perimeter 6"
grep -q 'total_malformed == 0' "$URUQUIM_SUITE" ||
  fail "the malformed-reply assertion is gone; under saturation every outcome must be one the design NAMES, and that assertion is the only thing checking it"

# --- 1b. H-4: every lane 503 carries Retry-After -----------------------------
grep -q 'total_lane_503_no_retry == 0' "$URUQUIM_SUITE" ||
  fail "the Retry-After assertion is gone. A 503 lane refusal that does not tell the client when to come back invites an immediate retry onto the same contended pool, which collides again. The ramp reliably produces 503s, so the property is checked over real refusals."
grep -q 'total_lane_503 > 0' "$URUQUIM_SUITE" ||
  fail "the assertion that the ramp actually produces a lane 503 is gone; without it the Retry-After check is vacuous"
grep -q 'Retry-After' "$URUQUIM_ROOT/web/internal/transport/odin_http_adapter.odin" ||
  fail "the lane-refusal 503 no longer sets Retry-After (H-4). The refusal path at dispatch_exchange must add the header before respond()."

# --- 2. The F-C05-1 fix ------------------------------------------------------
grep -q 'HANDLER_ACCEPT_CANCEL_WAIT' "$URUQUIM_SERVER" || fail "$(cat <<'EOF'
the accept-cancel wait in handler_lane_enter is unbounded again (vendored patch
27 / F-C05-1). That spin runs on the LANE THREAD: a lane parked in it never
returns to its event loop, never observes s.closing, never calls
_server_thread_shutdown — and serve waits on threads_closed for EVERY lane. So
one lane in the spin is a process that cannot be stopped, past max_drain_time,
which bounds the drain and cannot bound a lane that never reaches the drain.
Measured: 4 runs in 6 wedged on the unpatched tree, and web.stop did not return
in 60 s against a 3 s drain deadline.
EOF
)"
grep -q 'cancel_observed = false' "$URUQUIM_SERVER" ||
  fail "the accept-cancel wait no longer records that it gave up; without that flag it would reattach an operation record whose completion may still arrive, trading a wedge for a use-after-free"

# --- 3. The measurement and the specification --------------------------------
URUQUIM_FLAT="$(tr '\n' ' ' <"$URUQUIM_DOC" | tr -s ' ')"
grep -qi 'binding constraint is the Handler lane' <<<"$URUQUIM_FLAT" ||
  fail "the perimeter-6 finding is gone from the record. That the LANE binds first — and at four concurrent clients, far below the twenty-slot connection budget — is the result; without it an operator tunes max_connections, which is not the constraint."
grep -qi 'Server_Stats' <<<"$URUQUIM_FLAT" ||
  fail "the perimeter-7 API specification is gone. Shipping it was DEFERRED on the explicit condition that it is specified and handed forward; without the specification this is an unowned gap again."
grep -qi 'aborted_slow' <<<"$URUQUIM_FLAT" ||
  fail "the record no longer names the stream counters that exist internally and are reachable from no public API — the concrete half of the observability gap"

# --- 4. Green ----------------------------------------------------------------
env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/c05-saturation" \
  "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
  "-out:$URUQUIM_TMP/c05"

echo "c05: the six refusal outcomes stay distinguishable; the binding constraint is still reported"
echo "c05: the accept-cancel wait stays bounded and still refuses to reattach on expiry (F-C05-1)"
echo "c05: the perimeter-6 finding and the perimeter-7 Server_Stats specification are on record"
echo "PASS: C-05 combined-saturation and write-observability controls"
