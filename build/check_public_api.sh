#!/usr/bin/env bash
# Phase-1 public API contract — static repository assertions.
#
# Surface checkpoints: WP1 = 29 symbols; WP2 = 32 (29 + Request + Method +
# Header_View, planning/18 Part I). The count is EXACT in both directions: a
# missing symbol and an extra symbol are equally a failure.
#
# WP3 (planning/21 Decision 2, planning/15 G-11) adds a SECOND, separate ledger.
# The application ledger stays frozen at exactly 32. The test-support facade in
# `web/test_support.odin` — package `web`, exactly `Recorded_Response` and
# `test_request` — is its own 2-symbol ledger. The exported union is exactly 34.
# The machinery lives in `web/testing/` (package `testing`), imports neither
# `uruquim:web` (cycle) nor `core:testing`, and exposes a locked, minimal set of
# bridge declarations the facade calls across the package boundary.
#
# Verification-only: this script never modifies sources. It enforces the
# anti-accretion guardrails of `planning/15-public-api-anti-accretion-guardrails.md`
# against the shipped public package.
#
# SCOPE (planning/15 G-06 and its false-positive rules): the transport-leak and
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
# WP2 adds request.odin, response.odin and headers.odin (planning/05 §WP2).
# It does NOT add a transport, a dispatch table, or a testing subpackage.
#
# WP3 adds exactly one top-level file, `test_support.odin` (the public
# test-support facade), and exactly one subdirectory, `web/testing/` (the
# machinery). No other top-level file and no other subdirectory is permitted.
# ---------------------------------------------------------------------------
URUQUIM_TEST_SUPPORT_FILE="test_support.odin"
URUQUIM_EXPECTED_APP_FILES="app.odin
context.odin
errors.odin
extract.odin
headers.odin
request.odin
respond.odin
response.odin
routing.odin
serve.odin"
URUQUIM_EXPECTED_FILES="$URUQUIM_EXPECTED_APP_FILES
$URUQUIM_TEST_SUPPORT_FILE"

# ---------------------------------------------------------------------------
# Expected Phase-1 exported surface after WP2 — 7 types + 25 procedures = 32.
# Every WP1 entry is justified in planning/17-wp1-gate.md and every WP2 entry
# in planning/20-wp2-gate.md, with its spec section, evidence, owning phase,
# and ratified/nominal status.
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
# package `web`, both declared in `web/test_support.odin` (planning/15 G-11,
# planning/21 Decision 2). `Recorded_Response` exposes only `status` and `body`;
# no `headers`, `committed`, allocator or transport field is public.
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_TESTSUPPORT_EXPORTS="Recorded_Response
test_request"

# The exact, locked set of declarations package `testing` (web/testing/) exports
# so the facade can call it across the package boundary. These are UNSUPPORTED
# INTERNALS, not a second public API: they are not part of the 34-symbol web
# surface, are undocumented for direct consumption, and this list exists to stop
# the bridge from growing silently (planning/23-wp3-gate.md; the WP3 prompt's
# "bridge exports internos"). Growth here is a human-review item.
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
# 0b. WP3 test machinery (planning/21, planning/15 G-11)
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
#     (planning/15 G-11, "no test-support package init side effect").
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
  fail "web/testing/ imports uruquim:web; the dependency is one-way and the back-edge is a compile cycle (planning/21 C5)"
fi

# `@(init)` (with or without a run-order argument) is banned in both the facade
# and the machinery: it would run unconditionally in every binary.
if grep -nE '^@\(init' "$URUQUIM_WEB/$URUQUIM_TEST_SUPPORT_FILE" "$URUQUIM_TESTING"/*.odin; then
  fail "an @(init) proc appears in the test-support facade or machinery; the state must be zero/lazy (planning/15 G-11)"
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
  fail "the test-support facade or machinery imports a networking/syscall package; the test transport must be in-memory (planning/21, KB §Test transport)"
fi

# The machinery file set is exactly the three planning/21 files.
URUQUIM_TESTING_ACTUAL_FILES="$(cd "$URUQUIM_TESTING" && find . -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)"
URUQUIM_TESTING_EXPECTED_FILES="$(printf 'recorder.odin\nrequest_builder.odin\ntest_transport.odin\n')"
if test "$URUQUIM_TESTING_ACTUAL_FILES" != "$URUQUIM_TESTING_EXPECTED_FILES"; then
  echo "--- expected web/testing/ files ---" >&2
  echo "$URUQUIM_TESTING_EXPECTED_FILES" >&2
  echo "--- actual web/testing/ files ---" >&2
  echo "$URUQUIM_TESTING_ACTUAL_FILES" >&2
  fail "web/testing/ file set does not match the planning/21 machinery contract"
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
# ledger (planning/15 G-11) and is scanned on its own below, so a symbol added
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
  fail "web/ file set does not match the Phase-1 contract (WP1 seven + WP2 three + WP2 internal tests)"
fi

# WP3 permits exactly ONE subdirectory, `web/testing/` (the machinery). It does
# NOT relax the general ban: `web/internal/` and any other subdirectory remain
# out of scope until their own work packages (planning/21 checker contract §1).
URUQUIM_WEB_SUBDIRS="$(find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)"
if test "$URUQUIM_WEB_SUBDIRS" != "testing"; then
  echo "--- web/ subdirectories (only 'testing' is allowed) ---" >&2
  echo "$URUQUIM_WEB_SUBDIRS" >&2
  fail "web/ has an unexpected subdirectory; WP3 permits only web/testing/"
fi

# ---------------------------------------------------------------------------
# 2. Exported-symbol inventory (planning/15 G-01, G-09)
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
  fail "web/ exports symbols outside the ratified Phase-1 surface (planning/15 G-01/G-09)"
fi
if test -n "$URUQUIM_MISSING"; then
  echo "--- missing exported symbols ---" >&2
  echo "$URUQUIM_MISSING" >&2
  fail "web/ is missing part of the ratified Phase-1 surface"
fi

echo "public API contract: application ledger is exactly 32 Phase-1 symbols"

# ---------------------------------------------------------------------------
# 2b. Test-support ledger (planning/15 G-11, planning/21 Decision 2)
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
  fail "web/$URUQUIM_TEST_SUPPORT_FILE exports outside the 2-symbol test-support ledger (planning/15 G-11)"
fi
if test -n "$URUQUIM_TS_MISSING"; then
  echo "--- missing test-support exports ---" >&2
  echo "$URUQUIM_TS_MISSING" >&2
  fail "web/$URUQUIM_TEST_SUPPORT_FILE is missing part of the test-support ledger"
fi

# `Recorded_Response` exposes exactly `status` and `body`, in that order, and NO
# other field — no `headers`, `committed`, allocator or transport (planning/21).
URUQUIM_RECORDED_FIELDS="$(awk '/^Recorded_Response :: struct \{/{f=1;next} /^\}/{f=0} f' \
  <<<"$URUQUIM_TESTSUPPORT_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -v '^$')"
URUQUIM_RECORDED_EXPECTED="$(printf 'status\nbody\n')"
if test "$URUQUIM_RECORDED_FIELDS" != "$URUQUIM_RECORDED_EXPECTED"; then
  echo "--- expected Recorded_Response fields ---" >&2
  echo "$URUQUIM_RECORDED_EXPECTED" >&2
  echo "--- actual Recorded_Response fields ---" >&2
  echo "$URUQUIM_RECORDED_FIELDS" >&2
  fail "Recorded_Response must expose exactly status and body (planning/21 Decision 1)"
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
# facade can call it across the package boundary (planning/23-wp3-gate.md).
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
  fail "web/testing/ exports a declaration outside the locked bridge set; minimize it or record the growth for human review (planning/23)"
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
# `test_request` is REMOVED from this list by WP3 (planning/21 §5): it is now a
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
# 4. Context is not an extension bag (planning/15 G-03)
#
# WP1 introduces no `any`, no dynamic bag, and no rawptr anywhere in web/.
# Phase 3 may introduce ONE private, typeid-validated rawptr for app_with_state
# (ADR-004); when it does, this check is narrowed spec-first to exported
# declarations rather than deleted.
# ---------------------------------------------------------------------------
if grep -nE '^[[:space:]]*(user_data|locals|values)[[:space:]]*:' <<<"$URUQUIM_WEB_CODE"; then
  fail "web/ declares an untyped request-local storage field (planning/15 G-03)"
fi
for URUQUIM_BAG in 'map\[string\]any' 'map\[any\]any' '\bany\b' '\brawptr\b' \
  'Handler_Error' 'Handler_Outcome'; do
  if grep -nE "$URUQUIM_BAG" <<<"$URUQUIM_WEB_CODE"; then
    fail "web/ uses a forbidden construct matching /$URUQUIM_BAG/ (planning/15 G-03, ADR-011)"
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
# 6. Transport / backend leakage (planning/15 G-06)
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
    fail "backend identifier matching /$URUQUIM_BACKEND/ reached the public package or examples (planning/15 G-06)"
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
    fail "transport-shaped name matching /$URUQUIM_TYPE/ appears in an exported declaration (planning/15 G-06)"
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
# 8. WP2 request/response model (planning/05 §WP2; planning/18 Part I;
#    planning/15 G-03/G-04/G-05)
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
  fail "Method is not the ratified Phase-1 set (planning/18 Part I)"
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
  fail "Header_View must expose only the nested private slot (planning/18 Part I)"
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
  fail "Context must expose exactly 'request' and the private slot: no public response, params or route (ADR-008, planning/18 P-1)"
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
  <<<"$URUQUIM_WEB_PUBLIC_CODE" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/' | grep -v '^$')"
URUQUIM_RESPONSE_EXPECTED="$(printf 'status\nheaders\nbody\ncommitted\n')"
if test "$URUQUIM_RESPONSE_FIELDS" != "$URUQUIM_RESPONSE_EXPECTED"; then
  echo "--- expected internal Response fields ---" >&2
  echo "$URUQUIM_RESPONSE_EXPECTED" >&2
  echo "--- actual internal Response fields ---" >&2
  echo "$URUQUIM_RESPONSE_FIELDS" >&2
  fail "the internal Response must carry status, headers, body and committed (planning/05 §WP2; WP4 needs the Allow header)"
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

echo "public API contract: web/ file set matches the Phase-1 contract through WP3"
echo "public API contract: application ledger 32 + test-support ledger 2 = union 34"
echo "public API contract: Method is the ratified UPPERCASE set; Request has the five ratified fields"
echo "public API contract: Response, Header_Pair and Header_View_Internal stayed internal"
echo "public API contract: web/testing machinery imports no uruquim:web / core:testing, declares no @(init)"
echo "public API contract: no later-phase symbol, dynamic storage, or backend leak"
echo "PASS: Phase-1 public API anti-accretion contract (WP1 + WP2)"
