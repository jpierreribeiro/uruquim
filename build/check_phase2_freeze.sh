#!/usr/bin/env bash
# Phase-2 freeze gate — the CLAIMS, not only the API.
#
# `check_phase1_freeze.sh` freezes symbols, signatures and dependencies. This
# script freezes the project's own SENTENCES, which Phase 1 did not, and which
# the reference study argues is the gap that closes last: prose has no compiler, so
# it drifts while every test stays green. Uruquim has already lived a small
# version of that — WP21 found three documents still promising a "panic
# recovery (Phase 2)" that ADR-020 had made impossible.
#
# It enforces the three ledgers the owner accepted in docket D-2:
#
#   1. CLAIM ledger    — every strong promise carries a NEGATIVE control and an
#                        explicit statement of what it does NOT guarantee. A
#                        claim without a negative control does not freeze.
#   2. LIFETIME ledger — owner / validity / may-it-escape / cleanup, one row per
#                        value a user can touch.
#   3. CAPACITY ledger — fixed, dynamic-at-registration, bounded-per-request,
#                        and — the column that keeps the word honest — what
#                        remains UNBOUNDED or delegated to the transport.
#
# The rule this gate exists to hold: "bounded" is never claimed for the
# framework as a whole while connections, queues and header counts belong to
# the transport. Name the perimeter, or do not use the word.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_P2="$URUQUIM_ROOT/planning/phase-2-freeze.md"

fail() {
  echo "PHASE2-FREEZE-FAIL: $*" >&2
  exit 1
}

test -f "$URUQUIM_P2" ||
  fail "planning/phase-2-freeze.md does not exist; Phase 2 cannot be frozen without it (WP25)"

# ---------------------------------------------------------------------------
# 1. The ledger counts agree with the CANONICAL source.
#
# Read out of check_public_api.sh rather than restated, so the freeze document
# cannot drift from the package while both still look green — the same
# technique check_docs.sh uses.
# ---------------------------------------------------------------------------
URUQUIM_APP_COUNT="$(grep -oE 'URUQUIM_APP_COUNT" -ne [0-9]+' "$URUQUIM_ROOT/build/check_public_api.sh" |
  grep -oE '[0-9]+$' | head -1)"
URUQUIM_UNION_COUNT="$(grep -oE 'URUQUIM_UNION" -ne [0-9]+' "$URUQUIM_ROOT/build/check_public_api.sh" |
  grep -oE '[0-9]+$' | head -1)"
test -n "$URUQUIM_APP_COUNT" && test -n "$URUQUIM_UNION_COUNT" ||
  fail "could not read the canonical ledger counts out of build/check_public_api.sh"

# WHAT THIS DOCUMENT'S NUMBERS ARE, and WP34 is the work package that forced the
# distinction. The table records what Phase 2 FROZE — 32 + 12 = 44 — which is a
# historical fact and must not move when a later phase adds a symbol. The
# original check compared it against the LIVE canonical count, which was
# indistinguishable from correct for as long as no phase grew the ledger after
# Phase 2, and went red the moment one did. A freeze document that has to be
# edited every time a later phase ships is not a freeze.
#
# So the anti-drift force is kept and re-aimed. Three assertions:
#
#   * the recorded Phase-2 totals are exactly the frozen 44 and 46 — the doc
#     cannot be quietly restated;
#   * its own arithmetic holds (32 + delta = total, 34 + delta = union), so a
#     hand-edited delta fails;
#   * the LIVE ledger is >= the frozen total. Phase 3 may add; nothing may
#     silently remove a symbol Phase 2 froze and leave this document claiming it.
URUQUIM_P2_APP=44
URUQUIM_P2_UNION=46

grep -qE "\| application \| 32 \| \+[0-9]+ \| \*\*$URUQUIM_P2_APP\*\* \|" "$URUQUIM_P2" ||
  fail "the freeze document no longer records the ledger Phase 2 froze ($URUQUIM_P2_APP application). That number is history, not a live measurement: it must not be edited to track a later phase."
grep -qE "\| union \| 34 \| \+[0-9]+ \| \*\*$URUQUIM_P2_UNION\*\* \|" "$URUQUIM_P2" ||
  fail "the freeze document no longer records the union Phase 2 froze ($URUQUIM_P2_UNION)"

URUQUIM_P2_DELTA="$(grep -oE "\| application \| 32 \| \+[0-9]+ \|" "$URUQUIM_P2" | grep -oE '[0-9]+ \|$' | grep -oE '[0-9]+')"
test "$(( 32 + URUQUIM_P2_DELTA ))" -eq "$URUQUIM_P2_APP" ||
  fail "the freeze document's own arithmetic does not hold: 32 + $URUQUIM_P2_DELTA is not $URUQUIM_P2_APP"
URUQUIM_P2_UNION_DELTA="$(grep -oE "\| union \| 34 \| \+[0-9]+ \|" "$URUQUIM_P2" | grep -oE '[0-9]+ \|$' | grep -oE '[0-9]+')"
test "$(( 34 + URUQUIM_P2_UNION_DELTA ))" -eq "$URUQUIM_P2_UNION" ||
  fail "the freeze document's own arithmetic does not hold: 34 + $URUQUIM_P2_UNION_DELTA is not $URUQUIM_P2_UNION"

test "$URUQUIM_APP_COUNT" -ge "$URUQUIM_P2_APP" ||
  fail "the live application ledger is $URUQUIM_APP_COUNT, BELOW the $URUQUIM_P2_APP Phase 2 froze. A frozen symbol was removed while this document still claims it."
test "$URUQUIM_UNION_COUNT" -ge "$URUQUIM_P2_UNION" ||
  fail "the live exported union is $URUQUIM_UNION_COUNT, below the $URUQUIM_P2_UNION Phase 2 froze"

echo "phase-2 freeze: ledger diff records the frozen $URUQUIM_P2_APP application / $URUQUIM_P2_UNION union; the live ledger is $URUQUIM_APP_COUNT / $URUQUIM_UNION_COUNT and has not shrunk"

# ---------------------------------------------------------------------------
# 2. CLAIM ledger — every claim carries a negative control.
#
# This is the assertion that does the real work. A claim with a positive test
# and no negative control is a claim nobody has tried to break.
# ---------------------------------------------------------------------------
grep -qE '^## ([0-9]+\. )?Claim ledger' "$URUQUIM_P2" || fail "the freeze document has no claim ledger (D-2)"

URUQUIM_CLAIMS="$(grep -cE '^### C-[0-9]+' "$URUQUIM_P2" || true)"
test "$URUQUIM_CLAIMS" -ge 5 ||
  fail "the claim ledger holds only $URUQUIM_CLAIMS claims; the project makes more strong promises than that"

# Each claim section must carry all four load-bearing fields. Checked per
# section, not per document: a single negative control somewhere would
# otherwise satisfy a table full of unverified claims.
URUQUIM_MISSING_CONTROL=0
while IFS= read -r URUQUIM_CLAIM; do
  URUQUIM_SECTION="$(awk -v id="$URUQUIM_CLAIM" '
    $0 ~ "^### " id " " { on = 1; next }
    on && /^### |^## / { exit }
    on { print }
  ' "$URUQUIM_P2")"

  for URUQUIM_FIELD in 'Negative control' 'Does NOT guarantee' 'Positive test'; do
    grep -qF "$URUQUIM_FIELD" <<<"$URUQUIM_SECTION" || {
      echo "    $URUQUIM_CLAIM has no '$URUQUIM_FIELD' entry" >&2
      URUQUIM_MISSING_CONTROL=$(( URUQUIM_MISSING_CONTROL + 1 ))
    }
  done
done < <(grep -oE '^### C-[0-9]+' "$URUQUIM_P2" | sed 's/^### //')

test "$URUQUIM_MISSING_CONTROL" -eq 0 ||
  fail "$URUQUIM_MISSING_CONTROL claim field(s) are missing. A claim with no negative control does not freeze (D-2): it is a promise nobody has tried to break."
echo "phase-2 freeze: claim ledger -> $URUQUIM_CLAIMS claims, each with a positive test, a negative control and a stated non-guarantee"

# Every evidence citation in the freeze document must resolve, exactly as the
# Phase-1 manifest's do. A claim pointing at a test that does not exist is
# worse than no claim.
URUQUIM_BAD_REFS=0
while IFS= read -r URUQUIM_REF; do
  [ -n "$URUQUIM_REF" ] || continue
  test -e "$URUQUIM_ROOT/$URUQUIM_REF" || {
    echo "    broken citation: $URUQUIM_REF (no such file)" >&2
    URUQUIM_BAD_REFS=$(( URUQUIM_BAD_REFS + 1 ))
  }
done < <(grep -oE '(build|tests|web|docs|planning|examples)/[A-Za-z0-9_./-]+\.(sh|odin|md|txt)' "$URUQUIM_P2" |
  LC_ALL=C sort -u)
test "$URUQUIM_BAD_REFS" -eq 0 ||
  fail "$URUQUIM_BAD_REFS citation(s) in the freeze document do not resolve"
echo "phase-2 freeze: every claim citation resolves to a real file"

# ---------------------------------------------------------------------------
# 3. LIFETIME ledger — the four questions, again, in the frozen record.
# ---------------------------------------------------------------------------
grep -qE '^## ([0-9]+\. )?Lifetime ledger' "$URUQUIM_P2" || fail "the freeze document has no lifetime ledger (D-2)"
for URUQUIM_COLUMN in 'Owner' 'Valid until' 'May it escape' 'Who cleans up'; do
  grep -qF "$URUQUIM_COLUMN" "$URUQUIM_P2" ||
    fail "the lifetime ledger is missing the '$URUQUIM_COLUMN' question"
done
grep -qiE 'only .Framework_Event. may escape' "$URUQUIM_P2" ||
  fail "the lifetime ledger does not state the one-sentence rule (only Framework_Event may escape a request)"
echo "phase-2 freeze: lifetime ledger -> four questions present, one-sentence rule stated"

# ---------------------------------------------------------------------------
# 4. CAPACITY ledger — and the honest word.
#
# The unbounded column is the whole point. A capacity ledger that lists only
# what IS bounded is marketing.
# ---------------------------------------------------------------------------
grep -qE '^## ([0-9]+\. )?Capacity ledger' "$URUQUIM_P2" || fail "the freeze document has no capacity ledger (D-2)"
for URUQUIM_SECTION in 'Fixed at compile time' 'Dynamic at registration' 'Bounded per request' 'Unbounded, or delegated'; do
  grep -qF "$URUQUIM_SECTION" "$URUQUIM_P2" ||
    fail "the capacity ledger is missing its '$URUQUIM_SECTION' section; all four perimeters must be named"
done

# The things this framework does NOT bound must be named, by name. Each of
# these belongs to the transport, and each is a way "bounded" could become a
# lie if it stopped being written down.
for URUQUIM_UNBOUNDED in 'concurrent connections' 'backlog' 'header count'; do
  grep -qiF "$URUQUIM_UNBOUNDED" "$URUQUIM_P2" ||
    fail "the capacity ledger does not name '$URUQUIM_UNBOUNDED' as unbounded/delegated; the honest word depends on saying so"
done

grep -qiE 'does not bound the server|not bound(ed)? by this framework' "$URUQUIM_P2" ||
  fail "the capacity ledger never states which perimeter is NOT bounded (D-2)"
echo "phase-2 freeze: capacity ledger -> four perimeters, and the unbounded ones named"

# ---------------------------------------------------------------------------
# 5. No document may claim the framework as a whole is "bounded".
#
# The rule stated as a scan. "bounded" is fine beside a named perimeter (a
# buffer, a request, a body); it is not fine as a property of the framework or
# the server.
# ---------------------------------------------------------------------------
for URUQUIM_DOC in "$URUQUIM_ROOT/README.md" "$URUQUIM_ROOT"/docs/*.md; do
  test -f "$URUQUIM_DOC" || continue
  if grep -niE '(uruquim|the framework|the server) (is|are) (fully )?bounded' "$URUQUIM_DOC"; then
    fail "$(basename "$URUQUIM_DOC") claims the framework/server as a whole is bounded; name the perimeter (D-2 capacity ledger)"
  fi
done
echo "phase-2 freeze: no document claims the framework as a whole is bounded"

# ---------------------------------------------------------------------------
# 6. The usage-laboratory finding must survive.
#
# A concept-count increase is a FINDING, not a footnote, and a later edit that
# quietly drops it turns an honest report into a flattering one.
# ---------------------------------------------------------------------------
grep -qE '^## ([0-9]+\. )?Usage laboratory, re-run' "$URUQUIM_P2" ||
  fail "the freeze document does not re-run the usage laboratory (WP25)"
# Anchored to the SECTION's own heading, not to the words "is a finding": the
# document quotes the plan's "that is a finding, not a footnote" earlier on, and
# a looser pattern matched that quotation while the actual finding had been
# softened away. A control caught exactly that.
grep -qF 'The finding, stated as a finding.' "$URUQUIM_P2" ||
  fail "the usage-laboratory section no longer reports its concept growth AS A FINDING; quoting the rule is not the same as obeying it"
echo "phase-2 freeze: usage laboratory re-run, concept growth reported as a finding"

echo "PASS: Phase 2 freeze gate (claims, lifetimes and capacities, not only the API)"
