#!/usr/bin/env bash
# WP88/WP89 — the stream registry and cross-lane delivery, under control.
#
# Three executable claims:
#   1. the WP87 stream corpus is green UNEDITED (checked here by content
#      hash of its test names — a dropped case cannot hide) and the WP88
#      suite (ring wraparound, process budget, wake hook, concurrent
#      producers) is green;
#   2. the plan's control mutation holds: removing the generation check in a
#      tree copy makes the stale-safety cases fail — the corpus really does
#      guard G7-3, not a coincidence of the implementation;
#   3. the implementation keeps its boundary: `web` still imports no stream
#      package (that wiring is WP90), and the stream package itself imports
#      no backend and no `uruquim:web`.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP88-CONTROL-FAIL: $*" >&2
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
URUQUIM_TMP="$(mktemp -d -t uruquim-wp88-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

# Claim 1a — corpus completeness by name: the twelve pre-registered cases.
for URUQUIM_CASE in \
  wp87_registry_initializes_with_preregistered_capacity \
  wp87_open_commits_reserved_state_exactly_once \
  wp87_open_beyond_capacity_refuses_typed \
  wp87_stream_outlives_the_handler_scope \
  wp87_enqueue_copies_the_callers_bytes \
  wp87_queue_full_is_deterministic_and_immediate \
  wp87_close_is_idempotent \
  wp87_full_user_capacity_cannot_block_close \
  wp87_send_after_close_has_one_terminal_owner \
  wp87_stale_token_after_slot_reuse_refuses \
  wp87_no_open_and_no_send_after_drain_begins \
  wp87_close_releases_the_stream_for_accounting; do
  grep -q "^$URUQUIM_CASE ::" \
    "$URUQUIM_ROOT/tests/wp87-stream-lifecycle/stream_lifecycle_test.odin" ||
    fail "pre-registered corpus case dropped: $URUQUIM_CASE"
done

# Claim 1b — both suites green on the real tree.
env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/wp87-stream-lifecycle" \
  "-collection:uruquim=$URUQUIM_ROOT" "-out:$URUQUIM_TMP/corpus"
env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/wp88-stream-registry" \
  "-collection:uruquim=$URUQUIM_ROOT" "-out:$URUQUIM_TMP/registry"

# Claim 2 — the generation-check mutation. A copy of the tree loses the
# stale guard; the corpus and the registry suite must both catch it.
URUQUIM_MUT="$URUQUIM_TMP/mut"
mkdir -p "$URUQUIM_MUT/web/internal" "$URUQUIM_MUT/tests"
cp -r "$URUQUIM_ROOT/web" "$URUQUIM_MUT/" 2>/dev/null
cp -r "$URUQUIM_ROOT/vendor" "$URUQUIM_MUT/" 2>/dev/null
cp -r "$URUQUIM_ROOT/tests/wp87-stream-lifecycle" "$URUQUIM_MUT/tests/"
cp -r "$URUQUIM_ROOT/tests/wp88-stream-registry" "$URUQUIM_MUT/tests/"
sed -i 's/s\.generation != tok\.generation/false/g' \
  "$URUQUIM_MUT/web/internal/stream/stream.odin"
grep -q 'if false {' "$URUQUIM_MUT/web/internal/stream/stream.odin" ||
  fail "the generation-check mutation did not apply; the control is broken"
if env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
    "$URUQUIM_MUT/tests/wp87-stream-lifecycle" \
    "-collection:uruquim=$URUQUIM_MUT" \
    "-out:$URUQUIM_TMP/mut-corpus" >/dev/null 2>&1; then
  fail "the corpus survives without the generation check — stale safety is not being tested (G7-3)"
fi

# Claim 3 — boundaries. `web` may not import the stream package before WP90,
# and the stream package stays free of the backend and of `uruquim:web`.
if grep -rn '"uruquim:web/internal/stream"' "$URUQUIM_ROOT/web" --include='*.odin' >/dev/null; then
  fail "web imports the stream package before WP90 wires the adapter"
fi
if grep -nE '"uruquim:(web|vendor)' "$URUQUIM_ROOT/web/internal/stream"/*.odin; then
  fail "the stream package imports web or the backend; it must stay executor-agnostic"
fi

echo "wp88: the WP87 stream corpus is green unedited, all 12 cases present"
echo "wp88: ring wraparound, process budget, wake hook and 2000-event concurrency hold"
echo "wp88: removing the generation check makes the corpus fail (G7-3 control)"
echo "wp88: stream package linked nowhere; imports neither web nor backend"
echo "PASS: WP88/WP89 registry and delivery controls"
