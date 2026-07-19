#!/usr/bin/env bash
# WP3 mutation checks — prove the dual-ledger guardrails actually REJECT the
# states they claim to forbid (WP3 prompt, TESTS-FIRST item 6).
#
# Each case copies the shipped package, tests, and checker into a throwaway
# tree, applies ONE forbidden mutation, runs the copied `check_public_api.sh`
# against that tree, and asserts it fails with the expected message. A guardrail
# that passes on a bad tree is worse than no guardrail; this file makes the
# rejection an executable, versioned fact rather than a claim.
#
# It never mutates the real repository: all work happens under `mktemp -d`.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "MUTATION-FAIL: $*" >&2
  exit 1
}

# Run the copied checker on a mutated tree; require a non-zero exit AND the
# expected diagnostic. A wrong-reason failure is itself a failure.
expect_reject() { # tree label expected-substring
  local tree="$1" label="$2" expected="$3" out
  if out="$(bash "$tree/build/check_public_api.sh" 2>&1)"; then
    echo "$out" >&2
    fail "'$label' was ACCEPTED; the guardrail does not reject it"
  fi
  if ! grep -qF "$expected" <<<"$out"; then
    echo "$out" >&2
    fail "'$label' was rejected for the wrong reason; expected: $expected"
  fi
  echo "PASS (mutation): $label -> rejected"
}

fresh_tree() {
  local t
  t="$(mktemp -d -t uruquim-wp3-mutation-XXXXXXXX)"
  mkdir -p "$t/build" "$t/web/testing" "$t/tests"
  cp "$URUQUIM_ROOT"/build/check_public_api.sh "$t/build/"
  cp "$URUQUIM_ROOT"/web/*.odin "$t/web/"
  cp "$URUQUIM_ROOT"/web/testing/*.odin "$t/web/testing/"
  cp -r "$URUQUIM_ROOT"/tests/. "$t/tests/"
  printf '%s' "$t"
}

TREES=()
cleanup() { for t in "${TREES[@]:-}"; do test -n "$t" && rm -rf "$t"; done; }
trap cleanup EXIT

# 1. An extra symbol in the APPLICATION ledger.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nextra_app_symbol :: proc() {}\n' >>"$T/web/serve.odin"
expect_reject "$T" "extra application-ledger symbol" \
  "exports symbols outside the ratified Phase-1 surface"

# 2. An extra symbol in the TEST-SUPPORT ledger.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nextra_ts_symbol :: proc() {}\n' >>"$T/web/test_support.odin"
expect_reject "$T" "extra test-support-ledger symbol" \
  "outside the 2-symbol test-support ledger"

# 3. A subdirectory other than web/testing.
T="$(fresh_tree)"; TREES+=("$T")
mkdir -p "$T/web/internal"
printf 'package internal\n' >"$T/web/internal/x.odin"
expect_reject "$T" "disallowed web/ subdirectory" \
  "unexpected subdirectory"

# 4. core:testing imported by the machinery.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nimport _ "core:testing"\n' >>"$T/web/testing/recorder.odin"
expect_reject "$T" "core:testing in machinery" \
  "web/testing/ imports core:testing"

# 5. The back-edge import (uruquim:web) inside the machinery.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nimport _ "uruquim:web"\n' >>"$T/web/testing/recorder.odin"
expect_reject "$T" "uruquim:web import in machinery" \
  "web/testing/ imports uruquim:web"

# 6. An @(init) proc in the machinery.
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(init)\nboot :: proc() {}\n' >>"$T/web/testing/recorder.odin"
expect_reject "$T" "@(init) in machinery" \
  "an @(init) proc appears in the test-support facade or machinery"

# 7. A bridge export beyond the locked set.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nextra_bridge :: proc() {}\n' >>"$T/web/testing/test_transport.odin"
expect_reject "$T" "extra web/testing bridge export" \
  "outside the locked bridge set"

# 8. A public `headers` field smuggled onto Recorded_Response.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/test_support.odin" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("\tstatus: Status,\n\tbody:   string,\n}",
              "\tstatus:  Status,\n\tbody:    string,\n\theaders: int,\n}", 1)
open(p, "w").write(s)
PY
expect_reject "$T" "public headers field on Recorded_Response" \
  "must expose exactly status and body"

echo "PASS: WP3 mutation checks (8 forbidden states all rejected)"
