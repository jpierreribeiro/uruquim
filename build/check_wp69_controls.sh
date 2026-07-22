#!/usr/bin/env bash
# WP69 — deterministic blocking boundary. WP70 amended the drain obligation GREEN.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP69-CONTROL-FAIL: $*" >&2
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
URUQUIM_TMP="$(mktemp -d -t uruquim-wp69-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

run_green() {
  local suite="$1"
  timeout 20 env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
    "$URUQUIM_ROOT/tests/wp69-concurrency-lab/$suite" \
    "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
    "-out:$URUQUIM_TMP/$suite"
}

for URUQUIM_SUITE in candidate negative saturation slow-io repeatability drain; do
  run_green "$URUQUIM_SUITE"
done

URUQUIM_REPORT="$(timeout 20 env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" run \
  "$URUQUIM_ROOT/experiments/15-blocking-boundary" \
  "-collection:uruquim=$URUQUIM_ROOT" "-out:$URUQUIM_TMP/report")"
for URUQUIM_FACT in \
  "one-lane, one blocker      health_before_release=false" \
  "four lanes, three blockers health_before_release=true" \
  "four lanes, four blockers  health_before_release=false" \
  "job-pool arm                 not viable"; do
  grep -qF "$URUQUIM_FACT" <<<"$URUQUIM_REPORT" || fail "report drifted: $URUQUIM_FACT"
done

URUQUIM_MUTANT="$URUQUIM_TMP/mutant"
mkdir "$URUQUIM_MUTANT"
cp "$URUQUIM_ROOT/tests/wp69-concurrency-lab/candidate/candidate_test.odin" "$URUQUIM_MUTANT/"
sed -i 's/50970, 4/50970, 1/' "$URUQUIM_MUTANT/candidate_test.odin"
if timeout 20 env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
    "$URUQUIM_MUTANT" "-collection:uruquim=$URUQUIM_ROOT" \
    -define:ODIN_TEST_THREADS=1 "-out:$URUQUIM_TMP/mutant-bin" >/dev/null 2>&1; then
  fail "one-lane mutation unexpectedly preserved candidate liveness"
fi

grep -qF "opts.thread_count = 1" "$URUQUIM_ROOT/web/internal/transport/odin_http_adapter.odin" ||
  fail "WP69 must not ship speculative public concurrency"

echo "wp69: one lane loses health; four lanes retain it at three blocked handlers"
echo "wp69: idle/partial/slow-write I/O and repeated lifecycle controls are green"
echo "wp69: multi-lane drain is GREEN after WP70 made shutdown ownership exact-once"
echo "PASS: WP69 blocking-boundary controls"
