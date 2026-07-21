#!/usr/bin/env bash
# WP67 — JSON anatomy RED controls.
#
# Decoder/schema/internal suites are intentionally RED before WP68/WP81. This
# checker proves they fail for the registered missing behaviour, while the
# real-socket parity control and the disposable anatomy instrument stay green.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP67-CONTROL-FAIL: $*" >&2
  exit 1
}

if test -n "${URUQUIM_COMPILER:-}"; then
  URUQUIM_ODIN="$URUQUIM_COMPILER"
elif test -n "${URUQUIM_ODIN_BIN:-}"; then
  URUQUIM_ODIN="$URUQUIM_ODIN_BIN"
elif command -v odin >/dev/null 2>&1; then
  URUQUIM_ODIN="$(command -v odin)"
elif test -x /tmp/uruquim-odin-toolchain/odin; then
  URUQUIM_ODIN=/tmp/uruquim-odin-toolchain/odin
else
  fail "odin compiler not found"
fi

URUQUIM_ODIN="$(readlink -f "$URUQUIM_ODIN")"
URUQUIM_ODIN_ROOT="$(cd "$(dirname "$URUQUIM_ODIN")" && pwd)"
URUQUIM_TMP="$(mktemp -d -t uruquim-wp67-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

run_expected_red() { # package, output binary, diagnostic tokens...
  local package="$1" binary="$2"
  shift 2
  local output
  if output="$(env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
      "$package" "-collection:uruquim=$URUQUIM_ROOT" \
      "-out:$URUQUIM_TMP/$binary" 2>&1)"; then
    fail "$package unexpectedly passed; its owning implementation WP has not amended this control"
  fi
  for token in "$@"; do
    grep -qF "$token" <<<"$output" || {
      echo "$output" >&2
      fail "$package failed for the wrong reason; missing diagnostic token: $token"
    }
  done
}

run_expected_red \
  "$URUQUIM_ROOT/tests/wp67-json-boundary/decoder" decoder-red \
  "wp67_wrong_scalar_type_is_an_invalid_field" \
  "wp67_nested_type_mismatch_carries_a_stable_path" \
  "wp67_unknown_field_is_rejected_by_the_canonical_strict_path" \
  "3 tests failed"

run_expected_red \
  "$URUQUIM_ROOT/tests/wp67-json-boundary/schema" schema-red \
  "wp67_an_explicitly_required_field_may_not_be_absent" \
  "wp67_a_declared_range_failure_is_an_invalid_field" \
  "All tests failed."

URUQUIM_INTERNAL="$URUQUIM_TMP/internal-package"
mkdir "$URUQUIM_INTERNAL"
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_INTERNAL/"
cp "$URUQUIM_ROOT"/tests/wp67-json-boundary/internal/*.odin "$URUQUIM_INTERNAL/"
run_expected_red \
  "$URUQUIM_INTERNAL" internal-red \
  "wp67_decoder_allocation_failure_must_not_return_success_with_zero_values" \
  "got {\"error\":{\"code\":\"invalid_json\""

env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/wp67-json-boundary/transport-control" \
  "-collection:uruquim=$URUQUIM_ROOT" \
  "-out:$URUQUIM_TMP/transport-control"

URUQUIM_ANATOMY="$(env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" run \
  "$URUQUIM_ROOT/experiments/14-json-failure-anatomy" \
  "-collection:uruquim=$URUQUIM_ROOT" \
  "-out:$URUQUIM_TMP/anatomy")"
for URUQUIM_FACT in \
  "wrong scalar             status=500" \
  "nested mismatch          status=500" \
  "unknown field            status=204" \
  "required absent          status=204" \
  "validation range         status=204" \
  "decoder nil allocator    err=nil name=\"\" tags=[]"; do
  grep -qF "$URUQUIM_FACT" <<<"$URUQUIM_ANATOMY" ||
    fail "anatomy result drifted; missing: $URUQUIM_FACT"
done

echo "wp67: decoder RED is exactly type/path/unknown-field classification"
echo "wp67: schema RED stays separate for WP81 requiredness and validation"
echo "wp67: allocation failure is observable as the registered internal RED"
echo "wp67: memory and real-socket controls agree on the current classification"
echo "PASS: WP67 JSON failure anatomy controls"
