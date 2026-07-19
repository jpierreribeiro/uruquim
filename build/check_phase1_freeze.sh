#!/usr/bin/env bash
# WP11 — Phase-1 freeze gate.
#
# The earlier checkers pin the surface by NAME (build/check_public_api.sh) and
# behavior by TEST (build/check.sh). This gate adds the last layer: the FULL
# COMPILER-REPORTED DECLARATIONS — argument lists, results, genericity, struct
# fields, enum members and backing types — snapshotted in
# `build/phase1-public-signatures.txt`, plus the direct-import inventory in
# `build/phase1-direct-dependencies.txt`, plus the evidence matrix in
# `planning/phase-1-freeze.md`, all compared against the live tree on every run.
#
# The source of truth is `odin doc` on the pinned toolchain, not a hand-written
# list: a signature that drifts fails here even when its name survives. The
# only normalization applied is stripping the `/* file!offset */` location
# comments — locations move with unrelated edits; declarations must not.
#
# This checker CONSUMES the earlier gates rather than duplicating them: run
# from `build/check.sh` it is the final step, after every compile/behavior/
# docs/example gate has already passed (URUQUIM_FREEZE_FROM_CHECK=1). Run
# standalone it re-executes the two cheap static gates itself so its verdict
# is still grounded, and documents that the compiled gates come from check.sh.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_MANIFEST="$URUQUIM_ROOT/planning/phase-1-freeze.md"
URUQUIM_SIG_SNAPSHOT="$URUQUIM_ROOT/build/phase1-public-signatures.txt"
URUQUIM_DEP_SNAPSHOT="$URUQUIM_ROOT/build/phase1-direct-dependencies.txt"

fail() {
  echo "FAIL(phase1-freeze): $*" >&2
  exit 1
}

# --- compiler resolution (same contract as build/check.sh) ------------------
if test -z "${URUQUIM_COMPILER:-}"; then
  if test -n "${URUQUIM_ODIN_BIN:-}"; then
    URUQUIM_COMPILER="$URUQUIM_ODIN_BIN"
  elif command -v odin >/dev/null 2>&1; then
    URUQUIM_COMPILER="$(command -v odin)"
  elif test -x /tmp/uruquim-odin-toolchain/odin; then
    URUQUIM_COMPILER=/tmp/uruquim-odin-toolchain/odin
  else
    fail "odin not found; install the pinned distribution or set URUQUIM_ODIN_BIN"
  fi
fi
URUQUIM_COMPILER="$(readlink -f "$URUQUIM_COMPILER")"
URUQUIM_COMPILER_DIR="$(cd "$(dirname "$URUQUIM_COMPILER")" && pwd)"
URUQUIM_EXPECTED_COMMIT="$(sed -n 's/^commit=//p' "$URUQUIM_ROOT/odin-version.txt")"
URUQUIM_VERSION="$(ODIN_ROOT="$URUQUIM_COMPILER_DIR" "$URUQUIM_COMPILER" version 2>&1)"
case "$URUQUIM_VERSION" in
  *"$URUQUIM_EXPECTED_COMMIT"*) ;;
  *) fail "compiler mismatch: expected $URUQUIM_EXPECTED_COMMIT, got: $URUQUIM_VERSION" ;;
esac

# --- 0. the three freeze artifacts exist ------------------------------------
test -f "$URUQUIM_MANIFEST" || fail "planning/phase-1-freeze.md is missing"
test -f "$URUQUIM_SIG_SNAPSHOT" || fail "build/phase1-public-signatures.txt is missing"
test -f "$URUQUIM_DEP_SNAPSHOT" || fail "build/phase1-direct-dependencies.txt is missing"

# --- 1. signature inventory from the compiler -------------------------------
# `odin doc` (without -short) prints every exported declaration WITH its body
# inline: struct fields, enum members and backing types included. Declarations
# are the tab-tab-indented `Name :: ...` lines; the trailing `/* file!offset */`
# comment is the location marker being normalized away. Names, types,
# arguments, results and genericity are NOT rewritten.
URUQUIM_TAB="$(printf '\t')"
URUQUIM_ACTUAL_SIGS="$(env ODIN_ROOT="$URUQUIM_COMPILER_DIR" \
  "$URUQUIM_COMPILER" doc "$URUQUIM_ROOT/web" \
  "-collection:uruquim=$URUQUIM_ROOT" 2>/dev/null |
  grep -E "^${URUQUIM_TAB}${URUQUIM_TAB}[A-Za-z_][A-Za-z0-9_]* :: " |
  sed -E 's-[[:space:]]*/\* [^*]*\*/$--' |
  sed -E "s/^${URUQUIM_TAB}${URUQUIM_TAB}//")"
test -n "$URUQUIM_ACTUAL_SIGS" || fail "odin doc produced no declarations"

if ! diff -u "$URUQUIM_SIG_SNAPSHOT" <(printf '%s\n' "$URUQUIM_ACTUAL_SIGS") >&2; then
  fail "the compiler-reported public declarations differ from build/phase1-public-signatures.txt; a frozen signature changed, or a symbol was added/removed (spec amendment required)"
fi
echo "phase1-freeze: all public declarations match the frozen snapshot"

# --- 2. ledgers: 32 application + 2 test-support = 34, disjoint --------------
URUQUIM_ALL_NAMES="$(printf '%s\n' "$URUQUIM_ACTUAL_SIGS" | sed -E 's/ ::.*$//' | LC_ALL=C sort -u)"
URUQUIM_TS_LEDGER="$(printf 'Recorded_Response\ntest_request\n')"
URUQUIM_APP_NAMES="$(LC_ALL=C comm -23 <(printf '%s\n' "$URUQUIM_ALL_NAMES") <(printf '%s\n' "$URUQUIM_TS_LEDGER"))"
URUQUIM_TS_FOUND="$(LC_ALL=C comm -12 <(printf '%s\n' "$URUQUIM_ALL_NAMES") <(printf '%s\n' "$URUQUIM_TS_LEDGER"))"
URUQUIM_APP_COUNT="$(grep -c . <<<"$URUQUIM_APP_NAMES" || true)"
URUQUIM_TS_COUNT="$(grep -c . <<<"$URUQUIM_TS_FOUND" || true)"
URUQUIM_UNION_COUNT="$(grep -c . <<<"$URUQUIM_ALL_NAMES" || true)"
test "$URUQUIM_APP_COUNT" -eq 32 || fail "application ledger is $URUQUIM_APP_COUNT, not 32"
test "$URUQUIM_TS_COUNT" -eq 2 || fail "test-support ledger is $URUQUIM_TS_COUNT, not 2"
test "$URUQUIM_UNION_COUNT" -eq 34 || fail "exported union is $URUQUIM_UNION_COUNT, not 34"
echo "phase1-freeze: ledgers hold at 32 application + 2 test-support = 34"

# --- 3. load-bearing shapes, asserted with their own diagnostics -------------
# The byte-exact snapshot above already pins these; the asserts exist so a
# violation names the CONTRACT it broke, not just a diff hunk.
grep -qxF 'Handler :: proc(ctx: ^Context)' <<<"$URUQUIM_ACTUAL_SIGS" ||
  fail "the canonical handler shape changed (ADR-011)"
grep -qE '^Method :: enum u8 \{UNKNOWN, GET, POST, PUT, PATCH, DELETE\}$' <<<"$URUQUIM_ACTUAL_SIGS" ||
  fail "Method is not the ratified enum u8 {UNKNOWN, GET, POST, PUT, PATCH, DELETE}"
grep -qE '^Status :: enum int \{OK = 200, Created = 201, Accepted = 202, No_Content = 204, Bad_Request = 400, Unauthorized = 401, Forbidden = 403, Not_Found = 404, Method_Not_Allowed = 405, Internal_Server_Error = 500\}$' <<<"$URUQUIM_ACTUAL_SIGS" ||
  fail "Status is not the ratified Phase-1 member set (the private 413 must NOT become a public member)"
grep -E '^Status ::' <<<"$URUQUIM_ACTUAL_SIGS" | grep -q '413' &&
  fail "a 413 member appeared on the public Status enum; body_too_large stays private (WP7 D3)"
# ADR-002: no value extractor may re-grow #optional_ok. Static half; the
# behavioral half is the three discard probes in build/check.sh.
if sed -E 's://.*$::' "$URUQUIM_ROOT"/web/*.odin | grep -n '#optional_ok'; then
  fail "#optional_ok appeared in the shipped package (ADR-002 option B)"
fi
echo "phase1-freeze: handler, Method, Status and no-#optional_ok contracts hold"

# --- 4. future-phase vocabulary stays off the surface ------------------------
for URUQUIM_FUTURE in use router group mount next state middleware recovery \
  request_id logger cors header bearer_token serve_with serve_transport \
  app_with_state redirect conflict bytes upload websocket stream openapi \
  body_limit; do
  if grep -qx "$URUQUIM_FUTURE" <<<"$URUQUIM_ALL_NAMES"; then
    fail "future-phase symbol '$URUQUIM_FUTURE' is exported by the frozen Phase-1 surface"
  fi
done
echo "phase1-freeze: no future-phase vocabulary on the exported surface"

# --- 5. direct-dependency inventory ------------------------------------------
# Direct imports, per shipped package plus the examples, read from the code.
# `vendor/odin-http` is the transitive dependency the adapter drags in; its
# distinct import set is recorded so a vendor update cannot silently widen
# what applications link.
uruquim_imports_of() { # dir...
  grep -hE '^import ' "$@" 2>/dev/null |
    sed -E 's/^import[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]+)?"([^"]+)".*$/\2/' |
    LC_ALL=C sort -u
}
URUQUIM_ACTUAL_DEPS="$(
  echo '[web]'
  uruquim_imports_of "$URUQUIM_ROOT"/web/*.odin
  echo '[web/testing]'
  uruquim_imports_of "$URUQUIM_ROOT"/web/testing/*.odin
  echo '[web/internal/transport]'
  uruquim_imports_of "$URUQUIM_ROOT"/web/internal/transport/*.odin
  echo '[vendor/odin-http]'
  uruquim_imports_of "$URUQUIM_ROOT"/vendor/odin-http/*.odin
  echo '[examples]'
  uruquim_imports_of "$URUQUIM_ROOT"/examples/*/main.odin
)"
if ! diff -u "$URUQUIM_DEP_SNAPSHOT" <(printf '%s\n' "$URUQUIM_ACTUAL_DEPS") >&2; then
  fail "direct imports differ from build/phase1-direct-dependencies.txt; a dependency changed without a spec amendment"
fi
# Policies the snapshot alone cannot state:
awk '/^\[web\]$/{f=1;next} /^\[/{f=0} f' <<<"$URUQUIM_ACTUAL_DEPS" |
  grep -vE '^(core:|uruquim:web/(testing|internal/transport)$)' | grep -q . &&
  fail "web/ imports outside core: plus its two internal packages"
awk '/^\[web\/testing\]$/{f=1;next} /^\[/{f=0} f' <<<"$URUQUIM_ACTUAL_DEPS" |
  grep -vE '^core:' | grep -q . &&
  fail "web/testing imports outside core: (back-edge or network dependency)"
awk '/^\[examples\]$/{f=1;next} /^\[/{f=0} f' <<<"$URUQUIM_ACTUAL_DEPS" |
  grep -vxF 'uruquim:web' | grep -q . &&
  fail "an example imports something other than uruquim:web (vendor/backend leak)"
grep -hE '^import ' "$URUQUIM_ROOT"/web/*.odin "$URUQUIM_ROOT"/web/testing/*.odin \
  "$URUQUIM_ROOT"/web/internal/transport/*.odin | grep -q 'core:testing' &&
  fail "core:testing is imported by a shipped package"
echo "phase1-freeze: direct dependencies match the frozen inventory"

# --- 6. the manifest is complete and every claim is checkable ----------------
# Pending-work markers keep the gate red: the manifest may not carry
# TODO/FIXME/TBD, MISSING/UNPROVEN/NOT_FROZEN results, or the skeleton's
# PENDING-EVIDENCE placeholder.
if grep -nE 'TODO|FIXME|TBD|MISSING|UNPROVEN|NOT_FROZEN|PENDING-EVIDENCE' "$URUQUIM_MANIFEST"; then
  fail "planning/phase-1-freeze.md still carries a pending-work marker"
fi
grep -qE '^Freeze state: (CANDIDATE|ACCEPTED)' "$URUQUIM_MANIFEST" ||
  fail "the manifest does not declare 'Freeze state: CANDIDATE' (or ACCEPTED after the human decision)"

# The evidence matrix: one row per exported symbol, every cell filled, every
# referenced path real, every referenced identifier present in its file, and
# every row PROVEN. 'covered by the general gate' is not a cell value.
URUQUIM_MATRIX="$(awk '/<!-- evidence-matrix:begin -->/{f=1;next} /<!-- evidence-matrix:end -->/{f=0} f' "$URUQUIM_MANIFEST")"
test -n "$URUQUIM_MATRIX" || fail "the evidence matrix block is missing or empty"

while IFS= read -r URUQUIM_SYM; do
  URUQUIM_ROWS="$(grep -cE "^\| \`$URUQUIM_SYM\` \|" <<<"$URUQUIM_MATRIX" || true)"
  test "$URUQUIM_ROWS" -eq 1 ||
    fail "evidence matrix has $URUQUIM_ROWS rows for '$URUQUIM_SYM' (exactly 1 required)"
  URUQUIM_ROW="$(grep -E "^\| \`$URUQUIM_SYM\` \|" <<<"$URUQUIM_MATRIX")"
  URUQUIM_NCELLS="$(awk -F'|' '{print NF-2}' <<<"$URUQUIM_ROW")"
  test "$URUQUIM_NCELLS" -eq 9 ||
    fail "evidence row for '$URUQUIM_SYM' has $URUQUIM_NCELLS cells, not 9"
  if awk -F'|' '{for (i=2; i<NF; i++) {gsub(/[[:space:]]/, "", $i); if ($i == "" || $i == "—" || $i == "-") exit 1}}' <<<"$URUQUIM_ROW"; then :; else
    fail "evidence row for '$URUQUIM_SYM' has an empty cell"
  fi
  URUQUIM_LEDGER_CELL="$(awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}' <<<"$URUQUIM_ROW")"
  URUQUIM_EXPECTED_LEDGER=application
  grep -qx "$URUQUIM_SYM" <<<"$URUQUIM_TS_LEDGER" && URUQUIM_EXPECTED_LEDGER=test-support
  test "$URUQUIM_LEDGER_CELL" = "$URUQUIM_EXPECTED_LEDGER" ||
    fail "'$URUQUIM_SYM' is recorded in ledger '$URUQUIM_LEDGER_CELL', not '$URUQUIM_EXPECTED_LEDGER' (symbols may not move between ledgers)"
  URUQUIM_RESULT_CELL="$(awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $(NF-1)); print $(NF-1)}' <<<"$URUQUIM_ROW")"
  test "$URUQUIM_RESULT_CELL" = "PROVEN" ||
    fail "'$URUQUIM_SYM' is '$URUQUIM_RESULT_CELL', not PROVEN; an unproven symbol cannot stay frozen"
done <<<"$URUQUIM_ALL_NAMES"

# Every backticked repo reference in the matrix must exist; every
# `path::identifier` must name an identifier that occurs in that path.
URUQUIM_REFS="$(grep -oE '`(web|tests|examples|docs|build|planning|experiments|vendor|ops)/[A-Za-z0-9_./-]+(::[A-Za-z0-9_]+)?`' <<<"$URUQUIM_MATRIX" | tr -d '`' | LC_ALL=C sort -u)"
test -n "$URUQUIM_REFS" || fail "the evidence matrix references no repository paths"
while IFS= read -r URUQUIM_REF; do
  URUQUIM_REF_PATH="${URUQUIM_REF%%::*}"
  URUQUIM_REF_IDENT=""
  case "$URUQUIM_REF" in *::*) URUQUIM_REF_IDENT="${URUQUIM_REF##*::}" ;; esac
  test -e "$URUQUIM_ROOT/$URUQUIM_REF_PATH" ||
    fail "evidence reference '$URUQUIM_REF_PATH' does not exist"
  if test -n "$URUQUIM_REF_IDENT"; then
    if test -d "$URUQUIM_ROOT/$URUQUIM_REF_PATH"; then
      grep -rqF "$URUQUIM_REF_IDENT" "$URUQUIM_ROOT/$URUQUIM_REF_PATH" ||
        fail "evidence identifier '$URUQUIM_REF_IDENT' not found under '$URUQUIM_REF_PATH'"
    else
      grep -qF "$URUQUIM_REF_IDENT" "$URUQUIM_ROOT/$URUQUIM_REF_PATH" ||
        fail "evidence identifier '$URUQUIM_REF_IDENT' not found in '$URUQUIM_REF_PATH'"
    fi
  fi
done <<<"$URUQUIM_REFS"
echo "phase1-freeze: evidence matrix complete — every symbol PROVEN, every reference real"

# --- 7. no open Phase-1 blocker ----------------------------------------------
# Convention (normative; this script is its definition, the manifest points
# here): an open blocker assigned to Phase 1 must be written as the literal
# token PHASE1-BLOCKER in a planning document. Phase 1 cannot freeze while one
# exists. The manifest refers to the token without spelling it, so this scan
# has no false positive on its own definition.
if grep -rn 'PHASE1-BLOCKER' "$URUQUIM_ROOT/planning/"; then
  fail "an open PHASE1-BLOCKER is recorded in planning/; Phase 1 cannot freeze over it"
fi
echo "phase1-freeze: no open Phase-1 blocker in planning/"

# --- 8. documentation and example gates --------------------------------------
# Invoked from build/check.sh (URUQUIM_FREEZE_FROM_CHECK=1) they have ALREADY
# run in this same gate execution, immediately before this script; re-running
# them here would only duplicate work. Standalone, the two static gates are
# re-executed so this checker's verdict stays grounded; the compiled gates
# (tests, examples, conformance) always come from build/check.sh.
if test -z "${URUQUIM_FREEZE_FROM_CHECK:-}"; then
  bash "$URUQUIM_ROOT/build/check_public_api.sh" >/dev/null
  bash "$URUQUIM_ROOT/build/check_docs.sh" >/dev/null
  echo "phase1-freeze: static public-api and docs-parity gates re-executed (standalone mode)"
fi

echo "PASS: Phase-1 freeze gate — the frozen surface, dependencies and evidence matrix all hold"
