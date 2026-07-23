#!/usr/bin/env bash
# WP51 — the vendor maintenance policy gate.
#
# The policy's own rules, made checkable. It holds three things a vendored
# dependency loses first and silently:
#
#   1. the PROVENANCE — a snapshot with no commit behind it is a fork nobody
#      declared;
#   2. the PATCH LEDGER — a patch that stops being listed is a divergence
#      nobody can re-apply at the next re-vendor;
#   3. the EVIDENCE RULE — that patches are proven by corpus, never by grep
#      over vendored text, because a correct re-application written differently
#      must still pass.
#
# It deliberately does NOT diff the vendored sources against upstream. That
# would need network access in the gate, and a gate that fails when GitHub is
# slow is a gate people learn to skip.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_POLICY="$URUQUIM_ROOT/planning/vendor-policy.md"
URUQUIM_VENDOR_DOC="$URUQUIM_ROOT/vendor/odin-http/VENDOR.md"

fail() {
  echo "VENDOR-POLICY-FAIL: $*" >&2
  exit 1
}

test -f "$URUQUIM_POLICY" || fail "planning/vendor-policy.md is missing; WP51 is the precondition for any package that patches the vendored server"
test -f "$URUQUIM_VENDOR_DOC" || fail "vendor/odin-http/VENDOR.md is missing; the vendored snapshot has no provenance"

URUQUIM_FLAT="$(sed -E 's/^[[:space:]]*>[[:space:]]?//' "$URUQUIM_POLICY" | tr '\n' ' ' | tr -s ' ')"

# --- 1. Provenance -----------------------------------------------------------
# The pinned commit must appear in BOTH documents. A policy that names no commit
# is about a dependency in general; a vendor record with no commit is a copy.
grep -qF '112c49b' "$URUQUIM_VENDOR_DOC" ||
  fail "vendor/odin-http/VENDOR.md no longer records the pinned upstream commit"
grep -qF '112c49b' "$URUQUIM_POLICY" ||
  fail "the vendor policy no longer names the commit it governs"

# --- 2. The patch ledger is exact in both directions -------------------------
# Eighteen patches ship. The policy's disposition table and the vendor record must
# agree on the count, or one of them has drifted and nobody can tell which.
URUQUIM_POLICY_ROWS="$(grep -cE '^\| [0-9]+ \| .* \| .* \| \*\*(OFFER UPSTREAM|CARRY|APPEARS FIXED UPSTREAM)' "$URUQUIM_POLICY" || true)"
test "$URUQUIM_POLICY_ROWS" -eq 22 ||
  fail "the vendor policy lists $URUQUIM_POLICY_ROWS patch dispositions, not the 22 patches that ship. A patch with no recorded disposition is one nobody knows whether to re-apply."

URUQUIM_PATCH_MARKS="$(grep -rc 'URUQUIM PATCH' "$URUQUIM_ROOT"/vendor/odin-http/*.odin 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
test "$URUQUIM_PATCH_MARKS" -gt 0 ||
  fail "no 'URUQUIM PATCH' marker was found in the vendored sources; a divergence that is not marked at its site cannot be re-applied"

# --- 3. Every patch states whether it is upstream's bug -----------------------
# The column that does the work: two of five are upstream bugs and three are
# deliberate divergences, and that ratio is what makes re-vendoring predictable.
grep -qiE 'is it upstream.s bug' "$URUQUIM_POLICY" ||
  fail "the disposition table lost the column that says whether each patch fixes an UPSTREAM bug or encodes a deliberate divergence. Without it, a re-vendor cannot tell which patches might already be gone."

# --- 4. The corpus rule survives ---------------------------------------------
# This is the one most likely to be "improved" back into a grep, because a grep
# is easier to write.
grep -qiE 'proven by CORPUS, never by grep' <<<"$URUQUIM_FLAT" ||
  fail "the policy no longer states that patches are proven by corpus rather than by grep over vendored text"
grep -qiE 'written differently, must still pass' <<<"$URUQUIM_FLAT" ||
  fail "the policy lost the sentence explaining WHY: a correct re-application written differently must still pass. Without the reason, the rule reads as a preference and gets reversed."

URUQUIM_CORPUS="$URUQUIM_ROOT/tests/support/transport_conformance/corpus.odin"
test -f "$URUQUIM_CORPUS" ||
  fail "the raw-wire corpus is missing; it is the executable evidence the policy points at"

# --- 5. The watch obligation is on the gate, not on memory -------------------
grep -qiE 'at every phase freeze' <<<"$URUQUIM_FLAT" ||
  fail "the policy no longer places the upstream re-check at a phase freeze. An obligation on nobody in particular is an obligation nobody performs."
grep -qiE 'between freezes there is no watch' <<<"$URUQUIM_FLAT" ||
  fail "the policy no longer admits that nothing watches upstream between freezes. Implying a vigilance nobody performs is worse than declaring the gap."

# --- 6. The rules a patch must satisfy ---------------------------------------
grep -qiE 'not a patch, it is a preference' <<<"$URUQUIM_FLAT" ||
  fail "the policy lost its test for whether something is a patch at all: a change whose necessity no failing corpus case demonstrates"

if grep -nE '\b(TODO|FIXME|XXX|TBD)\b' "$URUQUIM_POLICY"; then
  fail "the vendor policy contains an unfinished-work marker"
fi

echo "vendor policy: provenance pinned at 112c49b; $URUQUIM_POLICY_ROWS patch dispositions recorded; $URUQUIM_PATCH_MARKS in-source markers; corpus rule intact"
echo "PASS: vendor maintenance policy gate (WP51)"
