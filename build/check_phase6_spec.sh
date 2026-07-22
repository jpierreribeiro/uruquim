#!/usr/bin/env bash
# WP66 — Phase-6 specification and governance gate.
#
# The phase has no implementation yet. Its deliverable is that the experiment
# cannot choose its own question, threshold or ownership boundary after seeing
# a result. This gate therefore pins the entry snapshot, owner amendments,
# liveness controls and one-way ecosystem dependency before WP67/WP69 begin.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_SPEC="$URUQUIM_ROOT/planning/phase-6-spec.md"
URUQUIM_PLAN="$URUQUIM_ROOT/planning/phase-6-plan.md"
URUQUIM_PROGRAM="$URUQUIM_ROOT/planning/phases-6-8-program.md"

fail() {
  echo "PHASE6-SPEC-FAIL: $*" >&2
  exit 1
}

for URUQUIM_FILE in \
  "$URUQUIM_SPEC" \
  "$URUQUIM_PLAN" \
  "$URUQUIM_PROGRAM" \
  "$URUQUIM_ROOT/planning/phase-7-plan.md" \
  "$URUQUIM_ROOT/planning/phase-8-plan.md"; do
  test -f "$URUQUIM_FILE" || fail "missing ${URUQUIM_FILE#"$URUQUIM_ROOT/"}"
done

URUQUIM_FLAT="$(tr '\n' ' ' < "$URUQUIM_SPEC" | tr -s ' ')"

# Entry is history. Later phases may grow the live ledger; the spec must keep
# saying what Phase 6 actually began from.
grep -q 'Phase 5 frozen at `6b6edbc`' "$URUQUIM_SPEC" ||
  fail "entry commit is not the Phase-5 freeze"
grep -q '62 application + 2' "$URUQUIM_SPEC" ||
  fail "entry ledger 62 + 2 is missing"
grep -q '\*\*Status:\*\* SPEC, 2026-07-21, WP66' "$URUQUIM_SPEC" ||
  fail "WP66 status is not normative SPEC"

# The work-package sequence cannot silently gain or lose a package.
test "$(grep -cE '^\| (6[6-9]|7[0-9]|8[0-4]) \|' "$URUQUIM_SPEC")" -eq 19 ||
  fail "the normative WP66-WP84 table does not contain exactly 19 packages"
test "$(grep -cE '^### WP(6[6-9]|7[0-9]|8[0-4]) ' "$URUQUIM_PLAN")" -eq 19 ||
  fail "the execution plan does not contain exactly WP66-WP84"
test "$(grep -cE '^### WP(8[5-9]|9[0-9]|10[01]) ' "$URUQUIM_ROOT/planning/phase-7-plan.md")" -eq 17 ||
  fail "the Phase-7 plan does not contain exactly WP85-WP101"
test "$(grep -cE '^### WP(10[2-9]|11[0-3]) ' "$URUQUIM_ROOT/planning/phase-8-plan.md")" -eq 12 ||
  fail "the Phase-8 plan does not contain exactly WP102-WP113"

# ADR-030 is reopened on a different experiment, without rewriting its old
# throughput result.
case "$URUQUIM_FLAT" in
  *"liveness, not throughput"*) ;;
  *) fail "ADR-030 is not explicitly reopened for liveness rather than throughput" ;;
esac
grep -q 'negative control, one lane' "$URUQUIM_SPEC" ||
  fail "the one-lane negative control is missing"
grep -q 'candidate, four lanes' "$URUQUIM_SPEC" ||
  fail "the four-lane candidate is missing"
grep -q 'three blocked Handlers' "$URUQUIM_SPEC" ||
  fail "the lanes-1 liveness condition is missing"
grep -q '250 ms' "$URUQUIM_SPEC" ||
  fail "the pre-registered liveness observation window is missing"
grep -q 'unblocked baseline is' "$URUQUIM_SPEC" ||
  fail "the invalid-environment baseline rule is missing"

# Database backpressure is a relationship, not a claim that threads make
# saturation disappear.
grep -q 'pool capacity of' "$URUQUIM_SPEC" ||
  fail "the database capacity control is missing"
grep -q 'configured 100 ms deadline' "$URUQUIM_SPEC" ||
  fail "bounded pool acquisition has no fixed lab deadline"
grep -q 'pool capacity < lane' "$URUQUIM_SPEC" ||
  fail "the control-capacity relationship is missing"
case "$URUQUIM_FLAT" in
  *"full saturation:"*"may prevent health progress"*) ;;
  *) fail "full lane saturation is no longer stated honestly" ;;
esac

# Core/ecosystem direction and SQL philosophy are owner decisions, not details
# an implementation WP may reverse for convenience.
grep -q 'CE-E3 remains intact' "$URUQUIM_SPEC" ||
  fail "CE-E3 is not preserved"
grep -q 'No server boot automatically migrates production' "$URUQUIM_SPEC" ||
  fail "the no-auto-migrate rule is missing"
grep -q 'explicit pre-serve application call' "$URUQUIM_PLAN" ||
  fail "the owner-approved in-band migration path is missing"
grep -q 'ahead-of-binary history refuses by default' "$URUQUIM_PLAN" ||
  fail "the ahead-of-binary migration refusal is missing"
grep -q 'expand-contract' "$URUQUIM_PLAN" ||
  fail "the forward-only expand-contract discipline is missing"
grep -q 'Directory SQL and' "$URUQUIM_ROOT/planning/adrs.md" ||
  fail "directory/embedded migration source parity is missing"
grep -q 'No row mismatch becomes a' "$URUQUIM_SPEC" ||
  fail "fail-closed row decoding is missing"
case "$URUQUIM_FLAT" in
  *"invents no compatibility shim"*) ;;
  *) fail "the unreleased official adapter is being treated as an invented API" ;;
esac

# The plain-language owner record and permanent ADR record must agree.
grep -q 'Fase 6 é a classe “primeira aplicação real”' \
  "$URUQUIM_ROOT/planning/decisoes-do-dono.md" ||
  fail "owner scope amendment is absent"
grep -q 'ADR-030 — Amendment 1: reopened for blocking-I/O liveness' \
  "$URUQUIM_ROOT/planning/adrs.md" ||
  fail "ADR-030 liveness amendment is absent"
grep -q 'ADR-035 — first-real-application work may precede external demand' \
  "$URUQUIM_ROOT/planning/adrs.md" ||
  fail "ADR-035 is absent"
grep -q 'ADR-036 — SQL-first data stack outside `web`' \
  "$URUQUIM_ROOT/planning/adrs.md" ||
  fail "ADR-036 is absent"

# The old backlog and roadmap were the two places most likely to silently
# restore the contradicted rules.
grep -q 'Phase 6 — Real applications' "$URUQUIM_ROOT/planning/roadmap.md" ||
  fail "roadmap has no Phase-6 section"
grep -q 'Phase 7 — Streaming foundation' "$URUQUIM_ROOT/planning/roadmap.md" ||
  fail "roadmap has no Phase-7 section"
grep -q 'Phase 8 — Proof by use' "$URUQUIM_ROOT/planning/roadmap.md" ||
  fail "roadmap has no Phase-8 section"
grep -q 'PHASE 6 CRYSTALS; STILL REJECTED FOR CORE' \
  "$URUQUIM_ROOT/planning/later-phases-plan.md" ||
  fail "database work is not reconciled as Phase-6 Crystals"
grep -q 'PHASE 7, SPLIT OWNERSHIP' \
  "$URUQUIM_ROOT/planning/later-phases-plan.md" ||
  fail "streaming is not reconciled as the Phase-7 split boundary"

# Phase 7 must solve the limitation Phase 5 recorded, while preserving the
# simple buffered path. Server push alone is no longer the approved plan.
grep -q 'opt-in large-body contract' "$URUQUIM_ROOT/planning/phase-7-plan.md" ||
  fail "Phase 7 lost inbound large-body work"
grep -q 'large multipart never requires RAM proportional' \
  "$URUQUIM_ROOT/planning/phase-7-plan.md" ||
  fail "Phase 7 has no bounded-memory large-upload exit gate"
grep -q 'buffered-only application links no stream' \
  "$URUQUIM_ROOT/planning/phase-7-plan.md" ||
  fail "Phase 7 lost the common-path cost control"

if grep -qE '^- \[ \]' "$URUQUIM_SPEC"; then
  fail "the Phase-6 spec contains an unchecked item"
fi

echo "phase-6 spec: entry 6b6edbc, ledger 62 + 2, WP66-WP84"
echo "phase-6 spec: liveness controls and bounded database capacity are pre-registered"
echo "phase-6 spec: SQL-first Crystals remain one-way; official adapter API is not guessed"
echo "phase-6 program: WP85-WP101 and WP102-WP113 are numbered and bounded"
echo "PASS: WP66 Phase-6 spec and governance gate"
