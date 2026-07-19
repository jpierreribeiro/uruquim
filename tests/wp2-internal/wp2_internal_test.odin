// WP2 internal behavior tests.
//
// This file declares `package web` but does NOT live in `web/`, and it must
// never be moved there. The declarations it covers — `Response`,
// `response_commit`, `method_from_token`, `Header_Pair` — are package-private,
// and on the pinned toolchain an `@(test)` procedure must be compiled as part
// of the package it tests. Compiling it inside the shipped package would link
// `core:testing` into every application binary: measured at +41,592 bytes on
// 819fdc7, against +248 for `core:strings`.
//
// So `build/check.sh` assembles a THROWAWAY package instead: it copies the
// real sources from `web/` plus this file into a `mktemp -d` directory, runs
// `odin test` there, and deletes the directory afterwards — including on
// failure. The tests see the genuine sources, and the shipped package ships no
// test code. `build/check_public_api.sh` permanently forbids `*_test.odin`
// files and `core:testing` under `web/`, so this cannot silently regress.
//
// `#+private` is kept as a defensive default: if this file were ever copied
// back into the package, its declarations still would not be exported.
#+private
package web

import "core:slice"
import "core:strings"
import "core:testing"

// ---------------------------------------------------------------------------
// Shared fixture: a transport-owned buffer with request views cut out of it.
//
// This is exactly the arrangement a real adapter produces (WP8): one buffer
// owned by the transport, and a Request whose strings and slices alias it. No
// copy is made anywhere in this helper — that is the point.
// ---------------------------------------------------------------------------

WP2_FIXTURE_TEXT :: "GET /users?page=2 application/json body-bytes-here"

// Byte offsets into WP2_FIXTURE_TEXT. Written out so the views are obviously
// aliases of one buffer rather than incidental literals.
WP2_PATH_LO :: 4
WP2_PATH_HI :: 10 // "/users"
WP2_QUERY_LO :: 11
WP2_QUERY_HI :: 17 // "page=2"
WP2_VALUE_LO :: 18
WP2_VALUE_HI :: 34 // "application/json"
WP2_BODY_LO :: 35 // "body-bytes-here"

@(private = "file")
wp2_request_over :: proc(buf: []u8, pairs: []Header_Pair) -> Request {
	pairs[0] = Header_Pair {
		name  = "content-type",
		value = string(buf[WP2_VALUE_LO:WP2_VALUE_HI]),
	}

	return Request {
		method  = method_from_token("GET"),
		path    = string(buf[WP2_PATH_LO:WP2_PATH_HI]),
		query   = string(buf[WP2_QUERY_LO:WP2_QUERY_HI]),
		headers = header_view_from_pairs(pairs),
		body    = buf[WP2_BODY_LO:],
	}
}

// ---------------------------------------------------------------------------
// 1. Aliasing and invalidation (port of exp-06)
//
// Reusing the transport buffer invalidates every retained view. The failure is
// SILENT: the view stays the same length and keeps pointing at live memory, it
// simply reads different bytes. That silence is why "copy to persist" is a
// normative rule and not a suggestion.
// ---------------------------------------------------------------------------

@(test)
wp2_buffer_reuse_invalidates_retained_views :: proc(t: ^testing.T) {
	buf := make([]u8, len(WP2_FIXTURE_TEXT))
	defer delete_slice(buf)
	copy(buf, transmute([]u8)string(WP2_FIXTURE_TEXT))

	pairs := make([]Header_Pair, 1)
	defer delete_slice(pairs)

	r := wp2_request_over(buf, pairs)

	testing.expect_value(t, r.method, Method.GET)
	testing.expect_value(t, r.path, "/users")
	testing.expect_value(t, r.query, "page=2")
	testing.expect_value(t, r.headers.private.pairs[0].value, "application/json")
	testing.expect_value(t, string(r.body), "body-bytes-here")

	// The transport reuses its buffer for the next request.
	slice.fill(buf, '#')

	testing.expect(
		t,
		r.path != "/users",
		"a retained path view must not survive reuse of the transport buffer",
	)
	testing.expect_value(t, r.path, "######")
	testing.expect_value(t, r.query, "######")
	testing.expect(
		t,
		r.headers.private.pairs[0].value != "application/json",
		"a retained header value view must not survive reuse of the buffer",
	)
	testing.expect_value(t, string(r.body), "###############")

	// Length is unchanged: nothing became nil and nothing reported an error.
	testing.expect_value(t, len(r.path), len("/users"))
}

// ---------------------------------------------------------------------------
// 2. An explicit copy survives the same reuse (port of exp-06)
// ---------------------------------------------------------------------------

@(test)
wp2_explicit_copy_survives_buffer_reuse :: proc(t: ^testing.T) {
	buf := make([]u8, len(WP2_FIXTURE_TEXT))
	defer delete_slice(buf)
	copy(buf, transmute([]u8)string(WP2_FIXTURE_TEXT))

	pairs := make([]Header_Pair, 1)
	defer delete_slice(pairs)

	r := wp2_request_over(buf, pairs)

	// The one supported way to keep request data: copy it, with an explicit
	// allocator, BEFORE the buffer is reused.
	saved_path := strings.clone(r.path, context.allocator)
	defer delete_string(saved_path)

	saved_header := strings.clone(r.headers.private.pairs[0].value, context.allocator)
	defer delete_string(saved_header)

	saved_body := slice.clone(r.body, context.allocator)
	defer delete_slice(saved_body)

	slice.fill(buf, '#')

	testing.expect_value(t, saved_path, "/users")
	testing.expect_value(t, saved_header, "application/json")
	testing.expect_value(t, string(saved_body), "body-bytes-here")

	// The views next to them did not survive: the copy is what saved the data,
	// not the moment at which it was read.
	testing.expect_value(t, r.path, "######")
}

// ---------------------------------------------------------------------------
// 3. Single-commit guard, tested on the INTERNAL primitive (port of exp-08)
//
// Tested directly on `response_commit`, by observing the stored status,
// headers and body — NOT through `web.json`/`web.ok`. Those helpers are inert
// stubs until WP6, and routing a WP2 test through them would start WP6 early
// and would prove nothing about the guard.
//
// The commit records status, headers and body ATOMICALLY: a rejected attempt
// must leave all three exactly as the first commit left them. Partial
// overwrite — a rejected commit that nevertheless replaced the headers — is
// the specific bug these tests exist to make impossible.
//
// `headers` is NOT owned by Response at this stage: it is a view, like `body`.
// WP6 defines the concrete allocation and lifetime of a rendered response.
// ---------------------------------------------------------------------------

@(private = "file")
WP2_JSON_HEADERS := []Header_Pair{{name = "content-type", value = "application/json"}}

// The 405 shape WP4 must be able to store and assert on. WP4's TESTS-FIRST
// contract requires "405-when-other-method with exact Allow header", and WP4
// depends on WP2/WP3 — it lands before WP6. Without internal header storage
// here, WP4 could not express, let alone test, its own ratified contract.
@(private = "file")
WP2_ALLOW_HEADERS := []Header_Pair{{name = "allow", value = "GET, POST"}}

@(test)
wp2_first_commit_records_status_headers_and_body :: proc(t: ^testing.T) {
	res: Response

	testing.expect(t, !res.committed, "a fresh Response must not be committed")
	testing.expect_value(t, len(res.headers), 0)

	accepted := response_commit(&res, .OK, WP2_JSON_HEADERS, transmute([]u8)string("first"))

	testing.expect(t, accepted, "the first commit must be accepted")
	testing.expect(t, res.committed, "the first commit must set the guard")
	testing.expect_value(t, res.status, Status.OK)
	testing.expect_value(t, len(res.headers), 1)
	testing.expect_value(t, res.headers[0].name, "content-type")
	testing.expect_value(t, res.headers[0].value, "application/json")
	testing.expect_value(t, string(res.body), "first")
}

@(test)
wp2_second_commit_is_rejected_and_changes_nothing :: proc(t: ^testing.T) {
	res: Response

	testing.expect(
		t,
		response_commit(&res, .Bad_Request, WP2_JSON_HEADERS, transmute([]u8)string("envelope")),
	)

	// Continued handler code tries to respond again — the exact shape of the
	// bug the guard exists to make impossible on the supported paths.
	rejected := response_commit(
		&res,
		.OK,
		WP2_ALLOW_HEADERS,
		transmute([]u8)string("overwrite"),
	)

	testing.expect(t, !rejected, "a second commit must be rejected")
	testing.expect(t, res.committed, "the guard must stay set after a rejected commit")

	// All three survive together. A guard that kept the status but let the
	// headers through would still be a double-write.
	testing.expect_value(t, res.status, Status.Bad_Request)
	testing.expect_value(t, len(res.headers), 1)
	testing.expect_value(t, res.headers[0].name, "content-type")
	testing.expect_value(t, res.headers[0].value, "application/json")
	testing.expect_value(t, string(res.body), "envelope")

	// A third attempt behaves identically: the guard is not a one-shot latch
	// that opens again after it fires. Committing nil headers and a nil body
	// must not clear what is stored either.
	testing.expect(t, !response_commit(&res, .Internal_Server_Error, nil, nil))
	testing.expect_value(t, res.status, Status.Bad_Request)
	testing.expect_value(t, len(res.headers), 1)
	testing.expect_value(t, res.headers[0].value, "application/json")
	testing.expect_value(t, string(res.body), "envelope")
}

@(test)
wp2_commit_stores_headers_a_405_needs :: proc(t: ^testing.T) {
	// WP2 stores the header; it does NOT decide that a 405 is warranted. The
	// decision, the Allow value, and the dispatch that produces them are WP4.
	res: Response

	testing.expect(
		t,
		response_commit(&res, .Method_Not_Allowed, WP2_ALLOW_HEADERS, nil),
	)

	testing.expect_value(t, res.status, Status.Method_Not_Allowed)
	testing.expect_value(t, res.headers[0].name, "allow")
	testing.expect_value(t, res.headers[0].value, "GET, POST")
	testing.expect_value(t, len(res.body), 0)
}

@(test)
wp2_commit_headers_are_views_not_copies :: proc(t: ^testing.T) {
	// Response does not own the header storage at this stage: it aliases what
	// the caller supplied, exactly as `body` does. WP6 defines the concrete
	// allocation and lifetime of a rendered response.
	pairs := make([]Header_Pair, 1)
	defer delete_slice(pairs)
	pairs[0] = Header_Pair{name = "content-type", value = "text/plain"}

	res: Response
	testing.expect(t, response_commit(&res, .OK, pairs, nil))

	pairs[0].value = "application/json"
	testing.expect_value(t, res.headers[0].value, "application/json")
}

@(test)
wp2_commit_guard_is_per_response :: proc(t: ^testing.T) {
	first: Response
	second: Response

	testing.expect(t, response_commit(&first, .OK, nil, transmute([]u8)string("a")))
	testing.expect(
		t,
		response_commit(&second, .Created, nil, transmute([]u8)string("b")),
		"one committed response must not block a different response",
	)

	testing.expect_value(t, first.status, Status.OK)
	testing.expect_value(t, second.status, Status.Created)
}

@(test)
wp2_context_carries_an_uncommitted_response :: proc(t: ^testing.T) {
	ctx: Context

	// The response state reached through the Context is the same primitive,
	// with the same guard. WP2 wires no public path onto it; WP6 does.
	testing.expect(t, !ctx.private.response.committed)
	testing.expect(t, response_commit(&ctx.private.response, .No_Content, nil, nil))
	testing.expect(t, !response_commit(&ctx.private.response, .OK, WP2_JSON_HEADERS, nil))
	testing.expect_value(t, ctx.private.response.status, Status.No_Content)
	testing.expect_value(t, len(ctx.private.response.headers), 0)
}

// ---------------------------------------------------------------------------
// 4. Method conversion — tokens only, no HTTP status anywhere
// ---------------------------------------------------------------------------

@(test)
wp2_supported_method_tokens_convert_exactly :: proc(t: ^testing.T) {
	testing.expect_value(t, method_from_token("GET"), Method.GET)
	testing.expect_value(t, method_from_token("POST"), Method.POST)
	testing.expect_value(t, method_from_token("PUT"), Method.PUT)
	testing.expect_value(t, method_from_token("PATCH"), Method.PATCH)
	testing.expect_value(t, method_from_token("DELETE"), Method.DELETE)
}

@(test)
wp2_unsupported_method_tokens_convert_to_unknown :: proc(t: ^testing.T) {
	// Absent from the Phase-1 set by decision, not by oversight: neither has a
	// ratified Phase-1 contract, and `.UNKNOWN` is the correct conversion.
	testing.expect_value(t, method_from_token("HEAD"), Method.UNKNOWN)
	testing.expect_value(t, method_from_token("OPTIONS"), Method.UNKNOWN)

	// A registered but unimplemented method is a valid HTTP method, not a
	// malformed request (RFC 9110 §9.1; IANA HTTP Method Registry).
	testing.expect_value(t, method_from_token("PROPFIND"), Method.UNKNOWN)
	testing.expect_value(t, method_from_token("TRACE"), Method.UNKNOWN)

	// Methods are case-sensitive.
	testing.expect_value(t, method_from_token("get"), Method.UNKNOWN)
	testing.expect_value(t, method_from_token("Get"), Method.UNKNOWN)

	// Arbitrary and degenerate tokens are total, never a panic.
	testing.expect_value(t, method_from_token("BREW"), Method.UNKNOWN)
	testing.expect_value(t, method_from_token(""), Method.UNKNOWN)
	testing.expect_value(t, method_from_token("GET "), Method.UNKNOWN)
	testing.expect_value(t, method_from_token("GETX"), Method.UNKNOWN)
}

@(test)
wp2_unknown_method_carries_no_http_decision :: proc(t: ^testing.T) {
	// The whole behavior of an unrecognized method in WP2 is the enum value.
	// No status is produced, and the response stays uncommitted: deciding 405
	// or 501 belongs to WP4/WP9, and doing it here would push response policy
	// into every transport adapter.
	ctx: Context
	ctx.request.method = method_from_token("PROPFIND")

	testing.expect_value(t, ctx.request.method, Method.UNKNOWN)
	testing.expect(
		t,
		!ctx.private.response.committed,
		"an unknown method must not produce a response in WP2",
	)
}

// ---------------------------------------------------------------------------
// 5. Header view shape — no lookup exists in Phase 1
// ---------------------------------------------------------------------------

@(test)
wp2_header_view_wraps_pairs_without_copying :: proc(t: ^testing.T) {
	pairs := make([]Header_Pair, 2)
	defer delete_slice(pairs)
	pairs[0] = Header_Pair{name = "content-type", value = "application/json"}
	pairs[1] = Header_Pair{name = "x-api-key", value = "abc"}

	view := header_view_from_pairs(pairs)

	testing.expect_value(t, len(view.private.pairs), 2)
	testing.expect_value(t, view.private.pairs[1].name, "x-api-key")

	// The view aliases the caller's array: it did not copy it.
	pairs[1].value = "changed"
	testing.expect_value(t, view.private.pairs[1].value, "changed")

	// Ordering is preserved as received. Phase 1 performs NO lookup and NO
	// normalization, so there is nothing else to assert here.
	testing.expect_value(t, view.private.pairs[0].name, "content-type")
}

@(test)
wp2_zero_request_is_inert :: proc(t: ^testing.T) {
	r: Request

	testing.expect_value(t, r.method, Method.UNKNOWN)
	testing.expect_value(t, r.path, "")
	testing.expect_value(t, r.query, "")
	testing.expect_value(t, len(r.headers.private.pairs), 0)
	testing.expect_value(t, len(r.body), 0)
}
