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

# ---------------------------------------------------------------------------
# WP4 mutation checks — the section-9 dispatch guardrails must REJECT the states
# they claim to forbid, for the same reason as every case above: a guardrail
# that passes on a bad tree is worse than no guardrail.
# ---------------------------------------------------------------------------

# 9. A BRAND-NEW exported symbol in the WP4 dispatch files. The frozen 32-symbol
#    ledger catches this first, which is the stronger message of the two.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nexported_dispatch_helper :: proc() {}\n' >>"$T/web/dispatch_match.odin"
expect_reject "$T" "new exported symbol in the WP4 dispatch files" \
  "exports symbols outside the ratified Phase-1 surface"

# 9b. A RATIFIED symbol exported from a dispatch file. The ledger cannot see
#     this — the name is still expected and the count is still 32 — so it is
#     exactly the case section 9a exists for: the interim dispatcher must stay
#     entirely internal, and it must not become a second home for public API.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nserve :: proc(a: ^App, port: int) {}\n' >>"$T/web/dispatch_match.odin"
expect_reject "$T" "ratified symbol exported from a dispatch file" \
  "the WP4 dispatch files export a symbol"

# 10. `dispatch` losing its explicit App parameter (D3).
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^dispatch :: proc(a: \^App, ctx: \^Context) {$/dispatch :: proc(ctx: ^Context) {/' \
  "$T/web/dispatch_match.odin"
expect_reject "$T" "dispatch without the explicit App parameter" \
  "dispatch does not have the ratified internal signature"

# 11. A non-canonical `Allow` header name.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^ALLOW_HEADER_NAME :: "Allow"$/ALLOW_HEADER_NAME :: "allow"/' \
  "$T/web/dispatch_table.odin"
expect_reject "$T" "lowercase Allow header name" \
  "the 405 header name is not exactly"

# 12. A scrambled `Allow` method order — the value must not depend on it.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^ALLOW_METHOD_ORDER :: .*$/ALLOW_METHOD_ORDER :: [5]Method{.DELETE, .PATCH, .PUT, .POST, .GET}/' \
  "$T/web/dispatch_table.odin"
expect_reject "$T" "non-canonical Allow method order" \
  "the Allow method order is not the canonical"

# 13. A later-phase routing construct entering the interim dispatcher (R-12).
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(private)\nradix_node_lookup :: proc() {}\n' >>"$T/web/dispatch_match.odin"
expect_reject "$T" "radix construct in the interim dispatcher" \
  "later-phase routing construct"

# 14. The dispatcher deciding a status outside 404/405.
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(private)\nwp4_extra_status :: proc(res: ^Response) {\n\tresponse_commit(res, .Internal_Server_Error, nil, nil)\n}\n' \
  >>"$T/web/dispatch_match.odin"
expect_reject "$T" "dispatcher deciding a status outside 404/405" \
  "decides a status outside 404/405"

# 15. A missing WP4 dispatch file.
T="$(fresh_tree)"; TREES+=("$T")
rm -f "$T/web/dispatch_match.odin"
expect_reject "$T" "missing WP4 dispatch file" \
  "web/ file set does not match the Phase-1 contract"

echo "PASS: WP4 mutation checks (8 forbidden dispatch states all rejected)"

# ---------------------------------------------------------------------------
# WP5 mutation checks — the section-10 extractor guardrails must REJECT the
# states they claim to forbid.
#
# The `#optional_ok` case is the one that matters most. Section 10b is a
# NEGATIVE grep, and a negative grep passes just as happily when the pattern is
# wrong, when the file it reads is empty, or when the variable it scans was
# renamed out from under it. Without the mutation below, "the checker rejects
# #optional_ok" would be an untested claim about a guardrail whose entire job is
# to catch a one-word regression (ADR-002, R-07).
# ---------------------------------------------------------------------------

# 16. `#optional_ok` re-added to a value-producing extractor.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^path_int :: proc(ctx: \^Context, name: string) -> (value: int, ok: bool) {$/path_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool) #optional_ok {/' \
  "$T/web/extract.odin"
grep -q '#optional_ok' "$T/web/extract.odin" ||
  fail "MUTATION-SETUP: #optional_ok was not injected into the copied extract.odin"
expect_reject "$T" "#optional_ok re-added to path_int" \
  "#optional_ok appears in web/"

# 16b. The same directive on `query_int_or` — the extractor most likely to be
#      mistaken for a total function and "simplified" with the directive.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^query_int_or :: proc(ctx: \^Context, name: string, default_value: int) -> (value: int, ok: bool) {$/query_int_or :: proc(ctx: ^Context, name: string, default_value: int) -> (value: int, ok: bool) #optional_ok {/' \
  "$T/web/extract.odin"
grep -q '#optional_ok' "$T/web/extract.odin" ||
  fail "MUTATION-SETUP: #optional_ok was not injected into query_int_or"
expect_reject "$T" "#optional_ok re-added to query_int_or" \
  "#optional_ok appears in web/"

# 17. A changed extractor signature. The 32-symbol ledger cannot see this: the
#     name is still present and the count is still 32, but the public contract
#     changed.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^query_int_or :: proc(ctx: \^Context, name: string, default_value: int) -> (value: int, ok: bool) {$/query_int_or :: proc(ctx: ^Context, name: string, default_value: i64) -> (value: i64, ok: bool) {/' \
  "$T/web/extract.odin"
expect_reject "$T" "altered query_int_or signature" \
  "the ratified web.query_int_or signature is not exactly"

# 18. A WP6 responder implemented early.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/errors.odin" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "bad_request :: proc(ctx: ^Context, message: string) {\n}"
if old not in s:
    sys.exit("MUTATION-SETUP: the bad_request stub was not found in web/errors.odin")
new = ("bad_request :: proc(ctx: ^Context, message: string) {\n"
       "\tresponse_commit(&ctx.private.response, .Bad_Request, nil, nil)\n}")
open(p, "w").write(s.replace(old, new, 1))
PY
expect_reject "$T" "WP6 responder implemented early" \
  "is no longer an empty stub"

# 19. The JSON encoder linked into the shipped package. WP5's envelope is
#     hand-escaped into fixed storage precisely so this import stays absent.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nimport _ "core:encoding/json"\n' >>"$T/web/errors.odin"
expect_reject "$T" "core:encoding/json imported by web/" \
  "web/ imports core:encoding/json"

# 20. WP7 machinery starting early.
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(private)\nBODY_LIMIT :: 4194304\n' >>"$T/web/extract.odin"
expect_reject "$T" "WP7 body cap in the package" \
  "WP7 construct matching"

# 21. `web.body` implemented early, so the WP7 stub no longer returns false.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/extract.odin" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "body :: proc(ctx: ^Context, dst: ^$T) -> bool {\n\treturn false\n}"
if old not in s:
    sys.exit("MUTATION-SETUP: the body stub was not found in web/extract.odin")
new = "body :: proc(ctx: ^Context, dst: ^$T) -> bool {\n\treturn true\n}"
open(p, "w").write(s.replace(old, new, 1))
PY
expect_reject "$T" "web.body implemented early" \
  "web.body is no longer the WP7 stub"

# 22. A misspelled error code. Clients match on `code`, so a typo is a silent
#     compatibility break rather than a visible failure.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/invalid_query_parameter/invalid_query_param/g' "$T/web/errors.odin"
expect_reject "$T" "misspelled invalid_query_parameter code" \
  "the ratified error code 'invalid_query_parameter' is missing"

echo "PASS: WP5 mutation checks (8 forbidden extractor states all rejected)"
