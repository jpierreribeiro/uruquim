// WP5 internal behavior tests — the canonical path/query extractors and the
// package-private 400 envelope they commit on failure.
//
// This file declares `package web` but does NOT live in `web/`, and it must
// never be moved there. The declarations it covers — `Context_Internal`, the
// captured `Route_Param`, `Response`, `response_commit` and the whole private
// error-envelope machinery — are package-private, and on the pinned toolchain
// an `@(test)` procedure must be compiled as part of the package it tests.
// Compiling it inside the shipped package would link `core:testing` into every
// application binary (+41,592 bytes measured on 819fdc7). `build/check.sh`
// therefore assembles a THROWAWAY package from the real `web/` sources plus
// this file, exactly as it already does for WP2, WP3 and WP4, and
// `build/check_public_api.sh` permanently forbids `*_test.odin` and
// `core:testing` under `web/`.
//
// WHY THESE TESTS ARE INTERNAL. Three WP5 contracts cannot be observed from
// outside the package:
//
//   - the exact bytes of the committed 400 envelope, because `Recorded_Response`
//     exposes `body` but the failure path must also be checked against the
//     private `Response` before and after a second commit attempt;
//   - that the envelope body is a VIEW over request-local storage owned by the
//     Context rather than an allocation nobody frees;
//   - that `web.path` reads the private `Route_Param` captured by WP4, since
//     there is no public `ctx.params` and never will be (WP4 D1).
//
// THE JSON ORACLE. Every envelope assertion parses the committed bytes with the
// official `core:encoding/json` parser in STRICT `.JSON` mode — not the default
// `DEFAULT_SPECIFICATION`, which is JSON5 and would accept unquoted keys,
// trailing commas and single-quoted strings that are NOT valid JSON. The
// framework emits the envelope with a hand-written escaper (no encoder is
// linked into `web/`), so validating it with the official parser is what makes
// "the envelope is always valid JSON" an executed fact rather than a claim.
//
// `#+private` is kept as a defensive default: if this file were ever copied
// back into the package, its declarations still would not be exported.
#+private
package web

import json_oracle "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:testing"

// ---------------------------------------------------------------------------
// Harness
//
// Every helper fills a CALLER-OWNED Context. The Context must stay alive in the
// caller: the committed envelope body is a VIEW over request-local storage
// inside `Context_Internal`, exactly like WP4's `Allow` value. Returning a
// `Response` by value from a helper would hand back a view into a dead stack
// frame — the precise ownership bug WP5 must not have.
// ---------------------------------------------------------------------------

@(private = "file")
wp5_with_param :: proc(ctx: ^Context, name: string, value: string) {
	ctx.private.param = Route_Param{name = name, value = value, found = true}
}

@(private = "file")
wp5_with_query :: proc(ctx: ^Context, query: string) {
	ctx.request.query = query
}

// wp5_expect_envelope parses the committed body with the OFFICIAL parser in
// strict JSON mode and asserts the three envelope members.
//
// `field` is asserted as a DECODED string, so a name containing `"` or `\`
// proves round-trip correctness of the escaper rather than merely "some bytes
// were written".
@(private = "file")
wp5_expect_envelope :: proc(
	t: ^testing.T,
	body: []u8,
	code: string,
	message: string,
	field: string,
	loc := #caller_location,
) {
	value, err := json_oracle.parse(body, json_oracle.Specification.JSON, false, context.allocator)
	if !testing.expect_value(t, err, json_oracle.Error.None, loc = loc) {
		return
	}
	defer json_oracle.destroy_value(value, context.allocator)

	root := value.(json_oracle.Object) or_else nil
	if !testing.expect(t, root != nil, "the envelope root must be a JSON object", loc = loc) {
		return
	}

	inner_value, has_error := root["error"]
	if !testing.expect(t, has_error, "the envelope must carry an 'error' member", loc = loc) {
		return
	}
	inner := inner_value.(json_oracle.Object) or_else nil
	if !testing.expect(t, inner != nil, "'error' must be a JSON object", loc = loc) {
		return
	}

	// `field` is always present for these two WP5 codes. WP6 owns the general
	// rule that `field` is omitted when no input field caused the error.
	for member in ([]string{"code", "message", "field"}) {
		_, present := inner[member]
		testing.expect(t, present, "the envelope must carry code, message and field", loc = loc)
	}

	testing.expect_value(t, string(inner["code"].(json_oracle.String) or_else ""), code, loc = loc)
	testing.expect_value(t, string(inner["message"].(json_oracle.String) or_else ""), message, loc = loc)
	testing.expect_value(t, string(inner["field"].(json_oracle.String) or_else ""), field, loc = loc)
}

@(private = "file")
wp5_noop_handler :: proc(ctx: ^Context) {
}

// ---------------------------------------------------------------------------
// 1-4. `path` reads the private parameter WP4 captured.
// ---------------------------------------------------------------------------

@(test)
wp5_path_returns_the_captured_value_for_the_matching_name :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_param(&ctx, "id", "42")

	testing.expect_value(t, path(&ctx, "id"), "42")
	testing.expect(t, !ctx.private.response.committed, "path must never commit a response")
}

@(test)
wp5_path_returns_empty_for_a_different_name :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_param(&ctx, "id", "42")

	// The name must match EXACTLY. A near-miss is an absence, never the value
	// of the one parameter that happens to be captured.
	for name in ([]string{"Id", "ID", "i", "idd", "", "user_id"}) {
		testing.expect_value(t, path(&ctx, name), "")
	}
	testing.expect(t, !ctx.private.response.committed, "a path miss must not commit")
}

@(test)
wp5_path_on_a_static_route_has_no_parameter :: proc(t: ^testing.T) {
	// A static match captures nothing (WP4), so every lookup is an absence.
	ctx: Context
	testing.expect(t, !ctx.private.param.found)

	testing.expect_value(t, path(&ctx, "id"), "")
	testing.expect_value(t, path(&ctx, ""), "")
}

@(test)
wp5_path_ignores_a_capture_that_was_not_found :: proc(t: ^testing.T) {
	// `found` is authoritative. A zero-value name/value pair must not be
	// readable just because the name happens to compare equal.
	ctx: Context
	ctx.private.param = Route_Param{name = "id", value = "42", found = false}

	testing.expect_value(t, path(&ctx, "id"), "")
}

@(test)
wp5_path_value_is_a_view_over_the_request_path :: proc(t: ^testing.T) {
	// The extractor must hand back the WP4 view unchanged, not a copy: the
	// value is request-lifetime data and copying it would put a per-request
	// allocation on the hot path (G-05).
	backing := make([]u8, len("/users/42"))
	defer delete_slice(backing)
	copy(backing, transmute([]u8)string("/users/42"))

	ctx: Context
	wp5_with_param(&ctx, "id", string(backing)[len("/users/"):])

	testing.expect_value(t, path(&ctx, "id"), "42")

	slice.fill(backing, '#')
	testing.expect(
		t,
		path(&ctx, "id") != "42",
		"path must return a view over the request path, not a copy",
	)
}

@(test)
wp5_path_reads_what_real_dispatch_captured :: proc(t: ^testing.T) {
	// The whole point of WP5's path extractor: it consumes the storage the REAL
	// WP4 dispatcher writes, with no public `ctx.params` in between (WP4 D1).
	a := app()
	defer destroy(&a)

	get(&a, "/users/:id", wp5_noop_handler)

	ctx: Context
	ctx.request.method = .GET
	ctx.request.path = "/users/42"
	dispatch(&a, &ctx)

	testing.expect_value(t, path(&ctx, "id"), "42")
	testing.expect_value(t, path(&ctx, "other"), "")
}

// ---------------------------------------------------------------------------
// 5-7. `path_int` parses, and commits `invalid_path_parameter` on failure.
// ---------------------------------------------------------------------------

@(test)
wp5_path_int_accepts_positive_and_negative_integers :: proc(t: ^testing.T) {
	for pair in ([]struct {
		raw:      string,
		expected: int,
	}{{"42", 42}, {"0", 0}, {"-1", -1}, {"-42", -42}, {"7", 7}, {"000123", 123}}) {
		ctx: Context
		wp5_with_param(&ctx, "id", pair.raw)

		value, ok := path_int(&ctx, "id")
		testing.expectf(t, ok, "path_int must accept %q", pair.raw)
		testing.expect_value(t, value, pair.expected)
		testing.expectf(
			t,
			!ctx.private.response.committed,
			"a successful path_int must not commit a response (raw=%q)",
			pair.raw,
		)
	}
}

@(test)
wp5_path_int_accepts_the_extremes_of_int :: proc(t: ^testing.T) {
	ctx_max: Context
	wp5_with_param(&ctx_max, "id", "9223372036854775807")
	value_max, ok_max := path_int(&ctx_max, "id")
	testing.expect(t, ok_max, "max(int) must parse")
	testing.expect_value(t, value_max, max(int))

	// The negative extreme has a magnitude one larger than max(int), so a parser
	// that accumulates into a signed `int` overflows exactly here.
	ctx_min: Context
	wp5_with_param(&ctx_min, "id", "-9223372036854775808")
	value_min, ok_min := path_int(&ctx_min, "id")
	testing.expect(t, ok_min, "min(int) must parse")
	testing.expect_value(t, value_min, min(int))
}

@(test)
wp5_path_int_rejects_empty_text_and_overflow :: proc(t: ^testing.T) {
	for raw in ([]string{
		"", // present but empty
		"abc", // not a number
		"4x", // trailing garbage
		"x4", // leading garbage
		" 42", // leading space
		"42 ", // trailing space
		"4 2", // embedded space
		"+42", // an explicit plus is not accepted
		"-", // a sign with no digits
		"4.2", // not an integer
		"0x1f", // no base prefixes: this is not a decimal integer
		"1_000", // no digit separators
		"9223372036854775808", // max(int) + 1
		"-9223372036854775809", // min(int) - 1
		"99999999999999999999999", // far past the range
	}) {
		ctx: Context
		wp5_with_param(&ctx, "id", raw)

		value, ok := path_int(&ctx, "id")
		testing.expectf(t, !ok, "path_int must reject %q", raw)
		testing.expect_value(t, value, 0)
		testing.expectf(t, ctx.private.response.committed, "rejecting %q must commit a 400", raw)
		testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
	}
}

@(test)
wp5_path_int_rejects_an_absent_parameter :: proc(t: ^testing.T) {
	// No capture at all — a static route, or the wrong name.
	ctx: Context
	value, ok := path_int(&ctx, "id")

	testing.expect(t, !ok)
	testing.expect_value(t, value, 0)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
}

@(test)
wp5_path_int_failure_commits_the_exact_envelope :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_param(&ctx, "id", "banana")

	_, ok := path_int(&ctx, "id")
	testing.expect(t, !ok)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)

	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_path_parameter",
		"Path parameter 'id' must be an integer",
		"id",
	)

	// AMENDED IN WP6: the envelope now carries a `Content-Type`. The body still
	// lives on the fixed request-local buffer, so it is BORROWED, not owned —
	// WP5's allocation-free error path is unchanged.
	testing.expect_value(t, len(ctx.private.response.headers), 1)
	testing.expect_value(t, ctx.private.response.headers[0].name, "Content-Type")
	testing.expect_value(t, ctx.private.response.headers[0].value, "application/json")
}

// ---------------------------------------------------------------------------
// 8-14. `query` scans the raw query string in place.
// ---------------------------------------------------------------------------

@(test)
wp5_query_finds_a_key_at_the_start_middle_and_end :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "first=1&middle=2&last=3")

	for pair in ([]struct {
		key:      string,
		expected: string,
	}{{"first", "1"}, {"middle", "2"}, {"last", "3"}}) {
		value, found := query(&ctx, pair.key)
		testing.expectf(t, found, "%q must be found", pair.key)
		testing.expect_value(t, value, pair.expected)
	}

	testing.expect(t, !ctx.private.response.committed, "query must never commit a response")
}

@(test)
wp5_query_is_case_sensitive :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "Page=1")

	_, found_lower := query(&ctx, "page")
	testing.expect(t, !found_lower, "query comparison is exact and case-sensitive")

	value, found_exact := query(&ctx, "Page")
	testing.expect(t, found_exact)
	testing.expect_value(t, value, "1")
}

@(test)
wp5_query_treats_an_empty_value_as_present :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "a=&b=2")

	value, found := query(&ctx, "a")
	testing.expect(t, found, "a key with an empty value is PRESENT")
	testing.expect_value(t, value, "")
	testing.expect_value(t, len(value), 0)
}

@(test)
wp5_query_treats_a_bare_key_as_present_and_empty :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "flag&b=2")

	value, found := query(&ctx, "flag")
	testing.expect(t, found, "a key with no '=' is PRESENT with an empty value")
	testing.expect_value(t, value, "")

	// The same holds for a bare key in the last position.
	ctx2: Context
	wp5_with_query(&ctx2, "b=2&flag")
	value2, found2 := query(&ctx2, "flag")
	testing.expect(t, found2)
	testing.expect_value(t, value2, "")
}

@(test)
wp5_query_reports_an_absent_key :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "a=1&b=2")

	value, found := query(&ctx, "c")
	testing.expect(t, !found)
	testing.expect_value(t, value, "")
	testing.expect(t, !ctx.private.response.committed, "an absent key must not commit")

	// An empty query string finds nothing and does not misbehave.
	empty: Context
	_, found_empty := query(&empty, "a")
	testing.expect(t, !found_empty)
}

@(test)
wp5_query_does_not_confuse_prefixes_or_suffixes :: proc(t: ^testing.T) {
	// The scan compares WHOLE keys. A substring match would make `id` read the
	// value of `user_id` — a silent wrong answer, not a visible failure.
	ctx: Context
	wp5_with_query(&ctx, "user_id=7&id=3&idx=9")

	id, id_found := query(&ctx, "id")
	testing.expect(t, id_found)
	testing.expect_value(t, id, "3")

	user_id, user_found := query(&ctx, "user_id")
	testing.expect(t, user_found)
	testing.expect_value(t, user_id, "7")

	idx, idx_found := query(&ctx, "idx")
	testing.expect(t, idx_found)
	testing.expect_value(t, idx, "9")

	// A key that is only a prefix of a present key is absent.
	_, found_u := query(&ctx, "user")
	testing.expect(t, !found_u)
}

@(test)
wp5_query_does_not_match_inside_a_value :: proc(t: ^testing.T) {
	// `b` appears inside the VALUE of `a`. Only keys are compared.
	ctx: Context
	wp5_with_query(&ctx, "a=b=c")

	value, found := query(&ctx, "a")
	testing.expect(t, found)
	// The split is at the FIRST '=' only, so the rest stays in the value.
	testing.expect_value(t, value, "b=c")

	_, found_b := query(&ctx, "b")
	testing.expect(t, !found_b)
}

@(test)
wp5_query_first_occurrence_wins :: proc(t: ^testing.T) {
	// A minimal internal rule, deliberately NOT announced as a permanent
	// duplicate-key contract: WP5 does no percent-decoding and freezes no
	// advanced query semantics.
	ctx: Context
	wp5_with_query(&ctx, "a=1&a=2&a=3")

	value, found := query(&ctx, "a")
	testing.expect(t, found)
	testing.expect_value(t, value, "1")
}

@(test)
wp5_query_value_is_a_view_over_the_request_query :: proc(t: ^testing.T) {
	backing := make([]u8, len("page=42"))
	defer delete_slice(backing)
	copy(backing, transmute([]u8)string("page=42"))

	ctx: Context
	wp5_with_query(&ctx, string(backing))

	value, found := query(&ctx, "page")
	testing.expect(t, found)
	testing.expect_value(t, value, "42")

	slice.fill(backing, '#')
	testing.expect(
		t,
		value != "42",
		"query must return a view over the request query, not a copy",
	)
}

@(test)
wp5_query_does_not_decode_anything :: proc(t: ^testing.T) {
	// WP5 does NO percent-decoding and does NOT turn '+' into a space. The raw
	// bytes come back exactly as they arrived; a decoding policy is later work
	// and must not be frozen by accident here.
	ctx: Context
	wp5_with_query(&ctx, "q=a%20b+c%26d")

	value, found := query(&ctx, "q")
	testing.expect(t, found)
	testing.expect_value(t, value, "a%20b+c%26d")
}

// ---------------------------------------------------------------------------
// 15-17. `query_int` — required, responds on failure.
// ---------------------------------------------------------------------------

@(test)
wp5_query_int_accepts_a_valid_integer :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "page=7&other=x")

	value, ok := query_int(&ctx, "page")
	testing.expect(t, ok)
	testing.expect_value(t, value, 7)
	testing.expect(t, !ctx.private.response.committed, "a successful query_int must not commit")
}

@(test)
wp5_query_int_absent_commits_the_required_envelope :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "other=1")

	value, ok := query_int(&ctx, "page")
	testing.expect(t, !ok)
	testing.expect_value(t, value, 0)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)

	// An ABSENT required parameter says "is required" — it does not claim the
	// value was malformed.
	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_query_parameter",
		"Query parameter 'page' is required",
		"page",
	)
}

@(test)
wp5_query_int_present_but_invalid_commits_the_integer_envelope :: proc(t: ^testing.T) {
	for raw in ([]string{"", "banana", "1.5", "9223372036854775808", "+3", "3 "}) {
		ctx: Context
		// Build "page=<raw>" without allocating in the test body.
		buffer: [64]u8
		n := copy(buffer[:], "page=")
		n += copy(buffer[n:], raw)
		wp5_with_query(&ctx, string(buffer[:n]))

		value, ok := query_int(&ctx, "page")
		testing.expectf(t, !ok, "query_int must reject %q", raw)
		testing.expect_value(t, value, 0)
		testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)

		// PRESENT but unparseable says "must be an integer", which is a
		// different message from the absent case above.
		wp5_expect_envelope(
			t,
			ctx.private.response.body,
			"invalid_query_parameter",
			"Query parameter 'page' must be an integer",
			"page",
		)
	}
}

// ---------------------------------------------------------------------------
// 18-20. `query_int_or` — the default applies ONLY to absence.
// ---------------------------------------------------------------------------

@(test)
wp5_query_int_or_returns_the_default_when_absent :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "other=1")

	value, ok := query_int_or(&ctx, "limit", 20)
	testing.expect(t, ok, "an absent optional parameter is a SUCCESS")
	testing.expect_value(t, value, 20)
	testing.expect(t, !ctx.private.response.committed, "absence must not commit a response")

	// The default is returned verbatim, including zero and negatives.
	for def in ([]int{0, -5, max(int), min(int)}) {
		fresh: Context
		v, k := query_int_or(&fresh, "limit", def)
		testing.expect(t, k)
		testing.expect_value(t, v, def)
	}
}

@(test)
wp5_query_int_or_ignores_the_default_when_present :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_query(&ctx, "limit=50")

	value, ok := query_int_or(&ctx, "limit", 20)
	testing.expect(t, ok)
	testing.expect_value(t, value, 50)
	testing.expect(t, !ctx.private.response.committed)
}

@(test)
wp5_query_int_or_never_substitutes_the_default_for_a_malformed_value :: proc(t: ^testing.T) {
	// The load-bearing distinction of this extractor: a present-but-malformed
	// value is a 400, NEVER silently replaced by the default. Silently
	// defaulting would turn `?limit=banana` into a successful request.
	ctx: Context
	wp5_with_query(&ctx, "limit=banana")

	value, ok := query_int_or(&ctx, "limit", 20)
	testing.expect(t, !ok)
	testing.expect_value(t, value, 0)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)

	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_query_parameter",
		"Query parameter 'limit' must be an integer",
		"limit",
	)
}

@(test)
wp5_query_int_or_treats_an_empty_value_as_malformed_not_absent :: proc(t: ^testing.T) {
	// `?limit=` is PRESENT with an empty value. Presence is decided by the key,
	// not by whether the value happens to be usable, so this is a 400 and not
	// the default.
	ctx: Context
	wp5_with_query(&ctx, "limit=")

	value, ok := query_int_or(&ctx, "limit", 20)
	testing.expect(t, !ok)
	testing.expect_value(t, value, 0)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
}

// ---------------------------------------------------------------------------
// 21-23. Exactly one commit, and the FIRST response always wins (ADR-008).
// ---------------------------------------------------------------------------

@(test)
wp5_a_failure_commits_exactly_once :: proc(t: ^testing.T) {
	ctx: Context
	wp5_with_param(&ctx, "id", "banana")

	_, first_ok := path_int(&ctx, "id")
	testing.expect(t, !first_ok)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)

	first_body := string(ctx.private.response.body)
	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_path_parameter",
		"Path parameter 'id' must be an integer",
		"id",
	)

	// A SECOND failing extraction, with a different name, must change nothing.
	// If the second call rewrote the shared request-local envelope buffer, the
	// first response's body — which is a VIEW over it — would silently mutate.
	ctx.private.param = Route_Param{name = "other", value = "nope", found = true}
	_, second_ok := query_int(&ctx, "page")
	testing.expect(t, !second_ok, "a second failure still reports failure")

	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
	testing.expect_value(t, string(ctx.private.response.body), first_body)
	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_path_parameter",
		"Path parameter 'id' must be an integer",
		"id",
	)
}

@(test)
wp5_continued_handler_code_cannot_replace_the_extractor_error :: proc(t: ^testing.T) {
	// The canonical contract of G-04: a handler that ignores `ok` and keeps
	// going cannot overwrite the response the extractor already produced.
	ctx: Context
	wp5_with_query(&ctx, "page=banana")

	_, ok := query_int(&ctx, "page")
	testing.expect(t, !ok)

	replaced := response_commit(
		&ctx.private.response,
		.OK,
		nil,
		transmute([]u8)string("late success"),
	)
	testing.expect(t, !replaced, "the commit guard must reject the second write")

	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_query_parameter",
		"Query parameter 'page' must be an integer",
		"page",
	)
}

@(test)
wp5_an_extractor_error_cannot_replace_an_already_committed_response :: proc(t: ^testing.T) {
	// The mirror image: a response committed BEFORE the extractor runs survives
	// intact, and the extractor still reports failure so the handler returns.
	ctx: Context
	wp5_with_param(&ctx, "id", "banana")

	testing.expect(
		t,
		response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("first")),
	)

	value, ok := path_int(&ctx, "id")
	testing.expect(t, !ok, "the extractor still fails, so the handler still returns")
	testing.expect_value(t, value, 0)

	testing.expect_value(t, ctx.private.response.status, Status.OK)
	testing.expect_value(t, string(ctx.private.response.body), "first")
	testing.expect_value(t, len(ctx.private.response.headers), 0)
}

// ---------------------------------------------------------------------------
// 24. The parameter name is correctly escaped into valid JSON.
// ---------------------------------------------------------------------------

@(test)
wp5_envelope_escapes_quotes_and_backslashes_in_the_name :: proc(t: ^testing.T) {
	// A name carrying the two characters that would otherwise terminate or
	// corrupt a JSON string. The official parser both proves the bytes are
	// valid JSON and decodes `field` back to the original name.
	name := "he said \"hi\"\\done"

	ctx: Context
	wp5_with_param(&ctx, name, "banana")

	_, ok := path_int(&ctx, name)
	testing.expect(t, !ok)

	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_path_parameter",
		"Path parameter 'he said \"hi\"\\done' must be an integer",
		name,
	)
}

@(test)
wp5_envelope_escapes_control_characters_in_the_name :: proc(t: ^testing.T) {
	// Raw control characters are not permitted inside a JSON string and must be
	// escaped. An unescaped newline here would make the envelope unparseable.
	name := "a\nb\tc\x01d"

	ctx: Context
	wp5_with_query(&ctx, "other=1")

	_, ok := query_int(&ctx, name)
	testing.expect(t, !ok)

	wp5_expect_envelope(
		t,
		ctx.private.response.body,
		"invalid_query_parameter",
		"Query parameter 'a\nb\tc\x01d' is required",
		name,
	)
}

@(test)
wp5_envelope_stays_valid_json_for_a_very_long_name :: proc(t: ^testing.T) {
	// The envelope is built into FIXED request-local storage, so an unbounded
	// name must be bounded by the emitter rather than overflowing it or
	// producing a truncated, unparseable body.
	long: [512]u8
	slice.fill(long[:], 'x')
	name := string(long[:])

	ctx: Context
	wp5_with_param(&ctx, name, "banana")

	_, ok := path_int(&ctx, name)
	testing.expect(t, !ok)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)

	// Whatever the emitter decided to include, the result must still parse as
	// strict JSON and still carry all three members.
	value, err := json_oracle.parse(
		ctx.private.response.body,
		json_oracle.Specification.JSON,
		false,
		context.allocator,
	)
	testing.expect_value(t, err, json_oracle.Error.None)
	defer json_oracle.destroy_value(value, context.allocator)

	root := value.(json_oracle.Object) or_else nil
	testing.expect(t, root != nil)
	inner := root["error"].(json_oracle.Object) or_else nil
	testing.expect(t, inner != nil, "a bounded name must still produce a complete envelope")
	testing.expect_value(
		t,
		string(inner["code"].(json_oracle.String) or_else ""),
		"invalid_path_parameter",
	)
}

@(test)
wp5_envelope_stays_valid_json_for_a_long_name_full_of_escapes :: proc(t: ^testing.T) {
	// The worst case for a fixed buffer: every byte expands to a 6-byte `\u00XX`
	// escape. Truncation must land on an escape boundary, never in the middle
	// of one.
	long: [512]u8
	slice.fill(long[:], 0x01)
	name := string(long[:])

	ctx: Context
	wp5_with_query(&ctx, "other=1")

	_, ok := query_int(&ctx, name)
	testing.expect(t, !ok)

	value, err := json_oracle.parse(
		ctx.private.response.body,
		json_oracle.Specification.JSON,
		false,
		context.allocator,
	)
	testing.expect_value(t, err, json_oracle.Error.None)
	defer json_oracle.destroy_value(value, context.allocator)

	root := value.(json_oracle.Object) or_else nil
	testing.expect(t, root != nil, "an all-escape name must still produce valid JSON")
}

@(test)
wp5_envelope_stays_valid_json_for_a_multibyte_name :: proc(t: ^testing.T) {
	// Multi-byte UTF-8 must never be split by truncation: half a sequence is
	// not valid UTF-8 and therefore not valid JSON.
	buffer: [512]u8
	n := 0
	for n + 3 <= len(buffer) {
		n += copy(buffer[n:], "é")
	}
	name := string(buffer[:n])

	ctx: Context
	wp5_with_param(&ctx, name, "banana")

	_, ok := path_int(&ctx, name)
	testing.expect(t, !ok)

	value, err := json_oracle.parse(
		ctx.private.response.body,
		json_oracle.Specification.JSON,
		false,
		context.allocator,
	)
	testing.expect_value(t, err, json_oracle.Error.None)
	defer json_oracle.destroy_value(value, context.allocator)

	root := value.(json_oracle.Object) or_else nil
	testing.expect(t, root != nil, "a multi-byte name must not be split mid-sequence")
}

// ---------------------------------------------------------------------------
// 25-26. Ownership and allocation.
// ---------------------------------------------------------------------------

@(test)
wp5_the_envelope_body_is_owned_by_the_context :: proc(t: ^testing.T) {
	// The committed body must be a VIEW over request-local storage inside the
	// Context — the same arrangement WP4 uses for the `Allow` value. It must
	// not be an allocation (nobody would free it) and it must not be a view
	// into a dead stack frame (it is read after the extractor returns).
	ctx: Context
	wp5_with_param(&ctx, "id", "banana")

	_, ok := path_int(&ctx, "id")
	testing.expect(t, !ok)

	body := ctx.private.response.body
	testing.expect(t, len(body) > 0, "the failure must have produced a body")

	base := uintptr(raw_data(body))
	low := uintptr(rawptr(&ctx))
	high := low + size_of(Context)
	testing.expect(
		t,
		base >= low && base < high,
		"the envelope body must live inside the caller's Context, not in an allocation",
	)
}

@(test)
wp5_successful_extraction_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	context.allocator = mem.tracking_allocator(&track)

	ctx: Context
	wp5_with_param(&ctx, "id", "42")
	wp5_with_query(&ctx, "page=3&limit=50&flag&name=x")

	testing.expect_value(t, path(&ctx, "id"), "42")

	id, id_ok := path_int(&ctx, "id")
	testing.expect(t, id_ok)
	testing.expect_value(t, id, 42)

	page, page_ok := query_int(&ctx, "page")
	testing.expect(t, page_ok)
	testing.expect_value(t, page, 3)

	limit, limit_ok := query_int_or(&ctx, "limit", 20)
	testing.expect(t, limit_ok)
	testing.expect_value(t, limit, 50)

	missing, missing_ok := query_int_or(&ctx, "absent", 9)
	testing.expect(t, missing_ok)
	testing.expect_value(t, missing, 9)

	name, name_found := query(&ctx, "name")
	testing.expect(t, name_found)
	testing.expect_value(t, name, "x")

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
wp5_a_failing_extraction_allocates_nothing_either :: proc(t: ^testing.T) {
	// The envelope goes into fixed request-local storage, so even the error
	// path — which an unauthenticated client can trigger at will — allocates
	// nothing. An allocation here would be a remote memory-pressure lever.
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	context.allocator = mem.tracking_allocator(&track)

	ctx: Context
	wp5_with_param(&ctx, "id", "banana")

	_, ok := path_int(&ctx, "id")
	testing.expect(t, !ok)
	testing.expect(t, ctx.private.response.committed)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

// ---------------------------------------------------------------------------
// 27. No WP6 or WP7 machinery was activated.
// ---------------------------------------------------------------------------

@(test)
wp5_extractor_errors_are_unchanged_by_wp6 :: proc(t: ^testing.T) {
	// SUPERSEDES `wp5_did_not_start_wp6_responders`, which asserted that the
	// WP6 responders committed nothing. WP6 has now shipped, so that guard is
	// obsolete — keeping it would assert the absence of a delivered feature.
	//
	// What WP5 still owns, and what this checks instead, is that its own two
	// envelopes did not change when WP6 landed: same status, same code, same
	// message, same `field`, and still on the fixed request-local buffer rather
	// than an owned allocation.
	ctx: Context
	wp5_with_param(&ctx, "id", "banana")

	_, ok := path_int(&ctx, "id")
	testing.expect(t, !ok)
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
	testing.expect(
		t,
		!ctx.private.response.owned_body,
		"the WP5 envelope must stay on the fixed buffer, not become an allocation",
	)
}

@(test)
wp5_body_binding_does_not_disturb_the_extractors :: proc(t: ^testing.T) {
	// SUPERSEDES `wp5_did_not_start_wp7_body_binding`, which asserted `web.body`
	// was still a stub. WP7 shipped it, so that guard is obsolete — keeping it
	// would assert the absence of a delivered feature.
	//
	// What WP5 still owns, and what this checks, is that body binding does not
	// interfere with the path/query extractors: an empty body commits its own
	// 400 (WP7), and that must be a DIFFERENT envelope from the extractor errors,
	// on the same single-commit guard.
	ctx: Context

	Payload :: struct {
		name: string `json:"name"`,
	}
	dst: Payload

	// An empty body now fails with WP7's invalid_json, not silently.
	testing.expect(t, !body(&ctx, &dst), "an empty body must fail")
	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
	testing.expect_value(
		t,
		string(ctx.private.response.body),
		`{"error":{"code":"invalid_json","message":"Request body must be valid JSON"}}`,
	)
}
