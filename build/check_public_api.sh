#!/usr/bin/env bash
# WP1 public API contract — static repository assertions.
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
# Expected WP1 production files. WP1 is limited to these seven; anything else
# under web/ is scope creep or a later work package starting early.
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_FILES="app.odin
context.odin
errors.odin
extract.odin
respond.odin
routing.odin
serve.odin"

# ---------------------------------------------------------------------------
# Expected WP1 exported surface — 4 types + 25 procedures.
# Every entry is justified in planning/17-wp1-gate.md with its spec section,
# experiment evidence, owning phase, and ratified/nominal status.
# ---------------------------------------------------------------------------
URUQUIM_EXPECTED_EXPORTS="App
Context
Handler
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
  fail "web/ file set does not match the WP1 contract"
fi

if test -n "$(find "$URUQUIM_WEB" -mindepth 1 -maxdepth 1 -type d -print -quit)"; then
  fail "web/ has subdirectories; WP1 ships no internals, middleware, or testing package"
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
  ' "$URUQUIM_WEB"/*.odin | LC_ALL=C sort -u
}

URUQUIM_ACTUAL_EXPORTS="$(uruquim_exported_names)"
URUQUIM_EXPECTED_EXPORTS_SORTED="$(LC_ALL=C sort -u <<<"$URUQUIM_EXPECTED_EXPORTS")"

URUQUIM_EXTRA="$(comm -13 <(echo "$URUQUIM_EXPECTED_EXPORTS_SORTED") <(echo "$URUQUIM_ACTUAL_EXPORTS"))"
URUQUIM_MISSING="$(comm -23 <(echo "$URUQUIM_EXPECTED_EXPORTS_SORTED") <(echo "$URUQUIM_ACTUAL_EXPORTS"))"

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
  redirect conflict bytes logger recovery request_id cors; do
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
if grep -nE '^[[:space:]]*(user_data|locals|values)[[:space:]]*:' "$URUQUIM_WEB"/*.odin; then
  fail "web/ declares an untyped request-local storage field (planning/15 G-03)"
fi
for URUQUIM_BAG in 'map\[string\]any' 'map\[any\]any' '\bany\b' '\brawptr\b' \
  'Handler_Error' 'Handler_Outcome'; do
  if grep -nE "$URUQUIM_BAG" "$URUQUIM_WEB"/*.odin; then
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
URUQUIM_LEAK_ROOTS=("$URUQUIM_WEB")
test -d "$URUQUIM_ROOT/examples" && URUQUIM_LEAK_ROOTS+=("$URUQUIM_ROOT/examples")

for URUQUIM_BACKEND in 'odin[-_]http' 'nbio' 'laytan'; do
  if grep -rniE "$URUQUIM_BACKEND" "${URUQUIM_LEAK_ROOTS[@]}"; then
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
  ' "$URUQUIM_WEB"/*.odin
}

URUQUIM_EXPORTED_BLOCKS="$(uruquim_exported_blocks)"
for URUQUIM_TYPE in 'Transport' 'Socket' 'TCP' 'Connection' 'Server' 'net\.' 'http\.'; do
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

echo "public API contract: web/ file set matches WP1"
echo "public API contract: exported surface is exactly $(wc -l <<<"$URUQUIM_ACTUAL_EXPORTS") Phase-1 symbols"
echo "public API contract: no later-phase symbol, dynamic storage, or backend leak"
echo "PASS: WP1 public API anti-accretion contract"
