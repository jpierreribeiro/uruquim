#!/usr/bin/env bash
# WP18 — the five required route-organisation mutation controls, as one
# executable run.
#
# The WP17 protocol, unchanged: each control re-creates a specific defect in a
# THROWAWAY copy of the shipped sources and requires the WP18 test suite to
# catch it. Every probe (a) runs its selected tests UNMUTATED first and
# requires them green with at least one test executed, (b) asserts its own
# edit applied by md5 — BROKEN PROBE otherwise, never a false verdict — and
# (c) requires the selected tests red after the mutation.
#
#   1  prefix concatenation swallows the '/'    -> verbatim-concat test MUST go red
#   2  router middleware dropped from the chain -> nested-order test MUST go red
#   3  mount does not close the router          -> closed-router test MUST go red
#   4  poison not propagated on mount           -> security test MUST go red
#   5  app globals appended AFTER the router's  -> order test MUST go red
#
# All five need the pinned compiler; without one this script reports BLOCKED
# and exits 2. On-demand, like the WP16/WP17 controls — not a per-gate step.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP18-CONTROL-FAIL: $*" >&2
  exit 1
}

URUQUIM_W18_ODIN="${URUQUIM_ODIN_BIN:-}"
if test -z "$URUQUIM_W18_ODIN" && command -v odin >/dev/null 2>&1; then
  URUQUIM_W18_ODIN="$(command -v odin)"
fi
if test -z "$URUQUIM_W18_ODIN" && test -x /tmp/uruquim-odin-toolchain/odin; then
  URUQUIM_W18_ODIN=/tmp/uruquim-odin-toolchain/odin
fi
if test -z "$URUQUIM_W18_ODIN"; then
  echo "WP18 CONTROLS -> BLOCKED: no Odin toolchain found (set URUQUIM_ODIN_BIN). NOTHING RAN." >&2
  exit 2
fi

URUQUIM_W18_TMP="$(mktemp -d -t uruquim-wp18-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_W18_TMP"' EXIT

internal_tree() { # name
  local t="$URUQUIM_W18_TMP/$1"
  mkdir -p "$t"
  cp "$URUQUIM_ROOT"/web/*.odin "$t/"
  cp "$URUQUIM_ROOT"/tests/wp18-internal/*.odin "$t/"
  printf '%s' "$t"
}

assert_mutated() { # label file before-hash
  local after
  after="$(md5sum "$2" | cut -d' ' -f1)"
  test "$3" != "$after" ||
    fail "BROKEN PROBE ($1): the edit left ${2##*/} unchanged; this control would prove nothing"
}

run_selected() { # tree test-names
  env -u ODIN_ROOT "$URUQUIM_W18_ODIN" test "$1" \
    "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_W18_TMP/runner" \
    "-define:ODIN_TEST_NAMES=$2" 2>&1
}

assert_green_baseline() { # tree test-names label
  local out
  if ! out="$(run_selected "$1" "$2")"; then
    echo "$out" >&2
    fail "BROKEN PROBE ($3): the selected tests are not green BEFORE the mutation"
  fi
  grep -qE 'Finished [1-9][0-9]* tests?' <<<"$out" ||
    { echo "$out" >&2; fail "BROKEN PROBE ($3): the selection ran no test; a stale test name would fake a pass"; }
}

must_go_red() { # tree test-names label
  local out
  if out="$(run_selected "$1" "$2")"; then
    echo "$out" >&2
    fail "control '$3' stayed GREEN under the mutation; the suite does not catch this defect"
  fi
  echo "CONTROL $3 -> RED as required"
}

# --- 1. prefix concatenation swallows the '/' --------------------------------
# The mounted pattern becomes prefix + pattern[1:] — "/api" + "users" instead
# of "/api/users". The verbatim-concatenation test must observe the wrong path.
NAMES="web.wp18_mounted_route_is_reachable_at_prefix_plus_pattern"
T="$(internal_tree swallow)"
assert_green_baseline "$T" "$NAMES" "1: prefix swallow"
H="$(md5sum "$T/router.odin" | cut -d' ' -f1)"
# Anchored on the ARGUMENT line alone, so a future reflow of the call does not
# turn this control into a BROKEN PROBE (it already did once, at Amendment 1).
sed -i 's/^\t\t\t{prefix, entry.pattern},$/\t\t\t{prefix, entry.pattern[1:]},/' \
  "$T/router.odin"
assert_mutated "prefix swallow" "$T/router.odin" "$H"
must_go_red "$T" "$NAMES" "1: prefix swallow -> verbatim-concat test"

# --- 2. router middleware dropped from the composed chain --------------------
# mount copies only the HANDLER (the last chain step), losing every router
# middleware. The nested-order test must miss its O>/I> marks.
NAMES="web.wp18_nested_routers_outer_use_before_inner_use_before_handler"
T="$(internal_tree dropped)"
assert_green_baseline "$T" "$NAMES" "2: router middleware dropped"
H="$(md5sum "$T/router.odin" | cut -d' ' -f1)"
python3 - "$T/router.odin" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """	for step in r.private.mw_pool[entry.chain_start:entry.chain_start + entry.chain_len] {
		appended, err := append(&a.private.mw_pool, step)
		if err != nil || appended != 1 {
			return 0, 0, false
		}
	}"""
new = """	append(&a.private.mw_pool, r.private.mw_pool[entry.chain_start + entry.chain_len - 1])"""
assert old in s, "pattern not found"
open(p, 'w').write(s.replace(old, new, 1))
PYEOF
assert_mutated "router middleware dropped" "$T/router.odin" "$H"
must_go_red "$T" "$NAMES" "2: router middleware dropped -> nested-order test"

# --- 3. mount does not close the router --------------------------------------
# The late registration is then accepted and silently dead — exactly the
# quiet wrongness the closed rule exists to refuse.
NAMES="web.wp18_mount_closes_the_router"
T="$(internal_tree unclosed)"
assert_green_baseline "$T" "$NAMES" "3: router not closed"
H="$(md5sum "$T/router.odin" | cut -d' ' -f1)"
sed -i 's/^\tr.private.closed = true$/\t_ = r/' "$T/router.odin"
assert_mutated "router not closed" "$T/router.odin" "$H"
must_go_red "$T" "$NAMES" "3: router not closed -> closed-router test"

# --- 4. poison not propagated on mount ---------------------------------------
# A mis-ordered (poisoned) router mounted into a healthy app must reject the
# app; with the propagation deleted, the app would serve the router's routes
# as if the ordering violation never happened.
NAMES="web.wp18_mounting_a_poisoned_router_poisons_the_app"
T="$(internal_tree unpropagated)"
assert_green_baseline "$T" "$NAMES" "4: poison not propagated"
H="$(md5sum "$T/router.odin" | cut -d' ' -f1)"
sed -z -i 's/\tif r.private.poisoned {\n\t\tmount_poison(a, FRAMEWORK_MESSAGE_MOUNT_POISONED_ROUTER)\n\t\treturn\n\t}/\t_ = r.private.poisoned/' \
  "$T/router.odin"
assert_mutated "poison not propagated" "$T/router.odin" "$H"
must_go_red "$T" "$NAMES" "4: poison not propagated -> propagation test"

# --- 5. app globals appended AFTER the router's ------------------------------
# The composed chain then runs router middleware OUTSIDE the app's globals —
# the reverse of the §2.1 outermost-first rule.
NAMES="web.wp18_order_app_then_router_then_handler_exact_reverse_unwind"
T="$(internal_tree reversed)"
assert_green_baseline "$T" "$NAMES" "5: composition order reversed"
H="$(md5sum "$T/router.odin" | cut -d' ' -f1)"
python3 - "$T/router.odin" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
# WP18 Amendment 1 repaired this probe: `mount_chain_flatten` now checks every
# append, so the old anchor no longer exists. The mutation is the same one --
# app globals appended AFTER the router's steps -- expressed against the
# current body.
old = """	for middleware in a.private.mw_globals {
		appended, err := append(&a.private.mw_pool, middleware)
		if err != nil || appended != 1 {
			return 0, 0, false
		}
	}
	for step in r.private.mw_pool[entry.chain_start:entry.chain_start + entry.chain_len] {
		appended, err := append(&a.private.mw_pool, step)
		if err != nil || appended != 1 {
			return 0, 0, false
		}
	}"""
new = """	for step in r.private.mw_pool[entry.chain_start:entry.chain_start + entry.chain_len] {
		appended, err := append(&a.private.mw_pool, step)
		if err != nil || appended != 1 {
			return 0, 0, false
		}
	}
	for middleware in a.private.mw_globals {
		appended, err := append(&a.private.mw_pool, middleware)
		if err != nil || appended != 1 {
			return 0, 0, false
		}
	}"""
assert old in s, "pattern not found"
open(p, 'w').write(s.replace(old, new))
PYEOF
assert_mutated "composition order reversed" "$T/router.odin" "$H"
must_go_red "$T" "$NAMES" "5: composition order reversed -> order test"

# --- 6. the append result discarded again (WP18 Amendment 1) ----------------
# The regression this refuses is the original defect: Odin's `append` returns
# `num_appended = 0` instead of panicking when it cannot allocate, so dropping
# the check makes routes vanish in silence while the App still reports healthy
# -- a route the developer wrote answering 404 as though it never existed.
NAMES="web.wp18_mount_that_cannot_allocate_rejects_the_application,web.wp18_a_mount_that_cannot_allocate_never_serves"
T="$(internal_tree unchecked_append)"
assert_green_baseline "$T" "$NAMES" "6: append result discarded"
H="$(md5sum "$T/router.odin" | cut -d' ' -f1)"
python3 - "$T/router.odin" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """		if append_err != nil || appended != 1 {
			mount_poison(a, FRAMEWORK_MESSAGE_MOUNT_ALLOCATION_FAILED)
			return
		}"""
new = """		_ = append_err
		_ = appended"""
assert old in s, "pattern not found"
open(p, 'w').write(s.replace(old, new, 1))
PYEOF
assert_mutated "append result discarded" "$T/router.odin" "$H"
must_go_red "$T" "$NAMES" "6: append result discarded -> the fail-closed mount tests"

echo "PASS: all six WP18 mutation controls behaved as required"
