#!/usr/bin/env bash
# WP37 — the typed-application-state mutation controls.
#
# The WP17/WP18 protocol, with one addition this work package forced.
#
# TWO OF THE THREE GUARANTEES CANNOT BE TESTED FROM A TEST SUITE, and that is a
# property of the design rather than a gap. `web.state` ASSERTS before it casts,
# and a failing assert ABORTS the process (ADR-020: Odin has no recoverable
# panic, and the framework does not pretend otherwise). A test that could
# observe a failed assert and continue would be evidence the assert was not an
# assert.
#
# So those two are probed the only honest way: a small program is compiled and
# RUN as a subprocess, and the control asserts on its EXIT STATUS. The
# unmutated tree must abort; the mutated tree must not. That is a real negative
# control — it fails loudly if the assert is ever quietly removed — and it costs
# two compiles.
#
#   1  the nil-state rejection deleted  -> the fail-closed test MUST go red
#   2  the typeid assert deleted        -> the wrong-type probe MUST stop aborting
#   3  BOTH asserts deleted            -> the no-state probe MUST die undiagnosed
#
# All three need the pinned compiler; without one this script reports BLOCKED
# and exits 2. On-demand, like the WP16-WP30 controls — not a per-gate step.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP37-CONTROL-FAIL: $*" >&2
  exit 1
}

URUQUIM_W37_ODIN="${URUQUIM_ODIN_BIN:-}"
if test -z "$URUQUIM_W37_ODIN" && command -v odin >/dev/null 2>&1; then
  URUQUIM_W37_ODIN="$(command -v odin)"
fi
if test -z "$URUQUIM_W37_ODIN" && test -x /tmp/uruquim-odin-toolchain/odin; then
  URUQUIM_W37_ODIN=/tmp/uruquim-odin-toolchain/odin
fi
if test -z "$URUQUIM_W37_ODIN"; then
  echo "WP37 CONTROLS -> BLOCKED: no Odin toolchain found (set URUQUIM_ODIN_BIN). NOTHING RAN." >&2
  exit 2
fi

URUQUIM_W37_TMP="$(mktemp -d -t uruquim-wp37-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_W37_TMP"' EXIT

assert_mutated() { # label file before-hash
  local after
  after="$(md5sum "$2" | cut -d' ' -f1)"
  test "$3" != "$after" ||
    fail "BROKEN PROBE ($1): the edit left ${2##*/} unchanged; this control would prove nothing"
}

# --- the suite half -----------------------------------------------------------

suite_tree() { # name
  local t="$URUQUIM_W37_TMP/$1"
  mkdir -p "$t/uruquim/web" "$t/suite"
  cp "$URUQUIM_ROOT"/web/*.odin "$t/uruquim/web/"
  cp -r "$URUQUIM_ROOT"/web/testing "$t/uruquim/web/"
  cp -r "$URUQUIM_ROOT"/web/internal "$t/uruquim/web/"
  cp -r "$URUQUIM_ROOT"/vendor "$t/uruquim/"
  cp "$URUQUIM_ROOT"/tests/wp37-public-surface/*.odin "$t/suite/"
  printf '%s' "$t"
}

run_selected() { # tree test-names
  env -u ODIN_ROOT "$URUQUIM_W37_ODIN" test "$1/suite" \
    "-collection:uruquim=$1/uruquim" -out:"$URUQUIM_W37_TMP/runner" \
    "-define:ODIN_TEST_NAMES=$2" 2>&1
}

# --- the subprocess half ------------------------------------------------------
#
# The probe program calls `web.state` in a way the ratified implementation must
# refuse, and the control reads its exit status. A program that ABORTS is the
# guarantee holding; a program that exits 0 is the guarantee gone.

write_probe() { # tree kind
  mkdir -p "$1/probe"
  case "$2" in
    wrong_type)
      cat >"$1/probe/main.odin" <<'PROBE'
package main

import web "uruquim:web"

Registered :: struct {
	n: int,
}

Never_Registered :: struct {
	other: [64]u8,
}

handler :: proc(ctx: ^web.Context) {
	// The registered type is `Registered`. Asking for a different one must
	// abort BEFORE the cast; without the typeid assert this reinterprets the
	// bytes and returns quietly.
	s := web.state(ctx, Never_Registered)
	s.other[0] = 1
	web.no_content(ctx)
}

main :: proc() {
	value := Registered{}
	app := web.app_with_state(&value)
	defer web.destroy(&app)
	web.get(&app, "/x", handler)
	web.test_request(&app, .GET, "/x")
}
PROBE
      ;;
    no_state)
      cat >"$1/probe/main.odin" <<'PROBE'
package main

import web "uruquim:web"

Anything :: struct {
	n: int,
}

handler :: proc(ctx: ^web.Context) {
	// No state was ever registered: `web.app()` does not take one. This must
	// abort rather than dereference nil.
	s := web.state(ctx, Anything)
	s.n += 1
	web.no_content(ctx)
}

main :: proc() {
	app := web.app()
	defer web.destroy(&app)
	web.get(&app, "/x", handler)
	web.test_request(&app, .GET, "/x")
}
PROBE
      ;;
    *) fail "unknown probe kind '$2'" ;;
  esac
}

probe_exit() { # tree
  local bin="$URUQUIM_W37_TMP/probe-bin"
  env -u ODIN_ROOT "$URUQUIM_W37_ODIN" build "$1/probe" \
    "-collection:uruquim=$1/uruquim" -out:"$bin" >/dev/null 2>&1 ||
    fail "BROKEN PROBE: the subprocess program did not compile"
  set +e
  "$bin" >/dev/null 2>&1
  local status=$?
  set -e
  printf '%s' "$status"
}

# --- 1. the nil-state rejection deleted --------------------------------------
# `app_with_state(nil)` then builds an App that looks healthy and aborts inside
# the first handler instead — the same failure, later, in front of a client.
NAMES="test_wp37_public.wp37_a_nil_state_rejects_the_application"
T="$(suite_tree nil_accepted)"
OUT="$(run_selected "$T" "$NAMES")" || { echo "$OUT" >&2; fail "BROKEN PROBE (1): the selected test is not green BEFORE the mutation"; }
grep -qE 'Finished [1-9][0-9]* tests?' <<<"$OUT" ||
  { echo "$OUT" >&2; fail "BROKEN PROBE (1): the selection ran no test"; }
H="$(md5sum "$T/uruquim/web/state.odin" | cut -d' ' -f1)"
python3 - "$T/uruquim/web/state.odin" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """	if state == nil {"""
new = """	if false {"""
assert old in s, "pattern not found"
open(p, 'w').write(s.replace(old, new, 1))
PYEOF
assert_mutated "nil accepted" "$T/uruquim/web/state.odin" "$H"
if run_selected "$T" "$NAMES" >/dev/null 2>&1; then
  fail "control '1: nil-state rejection deleted' stayed GREEN; the suite does not catch this defect"
fi
echo "CONTROL 1: nil-state rejection deleted -> RED as required"

# --- 2. the typeid assert deleted --------------------------------------------
T="$(suite_tree wrong_type)"
write_probe "$T" wrong_type
BEFORE="$(probe_exit "$T")"
test "$BEFORE" -ne 0 ||
  fail "BROKEN PROBE (2): asking web.state for an unregistered type did NOT abort in the unmutated tree. The typeid assert is not doing anything."
echo "CONTROL 2 baseline: a wrong-type web.state aborts (exit $BEFORE)"
H="$(md5sum "$T/uruquim/web/state.odin" | cut -d' ' -f1)"
python3 - "$T/uruquim/web/state.odin" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """	assert(
		ctx.private.state_type == typeid_of(T),"""
new = """	assert(
		true,"""
assert old in s, "pattern not found"
open(p, 'w').write(s.replace(old, new, 1))
PYEOF
assert_mutated "typeid assert deleted" "$T/uruquim/web/state.odin" "$H"
AFTER="$(probe_exit "$T")"
test "$AFTER" -eq 0 ||
  fail "control '2: typeid assert deleted' still aborted (exit $AFTER); the probe is not isolating the assert"
echo "CONTROL 2: typeid assert deleted -> the wrong-type program STOPPED aborting, as required"

# --- 3. BOTH asserts deleted -------------------------------------------------
#
# WHY THIS CONTROL REMOVES TWO THINGS AND NOT ONE, recorded because the first
# version of it removed one and stayed red. Deleting only the registration
# assert does NOT stop the abort: an App built by `web.app()` has a ZERO
# `state_type`, which never equals `typeid_of(T)`, so the typeid assert catches
# the unregistered case anyway.
#
# The honest conclusion, stated rather than papered over: through the PUBLIC
# API the registration assert is not independently load-bearing. It exists for
# its DIAGNOSTIC — "you built this with web.app(), not web.app_with_state" is a
# different and much more useful sentence than "the type does not match" — and
# a message is worth an assert. What this control proves is that the PAIR is
# load-bearing, and it proves something sharper than "the program stops
# refusing": see the note at the assertion below.
T="$(suite_tree no_state)"
write_probe "$T" no_state
BEFORE="$(probe_exit "$T")"
test "$BEFORE" -ne 0 ||
  fail "BROKEN PROBE (3): web.state on an app() with no state did NOT abort in the unmutated tree."
echo "CONTROL 3 baseline: web.state without registration aborts (exit $BEFORE)"
H="$(md5sum "$T/uruquim/web/state.odin" | cut -d' ' -f1)"
python3 - "$T/uruquim/web/state.odin" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
for old in ("""	assert(
		ctx.private.state != nil,""", """	assert(
		ctx.private.state_type == typeid_of(T),"""):
    assert old in s, "pattern not found: %r" % old[:40]
    s = s.replace(old, """	assert(
		true,""", 1)
open(p, 'w').write(s)
PYEOF
assert_mutated "both asserts deleted" "$T/uruquim/web/state.odin" "$H"
AFTER="$(probe_exit "$T")"
# AND THIS IS THE RESULT WORTH RECORDING, because it is better than the one the
# control was written expecting. With both asserts gone the program does not
# quietly succeed — it dies from a SEGMENTATION FAULT (128+SIGSEGV = 139 on
# this platform) instead of the assert trap (132), because the handler
# dereferences a nil pointer one line later.
#
# So the asserts do not turn a crash into a non-crash. They turn an UNDIAGNOSED
# memory fault into a DIAGNOSED refusal that names what the programmer did
# wrong. That is the whole value of them and it is what this control now pins:
# the exit status must CHANGE, and the mutated status must not be the clean
# assert trap.
test "$AFTER" -ne 0 ||
  fail "control '3: both asserts deleted' made the program SUCCEED (exit 0); it should have dereferenced nil"
test "$AFTER" -ne "$BEFORE" ||
  fail "control '3: both asserts deleted' produced the same exit status ($AFTER); the probe is not isolating them"
echo "CONTROL 3: both asserts deleted -> the diagnosed refusal ($BEFORE) became an undiagnosed fault ($AFTER), as required"

echo "PASS: all three WP37 mutation controls behaved as required"
