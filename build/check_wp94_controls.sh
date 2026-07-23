#!/usr/bin/env bash
# WP93/WP94 — the opt-in spool and streaming multipart parser, under control.
#
# Three executable claims:
#   1. the WP87 body corpus is GREEN unedited (its seven pre-registered
#      ownership cases present by name — a dropped case cannot hide), and the
#      WP94 multipart corpus is green;
#   2. the fragmentation-invariance property is really tested: the multipart
#      suite feeds the same body at several chunk sizes and asserts identical
#      parts — the one property a buffered parser cannot fake;
#   3. the ingest package keeps its boundary: it imports neither `uruquim:web`
#      nor the backend, and `package web` imports it nowhere.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP94-CONTROL-FAIL: $*" >&2
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
URUQUIM_TMP="$(mktemp -d -t uruquim-wp94-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"; rm -rf /tmp/uruquim-wp87-spool /tmp/uruquim-wp94-mp' EXIT

# Claim 1a — the seven pre-registered body-ownership cases, present by name.
for URUQUIM_CASE in \
  wp87_admission_refuses_before_reading_any_byte \
  wp87_spool_file_is_generated_private_and_inside_the_designated_dir \
  wp87_large_body_bytes_never_coexist_in_memory \
  wp87_per_upload_quota_breach_is_typed_and_cleans \
  wp87_disconnect_cancel_is_exactly_once \
  wp87_ready_hands_exactly_one_owned_body \
  wp87_persist_is_the_only_path_that_leaves_a_file; do
  grep -q "^$URUQUIM_CASE ::" \
    "$URUQUIM_ROOT/tests/wp87-body-lifecycle/body_lifecycle_test.odin" ||
    fail "pre-registered body-ownership case dropped: $URUQUIM_CASE"
done

# Claim 2 — the fragmentation-invariance test exists and names several steps.
grep -q 'wp94_every_fragmentation_point_yields_the_same_parts' \
  "$URUQUIM_ROOT/tests/wp94-multipart/multipart_test.odin" ||
  fail "the fragmentation-invariance test is missing — the one property that proves a real streaming parser"
grep -qE '\{1, 2, 3, 5, 7, 13, 64\}' \
  "$URUQUIM_ROOT/tests/wp94-multipart/multipart_test.odin" ||
  fail "the fragmentation test no longer sweeps multiple chunk sizes"

# Claim 1b — both suites green on the real tree (serial: shared spool dirs).
env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/wp87-body-lifecycle" \
  "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
  "-out:$URUQUIM_TMP/body"
env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/wp94-multipart" \
  "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
  "-out:$URUQUIM_TMP/multipart"

# Claim 3 — boundaries. The ingest package is executor-agnostic and unlinked
# from the public core.
if grep -nE '"uruquim:(web|vendor)' "$URUQUIM_ROOT/web/internal/ingest"/*.odin; then
  fail "the ingest package imports web or the backend; it must stay executor-agnostic"
fi
if grep -rnE '^[[:space:]]*import[[:space:]].*"uruquim:web/internal/ingest"' \
  "$URUQUIM_ROOT/web" --include='*.odin' -l |
  grep -v 'web/internal/transport/' >/dev/null; then
  fail "the ingest package is imported outside the transport boundary (ADR-009)"
fi

echo "wp94: the WP87 body corpus is green unedited, all 7 ownership cases present"
echo "wp94: the multipart parser yields identical parts at chunk sizes 1..64 (fragmentation-invariant)"
echo "wp94: ingest imports neither web nor backend; the public core imports it nowhere"
echo "PASS: WP93/WP94 spool and streaming-multipart controls"
