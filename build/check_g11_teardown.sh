#!/usr/bin/env bash
# G-11 teardown-cost gate (planning/public-api-guardrails.md).
#
# The guardrail states, as ratified in WP3:
#
#   "the recorder teardown MUST be registered lazily — a private proc-pointer
#    set only inside `test_request` — so that when `test_request` is
#    dead-code-eliminated the teardown goes with it. The gate asserts this with
#    `nm`: a minimal application that never calls `test_request` links ZERO
#    `web/testing` teardown symbols."
#
# This script IS that gate. It was promised by the guardrail but never written,
# so the claim went unenforced and the code drifted from it: `web.destroy` called
# `testing.destroy` directly, a static edge that linked the recorder teardown
# into every binary. Measured on 819fdc7 before the fix, a minimal application
# that never tests linked FOUR teardown symbols (`web_testing::destroy`,
# `recorder_destroy`, and the `delete_dynamic_array`/`delete_slice`
# instantiations) and was 608 bytes larger.
#
# It builds two real consumers and inspects their symbol tables:
#
#   NEGATIVE — an application that never calls `web.test_request` must link
#              ZERO `web/testing` teardown symbols.
#   POSITIVE — an application that DOES call it must link them.
#
# The positive control is not decoration. Without it, a typo in the symbol
# pattern would make the negative assertion pass against every possible binary,
# and the gate would certify a property it never actually measured.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "G11-FAIL: $*" >&2
  exit 1
}

test -n "${URUQUIM_COMPILER:-}" ||
  fail "URUQUIM_COMPILER is not set; run this through build/check.sh"
test -x "$URUQUIM_COMPILER" || fail "compiler is not executable: $URUQUIM_COMPILER"
URUQUIM_COMPILER_DIR="$(cd "$(dirname "$URUQUIM_COMPILER")" && pwd)"

command -v nm >/dev/null 2>&1 ||
  fail "nm not found; the G-11 teardown assertion cannot be measured without it"

# Any symbol from the machinery package. The teardown routines are the ones the
# guardrail names, but the generic instantiations (`delete_dynamic_array` over
# `Recorded`, `delete_slice` over `Header`) are linked by the same static edge
# and are equally a shipped cost, so the assertion covers the whole package.
URUQUIM_G11_PATTERN='web_testing|recorder_destroy'

URUQUIM_G11_TMP="$(mktemp -d -t uruquim-g11-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_G11_TMP"' EXIT

# Each consumer gets its own tree with a real copy of the shipped package, so
# what is measured is the package as it would actually ship.
uruquim_g11_build() { # label main-source-file
  # Declared separately on purpose: within a single `local` statement bash does
  # not yet see the variables assigned to its left, so `tree` would expand
  # `$label` as empty and, under `set -u`, abort.
  local label="$1"
  local main_source="$2"
  local tree="$URUQUIM_G11_TMP/$label"
  mkdir -p "$tree/app"
  cp -r "$URUQUIM_ROOT/web" "$tree/web"
  cp "$main_source" "$tree/app/main.odin"
  ( cd "$tree" && env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
      PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
      "$URUQUIM_COMPILER" build app "-collection:uruquim=$tree" -out:app.bin ) ||
    fail "the $label consumer did not build"
  printf '%s' "$tree/app.bin"
}

uruquim_g11_symbols() { # binary
  nm "$1" 2>/dev/null | grep -cE "$URUQUIM_G11_PATTERN" || true
}

# --- NEGATIVE: never calls test_request -------------------------------------
cat >"$URUQUIM_G11_TMP/never_tests.odin" <<'ODIN'
package main

import web "uruquim:web"

main :: proc() {
	app := web.app()
	defer web.destroy(&app)
	web.serve(&app, 8080)
}
ODIN

URUQUIM_G11_NEG="$(uruquim_g11_build never-tests "$URUQUIM_G11_TMP/never_tests.odin")"
URUQUIM_G11_NEG_COUNT="$(uruquim_g11_symbols "$URUQUIM_G11_NEG")"
URUQUIM_G11_NEG_SIZE="$(stat -c%s "$URUQUIM_G11_NEG")"

if test "$URUQUIM_G11_NEG_COUNT" -ne 0; then
  echo "--- web/testing symbols linked into an application that never tests ---" >&2
  nm "$URUQUIM_G11_NEG" | grep -E "$URUQUIM_G11_PATTERN" | sed 's/^[0-9a-f]* //' >&2
  fail "an application that never calls test_request links $URUQUIM_G11_NEG_COUNT web/testing symbol(s); the teardown must be registered lazily inside test_request so dead-code elimination removes it (planning/public-api-guardrails.md G-11)"
fi

# --- POSITIVE control: does call test_request -------------------------------
cat >"$URUQUIM_G11_TMP/does_test.odin" <<'ODIN'
package main

import "core:fmt"
import web "uruquim:web"

main :: proc() {
	app := web.app()
	defer web.destroy(&app)
	res := web.test_request(&app, .GET, "/health")
	fmt.println(res.status, res.body)
}
ODIN

URUQUIM_G11_POS="$(uruquim_g11_build does-test "$URUQUIM_G11_TMP/does_test.odin")"
URUQUIM_G11_POS_COUNT="$(uruquim_g11_symbols "$URUQUIM_G11_POS")"
URUQUIM_G11_POS_SIZE="$(stat -c%s "$URUQUIM_G11_POS")"

if test "$URUQUIM_G11_POS_COUNT" -eq 0; then
  fail "an application that DOES call test_request links no web/testing symbol either; the pattern /$URUQUIM_G11_PATTERN/ matches nothing, so the negative assertion above proved nothing"
fi

# --- MUTATION: the gate must catch the regression it exists to prevent -------
#
# Restore the exact defect this guardrail is about — `destroy` calling
# `testing.destroy` directly instead of through the lazily-registered pointer —
# and confirm the teardown symbols come back. Without this, a future refactor
# could make the elimination accidental (or make the negative case unbuildable)
# and the gate would keep reporting PASS for the wrong reason.
mkdir -p "$URUQUIM_G11_TMP/mutated"
cp -r "$URUQUIM_ROOT/web" "$URUQUIM_G11_TMP/mutated/web"
mkdir -p "$URUQUIM_G11_TMP/mutated/app"
cp "$URUQUIM_G11_TMP/never_tests.odin" "$URUQUIM_G11_TMP/mutated/app/main.odin"

python3 - "$URUQUIM_G11_TMP/mutated/web/app.odin" <<'PY'
import sys

path = sys.argv[1]
source = open(path).read()
guarded = """	if a.private.test_teardown != nil {
		a.private.test_teardown(&a.private.test_transport)
	}"""
if guarded not in source:
    sys.exit("MUTATION-SETUP: the guarded teardown call was not found in web/app.odin")
open(path, "w").write(
    source.replace(guarded, "	testing.destroy(&a.private.test_transport)", 1)
)
PY

if ! ( cd "$URUQUIM_G11_TMP/mutated" && env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
    PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
    "$URUQUIM_COMPILER" build app "-collection:uruquim=$URUQUIM_G11_TMP/mutated" \
    -out:app.bin >/dev/null 2>&1 ); then
  fail "the mutated consumer did not build; the mutation check proved nothing"
fi

URUQUIM_G11_MUT_COUNT="$(uruquim_g11_symbols "$URUQUIM_G11_TMP/mutated/app.bin")"
if test "$URUQUIM_G11_MUT_COUNT" -eq 0; then
  fail "reinstating the static destroy -> testing.destroy edge did NOT relink the teardown; this gate is not measuring what it claims (planning/public-api-guardrails.md G-11)"
fi

echo "G-11: application that never tests  -> 0 web/testing symbols, $URUQUIM_G11_NEG_SIZE bytes"
echo "G-11: application that does test    -> $URUQUIM_G11_POS_COUNT web/testing symbols, $URUQUIM_G11_POS_SIZE bytes"
echo "G-11: static-edge mutation          -> $URUQUIM_G11_MUT_COUNT web/testing symbols (correctly rejected)"
echo "PASS: the test-support teardown is eliminated from applications that never test (G-11)"

rm -rf "$URUQUIM_G11_TMP"
trap - EXIT
