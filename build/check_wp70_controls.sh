#!/usr/bin/env bash
# WP70 — immutable serving publication and race-free framework-owned state.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP70-CONTROL-FAIL: $*" >&2
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
URUQUIM_TMP="$(mktemp -d -t uruquim-wp70-controls-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

run_internal() { # package, binary
  env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test "$1" \
    "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
    "-out:$URUQUIM_TMP/$2"
}

URUQUIM_INTERNAL="$URUQUIM_TMP/internal"
mkdir "$URUQUIM_INTERNAL"
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_INTERNAL/"
cp "$URUQUIM_ROOT/tests/wp70-thread-safety/wp70_internal_test.odin" "$URUQUIM_INTERNAL/"
run_internal "$URUQUIM_INTERNAL" internal-green

timeout 20 env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test \
  "$URUQUIM_ROOT/tests/wp70-thread-safety/stop" \
  "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
  "-out:$URUQUIM_TMP/stop"

# Three independent mutations prove the contention corpus owns the mechanism:
# IDs must allocate atomically, lazy miss state must be completed before
# publication, and configuration after publication must not alter the snapshot.
mutant_must_fail() { # name, sed expression, file
  local name="$1" expression="$2" file="$3"
  local mutant="$URUQUIM_TMP/mutant-$name"
  mkdir "$mutant"
  cp "$URUQUIM_ROOT"/web/*.odin "$mutant/"
  cp "$URUQUIM_ROOT/tests/wp70-thread-safety/wp70_internal_test.odin" "$mutant/"
  sed -i "$expression" "$mutant/$file"
  if env ODIN_ROOT="$URUQUIM_ODIN_ROOT" "$URUQUIM_ODIN" test "$mutant" \
      "-collection:uruquim=$URUQUIM_ROOT" -define:ODIN_TEST_THREADS=1 \
      "-out:$URUQUIM_TMP/mutant-$name-bin" >/dev/null 2>&1; then
    fail "$name mutation unexpectedly passed"
  fi
}

mutant_must_fail request-id \
  's/counter := sync.atomic_add(&request_id_counter, 1) + 1/counter := u64(1)/' \
  request_id.odin
mutant_must_fail miss-publication \
  's/^\tmiss_chain_ensure(a)$/\t\/\/ mutation: publish incomplete state/' \
  concurrency.odin
mutant_must_fail late-route \
  '0,/^\tif app_is_serving(a) {$/s//\tif false {/' \
  dispatch_table.odin

grep -qF 'mutex:  sync.Mutex' \
  "$URUQUIM_ROOT/web/internal/transport/odin_http_adapter.odin" ||
  fail "adapter server lifetime is not protected"
grep -qF 'sync.atomic_add(&server.refused_total, 1)' \
  "$URUQUIM_ROOT/vendor/odin-http/server.odin" ||
  fail "multi-lane refusal total is not atomic"
grep -qF 'date:       Server_Date' "$URUQUIM_ROOT/vendor/odin-http/server.odin" ||
  fail "the Date cache is not lane-owned"

echo "wp70: immutable App publication and 8-lane request-ID/dispatch contention are green"
echo "wp70: 16 concurrent stop callers elect exactly one backend shutdown owner"
echo "wp70: request-ID, miss-publication and late-route mutations are rejected"
echo "PASS: WP70 thread-safe core controls"
