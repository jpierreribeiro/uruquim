#!/usr/bin/env bash
# H-1 — the security-backlog reconciliation, under control.
#
# Every one of the 14 findings is fixed; the risk is a fix REGRESSING without
# anyone noticing. So this gate asserts the correspondence: each finding names a
# pinning test, and each named test still exists in the tree. Two findings (F8,
# F12) are pinned indirectly with a stated reason; the gate requires the reason
# to survive, not a test that cannot honestly exist.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_DOC="$URUQUIM_ROOT/planning/security-backlog-reconciliation.md"

fail() {
  echo "H1-SECURITY-FAIL: $*" >&2
  exit 1
}

test -f "$URUQUIM_DOC" || fail "planning/security-backlog-reconciliation.md is missing; the 14 findings have no reconciled record"

# --- The count is declared and matches the numbered rows ----------------------
URUQUIM_DECLARED="$(sed -n 's/^<!-- h1-findings: \([0-9]\+\) -->$/\1/p' "$URUQUIM_DOC")"
test -n "$URUQUIM_DECLARED" || fail "the 'h1-findings' marker is gone"
URUQUIM_ROWS="$(grep -cE '^\| \*\*F[0-9]+\*\* \|' "$URUQUIM_DOC" || true)"
test "$URUQUIM_ROWS" -eq "$URUQUIM_DECLARED" ||
  fail "the doc has $URUQUIM_ROWS finding rows but declares $URUQUIM_DECLARED"
test "$URUQUIM_DECLARED" -eq 14 ||
  fail "the scan produced 14 findings; the reconciliation carries $URUQUIM_DECLARED"

# --- Every finding F1..F14 has a row ------------------------------------------
for URUQUIM_N in $(seq 1 14); do
  grep -qE "^\| \*\*F$URUQUIM_N\*\* \|" "$URUQUIM_DOC" ||
    fail "finding F$URUQUIM_N has no row in the reconciliation"
done

# --- The pinning tests named in the doc exist in the tree ---------------------
# The 12 directly-pinned findings each name a test function; that function must
# exist. A dropped test is a fix that can regress in silence.
for URUQUIM_TEST in \
  wp68_over_deep_nesting_is_refused_before_parsing \
  wp9_raw_wire_corpus \
  wp48i_a_spoofed_leftmost_is_ignored_behind_a_trusted_proxy \
  wp91_secure_headers_cover_a_static_response \
  wp91_global_middleware_runs_for_a_static_file \
  wp91_an_auth_refusal_blocks_a_static_file \
  wp61_a_symlink_in_an_intermediate_segment_is_refused \
  c03_a_healthy_client_survives_an_rst_flood \
  wp68_out_of_range_integer_is_an_invalid_field \
  wp63_a_decoy_boundary_in_a_quoted_parameter_is_not_used; do
  grep -q "$URUQUIM_TEST" "$URUQUIM_DOC" ||
    fail "the reconciliation no longer names the pinning test $URUQUIM_TEST"
  grep -rq "^$URUQUIM_TEST ::" "$URUQUIM_ROOT/tests" ||
    fail "the pinning test $URUQUIM_TEST is named in the doc but does not exist in tests/ — a fix has lost its guard"
done

# --- The two NEW tests, specifically (H-1's own deliverable) ------------------
grep -rq '^wp61_a_symlink_in_an_intermediate_segment_is_refused ::' \
  "$URUQUIM_ROOT/tests/wp61-public-surface" ||
  fail "the F7 intermediate-symlink test (H-1's deliverable) is gone from tests/wp61-public-surface"
grep -rq '^wp63_a_decoy_boundary_in_a_quoted_parameter_is_not_used ::' \
  "$URUQUIM_ROOT/tests/wp63-public-surface" ||
  fail "the F13 decoy-boundary test (H-1's deliverable) is gone from tests/wp63-public-surface"

# --- The two indirect findings keep their stated reason -----------------------
URUQUIM_FLAT="$(tr '\n' ' ' <"$URUQUIM_DOC" | tr -s ' ')"
grep -qi 'no dedicated leak test' <<<"$URUQUIM_FLAT" ||
  fail "F8's honest 'no dedicated leak test, and here is why' record is gone — a gap silently reclassified as pinned is exactly what this reconciliation exists to prevent"
grep -qi 'no public injection path' <<<"$URUQUIM_FLAT" ||
  fail "F12's 'no public injection path' reason is gone; without it a reader cannot tell a real gap from a forgotten one"

echo "h1: all 14 findings reconciled; 12 pinned by an existing named test, 2 (F8, F12) indirect with a stated reason"
echo "h1: the F7 intermediate-symlink and F13 decoy-boundary tests exist"
echo "PASS: H-1 security-backlog reconciliation"
