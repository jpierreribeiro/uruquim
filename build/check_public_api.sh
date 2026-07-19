#!/usr/bin/env bash
# Phase-1 public API contract — static repository assertions.
#
# Surface checkpoints: WP1 = 29 symbols; WP2 = 32 (29 + Request + Method +
# Header_View). The count is EXACT in both directions: a
# missing symbol and an extra symbol are equally a failure.
#
# WP3 (planning/public-api-guardrails.md G-11) adds a SECOND, separate ledger.
# The application ledger stays frozen at exactly 32. The test-support facade in
# `web/test_support.odin` — package `web`, exactly `Recorded_Response` and
# `test_request` — is its own 2-symbol ledger. The exported union is exactly 34.
# The machinery lives in `web/testing/` (package `testing`), imports neither
# `uruquim:web` (cycle) nor `core:testing`, and exposes a locked, minimal set of
# bridge declarations the facade calls across the package boundary.
#
# Verification-only: this script never modifies sources. It enforces the
# anti-accretion guardrails of `planning/public-api-guardrails.md`
# against the shipped public package.
#
# SCOPE (planning/public-api-guardrails.md G-06 and its false-positive rules): the transport-leak and
# dynamic-storage scans read ONLY the exported public package `web/` and, once
# it exists, `examples/`. They deliberately never read `knowledge-base/`,
# `planning/`, `docs/`, or `experiments/`. Backend names are
# expected and legitimate in internal architecture documentation; a textual
# mention there is not leakage.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_WEB="$URUQUIM_ROOT/web"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Expected web/ files: the seven WP1 files plus the three WP2 files. Anything
# else under web/ is scope creep or a later work package starting early.
#
# NO TEST FILE APPEARS HERE, and none ever may: see section 0.
#
# WP2 adds request.odin, response.odin and headers.odin (planning/phase-1-plan.md §WP2).
# It does NOT add a transport, a dispatch table, or a testing subpackage.
#
# WP3 adds exactly one top-level file, `test_support.odin` (the public
# test-support facade), and exactly one subdirectory, `web/testing/` (the
# machinery). No other top-level file and no other subdirectory is permitted.
# ---------------------------------------------------------------------------
#
# WP4 adds exactly TWO top-level files, `dispatch_table.odin` and
# `dispatch_match.odin`, and NO subdirectory. Every declaration in them is
# package-private, so the application ledger stays at exactly 32.
#
# The original plan proposed `web/internal/dispatch/*.odin`. That is refuted by
# the language: in Odin a subdirectory is a separate package, and the dispatcher
# must name `App`, `Handler`, `Context`, `Method` and the internal `Response` —
# so a subpackage would have to import `uruquim:web`, the back-edge WP3 already
# ratified as a compile cycle (probe C5). The checker is therefore extended by
# exactly two file names; it is NOT relaxed to accept subdirectories or
# arbitrary files (planning/phase-1-plan.md §WP4 D2).
URUQUIM_TEST_SUPPORT_FILE="test_support.odin"
URUQUIM_EXPECTED_APP_FILES="app.odin
context.odin
dispatch_match.odin
dispatch_table.odin
errors.odin
extract.odin
headers.odin
request.odin
request_arena.odin
respond.odin
response.odin
routing.odin
serve.odin"
URUQUIM_EXPECTED_FILES="$URUQUIM_EXPECTED_APP_FILES
$URUQUIM_TEST_SUPPORT_FILE"

# ---------------------------------------------------------------------------
# Expected Phase-1 exported surface after WP2 — 7 types + 25 procedures = 32.
# The Knowledge Base defines the surface; the permanent contracts below and in
# tests/ record its executable evidence.
#
# WP2 adds exactly three names. `Header_View_Internal`, `Header_Pair`,
# `Response`, `response_commit`, `method_from_token` and `header_view_from_pairs`
# are package-private and must NEVER appear in this list. There is no public
# `Response`, no `method_raw`, and no header lookup in Phase 1.
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_EXPORTS="App
Context
Handler
Header_View
Method
Request
Status
app
bad_request
bare
body
created
delete
destroy
forbidden
get
internal_error
json
no_content
not_found
ok
patch
path
path_int
post
put
query
query_int
query_int_or
serve
text
unauthorized"

# ---------------------------------------------------------------------------
# Expected test-support ledger after WP3 — exactly two public symbols, both in
# package `web`, both declared in `web/test_support.odin`
# (planning/public-api-guardrails.md G-11). `Recorded_Response` exposes only
# `status` and `body`;
# no `headers`, `committed`, allocator or transport field is public.
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_TESTSUPPORT_EXPORTS="Recorded_Response
test_request"

# The exact, locked set of declarations package `testing` (web/testing/) exports
# so the facade can call it across the package boundary. These are UNSUPPORTED
# INTERNALS, not a second public API: they are not part of the 34-symbol web
# surface, are undocumented for direct consumption, and this list exists to stop
# the bridge from growing silently. Growth here is a human-review item.
URUQUIM_EXPECTED_BRIDGE_EXPORTS="Header
Request
Test_Transport
build_request
capture
destroy"

test -d "$URUQUIM_WEB" || fail "web/ does not exist; WP1 has not created the public package"
URUQUIM_TESTING="$URUQUIM_WEB/testing"

# Every structural scan below reads CODE, not comments: a comment that names a
# forbidden construct in order to prohibit it must not be reported as that
# construct. (No string literal in the public package contains "//".)
uruquim_code_only() {
  sed -E 's://.*$::' "$URUQUIM_WEB"/*.odin
}

# ---------------------------------------------------------------------------
# 0. The shipped package carries NO test code (permanent)
#
# `Response`, `response_commit`, `method_from_token` and `Header_Pair` are
# package-private, and on the pinned toolchain an `@(test)` procedure must be
# compiled as part of the package it tests. Doing that inside `web/` would link
# `core:testing` into EVERY application binary — measured on 819fdc7 at +41,592
# bytes for a minimal consumer (42,624 -> 84,216), against +248 bytes for
# `core:strings`. That is exactly the hidden cost
# `knowledge-base/02-odin-idioms-guidelines.md` forbids.
#
# The internal tests therefore live in `tests/wp2-internal/`, still declaring
# `package web`, and `build/check.sh` compiles them against the real sources in
# a throwaway `mktemp -d` package. Both halves of that arrangement are asserted
# here:
#
#   a. web/ contains no `*_test.odin` file and imports no `core:testing`;
#   b. the out-of-tree internal test package exists and really is `package web`
#      — otherwise the harness would be silently testing nothing.
#
# These are permanent bans, not WP2 conveniences. A future work package that
# needs internal tests adds them to `tests/wp2-internal/` (or its own sibling),
# never to the shipped package.
# ---------------------------------------------------------------------------
if find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -name '*_test.odin' -print -quit | grep -q .; then
  fail "web/ contains a test file; internal tests belong in tests/wp2-internal/ and are compiled by build/check.sh in a throwaway package (core:testing must never reach an application binary)"
fi

if grep -lE '"core:testing"' "$URUQUIM_WEB"/*.odin; then
  fail "web/ imports core:testing; it would be linked into every application binary (+41,592 bytes measured on 819fdc7)"
fi

URUQUIM_INTERNAL_TESTS="$URUQUIM_ROOT/tests/wp2-internal"
test -d "$URUQUIM_INTERNAL_TESTS" ||
  fail "tests/wp2-internal/ is missing; the internal-behavior tests have no home outside the shipped package"
grep -qx 'package web' "$URUQUIM_INTERNAL_TESTS"/*.odin ||
  fail "tests/wp2-internal/ does not declare 'package web'; it could not reach the package-private declarations it exists to test"

# ---------------------------------------------------------------------------
# 0b. WP3 test machinery (planning/public-api-guardrails.md G-11)
#
# The facade `web/test_support.odin` and the machinery `web/testing/` carry the
# same permanent bans as the rest of the shipped package, plus the ones the
# one-way dependency rests on:
#
#   - no `*_test.odin` and no `core:testing` in `web/testing/` — the machinery
#     ships in application binaries exactly like `web/`, so it must not drag the
#     test runner in either;
#   - `web/testing/` must NOT import `uruquim:web`: the back-edge is a compile
#     cycle (ratified as probe C5), and forbidding the import statically catches
#     it before the slower compile probe runs;
#   - no `@(init)` anywhere in the test-support facade or the machinery: the
#     App's test-support state is zero/lazy, created only on the first
#     `test_request`, and an `@(init)` would run in every application binary
#     (planning/public-api-guardrails.md G-11, "no test-support package init side effect").
# ---------------------------------------------------------------------------
test -d "$URUQUIM_TESTING" ||
  fail "web/testing/ is missing; WP3 has not created the test machinery"

if find "$URUQUIM_TESTING" -mindepth 1 -maxdepth 1 -name '*_test.odin' -print -quit | grep -q .; then
  fail "web/testing/ contains a test file; internal machinery tests belong in tests/wp3-internal/ and are compiled by build/check.sh in a throwaway package"
fi

if grep -lE '"core:testing"' "$URUQUIM_TESTING"/*.odin; then
  fail "web/testing/ imports core:testing; the machinery ships in every application binary and must not link the test runner"
fi

if grep -lE '"core:testing"' "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE"; then
  fail "web/$URUQUIM_TEST_SUPPORT_FILE imports core:testing; the facade ships in every application binary"
fi

if grep -nE '"uruquim:web"' "$URUQUIM_TESTING"/*.odin; then
  fail "web/testing/ imports uruquim:web; the dependency is one-way and the back-edge is a compile cycle (WP3 C5)"
fi

# `@(init)` (with or without a run-order argument) is banned in both the facade
# and the machinery: it would run unconditionally in every binary.
if grep -nE '^@\(init' "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE" "$URUQUIM_TESTING"/*.odin; then
  fail "an @(init) proc appears in the test-support facade or machinery; the state must be zero/lazy (planning/public-api-guardrails.md G-11)"
fi

# The machinery may import `core:` freely; it may import nothing else. In
# particular it names no backend and does not reach back into `uruquim:web`.
URUQUIM_TESTING_IMPORTS="$(grep -hE '^import' "$URUQUIM_TESTING"/*.odin || true)"
if test -n "$URUQUIM_TESTING_IMPORTS"; then
  if grep -vE '"core:' <<<"$URUQUIM_TESTING_IMPORTS"; then
    fail "web/testing/ imports a package outside the core collection"
  fi
fi

# The test transport is IN-MEMORY: no socket, port, or network syscall on its
# path. Neither the facade nor the machinery may import a networking package.
# This makes "no sockets" a static property, not just a runtime observation.
if grep -nE '"core:(net|nbio|sys)' \
  "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE" "$URUQUIM_TESTING"/*.odin; then
  fail "the test-support facade or machinery imports a networking/syscall package; the test transport must be in-memory (KB §Test transport)"
fi

# The WP3 machinery file set is exactly these three files.
URUQUIM_TESTING_ACTUAL_FILES="$(cd "$URUQUIM_TESTING" && find . -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
URUQUIM_TESTING_EXPECTED_FILES="$(printf 'recorder.odin\nrequest_builder.odin\ntest_transport.odin\n')"
if test "$URUQUIM_TESTING_ACTUAL_FILES" != "$URUQUIM_TESTING_EXPECTED_FILES"; then
  echo "--- expected web/testing/ files ---" >&2
  echo "$URUQUIM_TESTING_EXPECTED_FILES" >&2
  echo "--- actual web/testing/ files ---" >&2
  echo "$URUQUIM_TESTING_ACTUAL_FILES" >&2
  fail "web/testing/ file set does not match the WP3 machinery contract"
fi
if test -n "$(find "$URUQUIM_TESTING" -mindepth 1 -maxdepth 1 -type d -print -quit)"; then
  fail "web/testing/ has subdirectories; the machinery is flat"
fi
# The declared package name is `web_testing`, NOT `testing`: a package named
# `testing` collides with `core:testing` at link time (link-name prefixing
# requires a unique package name across the binary). The import ALIAS in the
# facade is still `testing`, so callers write `testing.*` and the C5 cyclic
# diagnostic still names 'testing'.
grep -qx 'package web_testing' "$URUQUIM_TESTING"/*.odin ||
  fail "web/testing/ does not declare 'package web_testing'"

# The export inventory below reads only files that are NOT `#+private`, which
# is exactly what the compiler exports. This narrows the scan to match the
# language; it never widens what may be exported.
#
# `test_support.odin` is held out of this list: it is the SEPARATE test-support
# ledger (planning/public-api-guardrails.md G-11) and is scanned on its own below, so a symbol added
# to the facade can never be laundered into the frozen application count.
URUQUIM_PUBLIC_FILES=()
while IFS= read -r URUQUIM_FILE; do
  if head -n 20 "$URUQUIM_FILE" | grep -qx '#+private'; then
    continue
  fi
  if test "$(basename "$URUQUIM_FILE")" = "$URUQUIM_TEST_SUPPORT_FILE"; then
    continue
  fi
  URUQUIM_PUBLIC_FILES+=("$URUQUIM_FILE")
done < <(find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -name '*.odin' -type f | LC_ALL=C sort)

test "${#URUQUIM_PUBLIC_FILES[@]}" -gt 0 || fail "web/ contains no public production file"

uruquim_public_code_only() {
  sed -E 's://.*$::' "${URUQUIM_PUBLIC_FILES[@]}"
}

test -f "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE" ||
  fail "web/$URUQUIM_TEST_SUPPORT_FILE is missing; WP3 has not created the test-support facade"

uruquim_testsupport_code_only() {
  sed -E 's://.*$::' "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE"
}

# ---------------------------------------------------------------------------
# 1. File set
# ---------------------------------------------------------------------------
URUQUIM_ACTUAL_FILES="$(cd "$URUQUIM_WEB" && find . -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
URUQUIM_EXPECTED_FILES_SORTED="$(LC_ALL=C sort <<<"$URUQUIM_EXPECTED_FILES")"
if test "$URUQUIM_ACTUAL_FILES" != "$URUQUIM_EXPECTED_FILES_SORTED"; then
  echo "--- expected web/ files ---" >&2
  echo "$URUQUIM_EXPECTED_FILES_SORTED" >&2
  echo "--- actual web/ files ---" >&2
  echo "$URUQUIM_ACTUAL_FILES" >&2
  fail "web/ file set does not match the Phase-1 contract (WP1 seven + WP2 three + WP3 facade + WP4 two + WP7 request_arena)"
fi

# WP3 added `web/testing/`; WP8 adds `web/internal/` (the private transport
# boundary and adapter). No other subdirectory is permitted. Both are internal:
# neither adds a symbol to the application ledger, which the inventory below
# still pins at exactly 32.
URUQUIM_WEB_SUBDIRS="$(find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)"
URUQUIM_WEB_SUBDIRS_EXPECTED="$(printf 'internal\ntesting\n')"
if test "$URUQUIM_WEB_SUBDIRS" != "$URUQUIM_WEB_SUBDIRS_EXPECTED"; then
  echo "--- web/ subdirectories (only 'internal' and 'testing' are allowed) ---" >&2
  echo "$URUQUIM_WEB_SUBDIRS" >&2
  fail "web/ has an unexpected subdirectory; Phase 1 permits only web/testing/ and web/internal/"
fi

# WP8 — the transport boundary and adapter live under web/internal/transport/.
# It is a SEPARATE package that must never import `uruquim:web` (the one-way
# boundary, ADR-009 / WP8 D1); the adapter is the only place the backend may be
# imported. These are static guards; the compile probes back them.
URUQUIM_WEB_INTERNAL="$URUQUIM_WEB/internal"
if test -d "$URUQUIM_WEB_INTERNAL"; then
  URUQUIM_INTERNAL_SUBDIRS="$(find "$URUQUIM_WEB_INTERNAL" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)"
  if test "$URUQUIM_INTERNAL_SUBDIRS" != "transport"; then
    echo "--- web/internal subdirectories (only 'transport' is allowed) ---" >&2
    echo "$URUQUIM_INTERNAL_SUBDIRS" >&2
    fail "web/internal/ has an unexpected subdirectory; WP8 permits only web/internal/transport/"
  fi
  URUQUIM_TRANSPORT="$URUQUIM_WEB_INTERNAL/transport"
  if grep -nE '"uruquim:web"' "$URUQUIM_TRANSPORT"/*.odin; then
    fail "web/internal/transport imports uruquim:web; the transport boundary is one-way (ADR-009 / WP8 D1)"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Exported-symbol inventory (planning/public-api-guardrails.md G-01, G-09)
#
# A top-level declaration is exported unless the immediately preceding
# attribute line marks it private. Struct/enum members are indented and are
# therefore never mistaken for declarations.
# ---------------------------------------------------------------------------
uruquim_exported_names() {
  awk '
    /^[[:space:]]*$/ { next }
    /^\/\// { next }
    /^@\(/ { pending_attr = 1; if ($0 ~ /^@\(private/) { pending_private = 1 } next }
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*::/ {
      name = $1
      if (pending_private) { pending_private = 0; pending_attr = 0; next }
      pending_attr = 0
      print name
      next
    }
    { pending_attr = 0; pending_private = 0 }
  ' <<<"$URUQUIM_WEB_PUBLIC_CODE" | LC_ALL=C sort -u
}

URUQUIM_WEB_CODE="$(uruquim_code_only)"
URUQUIM_WEB_PUBLIC_CODE="$(uruquim_public_code_only)"
URUQUIM_ACTUAL_EXPORTS="$(uruquim_exported_names)"
URUQUIM_EXPECTED_EXPORTS_SORTED="$(LC_ALL=C sort -u <<<"$URUQUIM_EXPECTED_EXPORTS")"

# `comm` must collate the way the inputs were sorted. Without LC_ALL=C it
# applies the ambient locale to lists sorted in C order and aborts with
# "input is not in sorted order" — which fails safe under `set -e`, but hides
# WHICH symbol was added or lost. The diagnostic is the point of this section.
URUQUIM_EXTRA="$(LC_ALL=C comm -13 <(echo "$URUQUIM_EXPECTED_EXPORTS_SORTED") <(echo "$URUQUIM_ACTUAL_EXPORTS"))"
URUQUIM_MISSING="$(LC_ALL=C comm -23 <(echo "$URUQUIM_EXPECTED_EXPORTS_SORTED") <(echo "$URUQUIM_ACTUAL_EXPORTS"))"

if test -n "$URUQUIM_EXTRA"; then
  echo "--- unexpected exported symbols ---" >&2
  echo "$URUQUIM_EXTRA" >&2
  fail "web/ exports symbols outside the ratified Phase-1 surface (planning/public-api-guardrails.md G-01/G-09)"
fi
if test -n "$URUQUIM_MISSING"; then
  echo "--- missing exported symbols ---" >&2
  echo "$URUQUIM_MISSING" >&2
  fail "web/ is missing part of the ratified Phase-1 surface"
fi

echo "public API contract: application ledger is exactly 32 Phase-1 symbols"

# ---------------------------------------------------------------------------
# 2b. Test-support ledger (planning/public-api-guardrails.md G-11)
#
# `web/test_support.odin` exports EXACTLY `Recorded_Response` and
# `test_request`, and nothing else. Held apart from the application count so the
# two ledgers cannot grow against each other under one number.
# ---------------------------------------------------------------------------
URUQUIM_TESTSUPPORT_PUBLIC_CODE="$(uruquim_testsupport_code_only)"
URUQUIM_TESTSUPPORT_ACTUAL_EXPORTS="$(URUQUIM_WEB_PUBLIC_CODE="$URUQUIM_TESTSUPPORT_PUBLIC_CODE" uruquim_exported_names)"
URUQUIM_TESTSUPPORT_EXPECTED_SORTED="$(LC_ALL=C sort -u <<<"$URUQUIM_EXPECTED_TESTSUPPORT_EXPORTS")"

URUQUIM_TS_EXTRA="$(LC_ALL=C comm -13 <(echo "$URUQUIM_TESTSUPPORT_EXPECTED_SORTED") <(echo "$URUQUIM_TESTSUPPORT_ACTUAL_EXPORTS"))"
URUQUIM_TS_MISSING="$(LC_ALL=C comm -23 <(echo "$URUQUIM_TESTSUPPORT_EXPECTED_SORTED") <(echo "$URUQUIM_TESTSUPPORT_ACTUAL_EXPORTS"))"
if test -n "$URUQUIM_TS_EXTRA"; then
  echo "--- unexpected test-support exports ---" >&2
  echo "$URUQUIM_TS_EXTRA" >&2
  fail "web/$URUQUIM_TEST_SUPPORT_FILE exports outside the 2-symbol test-support ledger (planning/public-api-guardrails.md G-11)"
fi
if test -n "$URUQUIM_TS_MISSING"; then
  echo "--- missing test-support exports ---" >&2
  echo "$URUQUIM_TS_MISSING" >&2
  fail "web/$URUQUIM_TEST_SUPPORT_FILE is missing part of the test-support ledger"
fi

# `Recorded_Response` exposes exactly `status` and `body`, in that order, and NO
# other field — no `headers`, `committed`, allocator or transport.
URUQUIM_RECORDED_FIELDS="$(awk '/^Recorded_Response :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_TESTSUPPORT_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -v '^$')"
URUQUIM_RECORDED_EXPECTED="$(printf 'status\nbody\n')"
if test "$URUQUIM_RECORDED_FIELDS" != "$URUQUIM_RECORDED_EXPECTED"; then
  echo "--- expected Recorded_Response fields ---" >&2
  echo "$URUQUIM_RECORDED_EXPECTED" >&2
  echo "--- actual Recorded_Response fields ---" >&2
  echo "$URUQUIM_RECORDED_FIELDS" >&2
  fail "Recorded_Response must expose exactly status and body"
fi

# 2c. The exported union is EXACTLY 34 (32 application + 2 test-support), and the
# two ledgers are disjoint.
URUQUIM_APP_COUNT="$(grep -c . <<<"$URUQUIM_ACTUAL_EXPORTS")"
URUQUIM_TS_COUNT="$(grep -c . <<<"$URUQUIM_TESTSUPPORT_ACTUAL_EXPORTS")"
URUQUIM_UNION="$(printf '%s\n%s\n' "$URUQUIM_ACTUAL_EXPORTS" "$URUQUIM_TESTSUPPORT_ACTUAL_EXPORTS" | LC_ALL=C sort -u | grep -c .)"
if test "$URUQUIM_APP_COUNT" -ne 32; then
  fail "application ledger is $URUQUIM_APP_COUNT, not 32"
fi
if test "$URUQUIM_TS_COUNT" -ne 2; then
  fail "test-support ledger is $URUQUIM_TS_COUNT, not 2"
fi
if test "$URUQUIM_UNION" -ne 34; then
  fail "exported union is $URUQUIM_UNION, not 34 (the two ledgers must be disjoint)"
fi
echo "public API contract: test-support ledger is exactly 2; exported union is exactly 34"

# ---------------------------------------------------------------------------
# 2d. Bridge exports — the LOCKED, minimal set package `testing` exports so the
# facade can call it across the package boundary.
#
# These are unsupported internals, not a public API. The list is exact in both
# directions so the bridge cannot grow silently: a new machinery export is a
# human-review item, exactly like a new public symbol.
# ---------------------------------------------------------------------------
uruquim_testing_public_code() {
  URUQUIM_TESTING_FILES=()
  while IFS= read -r URUQUIM_TF; do
    if head -n 20 "$URUQUIM_TF" | grep -qx '#+private'; then
      continue
    fi
    URUQUIM_TESTING_FILES+=("$URUQUIM_TF")
  done < <(find "$URUQUIM_TESTING" -mindepth 1 -maxdepth 1 -name '*.odin' -type f | LC_ALL=C sort)
  sed -E 's://.*$::' "${URUQUIM_TESTING_FILES[@]}"
}
URUQUIM_BRIDGE_ACTUAL="$(URUQUIM_WEB_PUBLIC_CODE="$(uruquim_testing_public_code)" uruquim_exported_names)"
URUQUIM_BRIDGE_EXPECTED_SORTED="$(LC_ALL=C sort -u <<<"$URUQUIM_EXPECTED_BRIDGE_EXPORTS")"
URUQUIM_BRIDGE_EXTRA="$(LC_ALL=C comm -13 <(echo "$URUQUIM_BRIDGE_EXPECTED_SORTED") <(echo "$URUQUIM_BRIDGE_ACTUAL"))"
URUQUIM_BRIDGE_MISSING="$(LC_ALL=C comm -23 <(echo "$URUQUIM_BRIDGE_EXPECTED_SORTED") <(echo "$URUQUIM_BRIDGE_ACTUAL"))"
if test -n "$URUQUIM_BRIDGE_EXTRA"; then
  echo "--- unexpected web/testing bridge exports ---" >&2
  echo "$URUQUIM_BRIDGE_EXTRA" >&2
  fail "web/testing/ exports a declaration outside the locked bridge set; minimize it or record the growth for human review"
fi
if test -n "$URUQUIM_BRIDGE_MISSING"; then
  echo "--- missing web/testing bridge exports ---" >&2
  echo "$URUQUIM_BRIDGE_MISSING" >&2
  fail "web/testing/ no longer exports part of the locked bridge set the facade depends on"
fi
echo "public API contract: web/testing bridge exports match the locked minimal set"

# ---------------------------------------------------------------------------
# 3. Phase-2+ surface must not exist yet
#
# `test_request` is REMOVED from this list by WP3: it is now a
# ratified test-support symbol, pinned by ledger 2b above. `Response` stays
# forbidden; `Recorded_Response` is a different exact name and is allowed.
# The application ledger scanned here excludes test_support.odin, so the two
# ratified test-support names never reach this loop.
# ---------------------------------------------------------------------------
for URUQUIM_FUTURE in use router group mount next state app_with_state \
  header bearer_token serve_with serve_transport app_init \
  redirect conflict bytes logger recovery request_id cors \
  Response Header Header_Pair Header_View_Internal Params Route_Info \
  Transport method_raw headers commit; do
  if grep -qx "$URUQUIM_FUTURE" <<<"$URUQUIM_ACTUAL_EXPORTS"; then
    fail "later-phase symbol '$URUQUIM_FUTURE' is exported by the Phase-1 package"
  fi
done

# ---------------------------------------------------------------------------
# 4. Context is not an extension bag (planning/public-api-guardrails.md G-03)
#
# WP1 introduces no `any`, no dynamic bag, and no rawptr anywhere in web/.
# Phase 3 may introduce ONE private, typeid-validated rawptr for app_with_state
# (ADR-004); when it does, this check is narrowed spec-first to exported
# declarations rather than deleted.
# ---------------------------------------------------------------------------
if grep -nE '^[[:space:]]*(user_data|locals|values)[[:space:]]*:' <<<"$URUQUIM_WEB_CODE"; then
  fail "web/ declares an untyped request-local storage field (planning/public-api-guardrails.md G-03)"
fi
for URUQUIM_BAG in 'map\[string\]any' 'map\[any\]any' '\bany\b' '\brawptr\b' \
  'Handler_Error' 'Handler_Outcome'; do
  if grep -nE "$URUQUIM_BAG" <<<"$URUQUIM_WEB_CODE"; then
    fail "web/ uses a forbidden construct matching /$URUQUIM_BAG/ (planning/public-api-guardrails.md G-03, ADR-011)"
  fi
done

# The machinery is production code too: no `any`, no `rawptr`, no state bag, no
# duplicated public web type. It moves data as neutral records only.
URUQUIM_TESTING_CODE="$(sed -E 's://.*$::' "$URUQUIM_TESTING"/*.odin)"
for URUQUIM_BAG in 'map\[string\]any' 'map\[any\]any' '\bany\b' '\brawptr\b'; do
  if grep -nE "$URUQUIM_BAG" <<<"$URUQUIM_TESTING_CODE"; then
    fail "web/testing/ uses a forbidden construct matching /$URUQUIM_BAG/ (WP3 prompt: no any/rawptr/state bag in machinery)"
  fi
done

# ---------------------------------------------------------------------------
# 5. Canonical handler shape (ADR-011)
# ---------------------------------------------------------------------------
grep -qx 'Handler :: proc(ctx: ^Context)' "$URUQUIM_WEB/context.odin" ||
  fail "the canonical handler is not exactly 'Handler :: proc(ctx: ^Context)'"

# ---------------------------------------------------------------------------
# 6. Transport / backend leakage (planning/public-api-guardrails.md G-06)
#
# 6a. Hard backend identifiers have no legitimate use anywhere in web/.
# 6b. Backend-shaped type names must not appear in EXPORTED declarations. An
#     exported declaration block is the declaration line plus, for aggregate
#     types, its body up to the closing brace in column 1.
# ---------------------------------------------------------------------------
# Scoped to the exported package files and application examples. It does NOT
# recurse into web/internal/, where a future adapter (WP8) is exactly where
# backend names belong.
URUQUIM_LEAK_TEXT="$URUQUIM_WEB_CODE"
if test -d "$URUQUIM_ROOT/examples"; then
  URUQUIM_LEAK_TEXT+="
$(find "$URUQUIM_ROOT/examples" -name '*.odin' -exec sed -E 's://.*$::' {} +)"
fi

for URUQUIM_BACKEND in 'odin[-_]http' 'nbio' 'laytan'; do
  if grep -niE "$URUQUIM_BACKEND" <<<"$URUQUIM_LEAK_TEXT"; then
    fail "backend identifier matching /$URUQUIM_BACKEND/ reached the public package or examples (planning/public-api-guardrails.md G-06)"
  fi
done

uruquim_exported_blocks() {
  awk '
    /^[[:space:]]*$/ { next }
    /^\/\// { next }
    /^@\(/ { if ($0 ~ /^@\(private/) { pending_private = 1 } next }
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*::/ {
      if (pending_private) { pending_private = 0; skipping = ($0 ~ /\{[[:space:]]*$/); next }
      print
      emitting = ($0 ~ /\{[[:space:]]*$/)
      next
    }
    /^\}/ { emitting = 0; skipping = 0; next }
    emitting { print }
    { pending_private = 0 }
  ' <<<"$URUQUIM_WEB_PUBLIC_CODE"
}

URUQUIM_EXPORTED_BLOCKS="$(uruquim_exported_blocks)"
# Word-bounded: `Internal_Server_Error` is an HTTP status name, not a
# transport type, and must not be reported as leakage.
for URUQUIM_TYPE in '\bTransport\b' '\bSocket\b' '\bTCP\b' '\bConnection\b' \
  '\bServer\b' '\bnet\.' '\bhttp\.'; do
  if grep -nE "$URUQUIM_TYPE" <<<"$URUQUIM_EXPORTED_BLOCKS"; then
    fail "transport-shaped name matching /$URUQUIM_TYPE/ appears in an exported declaration (planning/public-api-guardrails.md G-06)"
  fi
done

# ---------------------------------------------------------------------------
# 7. Dependency policy — the public package may only import `core:` or
#    `uruquim:` packages. This is what keeps the odin-http -> core:net/http
#    migration a non-event for applications.
# ---------------------------------------------------------------------------
URUQUIM_IMPORTS="$(grep -hE '^import' "$URUQUIM_WEB"/*.odin || true)"
if test -n "$URUQUIM_IMPORTS"; then
  if grep -vE '"(core|uruquim):' <<<"$URUQUIM_IMPORTS"; then
    fail "web/ imports a package outside the core/uruquim collections"
  fi
fi

# ---------------------------------------------------------------------------
# 8. WP2 request/response model (planning/phase-1-plan.md §WP2;
#    planning/public-api-guardrails.md G-03/G-04/G-05; ADR-007/ADR-008)
#
# The three symbols WP2 adds are already pinned by the inventory above. What
# follows pins the SHAPE the inventory cannot see: which fields are public,
# which spelling the enum uses, and which internals stayed internal.
# ---------------------------------------------------------------------------

# 8a. Method is the exact ratified set, spelled in UPPERCASE. `.GET`, never
#     `.Get`. HEAD and OPTIONS are absent by decision: with this set they
#     convert to `.UNKNOWN`, which is the ratified Phase-1 behavior.
URUQUIM_METHOD_BODY="$(awk '/^Method :: enum u8 \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | tr -d '\t ,' | grep -v '^$' | LC_ALL=C sort)"
URUQUIM_METHOD_EXPECTED="$(printf 'DELETE\nGET\nPATCH\nPOST\nPUT\nUNKNOWN\n')"
if test "$URUQUIM_METHOD_BODY" != "$URUQUIM_METHOD_EXPECTED"; then
  echo "--- expected Method members ---" >&2
  echo "$URUQUIM_METHOD_EXPECTED" >&2
  echo "--- actual Method members ---" >&2
  echo "$URUQUIM_METHOD_BODY" >&2
  fail "Method is not the ratified Phase-1 set"
fi

# 8b. Request exposes exactly the five ratified fields, in the spec's order.
URUQUIM_REQUEST_FIELDS="$(awk '/^Request :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -v '^$')"
URUQUIM_REQUEST_EXPECTED="$(printf 'method\npath\nquery\nheaders\nbody\n')"
if test "$URUQUIM_REQUEST_FIELDS" != "$URUQUIM_REQUEST_EXPECTED"; then
  echo "--- expected Request fields ---" >&2
  echo "$URUQUIM_REQUEST_EXPECTED" >&2
  echo "--- actual Request fields ---" >&2
  echo "$URUQUIM_REQUEST_FIELDS" >&2
  fail "Request does not expose exactly the ratified fields (spec §Request/Response ownership)"
fi

# 8c. Header_View announces no representation. Exposing `pairs` as a public
#     field would freeze the pair layout into the API and export Header_Pair
#     with it; the nested private slot is the whole point of the wrapper.
URUQUIM_HEADER_VIEW_FIELDS="$(awk '/^Header_View :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -v '^$')"
if test "$URUQUIM_HEADER_VIEW_FIELDS" != "private"; then
  echo "--- actual Header_View fields ---" >&2
  echo "$URUQUIM_HEADER_VIEW_FIELDS" >&2
  fail "Header_View must expose only the nested private slot"
fi

# 8d. Context carries `request` and NEVER a `response` field. Applications
#     respond through the helpers; the commit state is internal (ADR-008).
URUQUIM_CONTEXT_FIELDS="$(awk '/^Context :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -v '^$')"
URUQUIM_CONTEXT_EXPECTED="$(printf 'request\nprivate\n')"
if test "$URUQUIM_CONTEXT_FIELDS" != "$URUQUIM_CONTEXT_EXPECTED"; then
  echo "--- expected Context fields ---" >&2
  echo "$URUQUIM_CONTEXT_EXPECTED" >&2
  echo "--- actual Context fields ---" >&2
  echo "$URUQUIM_CONTEXT_FIELDS" >&2
  fail "Context must expose exactly 'request' and the private slot: no public response, params or route (ADR-008)"
fi

# 8e-pre. The internal Response carries the minimum state WP4 depends on.
#
# WP4's TESTS-FIRST contract requires "405-when-other-method with exact Allow
# header", and WP4 depends on WP2/WP3 — it lands BEFORE WP6. Without internal
# header storage, WP4 could not express or test its own ratified contract, so
# `headers` is WP2 state, not deferred work. `Response` does not own that
# storage yet: headers and body are views until WP6 defines the concrete
# allocation and lifetime of a rendered response.
URUQUIM_RESPONSE_FIELDS="$(awk '/^Response :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -vE '^[[:space:]]*$')"
# AMENDED IN WP6 (ADR-014): `owned_body` and `body_allocator` record whether the
# committed body is an allocation this Response must release. Both are
# package-private, so the application ledger is unaffected.
URUQUIM_RESPONSE_EXPECTED="$(printf 'status\nheaders\nbody\ncommitted\nowned_body\nbody_allocator\n')"
if test "$URUQUIM_RESPONSE_FIELDS" != "$URUQUIM_RESPONSE_EXPECTED"; then
  echo "--- expected internal Response fields ---" >&2
  echo "$URUQUIM_RESPONSE_EXPECTED" >&2
  echo "--- actual internal Response fields ---" >&2
  echo "$URUQUIM_RESPONSE_FIELDS" >&2
  fail "the internal Response must carry status, headers, body and committed (planning/phase-1-plan.md §WP2; WP4 needs the Allow header)"
fi

# The commit primitive records all three together, so a rejected attempt
# cannot replace one of them while the guard blocks the others.
grep -qE '^response_commit :: proc\(res: \^Response, status: Status, headers: \[\]Header_Pair, body: \[\]u8\) -> bool \{$' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" ||
  fail "response_commit does not take status, headers and body together; the commit must be atomic across all three"

# 8e. The internal model stayed internal. Each of these must be declared, and
#     each must be preceded by @(private) — the inventory in section 2 already
#     proves they are not exported, and this proves they still exist and were
#     not quietly promoted.
for URUQUIM_INTERNAL in Response Header_Pair Header_View_Internal \
  response_commit method_from_token header_view_from_pairs; do
  grep -qE "^${URUQUIM_INTERNAL} ::" <<<"$URUQUIM_WEB_PUBLIC_CODE" ||
    fail "internal WP2 declaration '$URUQUIM_INTERNAL' is missing from web/"
  grep -qx "$URUQUIM_INTERNAL" <<<"$URUQUIM_ACTUAL_EXPORTS" &&
    fail "internal WP2 declaration '$URUQUIM_INTERNAL' became exported"
done

# 8f. WP2 decides no HTTP status automatically. 404/405/501 are WP4/WP9, and a
#     status literal in the request/response model would mean WP2 started
#     making response policy decisions.
URUQUIM_WP2_CODE="$(sed -E 's://.*$::' \
  "$URUQUIM_WEB/request.odin" "$URUQUIM_WEB/response.odin" "$URUQUIM_WEB/headers.odin")"
if grep -nE '\b(404|405|501|Not_Found|Method_Not_Allowed)\b' <<<"$URUQUIM_WP2_CODE"; then
  fail "the WP2 model decides an HTTP status; 404/405/501 decisions belong to WP4/WP9"
fi

# 8g. No header lookup exists in Phase 1 (`web.header` is Phase 2).
if grep -nE '^(header|headers|bearer_token|header_get) ::' <<<"$URUQUIM_WEB_PUBLIC_CODE"; then
  fail "a header lookup entered the Phase-1 package; web.header is Phase 2"
fi

# ---------------------------------------------------------------------------
# 9. WP4 route registration and dispatch (planning/phase-1-plan.md §WP4 D1-D5)
#
# WP4 adds BEHAVIOR, not surface. The inventory above already proves the ledger
# stayed at 32; what follows pins the properties the inventory cannot see.
# ---------------------------------------------------------------------------
URUQUIM_DISPATCH_TABLE="$URUQUIM_WEB/dispatch_table.odin"
URUQUIM_DISPATCH_MATCH="$URUQUIM_WEB/dispatch_match.odin"
test -f "$URUQUIM_DISPATCH_TABLE" ||
  fail "web/dispatch_table.odin is missing; WP4 has not created the route table"
test -f "$URUQUIM_DISPATCH_MATCH" ||
  fail "web/dispatch_match.odin is missing; WP4 has not created the matcher"

URUQUIM_WP4_CODE="$(sed -E 's://.*$::' "$URUQUIM_DISPATCH_TABLE" "$URUQUIM_DISPATCH_MATCH")"

# 9a. EVERY declaration the two WP4 files add is package-private. The route
#     table, the entry type, the matcher and `dispatch` are all internal: Phase
#     3 replaces them wholesale, and an exported one would freeze the interim
#     dispatcher into the public API.
URUQUIM_WP4_EXPORTS="$(URUQUIM_WEB_PUBLIC_CODE="$URUQUIM_WP4_CODE" uruquim_exported_names)"
if test -n "$URUQUIM_WP4_EXPORTS"; then
  echo "--- exported symbols in the WP4 dispatch files ---" >&2
  echo "$URUQUIM_WP4_EXPORTS" >&2
  fail "the WP4 dispatch files export a symbol; every dispatch declaration must be package-private (planning/phase-1-plan.md §WP4 D1/D2)"
fi

# 9b. `dispatch` takes the App EXPLICITLY (D3). The WP3 stub `dispatch(ctx)` had
#     no access to the App-owned table; no pointer to App is stored on Context.
grep -qE '^dispatch :: proc\(a: \^App, ctx: \^Context\) \{$' <<<"$URUQUIM_WP4_CODE" ||
  fail "dispatch does not have the ratified internal signature 'dispatch :: proc(a: ^App, ctx: ^Context)' (planning/phase-1-plan.md §WP4 D3)"

# 9c. The App holds no back-pointer inside the Context. A stored `^App` would
#     make the request context outlive-sensitive and is not how dispatch reaches
#     the table (D3).
if grep -nE '^[[:space:]]*[a-z_]+:[[:space:]]*\^App' <<<"$(awk '/^Context_Internal :: struct \{/{f=1;next} /^\}/{f=0} f' <<<"$URUQUIM_WEB_CODE")"; then
  fail "Context_Internal stores a pointer to App; dispatch receives the App explicitly instead (planning/phase-1-plan.md §WP4 D3)"
fi

# 9d. The `Allow` header name and its canonical method order are exact and
#     deterministic (D4). The order is a property of the framework, never of the
#     application's registration sequence.
grep -qE '^ALLOW_HEADER_NAME :: "Allow"$' <<<"$URUQUIM_WP4_CODE" ||
  fail "the 405 header name is not exactly \"Allow\" (planning/phase-1-plan.md §WP4 D4)"
grep -qE '^ALLOW_METHOD_ORDER :: \[5\]Method\{\.GET, \.POST, \.PUT, \.PATCH, \.DELETE\}$' \
  <<<"$URUQUIM_WP4_CODE" ||
  fail "the Allow method order is not the canonical GET, POST, PUT, PATCH, DELETE (planning/phase-1-plan.md §WP4 D4)"

# 9e. WP4 is the INTERIM dispatcher. Radix/trie/wildcard vocabulary and any
#     middleware machinery belong to Phase 3 and Phase 2 respectively; finding
#     them here means a later phase started early (R-12).
for URUQUIM_EARLY in 'radix' '\btrie\b' 'wildcard' 'Route_Node' 'Resolved_Route' \
  'middleware' 'chain_cursor'; do
  if grep -niE "$URUQUIM_EARLY" <<<"$URUQUIM_WP4_CODE"; then
    fail "later-phase routing construct matching /$URUQUIM_EARLY/ appears in the WP4 dispatcher (Phase 2/3 scope, R-12)"
  fi
done

# 9f. WP4 decides 404 and 405 — and NOTHING else. A 501 for an unknown method,
#     or any other automatic status, is a response policy WP4 has no mandate to
#     freeze (D4).
if grep -nE '\b(501|Not_Implemented|Internal_Server_Error|Bad_Request|Unauthorized|Forbidden)\b' \
  <<<"$URUQUIM_WP4_CODE"; then
  fail "the WP4 dispatcher decides a status outside 404/405; .UNKNOWN never becomes a 501 (planning/phase-1-plan.md §WP4 D4)"
fi

# 9g. The WP4 internal tests live OUTSIDE the shipped package, like WP2/WP3.
URUQUIM_WP4_TESTS="$URUQUIM_ROOT/tests/wp4-internal"
test -d "$URUQUIM_WP4_TESTS" ||
  fail "tests/wp4-internal/ is missing; the WP4 internal-behavior tests have no home outside the shipped package"
grep -qx 'package web' "$URUQUIM_WP4_TESTS"/*.odin ||
  fail "tests/wp4-internal/ does not declare 'package web'; it could not reach the package-private dispatcher it exists to test"

# ---------------------------------------------------------------------------
# 10. WP5 canonical extractors (planning/phase-1-plan.md §WP5; ADR-002; ADR-008)
#
# WP5 adds BEHAVIOR, not surface. The inventory above already proves the ledger
# stayed at 32 + 2 = 34; what follows pins the properties the inventory cannot
# see: the exact signatures, the absence of `#optional_ok`, and the fact that
# neither WP6 nor WP7 started early.
# ---------------------------------------------------------------------------
URUQUIM_EXTRACT="$URUQUIM_WEB/extract.odin"
test -f "$URUQUIM_EXTRACT" || fail "web/extract.odin is missing"
URUQUIM_EXTRACT_CODE="$(sed -E 's://.*$::' "$URUQUIM_EXTRACT")"

# 10a. `#optional_ok` appears NOWHERE in the shipped package (ADR-002 option B,
#      R-07).
#
#      The directive is not part of a procedure's type, so no signature
#      assertion below can see it and no public contract test can observe it.
#      This static ban plus the three compile probes in `build/check.sh` are the
#      only enforcement there is: with the directive, `id := web.path_int(...)`
#      compiles and silently drops an error the extractor already responded to.
#
#      It is checked BEFORE the signature assertions on purpose. Adding the
#      directive also breaks the exact-signature match below, so testing
#      signatures first would report "the signature changed" for what is really
#      a re-introduced `#optional_ok` — a true failure with a misleading cause.
#      The mutation cases in `build/check_wp3_mutations.sh` pin this ordering.
if grep -nE '#optional_ok' <<<"$URUQUIM_WEB_CODE"; then
  fail "#optional_ok appears in web/; the HTTP extractors must force the caller to handle ok (ADR-002, R-07)"
fi

# 10b. The five extractor signatures are EXACT. These are the ratified Phase-1
#      shapes (spec §Canonical Extractor Control Flow and §Canonical query
#      extractor family); WP5 implements them and changes none of them.
#
#      A signature change is a public API change even when the symbol count is
#      unmoved, which is precisely what the 32-symbol ledger cannot detect.
uruquim_expect_signature() { # exact-declaration-line label
  local decl="$1" label="$2"
  grep -qxF "$decl {" <<<"$URUQUIM_EXTRACT_CODE" ||
    fail "the ratified $label signature is not exactly '$decl' (planning/phase-1-plan.md §WP5)"
}

uruquim_expect_signature \
  'path :: proc(ctx: ^Context, name: string) -> string' 'web.path'
uruquim_expect_signature \
  'path_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool)' 'web.path_int'
uruquim_expect_signature \
  'query :: proc(ctx: ^Context, name: string) -> (value: string, found: bool)' 'web.query'
uruquim_expect_signature \
  'query_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool)' 'web.query_int'
uruquim_expect_signature \
  'query_int_or :: proc(ctx: ^Context, name: string, default_value: int) -> (value: int, ok: bool)' \
  'web.query_int_or'
uruquim_expect_signature \
  'body :: proc(ctx: ^Context, dst: ^$T) -> bool' 'web.body'

# 10c. WP6 shipped the responders WP5 deliberately left inert.
#
#      The "these must be empty stubs" assertions this section carried during
#      WP5 are GONE: keeping them would assert the absence of a delivered
#      feature. What replaces them pins the WP6 contract instead.
#
#      The JSON encoder may be imported, but only by the files that render or
#      decode: respond.odin and errors.odin marshal responses (WP6), and
#      extract.odin decodes the request body (WP7). The dispatcher must stay
#      encoder-free so that an application which never renders or binds a payload
#      does not drag the marshaller in.
URUQUIM_ENCODER_USERS="$(grep -lE '"core:encoding/json"' "$URUQUIM_WEB"/*.odin | xargs -r -n1 basename | LC_ALL=C sort)"
URUQUIM_ENCODER_EXPECTED="$(printf 'errors.odin\nextract.odin\nrespond.odin\n')"
if test "$URUQUIM_ENCODER_USERS" != "$URUQUIM_ENCODER_EXPECTED"; then
  echo "--- expected core:encoding/json importers ---" >&2
  echo "$URUQUIM_ENCODER_EXPECTED" >&2
  echo "--- actual ---" >&2
  echo "$URUQUIM_ENCODER_USERS" >&2
  fail "the JSON encoder is imported outside web/{respond,errors,extract}.odin; the dispatcher must stay encoder-free (WP6 D5 / WP7)"
fi

# The interim dispatcher must not marshal. Its 404/405 bodies are compile-time
# constants, which is what keeps it allocation-free and keeps the encoder out of
# every application that calls `web.app()` (WP6 D5).
if grep -nE 'encoding_json|marshal' <<<"$URUQUIM_WP4_CODE"; then
  fail "the WP4 dispatcher marshals a response; the automatic 404/405 bodies must stay static constants (WP6 D5)"
fi

# 10c-i. The response ownership machinery stayed INTERNAL. Each must exist and
#        each must be package-private: the ledger in section 2 proves they are
#        not exported, and this proves they were not quietly removed either.
for URUQUIM_WP6_INTERNAL in Response response_commit response_commit_owned \
  response_destroy Error_Envelope Framework_Report framework_report; do
  grep -qE "^${URUQUIM_WP6_INTERNAL} ::" <<<"$URUQUIM_WEB_PUBLIC_CODE" ||
    fail "internal WP6 declaration '$URUQUIM_WP6_INTERNAL' is missing from web/"
  grep -qx "$URUQUIM_WP6_INTERNAL" <<<"$URUQUIM_ACTUAL_EXPORTS" &&
    fail "internal WP6 declaration '$URUQUIM_WP6_INTERNAL' became exported; response ownership is not public API (ADR-014)"
done

# 10c-ii. No public cleanup symbol. An application must never be asked to free a
#         response: the driver does it (ADR-014 D1).
for URUQUIM_CLEANUP in response_destroy response_free response_release \
  free_response destroy_response; do
  if grep -qx "$URUQUIM_CLEANUP" <<<"$URUQUIM_ACTUAL_EXPORTS"; then
    fail "'$URUQUIM_CLEANUP' is exported; response teardown is framework business and must stay private"
  fi
done

# 10c-iii. The exact ratified Content-Type values (WP6 D3).
grep -qE '^CONTENT_TYPE_JSON :: "application/json"$' <<<"$URUQUIM_WEB_PUBLIC_CODE" ||
  fail "the JSON Content-Type is not exactly \"application/json\" (WP6 D3)"
grep -qE '^CONTENT_TYPE_TEXT :: "text/plain; charset=utf-8"$' <<<"$URUQUIM_WEB_PUBLIC_CODE" ||
  fail "the text Content-Type is not exactly \"text/plain; charset=utf-8\" (WP6 D3)"

# 10c-iv. `field` is OMITTED for a general error, never emitted empty or null
#         (AMEND-2). The envelope struct WP6 marshals must therefore have NO
#         `field` member at all — the omission is a property of the type, not of
#         a runtime emptiness check.
URUQUIM_ENVELOPE_FIELDS="$(awk '/^Error_Envelope_Body :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -vE '^[[:space:]]*$')"
URUQUIM_ENVELOPE_EXPECTED="$(printf 'code\nmessage\n')"
if test "$URUQUIM_ENVELOPE_FIELDS" != "$URUQUIM_ENVELOPE_EXPECTED"; then
  echo "--- expected Error_Envelope_Body members ---" >&2
  echo "$URUQUIM_ENVELOPE_EXPECTED" >&2
  echo "--- actual ---" >&2
  echo "$URUQUIM_ENVELOPE_FIELDS" >&2
  fail "the general error envelope must carry exactly code and message; 'field' is omitted by TYPE, not by omitempty (AMEND-2)"
fi
if grep -nE 'omitempty' <<<"$URUQUIM_WEB_CODE"; then
  fail "omitempty is used in web/; it decides on EMPTINESS and would also drop a field legitimately named \"\" (AMEND-2)"
fi

# 10c-v. Pointer payload support was NOT adopted. ADR-003's value-only baseline
#        stands until a human ratifies an amendment; the WP6 prototype is
#        recorded in the PR, not shipped.
if grep -nE 'Type_Info_Pointer|dereference|deref' <<<"$URUQUIM_WEB_CODE"; then
  fail "web/ appears to implement pointer-payload dereference; ADR-003 is value-only until a spec amendment is ratified (R-13)"
fi

# 10d. WP7 body binding — the positive contract that REPLACES the WP5/WP6 bans.
#
# WP7 shipped body binding, the request-lifetime arena and the 4 MiB cap, so the
# temporary "these must not exist" grep bans are gone. What replaces them pins
# the shape WP7 must actually have.
URUQUIM_ARENA_FILE="$URUQUIM_WEB/request_arena.odin"
test -f "$URUQUIM_ARENA_FILE" ||
  fail "web/request_arena.odin is missing; WP7 has not created the request arena machinery"
URUQUIM_ARENA_CODE="$(sed -E 's://.*$::' "$URUQUIM_ARENA_FILE")"

# 10d-i. The arena file exports NOTHING. Every declaration is package-private:
#        BODY_LIMIT, Body_State and the request_arena_* procedures are internal,
#        so the application ledger is unchanged (WP7 D1).
URUQUIM_ARENA_EXPORTS="$(URUQUIM_WEB_PUBLIC_CODE="$URUQUIM_ARENA_CODE" uruquim_exported_names)"
if test -n "$URUQUIM_ARENA_EXPORTS"; then
  echo "--- exported symbols in web/request_arena.odin ---" >&2
  echo "$URUQUIM_ARENA_EXPORTS" >&2
  fail "web/request_arena.odin exports a symbol; the arena machinery must be package-private (WP7 D1)"
fi

# 10d-ii. The cap is EXACTLY 4 MiB, spelled as the arithmetic the reviewer saw,
#         and the comparison rejects only a STRICTLY larger body (WP7 D3).
grep -qE '^BODY_LIMIT :: 4 \* 1024 \* 1024$' <<<"$URUQUIM_ARENA_CODE" ||
  fail "BODY_LIMIT is not exactly '4 * 1024 * 1024' (WP7 D3)"
# The over-limit test uses `>`, never `>=`: exactly 4 MiB must be accepted.
if grep -nE 'len\(raw\) >= BODY_LIMIT' <<<"$URUQUIM_EXTRACT_CODE"; then
  fail "the body cap uses '>=', so exactly 4 MiB would be rejected; it must be '>' (WP7 D3)"
fi
grep -qE 'len\(raw\) > BODY_LIMIT' <<<"$URUQUIM_EXTRACT_CODE" ||
  fail "web.body does not compare the body length against BODY_LIMIT with '>' (WP7 D3)"

# 10d-iii. The cap is checked BEFORE the parser. `unmarshal` must appear AFTER
#          the `len(raw) > BODY_LIMIT` guard in the source of `body`, so an
#          over-limit body is never handed to the decoder (WP7 D3).
URUQUIM_BODY_SRC="$(awk '/^body :: proc/{f=1} f{print} f && /^}/{exit}' <<<"$URUQUIM_EXTRACT_CODE")"
URUQUIM_LIMIT_LINE="$(grep -nE 'len\(raw\) > BODY_LIMIT' <<<"$URUQUIM_BODY_SRC" | head -1 | cut -d: -f1)"
URUQUIM_PARSE_LINE="$(grep -nE 'unmarshal\(' <<<"$URUQUIM_BODY_SRC" | head -1 | cut -d: -f1)"
test -n "$URUQUIM_LIMIT_LINE" -a -n "$URUQUIM_PARSE_LINE" ||
  fail "web.body must contain both the BODY_LIMIT guard and the unmarshal call (WP7 D3)"
test "$URUQUIM_LIMIT_LINE" -lt "$URUQUIM_PARSE_LINE" ||
  fail "web.body parses before checking the 4 MiB cap; the cap must gate the parser (WP7 D3)"

# 10d-iv. Decoding is STRICT JSON. The pinned encoder's default spec is JSON5,
#         which would accept unquoted keys, comments and single-quoted strings,
#         so the unmarshal call must pass `.JSON` explicitly (WP7 D5).
grep -qE 'unmarshal\(raw, dst, \.JSON,' <<<"$URUQUIM_EXTRACT_CODE" ||
  fail "web.body does not unmarshal in strict .JSON mode; JSON5 would be accepted (WP7 D5)"

# 10d-v. Body data is decoded into the ARENA, never context.allocator directly.
#        The unmarshal allocator must be the request arena, or nested data would
#        outlive nothing and leak (ADR-006).
grep -qE 'request_arena_allocator\(ctx\)' <<<"$URUQUIM_EXTRACT_CODE" ||
  fail "web.body does not decode into the request arena allocator (ADR-006 / WP7 D4)"
if grep -nE 'unmarshal\([^)]*context\.allocator' <<<"$URUQUIM_EXTRACT_CODE"; then
  fail "web.body unmarshals with context.allocator; decoded data must live in the request arena (ADR-006)"
fi

# 10d-vi. The single-consumer state machine exists and consumes BEFORE parsing.
#         `.Consumed` must be assigned before the unmarshal call (ADR-012 A).
URUQUIM_CONSUME_LINE="$(grep -nE 'body_state = \.Consumed' <<<"$URUQUIM_BODY_SRC" | head -1 | cut -d: -f1)"
test -n "$URUQUIM_CONSUME_LINE" ||
  fail "web.body never marks the body capability consumed; ADR-012 requires single use"
test "$URUQUIM_CONSUME_LINE" -lt "$URUQUIM_PARSE_LINE" ||
  fail "web.body consumes the capability after parsing; it must consume before (ADR-012 A)"

# 10d-vii. The driver frees the arena. `request_arena_destroy` must be called
#          from the test-support facade (the response driver), or a bound body
#          leaks (WP7 D4).
grep -qE 'request_arena_destroy\(' "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE" ||
  fail "web/$URUQUIM_TEST_SUPPORT_FILE does not call request_arena_destroy; the driver must free the arena (WP7 D4)"

# 10d-viii. NO configurable body limit, replay, or cache entered the package.
#           These are the WP7 non-goals the prompt forbids. The patterns target
#           configurability and replay specifically — a per-request `body_limit`
#           FIELD, a setter, a size knob, a replay/cache — without matching the
#           fixed `BODY_LIMIT` constant that the cap legitimately uses.
for URUQUIM_WP7_BAN in 'set_body_limit' 'max_body' 'body_replay' '\breplay\b' \
  'body_cache' 'Body_Cache' 'body_limit[[:space:]]*:' 'configurable'; do
  if grep -nE "$URUQUIM_WP7_BAN" <<<"$URUQUIM_WEB_CODE"; then
    fail "web/ contains a WP7 non-goal matching /$URUQUIM_WP7_BAN/ (no configurable limit, replay or cache)"
  fi
done

# 10d-ix. The two WP7 wire codes are spelled exactly right (docs/errors.md).
for URUQUIM_CODE in invalid_json body_too_large; do
  grep -qE "\"$URUQUIM_CODE\"" <<<"$URUQUIM_WEB_CODE" ||
    fail "the ratified WP7 error code '$URUQUIM_CODE' is missing from web/ (docs/errors.md)"
done

# 10d-x. 413 is carried WITHOUT a public Status member. The public enum member
#        list is frozen; a private `Status(413)` value is the sanctioned path
#        (WP7 D3).
if awk '/^Status :: enum int \{/{f=1;next} /^\}/{f=0} f' <<<"$URUQUIM_WEB_PUBLIC_CODE" |
  grep -qiE 'Payload_Too_Large|Too_Large|413'; then
  fail "a 413 member was added to the public Status enum; use a private Status(413) value instead (WP7 D3)"
fi
grep -qE '^STATUS_BODY_TOO_LARGE :: Status\(413\)$' <<<"$URUQUIM_WEB_CODE" ||
  fail "the private STATUS_BODY_TOO_LARGE :: Status(413) value is missing (WP7 D3)"

# 10e. The two WP5 error codes are spelled exactly as the ratified wire contract
#      requires (docs/errors.md). A typo here is a silent compatibility break:
#      clients match on `code`.
for URUQUIM_CODE in invalid_path_parameter invalid_query_parameter; do
  grep -qE "\"$URUQUIM_CODE\"" <<<"$URUQUIM_WEB_CODE" ||
    fail "the ratified error code '$URUQUIM_CODE' is missing from web/ (docs/errors.md)"
done

# 10f. The WP5 internal tests live OUTSIDE the shipped package, like WP2/WP3/WP4.
URUQUIM_WP5_TESTS="$URUQUIM_ROOT/tests/wp5-internal"
test -d "$URUQUIM_WP5_TESTS" ||
  fail "tests/wp5-internal/ is missing; the WP5 internal-behavior tests have no home outside the shipped package"
grep -qx 'package web' "$URUQUIM_WP5_TESTS"/*.odin ||
  fail "tests/wp5-internal/ does not declare 'package web'; it could not reach the package-private envelope machinery it exists to test"

# The three discard probes must exist: they are the ONLY executable evidence
# that `#optional_ok` was not re-added.
for URUQUIM_PROBE_FILE in discard_path_int_ok discard_query_int_ok discard_query_int_or_ok; do
  test -f "$URUQUIM_ROOT/tests/wp5-public-surface/probes/$URUQUIM_PROBE_FILE.odin" ||
    fail "the WP5 negative probe '$URUQUIM_PROBE_FILE.odin' is missing; ADR-002 would be unenforced"
done

echo "public API contract: web/ file set matches the Phase-1 contract through WP3"
echo "public API contract: application ledger 32 + test-support ledger 2 = union 34"
echo "public API contract: Method is the ratified UPPERCASE set; Request has the five ratified fields"
echo "public API contract: Response, Header_Pair and Header_View_Internal stayed internal"
echo "public API contract: web/testing machinery imports no uruquim:web / core:testing, declares no @(init)"
echo "public API contract: no later-phase symbol, dynamic storage, or backend leak"
echo "public API contract: WP4 dispatch files export nothing; dispatch takes the App explicitly"
echo "public API contract: Allow is exactly 'Allow' in canonical GET, POST, PUT, PATCH, DELETE order"
echo "public API contract: no radix/wildcard/middleware construct entered the interim dispatcher"
echo "public API contract: the five extractor signatures are exact and carry no #optional_ok"
echo "public API contract: the JSON encoder is imported only by respond.odin and errors.odin"
echo "public API contract: response ownership and the envelope machinery stayed internal"
echo "public API contract: Content-Type values are exact and 'field' is omitted by type"
echo "public API contract: WP7 arena is private; the 4 MiB cap gates the parser; strict JSON; 413 is a private Status value"
echo "PASS: Phase-1 public API anti-accretion contract (WP1 + WP2 + WP3 + WP4 + WP5 + WP6 + WP7)"
