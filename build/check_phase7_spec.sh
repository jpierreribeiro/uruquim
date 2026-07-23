#!/usr/bin/env bash
# WP85 — Phase-7 specification and governance gate.
#
# The phase has no implementation yet. Its deliverable is that the streaming
# experiments cannot choose their own thresholds, ownership rules or refusal
# policies after seeing a result. This gate pins the entry snapshot, the two
# orthogonal contracts, the pre-registered capacity/backpressure numbers, the
# sync/async tie-in, the inherited ADR-039 work and the ADR reopenings before
# WP86 builds a prototype.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_SPEC="$URUQUIM_ROOT/planning/phase-7-spec.md"
URUQUIM_PLAN="$URUQUIM_ROOT/planning/phase-7-plan.md"
URUQUIM_ADRS="$URUQUIM_ROOT/planning/adrs.md"
URUQUIM_OQ="$URUQUIM_ROOT/planning/open-questions.md"

fail() {
  echo "PHASE7-SPEC-FAIL: $*" >&2
  exit 1
}

for URUQUIM_FILE in \
  "$URUQUIM_SPEC" \
  "$URUQUIM_PLAN" \
  "$URUQUIM_ADRS" \
  "$URUQUIM_OQ" \
  "$URUQUIM_ROOT/planning/production-service-bom.md" \
  "$URUQUIM_ROOT/planning/sync-async-evaluation.md"; do
  test -f "$URUQUIM_FILE" || fail "missing ${URUQUIM_FILE#"$URUQUIM_ROOT/"}"
done

URUQUIM_FLAT="$(tr '\n' ' ' < "$URUQUIM_SPEC" | tr -s ' ')"

# Entry is history: the spec must keep saying what Phase 7 actually began from.
grep -q '\*\*Status:\*\* SPEC, 2026-07-23, WP85' "$URUQUIM_SPEC" ||
  fail "WP85 status is not normative SPEC"
grep -q 'anchored at `f51fc127`' "$URUQUIM_SPEC" ||
  fail "entry anchor is not the Phase-6 concurrency freeze"
case "$URUQUIM_FLAT" in
  *"63 application + 2 test-support = 65"*) ;;
  *) fail "entry ledger 63 + 2 = 65 is missing" ;;
esac
grep -q '+5,472 bytes' "$URUQUIM_SPEC" ||
  fail "the measured Phase-6 base cost is not carried"
grep -q 'not preemption of arbitrary blocking code' "$URUQUIM_SPEC" ||
  fail "the honest non-preemption limitation is not quoted"
grep -q '`max_drain_time` remains the single honest process' "$URUQUIM_SPEC" ||
  fail "the one-process-deadline rule is missing"

# Two orthogonal contracts, never one magic stream.
case "$URUQUIM_FLAT" in
  *"two orthogonal contracts"*) ;;
  *) fail "the two-contract product decision is missing" ;;
esac
case "$URUQUIM_FLAT" in
  *"fuses them into a single public \"stream\" concept fails this spec"*) ;;
  *) fail "the anti-fusion rule is missing" ;;
esac

# The required state machines, with ownership named per transition.
grep -q 'Reserved → Headers_Committed → Open → Closing → Closed' "$URUQUIM_SPEC" ||
  fail "the response-stream state machine is missing"
grep -q 'Reading → In_Memory | Streaming | Spooling → Ready → Consumed → Released' "$URUQUIM_SPEC" ||
  fail "the inbound-body state machine is missing"
case "$URUQUIM_FLAT" in
  *"generation invalidated **before** queued items are released"*) ;;
  *) fail "the close-before-release generation rule is missing" ;;
esac

# Pre-registered capacity/backpressure numbers. Changing one after a result
# requires a dated amendment; deleting one must break this gate.
grep -q '| open streams per process | 1,024' "$URUQUIM_SPEC" ||
  fail "the open-streams cap is not pre-registered"
grep -q '| queued events per stream | 64 |' "$URUQUIM_SPEC" ||
  fail "the per-stream event cap is not pre-registered"
grep -q '| queued bytes per stream | 256 KiB |' "$URUQUIM_SPEC" ||
  fail "the per-stream byte cap is not pre-registered"
grep -q '| total queued stream bytes | 16 MiB per process |' "$URUQUIM_SPEC" ||
  fail "the process byte cap is not pre-registered"
grep -q 'canonical full result is \*\*refusal on' "$URUQUIM_SPEC" ||
  fail "the canonical full result is not refusal"
case "$URUQUIM_FLAT" in
  *"user sends can NEVER consume the capacity needed to deliver close/stop"*) ;;
  *) fail "the control-capacity reservation is missing" ;;
esac
grep -q '`handler lanes − 1`, floor 1' "$URUQUIM_SPEC" ||
  fail "the concurrent-spool admission cap is not pre-registered"
grep -q '| per-upload spool quota | 1 GiB |' "$URUQUIM_SPEC" ||
  fail "the per-upload quota is not pre-registered"
grep -q '| process-wide spool quota | 8 GiB |' "$URUQUIM_SPEC" ||
  fail "the process spool quota is not pre-registered"
grep -q 'uruquim-spool-' "$URUQUIM_SPEC" ||
  fail "the spool filename namespace is missing"
grep -q 'No producer blocks a Handler lane indefinitely' "$URUQUIM_SPEC" ||
  fail "the no-blocking-producer rule is missing"

# OQ-20 Amendment 1: the large-body ownership answers precede spool code.
case "$URUQUIM_FLAT" in
  *"disk-full, timeout, disconnect, shutdown, crash remnants and explicit persistence transfer"*) ;;
  *) fail "the OQ-20 Amendment-1 checklist is not answered in advance" ;;
esac
grep -q 'Formalized 2026-07-23 (WP85)' "$URUQUIM_OQ" ||
  fail "OQ-20 Amendment 1 is not formalized in open-questions.md"
grep -q 'IN EXECUTION since 2026-07-23' "$URUQUIM_OQ" ||
  fail "OQ-32 is not marked in execution"

# The concept budget under G-09.
grep -q '≤ 8 new application symbols' "$URUQUIM_SPEC" ||
  fail "the public-concept ceiling is missing"
grep -q 'Names wait for WP86' "$URUQUIM_SPEC" ||
  fail "the names-wait-for-evidence rule is missing"

# Sync/async tie-in: terminology, the two scheduled questions, the substrate.
grep -q 'one ordinary procedure runs until it returns' "$URUQUIM_SPEC" ||
  fail "the layer-terminology table is missing"
grep -q 'specialised async path' "$URUQUIM_SPEC" ||
  fail "Phase 7 is not identified as the specialised async path"
grep -q 'Is response streaming contained above the' "$URUQUIM_SPEC" ||
  fail "the first scheduled evidence question is missing"
grep -q 'spool or direct' "$URUQUIM_SPEC" ||
  fail "the second scheduled evidence question is missing"
grep -q 'executor-agnostic' "$URUQUIM_SPEC" ||
  fail "the executor-agnostic substrate mandate is missing"
grep -q 'nominal operating margin of 50–70%' "$URUQUIM_SPEC" ||
  fail "the WP102 capacity-envelope handoff note is missing"

# The composition half is anchored, not improvised.
grep -q 'production-service-bom.md' "$URUQUIM_SPEC" ||
  fail "the Crystals half has no BOM anchor"
grep -q 'E8-7' "$URUQUIM_SPEC" ||
  fail "the Phase-8 entry condition E8-7 is not named"
case "$URUQUIM_FLAT" in
  *"certificate verification (OpenSSL FFI) as an inseparable part"*) ;;
  *) fail "outbound TLS is being promised separately from the client" ;;
esac

# Inherited work is bound to named WPs, not floating.
grep -q 'ADR-039 (write + idle timeouts) closes inside WP90' "$URUQUIM_SPEC" ||
  fail "the ADR-039 inheritance is not bound to WP90"
grep -q 'one.*`Limits`.*amendment\|one\*\* `Limits`' "$URUQUIM_SPEC" ||
  fail "write and idle timeouts are not required to close together"
grep -q 'measure behaviour, never counters' "$URUQUIM_SPEC" ||
  fail "the two-package-instance diagnostic trap is not recorded"
grep -q 'ADR-039' "$URUQUIM_PLAN" ||
  fail "the plan's WP90 does not carry the ADR-039 inheritance"
grep -q 'F4 was fixed and merged' "$URUQUIM_PLAN" ||
  fail "the plan's security backlog is not status-refreshed"
grep -q 'static serving joins the ordinary' "$URUQUIM_SPEC" ||
  fail "the F5/F6 decision is missing"

# G7-8 measures against the Phase-6 binary in both documents.
grep -q 'Phase-6 frozen binary' "$URUQUIM_SPEC" ||
  fail "G7-8 is not re-baselined in the spec"
grep -q 'Phase-6\*\*' "$URUQUIM_PLAN" ||
  fail "G7-8 is not re-baselined in the plan"

# The ADR record: three reopenings scoped to the long path, one new ADR.
grep -q 'ADR-008 — Amendment 1: reopened strictly for the long-lived path' "$URUQUIM_ADRS" ||
  fail "ADR-008 amendment is absent"
grep -q 'ADR-009 — Amendment 1: the private boundary gains a long-lived capability' "$URUQUIM_ADRS" ||
  fail "ADR-009 amendment is absent"
grep -q 'ADR-012 — Amendment 1: one buffered consumer stays canonical' "$URUQUIM_ADRS" ||
  fail "ADR-012 amendment is absent"
grep -q 'ADR-044 — stream ownership, bounded backpressure and stale-safe identity' "$URUQUIM_ADRS" ||
  fail "ADR-044 is absent"

if grep -qE '^- \[ \]' "$URUQUIM_SPEC"; then
  fail "the Phase-7 spec contains an unchecked item"
fi

echo "phase-7 spec: entry f51fc127 + Phase 6.5, ledger 63 + 2 = 65, WP85-WP101"
echo "phase-7 spec: capacity, backpressure and spool thresholds are pre-registered"
echo "phase-7 spec: ADR-008/009/012 reopened for the long path only; ADR-044 proposed"
echo "phase-7 spec: ADR-039 and the security backlog are bound to named WPs"
echo "PASS: WP85 Phase-7 spec and governance gate"
