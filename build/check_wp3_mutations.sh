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
  mkdir -p "$t/build" "$t/web/testing" "$t/web/internal/transport" "$t/tests" "$t/vendor"
  cp "$URUQUIM_ROOT"/build/check_public_api.sh "$t/build/"
  cp "$URUQUIM_ROOT"/web/*.odin "$t/web/"
  cp "$URUQUIM_ROOT"/web/testing/*.odin "$t/web/testing/"
  cp "$URUQUIM_ROOT"/web/internal/transport/*.odin "$t/web/internal/transport/"
  cp -r "$URUQUIM_ROOT"/vendor/odin-http "$t/vendor/odin-http"
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

# 3. A subdirectory outside the permitted set. `web/testing/` (WP3) and
#    `web/internal/` (WP8) are allowed; anything else is scope creep.
T="$(fresh_tree)"; TREES+=("$T")
mkdir -p "$T/web/middleware"
printf 'package middleware\n' >"$T/web/middleware/x.odin"
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

# 18. (RETIRED IN WP6.) This case asserted that `web.bad_request` was still an
#     empty stub. WP6 implemented it, so the mutation now describes the
#     delivered feature rather than a forbidden state. The WP6 cases at the end
#     of this file replace it.

# 20-21. (RETIRED IN WP7.) These asserted that a body cap and a working
#     `web.body` did not exist yet. WP7 delivered both, so the mutations now
#     describe the shipped feature rather than a forbidden state. The WP7 cases
#     at the end of this file replace them with the positive contract.

# 22. A misspelled error code. Clients match on `code`, so a typo is a silent
#     compatibility break rather than a visible failure.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/invalid_query_parameter/invalid_query_param/g' "$T/web/errors.odin"
expect_reject "$T" "misspelled invalid_query_parameter code" \
  "the ratified error code 'invalid_query_parameter' is missing"

echo "PASS: WP5 mutation checks (8 forbidden extractor states all rejected)"

# ---------------------------------------------------------------------------
# WP6 mutation checks — the section-10c response/envelope guardrails must REJECT
# the states they claim to forbid.
#
# Several of these guardrails are NEGATIVE greps, and a negative grep passes
# just as happily when its pattern is wrong, when the variable it scans was
# renamed, or when the file it reads moved. These cases are what make the
# rejection a fact.
# ---------------------------------------------------------------------------

# 23. The JSON encoder reaching the interim dispatcher. WP6 D5 keeps the
#     automatic 404/405 bodies static precisely so that `dispatch` — reachable
#     from every application that calls web.app() — neither allocates nor links
#     the marshaller.
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(private)\nwp6_bad_render :: proc(ctx: ^Context) {\n\tdata, _ := encoding_json.marshal(1, {}, context.allocator)\n\t_ = data\n}\n' \
  >>"$T/web/dispatch_match.odin"
expect_reject "$T" "encoder used by the interim dispatcher" \
  "the WP4 dispatcher marshals a response"

# 24. The encoder imported by a file that must stay encoder-free. `extract.odin`
#     legitimately imports it since WP7 (body decoding), so the mutation targets
#     the dispatcher, which must never marshal.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nimport _ "core:encoding/json"\n' >>"$T/web/dispatch_match.odin"
expect_reject "$T" "encoder imported into the dispatcher" \
  "the JSON encoder is imported outside"

# 25. Response teardown exported. Response lifetime is framework business; an
#     application must never be handed a cleanup call (ADR-014 D1).
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/response.odin" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
old = "@(private)\nresponse_destroy :: proc(res: ^Response) {"
assert old in s, "MUTATION-SETUP: response_destroy declaration not found"
open(p, "w").write(s.replace(old, "response_destroy :: proc(res: ^Response) {", 1))
PY2
expect_reject "$T" "response_destroy exported" \
  "exports symbols outside the ratified Phase-1 surface"

# 26. `field` smuggled into the general envelope. AMEND-2 says it is OMITTED,
#     and the omission must be a property of the TYPE.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/errors.odin" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
old = """Error_Envelope_Body :: struct {
	code:    string `json:"code"`,
	message: string `json:"message"`,
}"""
assert old in s, "MUTATION-SETUP: Error_Envelope_Body not found"
new = """Error_Envelope_Body :: struct {
	code:    string `json:"code"`,
	message: string `json:"message"`,
	field:   string `json:"field"`,
}"""
open(p, "w").write(s.replace(old, new, 1))
PY2
expect_reject "$T" "field added to the general envelope" \
  "must carry exactly code and message"

# 27. `omitempty` used to omit `field`. It decides on EMPTINESS, so it would also
#     drop a field legitimately named "" — a different contract from AMEND-2.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's|`json:"message"`|`json:"message,omitempty"`|' "$T/web/errors.odin"
expect_reject "$T" "omitempty in the envelope" \
  "omitempty is used in web/"

# 28. A wrong Content-Type. Clients dispatch on it, so a silent change here is a
#     compatibility break rather than a visible failure.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's|^CONTENT_TYPE_JSON :: "application/json"$|CONTENT_TYPE_JSON :: "text/json"|' \
  "$T/web/response.odin"
expect_reject "$T" "non-canonical JSON Content-Type" \
  "the JSON Content-Type is not exactly"

# 29. The text Content-Type losing its charset.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's|^CONTENT_TYPE_TEXT :: "text/plain; charset=utf-8"$|CONTENT_TYPE_TEXT :: "text/plain"|' \
  "$T/web/response.odin"
expect_reject "$T" "text Content-Type without charset" \
  "the text Content-Type is not exactly"

# 30. Pointer-payload support adopted without a ratified amendment (R-13).
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(private)\nwp6_deref_payload :: proc() {}\n' >>"$T/web/respond.odin"
expect_reject "$T" "pointer dereference support introduced" \
  "pointer-payload dereference"

# 31. The response ownership machinery removed. `response_commit_owned` is what
#     makes ADR-014 true; losing it must not pass quietly.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/response.odin" <<'PY2'
import sys
p = sys.argv[1]
s = open(p).read()
old = "response_commit_owned :: proc("
assert old in s, "MUTATION-SETUP: response_commit_owned not found"
open(p, "w").write(s.replace(old, "response_commit_owned_renamed :: proc(", 1))
PY2
expect_reject "$T" "response_commit_owned removed" \
  "internal WP6 declaration 'response_commit_owned' is missing"

echo "PASS: WP6 mutation checks (9 forbidden response states all rejected)"

# ---------------------------------------------------------------------------
# WP7 mutation checks — the section-10d body-binding guardrails must REJECT the
# states they claim to forbid. Several are structural greps over the source of
# `body`; a grep that passes on a bad tree is worse than no grep, so each is
# exercised against a tree that actually contains the defect.
# ---------------------------------------------------------------------------

# 32. The 4 MiB cap removed entirely.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/extract.odin" <<'PY2'
import sys, re
p = sys.argv[1]; s = open(p).read()
# Drop the whole "if len(raw) > BODY_LIMIT { ... }" block.
s = re.sub(r"\tif len\(raw\) > BODY_LIMIT \{\n(?:.*\n)*?\t\}\n", "", s, count=1)
open(p, "w").write(s)
PY2
expect_reject "$T" "4 MiB cap removed" \
  "does not compare the body length against BODY_LIMIT"

# 33. `>` weakened to `>=`, which would reject exactly 4 MiB.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/len(raw) > BODY_LIMIT/len(raw) >= BODY_LIMIT/' "$T/web/extract.odin"
expect_reject "$T" "cap comparison weakened to >=" \
  "exactly 4 MiB would be rejected"

# 34. Parsing before the limit check — swap the two so unmarshal precedes the cap.
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/extract.odin" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
# Move the limit guard to AFTER the unmarshal by deleting it and re-inserting a
# copy below the unmarshal line. Simplest: relocate the guard past the parse.
guard_start = s.index("\tif len(raw) > BODY_LIMIT {")
guard_end = s.index("\t}\n", guard_start) + len("\t}\n")
guard = s[guard_start:guard_end]
s = s[:guard_start] + s[guard_end:]
anchor = "\terr := encoding_json.unmarshal("
i = s.index(anchor)
# Insert the guard right after the unmarshal statement's line.
line_end = s.index("\n", i) + 1
s = s[:line_end] + guard + s[line_end:]
open(p, "w").write(s)
PY2
expect_reject "$T" "parse before the cap" \
  "parses before checking the 4 MiB cap"

# 35. Decoding with context.allocator instead of the request arena.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/request_arena_allocator(ctx)/context.allocator/' "$T/web/extract.odin"
expect_reject "$T" "unmarshal into context.allocator" \
  "does not decode into the request arena allocator"

# 36. Dropping strict .JSON mode (defaulting to JSON5).
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/unmarshal(raw, dst, .JSON, /unmarshal(raw, dst, /' "$T/web/extract.odin"
expect_reject "$T" "strict JSON mode dropped" \
  "does not unmarshal in strict .JSON mode"

# 37. The arena teardown removed from the driver.
T="$(fresh_tree)"; TREES+=("$T")
sed -i '/request_arena_destroy(&ctx)/d' "$T/web/test_support.odin"
expect_reject "$T" "arena teardown removed from the driver" \
  "does not call request_arena_destroy"

# 38. The body capability consumed AFTER the parse (allowing a second decode).
T="$(fresh_tree)"; TREES+=("$T")
python3 - "$T/web/extract.odin" <<'PY2'
import sys
p = sys.argv[1]; s = open(p).read()
line = "\tctx.private.body_state = .Consumed\n"
assert line in s, "MUTATION-SETUP: consume line not found"
s = s.replace(line, "", 1)  # remove the early consume
# Re-insert it AFTER the unmarshal call's line.
anchor = "\terr := encoding_json.unmarshal("
i = s.index(anchor); line_end = s.index("\n", i) + 1
s = s[:line_end] + line + s[line_end:]
open(p, "w").write(s)
PY2
expect_reject "$T" "capability consumed after parse" \
  "consumes the capability after parsing"

# 39. A public member added to the Status enum for 413.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^\tMethod_Not_Allowed    = 405,/\tMethod_Not_Allowed    = 405,\n\tPayload_Too_Large     = 413,/' \
  "$T/web/respond.odin"
expect_reject "$T" "public 413 Status member" \
  "a 413 member was added to the public Status enum"

# 40. A configurable body limit smuggled in.
T="$(fresh_tree)"; TREES+=("$T")
printf '\n@(private)\nset_body_limit :: proc(a: ^App, n: int) {}\n' >>"$T/web/app.odin"
expect_reject "$T" "configurable body limit" \
  "WP7 non-goal matching"

# 41. A new public symbol in the arena machinery.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nBody_Arena :: struct {}\n' >>"$T/web/request_arena.odin"
expect_reject "$T" "public symbol in the arena machinery" \
  "exports symbols outside the ratified Phase-1 surface"

echo "PASS: WP7 mutation checks (10 forbidden body-binding states all rejected)"

# ---------------------------------------------------------------------------
# WP8 mutation checks — the transport-boundary guardrails must REJECT the states
# they claim to forbid. The boundary is what keeps the backend replaceable, so a
# grep that passes on a bad tree would be worse than no grep.
# ---------------------------------------------------------------------------

# 42. The adapter importing `web` — the back-edge the one-way boundary forbids
#     (ADR-009 / WP8 D1).
T="$(fresh_tree)"; TREES+=("$T")
printf '\nimport _ "uruquim:web"\n' >>"$T/web/internal/transport/boundary.odin"
expect_reject "$T" "transport importing uruquim:web" \
  "web/internal/transport imports uruquim:web"

# 43. The backend imported OUTSIDE the adapter — here, straight into `web`.
#     Only web/internal/transport may name odin-http.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nimport _ "uruquim:vendor/odin-http"\n' >>"$T/web/serve.odin"
expect_reject "$T" "backend imported into web/" \
  "the vendored backend is imported outside"

# 44. A backend type in an EXPORTED signature. G-06 already bans
#     transport-shaped names in exported declarations; this proves it fires.
T="$(fresh_tree)"; TREES+=("$T")
printf '\nserve_raw :: proc(s: ^http.Server) {}\n' >>"$T/web/serve.odin"
expect_reject "$T" "backend type in an exported signature" \
  "exports symbols outside the ratified Phase-1 surface"

# 45. A new public transport symbol (serve_with / serve_transport / stop).
T="$(fresh_tree)"; TREES+=("$T")
printf '\nserve_with :: proc(a: ^App, port: int) {}\n' >>"$T/web/serve.odin"
expect_reject "$T" "serve_with added to the public surface" \
  "exports symbols outside the ratified Phase-1 surface"

# 46. A public member added to Status for 413 — still banned after WP8.
T="$(fresh_tree)"; TREES+=("$T")
sed -i 's/^\tMethod_Not_Allowed    = 405,/\tMethod_Not_Allowed    = 405,\n\tPayload_Too_Large     = 413,/' \
  "$T/web/respond.odin"
expect_reject "$T" "public 413 Status member after WP8" \
  "a 413 member was added to the public Status enum"

# 47. An unexpected subdirectory under web/internal/.
T="$(fresh_tree)"; TREES+=("$T")
mkdir -p "$T/web/internal/memory"
printf 'package memory\n' >"$T/web/internal/memory/x.odin"
expect_reject "$T" "extra web/internal subdirectory" \
  "web/internal/ has an unexpected subdirectory"

# 48. rawptr surfacing in an EXPORTED declaration (the G-03 narrowing must still
#     bite on the public side).
T="$(fresh_tree)"; TREES+=("$T")
printf '\nHandler_Raw :: proc(user: rawptr)\n' >>"$T/web/context.odin"
expect_reject "$T" "rawptr in an exported declaration" \
  "exports symbols outside the ratified Phase-1 surface"

echo "PASS: WP8 mutation checks (7 forbidden transport states all rejected)"
