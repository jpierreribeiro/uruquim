#!/usr/bin/env bash
# WP10 — the example compile gate.
#
# The three Phase-1 examples are part of the compatibility contract
# (`knowledge-base/01-architecture-spec.md` §AI-Friendly API Rules: "Public
# examples ... compile in the mandatory verification gate"). If an example
# stops compiling, the documentation that teaches it is wrong, and this fails.
#
# Examples are COMPILED, never RUN: `web.serve` blocks forever by design.
#
# Every binary goes into one `mktemp -d`, removed on exit even when a build
# fails, so a red gate can never leave an ELF inside `examples/` or the
# repository root.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_EXAMPLES="$URUQUIM_ROOT/examples"

fail() {
  echo "EXAMPLES-FAIL: $*" >&2
  exit 1
}

test -n "${URUQUIM_COMPILER:-}" ||
  fail "URUQUIM_COMPILER is not set; run this through build/check.sh"
test -x "$URUQUIM_COMPILER" || fail "compiler is not executable: $URUQUIM_COMPILER"
URUQUIM_COMPILER_DIR="$(cd "$(dirname "$URUQUIM_COMPILER")" && pwd)"

# ---------------------------------------------------------------------------
# 1. The example set is EXACT.
#
# `examples/` also holds the throwaway prototypes from WP0 (`01-api-shape` and
# friends) that `experiments/run_checks.sh` owns. The Phase-1 application
# examples are exactly these three directories, and the gate names them so a
# deleted or renamed example is a failure rather than a silent gap.
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_EXAMPLES="01-hello-world
02-json-api
03-route-params"

test -d "$URUQUIM_EXAMPLES" || fail "examples/ does not exist"

for URUQUIM_NAME in $URUQUIM_EXPECTED_EXAMPLES; do
  test -d "$URUQUIM_EXAMPLES/$URUQUIM_NAME" ||
    fail "examples/$URUQUIM_NAME/ is missing; the three Phase-1 examples are a contract (WP10 D3)"
  test -f "$URUQUIM_EXAMPLES/$URUQUIM_NAME/main.odin" ||
    fail "examples/$URUQUIM_NAME/main.odin is missing; each example is a self-contained program"
done

# ---------------------------------------------------------------------------
# 2. Examples use the PUBLIC surface only.
#
# An example that reached into the machinery would teach a path applications
# must never take, and would quietly make the "34 symbols are enough" claim
# false.
# ---------------------------------------------------------------------------
for URUQUIM_NAME in $URUQUIM_EXPECTED_EXAMPLES; do
  URUQUIM_SRC="$URUQUIM_EXAMPLES/$URUQUIM_NAME/main.odin"
  URUQUIM_CODE="$(sed -E 's://.*$::' "$URUQUIM_SRC")"

  if grep -nE '"uruquim:web/testing"|"uruquim:web/internal|"uruquim:vendor' <<<"$URUQUIM_CODE"; then
    fail "examples/$URUQUIM_NAME imports test machinery, an internal package, or the backend"
  fi

  # Future-phase vocabulary must not appear in a Phase-1 example (AMEND-4).
  for URUQUIM_FUTURE in 'web\.use' 'web\.next' 'web\.router' 'web\.group' 'web\.mount' \
    'web\.header\(' 'web\.bearer_token' 'web\.state' 'web\.app_with_state' \
    'web\.serve_with' 'web\.serve_transport' 'web\.body_limit' 'web\.bytes' \
    'web\.redirect' 'web\.conflict'; do
    if grep -nE "$URUQUIM_FUTURE" <<<"$URUQUIM_CODE"; then
      fail "examples/$URUQUIM_NAME uses future-phase API matching /$URUQUIM_FUTURE/ (AMEND-4)"
    fi
  done

  # The canonical call-site rules the examples exist to teach.
  if grep -nE 'or_else[[:space:]]*\{' <<<"$URUQUIM_CODE"; then
    fail "examples/$URUQUIM_NAME uses an 'or_else { ... }' block, which is not valid Odin"
  fi
  if grep -nE 'web\.(ok|created|json)\([^,]+,[[:space:]]*&' <<<"$URUQUIM_CODE"; then
    fail "examples/$URUQUIM_NAME passes a POINTER payload; Phase-1 payloads are values (ADR-003)"
  fi
  if grep -nE '\.(Get|Post|Put|Patch|Delete)\b' <<<"$URUQUIM_CODE"; then
    fail "examples/$URUQUIM_NAME uses a mixed-case method member; Method members are UPPERCASE"
  fi
  grep -qE '^package main$' <<<"$URUQUIM_CODE" ||
    fail "examples/$URUQUIM_NAME is not 'package main'"
  grep -qE 'web\.destroy\(&app\)' <<<"$URUQUIM_CODE" ||
    fail "examples/$URUQUIM_NAME never destroys its App"
done

# ---------------------------------------------------------------------------
# 3. Compile each example. Binaries live in a temp directory only.
# ---------------------------------------------------------------------------
URUQUIM_BIN_TMP="$(mktemp -d -t uruquim-examples-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_BIN_TMP"' EXIT

for URUQUIM_NAME in $URUQUIM_EXPECTED_EXAMPLES; do
  echo "--- example: $URUQUIM_NAME (odin build) ---"
  env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
    "$URUQUIM_COMPILER" build "$URUQUIM_EXAMPLES/$URUQUIM_NAME" \
    "-collection:uruquim=$URUQUIM_ROOT" \
    -out:"$URUQUIM_BIN_TMP/$URUQUIM_NAME" ||
    fail "examples/$URUQUIM_NAME did not compile"
done

URUQUIM_TOTAL=0
for URUQUIM_NAME in $URUQUIM_EXPECTED_EXAMPLES; do
  URUQUIM_SIZE="$(stat -c%s "$URUQUIM_BIN_TMP/$URUQUIM_NAME")"
  URUQUIM_TOTAL=$((URUQUIM_TOTAL + URUQUIM_SIZE))
  echo "example $URUQUIM_NAME -> $URUQUIM_SIZE bytes"
done
echo "examples total: $URUQUIM_TOTAL bytes (built in $URUQUIM_BIN_TMP, removed on exit)"

# 4. No example binary may be left in the working tree.
if find "$URUQUIM_EXAMPLES" -type f -perm -u+x ! -name '*.odin' ! -name '*.md' -print -quit | grep -q .; then
  fail "an executable was left inside examples/; example binaries belong in a temp directory"
fi

rm -rf "$URUQUIM_BIN_TMP"
trap - EXIT

echo "PASS: the three Phase-1 examples compile and use only the public surface"
