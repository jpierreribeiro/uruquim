#!/usr/bin/env bash
# Phase-1 public API contract — static repository assertions.
#
# Surface checkpoints: WP1 = 29 symbols; WP2 = 32 (29 + Request + Method +
# Header_View, planning/18 Part I). The count is EXACT in both directions: a
# missing symbol and an extra symbol are equally a failure.
#
# Verification-only: this script never modifies sources. It enforces the
# anti-accretion guardrails of `planning/15-public-api-anti-accretion-guardrails.md`
# against the shipped public package.
#
# SCOPE (planning/15 G-06 and its false-positive rules): the transport-leak and
# dynamic-storage scans read ONLY the exported public package `web/` and, once
# it exists, `examples/`. They deliberately never read `knowledge-base/`,
# `planning/`, `docs/`, `referencias/`, or `experiments/`. Backend names are
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
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_FILES="app.odin
context.odin
errors.odin
extract.odin
headers.odin
request.odin
respond.odin
response.odin
routing.odin
serve.odin"

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

test -d "$URUQUIM_WEB" || fail "web/ does not exist; WP1 has not created the public package"

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

# The export inventory below reads only files that are NOT `#+private`, which
# is exactly what the compiler exports. This narrows the scan to match the
# language; it never widens what may be exported.
URUQUIM_PUBLIC_FILES=()
while IFS= read -r URUQUIM_FILE; do
  if head -n 20 "$URUQUIM_FILE" | grep -qx '#+private'; then
    continue
  fi
  URUQUIM_PUBLIC_FILES+=("$URUQUIM_FILE")
done < <(find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -name '*.odin' -type f | LC_ALL=C sort)

test "${#URUQUIM_PUBLIC_FILES[@]}" -gt 0 || fail "web/ contains no public production file"

uruquim_public_code_only() {
  sed -E 's://.*$::' "${URUQUIM_PUBLIC_FILES[@]}"
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

if test -n "$(find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -type d -print -quit)"; then
  fail "web/ has subdirectories; Phase 1 through WP2 ships no internals, middleware, or testing package"
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

# ---------------------------------------------------------------------------
# 3. Phase-2+ surface must not exist yet
# ---------------------------------------------------------------------------
for URUQUIM_FUTURE in use router group mount next state app_with_state \
  header bearer_token serve_with serve_transport app_init test_request \
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

echo "public API contract: web/ file set matches the Phase-1 contract through WP2"
echo "public API contract: exported surface is exactly $(wc -l <<<"$URUQUIM_ACTUAL_EXPORTS") Phase-1 symbols"
echo "public API contract: Method is the ratified UPPERCASE set; Request has the five ratified fields"
echo "public API contract: Response, Header_Pair and Header_View_Internal stayed internal"
echo "public API contract: no later-phase symbol, dynamic storage, or backend leak"
echo "PASS: Phase-1 public API anti-accretion contract (WP1 + WP2)"
