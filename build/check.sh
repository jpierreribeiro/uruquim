#!/usr/bin/env bash
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_PIN_FILE="$URUQUIM_ROOT/odin-version.txt"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

test -f "$URUQUIM_PIN_FILE" || fail "missing odin-version.txt"
URUQUIM_EXPECTED_COMMIT="$(sed -n 's/^commit=//p' "$URUQUIM_PIN_FILE")"
test -n "$URUQUIM_EXPECTED_COMMIT" || fail "missing commit pin"

if test -n "${URUQUIM_ODIN_BIN:-}"; then
  URUQUIM_COMPILER="$URUQUIM_ODIN_BIN"
elif command -v odin >/dev/null 2>&1; then
  URUQUIM_COMPILER="$(command -v odin)"
elif test -x /tmp/uruquim-odin-toolchain/odin; then
  URUQUIM_COMPILER=/tmp/uruquim-odin-toolchain/odin
else
  fail "odin not found; install the pinned distribution or set URUQUIM_ODIN_BIN"
fi

URUQUIM_COMPILER="$(readlink -f "$URUQUIM_COMPILER")" ||
  fail "cannot resolve compiler path: $URUQUIM_COMPILER"
test -x "$URUQUIM_COMPILER" || fail "compiler is not executable: $URUQUIM_COMPILER"
URUQUIM_COMPILER_DIR="$(cd "$(dirname "$URUQUIM_COMPILER")" && pwd)"
if ! URUQUIM_VERSION="$(ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
  "$URUQUIM_COMPILER" version 2>&1)"; then
  fail "compiler version check failed: $URUQUIM_VERSION"
fi
case "$URUQUIM_VERSION" in
  *"$URUQUIM_EXPECTED_COMMIT"*) ;;
  *) fail "compiler mismatch: expected commit $URUQUIM_EXPECTED_COMMIT, got: $URUQUIM_VERSION" ;;
esac

test -d "$URUQUIM_COMPILER_DIR/core/net" || fail "pinned core:net package missing"
test -d "$URUQUIM_COMPILER_DIR/core/nbio" || fail "pinned core:nbio package missing"
test -d "$URUQUIM_COMPILER_DIR/core/encoding/json" ||
  fail "pinned core:encoding/json package missing"
command -v clang >/dev/null 2>&1 ||
  fail "clang not found; Odin needs it to link runnable checks"

bash -n "$URUQUIM_ROOT/build/check.sh"
bash -n "$URUQUIM_ROOT/build/check_test.sh"
bash -n "$URUQUIM_ROOT/build/check_public_api.sh"
bash -n "$URUQUIM_ROOT/build/check_wp3_mutations.sh"
bash -n "$URUQUIM_ROOT/build/check_g11_teardown.sh"
bash -n "$URUQUIM_ROOT/build/install-hooks.sh"
bash -n "$URUQUIM_ROOT/experiments/run_checks.sh"
bash -n "$URUQUIM_ROOT/.githooks/pre-push"
bash -n "$URUQUIM_ROOT/ops/ci/run.sh"
bash -n "$URUQUIM_ROOT/ops/ci/status.sh"
bash -n "$URUQUIM_ROOT/ops/ci/install-odin.sh"

# `odin test` writes its runner executable into the CURRENT WORKING DIRECTORY.
# It removes it again on success — but NOT when the test run fails, which drops
# a ~650 KiB ELF binary into the repository root on exactly the runs a developer
# is already iterating on. Every test binary is therefore given an explicit
# `-out:` under one temporary directory, so a red gate can never leave an
# artifact in the working tree. The directory lives in $TMPDIR, never in the repo.
URUQUIM_BIN_TMP="$(mktemp -d -t uruquim-test-bin-XXXXXXXX)"

echo "toolchain version: $URUQUIM_VERSION"
echo "toolchain commit: $URUQUIM_EXPECTED_COMMIT"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  bash "$URUQUIM_ROOT/experiments/run_checks.sh"

# WP1 — the public package must compile and its compile contract must hold.
# `web` is a library package, so -no-entry-point is required: without it the
# pinned compiler reports "Undefined entry point procedure 'main'".
echo "--- WP1 public API package (odin check) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_ROOT/web" \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point

echo "--- WP1 public API compile contract (odin test) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp1-public-api" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp1-public-api"

# WP2 — the request/response model.
#
# `Response`, `response_commit`, `method_from_token` and `Header_Pair` are
# package-private, and on the pinned toolchain an `@(test)` procedure must be
# compiled as part of the package it tests. Compiling those tests inside `web/`
# would link `core:testing` into every application binary (+41,592 bytes,
# measured on 819fdc7), so the shipped package contains no test file at all.
#
# Instead the gate assembles a THROWAWAY package: the real sources from `web/`
# plus `tests/wp2-internal/`, copied into a fresh `mktemp -d` directory. The
# tests therefore run against the genuine sources, not a stand-in. The
# directory is removed afterwards, including when the test run fails — the trap
# fires on the `set -e` exit. `build/check_public_api.sh` permanently forbids
# `*_test.odin` and `core:testing` under `web/`, so this cannot regress.
echo "--- WP2 request/response model, internal behavior (throwaway package) ---"
URUQUIM_TMP_PKG="$(mktemp -d -t uruquim-wp2-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP_PKG"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_TMP_PKG/"
cp "$URUQUIM_ROOT"/tests/wp2-internal/*.odin "$URUQUIM_TMP_PKG/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_TMP_PKG" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp2-internal"
rm -rf "$URUQUIM_TMP_PKG"
trap - EXIT
test ! -d "$URUQUIM_TMP_PKG" ||
  fail "the throwaway internal-test package was not removed"
echo "PASS: internal tests ran against the real sources; throwaway package removed"

echo "--- WP2 public surface contract (odin test) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp2-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp2-public-surface"

# WP2 compile probes. A negative probe must fail to compile AND fail for the
# stated reason: an unrelated compile error must never be read as proof that a
# symbol is unreachable.
URUQUIM_PROBES="$URUQUIM_ROOT/tests/wp2-public-surface/probes"

uruquim_negative_probe() { # file expected-diagnostic label
  local file="$1" expected="$2" label="$3"
  local output
  echo "--- WP2 probe: $label (expected compile failure) ---"
  # The compile is EXPECTED to fail, so it is run as the condition of an `if`:
  # under `set -e` a bare assignment from a failing command would abort here.
  if output="$(env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
    PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
    "$URUQUIM_COMPILER" check "$URUQUIM_PROBES/$file" -file \
    "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point 2>&1)"; then
    echo "$output" >&2
    fail "probe '$label' compiled; the symbol it must not reach is reachable"
  fi
  if ! grep -qF "$expected" <<<"$output"; then
    echo "$output" >&2
    fail "probe '$label' failed for the wrong reason; expected: $expected"
  fi
  echo "PASS: $label"
}

uruquim_negative_probe header_pair_not_exported.odin \
  "'Header_Pair' is not exported by 'web'" \
  "Header_Pair is not nameable from outside the package"

uruquim_negative_probe header_view_internal_not_exported.odin \
  "'Header_View_Internal' is not exported by 'web'" \
  "Header_View_Internal is not nameable from outside the package"

uruquim_negative_probe context_has_no_response.odin \
  "has no field 'response'" \
  "Context exposes no public response field"

# The matching POSITIVE probe records an accepted fact rather than a feature:
# `Header_View` is encapsulated BY CONTRACT, not opaque. If this ever stopped
# compiling, the documentation would be claiming a barrier Odin does not give.
echo "--- WP2 probe: internal slot stays reachable (expected compile success) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_PROBES/internal_slot_is_reachable.odin" -file \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point ||
  fail "the encapsulation-by-contract probe stopped compiling; ADR-008's scope statement would be wrong"
echo "PASS: encapsulation is by contract, not a barrier (ADR-008 scope confirmed)"

# WP3 — in-memory test transport (facade in package `web`, machinery in
# `web/testing`). The dependency is one-way: `web` imports `web/testing`, and
# `web/testing` imports neither `uruquim:web` (cycle) nor `core:testing`.
#
# Probe C1 — the machinery compiles ALONE as neutral, core-only code.
echo "--- WP3 probe C1: web/testing machinery compiles alone (neutral, core-only) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_ROOT/web/testing" \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point
echo "PASS: web/testing compiles as standalone machinery (C1)"

# Probe C2 — the facade compiles importing the machinery. `odin check web` above
# (the WP1 step) already exercised this once web/test_support.odin exists; this
# line names it as the ratified C2 evidence.
echo "--- WP3 probe C2: web facade compiles importing web/testing ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_ROOT/web" \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point
echo "PASS: web imports web/testing one-way (C2)"

# WP3 machinery internal behavior — copy/lifetime/ownership tests, in a
# THROWAWAY package exactly like WP2: the machinery sources plus the out-of-tree
# test file, so the shipped machinery ships no test code.
echo "--- WP3 machinery internal behavior (throwaway package) ---"
URUQUIM_WP3_TMP="$(mktemp -d -t uruquim-wp3-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP3_TMP"' EXIT
cp "$URUQUIM_ROOT"/web/testing/*.odin "$URUQUIM_WP3_TMP/"
cp "$URUQUIM_ROOT"/tests/wp3-internal/*.odin "$URUQUIM_WP3_TMP/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_WP3_TMP" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp3-internal"
rm -rf "$URUQUIM_WP3_TMP"
trap - EXIT
test ! -d "$URUQUIM_WP3_TMP" || fail "the throwaway WP3 machinery-test package was not removed"
echo "PASS: machinery internal tests ran against the real sources; throwaway package removed"

# WP3 public surface — external consumer of `uruquim:web` that RUNS
# `web.test_request` (probe C4): it completes with no socket, and its result is
# readable as status/body. Memory tracking (default in `odin test`) enforces the
# lazy-state and cleanup claims.
echo "--- WP3 public surface contract, incl. C4 in-memory round trip (odin test) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp3-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp3-public-surface"

# WP3 negative probe — `Recorded_Response` has no public `headers` field.
URUQUIM_WP3_PROBE="$URUQUIM_ROOT/tests/wp3-public-surface/probes/recorded_response_has_no_headers.odin"
echo "--- WP3 probe: Recorded_Response has no public headers field (expected compile failure) ---"
if URUQUIM_WP3_OUT="$(env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
  PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_WP3_PROBE" -file \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point 2>&1)"; then
  echo "$URUQUIM_WP3_OUT" >&2
  fail "probe compiled; Recorded_Response.headers is reachable and must not be"
fi
if ! grep -qF "has no field 'headers'" <<<"$URUQUIM_WP3_OUT"; then
  echo "$URUQUIM_WP3_OUT" >&2
  fail "the no-headers probe failed for the wrong reason; expected: has no field 'headers'"
fi
echo "PASS: Recorded_Response exposes no public headers field"

# Probe C5 — the back-edge `web/testing -> web` is a COMPILE CYCLE. Copy the two
# packages into a throwaway tree, inject the committed back-edge fixture into the
# copied machinery, and check the copied facade: it must fail with the exact
# cyclic-import diagnostic. This is the versioned WP3 C5 contract.
echo "--- WP3 probe C5: web/testing -> web back-edge is a compile cycle (expected failure) ---"
URUQUIM_WP3_CYCLE="$(mktemp -d -t uruquim-wp3-cycle-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP3_CYCLE"' EXIT
mkdir -p "$URUQUIM_WP3_CYCLE/web/testing" "$URUQUIM_WP3_CYCLE/web/internal/transport" \
  "$URUQUIM_WP3_CYCLE/vendor/odin-http"
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_WP3_CYCLE/web/"
cp "$URUQUIM_ROOT"/web/testing/*.odin "$URUQUIM_WP3_CYCLE/web/testing/"
# WP8: `web` now imports the transport, which imports the vendored backend, so
# the throwaway tree must carry both or the probe fails to resolve an import
# instead of reporting the cycle it exists to prove.
cp "$URUQUIM_ROOT"/web/internal/transport/*.odin "$URUQUIM_WP3_CYCLE/web/internal/transport/"
cp "$URUQUIM_ROOT"/vendor/odin-http/*.odin "$URUQUIM_WP3_CYCLE/vendor/odin-http/"
cp "$URUQUIM_ROOT"/tests/wp3-probes/back_edge_import.odin "$URUQUIM_WP3_CYCLE/web/testing/"
if URUQUIM_WP3_CYCLE_OUT="$(env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
  PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_WP3_CYCLE/web" \
  "-collection:uruquim=$URUQUIM_WP3_CYCLE" -no-entry-point 2>&1)"; then
  echo "$URUQUIM_WP3_CYCLE_OUT" >&2
  fail "the back-edge compiled; web/testing -> web must be a compile cycle (C5)"
fi
# EITHER side of the cycle is acceptable evidence. The compiler names whichever
# package it reaches first, and that depends on import-resolution order — WP6
# added `core:` imports to `web/` and flipped the reported side from
# 'web_testing' to 'web' without changing the fact being proven. Matching one
# exact spelling made this probe fail for a reason that had nothing to do with
# the dependency direction it exists to enforce.
if ! grep -qE "Cyclic importation of '(web|web_testing)'" <<<"$URUQUIM_WP3_CYCLE_OUT"; then
  echo "$URUQUIM_WP3_CYCLE_OUT" >&2
  fail "the back-edge failed for the wrong reason; expected a cyclic-import diagnostic naming 'web' or 'web_testing'"
fi
rm -rf "$URUQUIM_WP3_CYCLE"
trap - EXIT
echo "PASS: the one-way dependency is enforced by the compiler (C5)"

# WP4 — route registration, matching and dispatch.
#
# The route table, the matcher, `dispatch` and the private parameter storage in
# `Context_Internal` are all package-private, so these tests run in a THROWAWAY
# package exactly like WP2 and WP3: the real `web/` sources plus the
# out-of-tree test file, copied into a fresh `mktemp -d`.
#
# Two WP4 contracts are only observable from inside the package: the exact
# `Allow` header (Recorded_Response has no public headers field) and a routed
# 200 with a real body (the public responders are inert until WP6). Both are
# still driven through the REAL registration + dispatch path.
echo "--- WP4 route registration and dispatch, internal behavior (throwaway package) ---"
URUQUIM_WP4_TMP="$(mktemp -d -t uruquim-wp4-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP4_TMP"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_WP4_TMP/"
cp "$URUQUIM_ROOT"/tests/wp4-internal/*.odin "$URUQUIM_WP4_TMP/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_WP4_TMP" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp4-internal"
rm -rf "$URUQUIM_WP4_TMP"
trap - EXIT
test ! -d "$URUQUIM_WP4_TMP" || fail "the throwaway WP4 internal-test package was not removed"
echo "PASS: WP4 internal tests ran against the real sources; throwaway package removed"

# WP4 public surface — an EXTERNAL consumer of `uruquim:web` that registers
# routes and drives them through `web.test_request`. It proves that routing is
# expressible with the ratified 34 symbols and adds none, and that `app()` and
# `bare()` are now observably different. Memory tracking (default in
# `odin test`) covers the App-owned route table's cleanup.
echo "--- WP4 public surface contract: routing, 404, 405, bare (odin test) ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp4-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp4-public-surface"

# WP5 — the canonical path/query extractors and their private 400 envelope.
#
# The envelope machinery, the request-local storage it writes into, and the
# captured `Route_Param` that `web.path` reads are all package-private, so these
# tests run in a THROWAWAY package exactly like WP2, WP3 and WP4: the real
# `web/` sources plus the out-of-tree test file, copied into a fresh `mktemp -d`.
#
# Three WP5 contracts are only observable from inside the package: the exact
# bytes of the committed envelope, that the envelope body lives in request-local
# Context storage rather than an allocation, and that `web.path` consumes WP4's
# private capture (there is no public `ctx.params`). All are driven through the
# real extractors, and every envelope assertion is validated by the OFFICIAL
# `core:encoding/json` parser in strict `.JSON` mode.
echo "--- WP5 canonical extractors, internal behavior (throwaway package) ---"
URUQUIM_WP5_TMP="$(mktemp -d -t uruquim-wp5-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP5_TMP"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_WP5_TMP/"
cp "$URUQUIM_ROOT"/tests/wp5-internal/*.odin "$URUQUIM_WP5_TMP/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_WP5_TMP" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp5-internal"
rm -rf "$URUQUIM_WP5_TMP"
trap - EXIT
test ! -d "$URUQUIM_WP5_TMP" || fail "the throwaway WP5 internal-test package was not removed"
echo "PASS: WP5 internal tests ran against the real sources; throwaway package removed"

# WP5 public surface — an EXTERNAL consumer of `uruquim:web` that reads path and
# query parameters through the ratified surface only, and observes a failing
# `path_int` as a complete 400 through `web.test_request`. It proves extraction
# is expressible with the ratified 34 symbols and adds none.
echo "--- WP5 public surface contract: path/query extraction and the 400 envelope ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp5-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp5-public-surface"

# WP5 negative probes — ADR-002 option B is enforced by the COMPILER.
#
# The value-producing extractors omit `#optional_ok`, so dropping `ok` must be a
# compile error. Each probe is required to fail with the exact `Assignment count
# mismatch` diagnostic: an unrelated compile error must never be read as proof
# that the directive is absent.
#
# `#optional_ok` is not part of a procedure's TYPE, so the signature assertions
# in the public contract test cannot see it. These probes are the only executable
# evidence that the directive was not re-added (R-07).
URUQUIM_WP5_PROBES="$URUQUIM_ROOT/tests/wp5-public-surface/probes"

uruquim_wp5_discard_probe() { # file label
  local file="$1" label="$2"
  local output
  echo "--- WP5 probe: $label (expected compile failure) ---"
  if output="$(env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
    PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
    "$URUQUIM_COMPILER" check "$URUQUIM_WP5_PROBES/$file" -file \
    "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point 2>&1)"; then
    echo "$output" >&2
    fail "probe '$label' compiled; the extractor permits dropping ok, so #optional_ok is present (ADR-002)"
  fi
  if ! grep -qF "Assignment count mismatch" <<<"$output"; then
    echo "$output" >&2
    fail "probe '$label' failed for the wrong reason; expected: Assignment count mismatch"
  fi
  echo "PASS: $label"
}

uruquim_wp5_discard_probe discard_path_int_ok.odin \
  "dropping the ok of path_int is rejected"
uruquim_wp5_discard_probe discard_query_int_ok.odin \
  "dropping the ok of query_int is rejected"
uruquim_wp5_discard_probe discard_query_int_or_ok.odin \
  "dropping the ok of query_int_or is rejected"

# WP6 — response rendering, body ownership and the error envelope.
#
# The `Response`, both commit primitives, `response_destroy`, the envelope
# machinery and the typed framework-error report are all package-private, so
# these tests run in a THROWAWAY package exactly like WP2-WP5.
#
# Four WP6 contracts are only observable from inside the package: who OWNS a
# rendered body and whether the teardown released it exactly once; the exact
# `Content-Type` (Phase 1 ratifies no header accessor); that a rejected commit
# FREES the body it could not transfer; and that a marshal failure is LOGGED
# BEFORE the 500 is committed. Memory tracking (default in `odin test`) is what
# turns the ownership claims into assertions.
echo "--- WP6 response rendering and ownership, internal behavior (throwaway package) ---"
URUQUIM_WP6_TMP="$(mktemp -d -t uruquim-wp6-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP6_TMP"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_WP6_TMP/"
cp "$URUQUIM_ROOT"/tests/wp6-internal/*.odin "$URUQUIM_WP6_TMP/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_WP6_TMP" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp6-internal"
rm -rf "$URUQUIM_WP6_TMP"
trap - EXIT
test ! -d "$URUQUIM_WP6_TMP" || fail "the throwaway WP6 internal-test package was not removed"
echo "PASS: WP6 internal tests ran against the real sources; throwaway package removed"

# WP6 public surface — an EXTERNAL consumer driving every responder end-to-end
# through `web.test_request`. It proves the response contract is expressible with
# the ratified 34 symbols and adds none, and that bodies handed back earlier stay
# valid after later requests render and tear down their own buffers.
echo "--- WP6 public surface contract: responders, envelopes, automatic 404/405 ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp6-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp6-public-surface"

# WP7 — JSON body binding, the 4 MiB cap, and the request-lifetime arena.
#
# The arena, the body-consumption state, `Context_Internal` and the typed report
# are all package-private, so these tests run in a THROWAWAY package exactly like
# WP2-WP6. Memory tracking (default in `odin test`) is what turns the arena
# ownership and no-leak claims into assertions, and the internal tests reach the
# private `Body_State` and `request_arena_*` machinery directly.
echo "--- WP7 body binding and the request arena, internal behavior (throwaway package) ---"
URUQUIM_WP7_TMP="$(mktemp -d -t uruquim-wp7-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP7_TMP"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_WP7_TMP/"
cp "$URUQUIM_ROOT"/tests/wp7-internal/*.odin "$URUQUIM_WP7_TMP/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_WP7_TMP" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp7-internal"
rm -rf "$URUQUIM_WP7_TMP"
trap - EXIT
test ! -d "$URUQUIM_WP7_TMP" || fail "the throwaway WP7 internal-test package was not removed"
echo "PASS: WP7 internal tests ran against the real sources; throwaway package removed"

# WP7 public surface — an EXTERNAL consumer binding a body through the ratified
# surface. It proves body binding is expressible with the ratified 34 symbols and
# adds none, and that a body handler driven by `web.test_request` tears down
# cleanly.
echo "--- WP7 public surface contract: body binding, single-consumer, envelopes ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp7-public-surface" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp7-public-surface"

# WP8 — the real transport adapter, the response-driver finalization, and one
# end-to-end socket round-trip.
#
# The driver finalization and the neutral-boundary conversions are
# package-private, so the internal tests run in a THROWAWAY package like
# WP2-WP7.
echo "--- WP8 driver finalization and boundary, internal behavior (throwaway package) ---"
URUQUIM_WP8_TMP="$(mktemp -d -t uruquim-wp8-internal-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_WP8_TMP"' EXIT
cp "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_WP8_TMP/"
cp "$URUQUIM_ROOT"/tests/wp8-internal/*.odin "$URUQUIM_WP8_TMP/"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_WP8_TMP" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp8-internal"
rm -rf "$URUQUIM_WP8_TMP"
trap - EXIT
test ! -d "$URUQUIM_WP8_TMP" || fail "the throwaway WP8 internal-test package was not removed"
echo "PASS: WP8 internal tests ran against the real sources; throwaway package removed"

# WP8 transport boundary compile probes — the one-way dependency (ADR-009).
#
# C1: the adapter package compiles standalone (it names no web type).
echo "--- WP8 probe: web/internal/transport compiles standalone ---"
env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" check "$URUQUIM_ROOT/web/internal/transport" \
  "-collection:uruquim=$URUQUIM_ROOT" -no-entry-point
echo "PASS: the transport adapter compiles as standalone neutral code"

# WP8 real-socket round-trip. It binds a loopback port, so it runs under an
# EXTERNAL timeout and is the only test that touches a real socket. It cleans up
# its server and thread even on failure, and never sends SIGINT to this runner.
echo "--- WP8 real-socket contract: GET /ping, POST JSON, 413, clean stop (odin test) ---"
timeout 120 env ODIN_ROOT="$URUQUIM_COMPILER_DIR" PATH="$URUQUIM_COMPILER_DIR:/usr/bin:/bin" \
  "$URUQUIM_COMPILER" test "$URUQUIM_ROOT/tests/wp8-socket" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_BIN_TMP/wp8-socket" ||
  fail "the WP8 real-socket contract did not pass within the timeout"

# G-11 — the test-support teardown must not ship in applications that never
# test. Promised by planning/public-api-guardrails.md and, until now, never
# actually asserted.
echo "--- G-11 test-support teardown cost (nm) ---"
env URUQUIM_COMPILER="$URUQUIM_COMPILER" bash "$URUQUIM_ROOT/build/check_g11_teardown.sh"

echo "--- Phase-1 public API anti-accretion contract ---"
bash "$URUQUIM_ROOT/build/check_public_api.sh"

echo "--- WP3 mutation checks: forbidden dual-ledger states are rejected ---"
bash "$URUQUIM_ROOT/build/check_wp3_mutations.sh"

# The gate leaves NO artifact in the working tree.
rm -rf "$URUQUIM_BIN_TMP"
if find "$URUQUIM_ROOT" -maxdepth 1 -type f -name 'uruquim-*' -print -quit | grep -q .; then
  fail "a test-runner binary was left in the repository root"
fi
echo "PASS: the gate left no test-runner binary in the working tree"
