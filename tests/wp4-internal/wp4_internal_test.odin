// WP4 internal behavior tests — route registration, matching and dispatch.
//
// This file declares `package web` but does NOT live in `web/`, and it must
// never be moved there. The declarations it covers — the route table, the
// matcher, `dispatch`, `response_commit`, `Context_Internal` — are all
// package-private, and on the pinned toolchain an `@(test)` procedure must be
// compiled as part of the package it tests. Compiling it inside the shipped
// package would link `core:testing` into every application binary (+41,592
// bytes measured on 819fdc7). `build/check.sh` therefore assembles a THROWAWAY
// package from the real `web/` sources plus this file, exactly as it already
// does for WP2 and WP3, and `build/check_public_api.sh` permanently forbids
// `*_test.odin` and `core:testing` under `web/`.
//
// WHY THESE TESTS ARE INTERNAL. Two of the WP4 contracts cannot be observed
// from outside the package:
//
//   - the exact `Allow` header, because `Recorded_Response` deliberately has no
//     public `headers` field and Phase 1 ratifies no header accessor (D4);
//   - a routed 200 with a real body, because the public responders are inert
//     stubs until WP6, so only `response_commit` can produce one today.
//
// Both are exercised through the REAL registration + dispatch path, never
// through a temporary public responder invented for testing.
//
// `#+private` is kept as a defensive default: if this file were ever copied
// back into the package, its declarations still would not be exported.
#+private
package web

import "core:mem"
import "core:slice"
import "core:testing"

// ---------------------------------------------------------------------------
// Harness
//
// `wp4_run` fills a CALLER-OWNED Context and dispatches into it. The Context
// must stay alive in the caller: the `Allow` value and its header pair are
// request-local storage inside `Context_Internal`, and the committed response
// holds VIEWS over them. Returning a `Response` by value from a helper would
// hand back views into a dead stack frame — the exact ownership bug WP4 must
// not have.
// ---------------------------------------------------------------------------

@(private = "file")
wp4_run :: proc(a: ^App, ctx: ^Context, method: Method, path: string) {
	ctx.request.method = method
	ctx.request.path = path
	dispatch(a, ctx)
}

// Handlers that commit a DISTINGUISHING body. Which one ran is then read back
// from the test's own Context, which is race-free: the pinned runner executes
// tests in parallel, so any counter shared by two tests would race.
//
// Only ONE handler can run per dispatch — `dispatch` returns immediately after
// invoking it — so the recorded body identifies the winner unambiguously.

@(private = "file")
wp4_static_handler :: proc(ctx: ^Context) {
	response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("static"))
}

@(private = "file")
wp4_param_handler :: proc(ctx: ^Context) {
	response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("param"))
}

@(private = "file")
wp4_noop_handler :: proc(ctx: ^Context) {
}

// Invocation counters. Each belongs to EXACTLY ONE test, so no two parallel
// tests ever touch the same counter.

@(private = "file")
wp4_once_hits: int

@(private = "file")
wp4_once_handler :: proc(ctx: ^Context) {
	wp4_once_hits += 1
	response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("static"))
}

@(private = "file")
wp4_bare_hits: int

@(private = "file")
wp4_bare_handler :: proc(ctx: ^Context) {
	wp4_bare_hits += 1
	response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("static"))
}

@(private = "file")
wp4_root_hits: int

@(private = "file")
wp4_root_handler :: proc(ctx: ^Context) {
	wp4_root_hits += 1
	response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("static"))
}

// ---------------------------------------------------------------------------
// 1. A static GET registers, matches, and invokes its handler exactly once.
// ---------------------------------------------------------------------------

@(test)
wp4_static_route_matches_and_runs_handler_once :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// A handler cannot capture a local, so the count lives in a counter this
	// test is the only user of.
	before := wp4_once_hits
	get(&a, "/health", wp4_once_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/health")

	testing.expect_value(t, wp4_once_hits - before, 1)
	testing.expect(t, ctx.private.response.committed, "the handler must have responded")
	testing.expect_value(t, ctx.private.response.status, Status.OK)
	testing.expect_value(t, string(ctx.private.response.body), "static")

}

// ---------------------------------------------------------------------------
// 2. Methods are isolated: a route registered on one method is invisible to
//    the others, and each verb registers independently.
// ---------------------------------------------------------------------------

@(test)
wp4_methods_are_isolated :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/g", wp4_noop_handler)
	post(&a, "/p", wp4_noop_handler)
	put(&a, "/u", wp4_noop_handler)
	patch(&a, "/a", wp4_noop_handler)
	delete(&a, "/d", wp4_noop_handler)

	// Each verb reaches its own path. The handler commits nothing, so a match
	// leaves the response UNCOMMITTED — the framework must not fabricate a 200.
	for pair in ([]struct {
		method: Method,
		path:   string,
	}{{.GET, "/g"}, {.POST, "/p"}, {.PUT, "/u"}, {.PATCH, "/a"}, {.DELETE, "/d"}}) {
		ctx: Context
		wp4_run(&a, &ctx, pair.method, pair.path)
		testing.expect(
			t,
			!ctx.private.response.committed,
			"a matched handler that did not respond must leave the response uncommitted",
		)
	}

	// The same path under a different method does NOT reach the handler; it is
	// a 405, which is the isolation proof.
	ctx: Context
	wp4_run(&a, &ctx, .POST, "/g")
	testing.expect_value(t, ctx.private.response.status, Status.Method_Not_Allowed)
}

// ---------------------------------------------------------------------------
// 3. A `:param` segment matches and is captured into the PRIVATE storage.
//
//    D1: there is no public `ctx.params` and no public accessor. The capture
//    lives in Context_Internal, and WP5 will make `web.path`/`web.path_int`
//    read it.
// ---------------------------------------------------------------------------

@(test)
wp4_param_segment_is_captured_privately :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users/:id", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/42")

	testing.expect(t, ctx.private.param.found, "the parameter must have been captured")
	testing.expect_value(t, ctx.private.param.name, "id")
	testing.expect_value(t, ctx.private.param.value, "42")
}

@(test)
wp4_param_value_is_a_view_over_the_request_path :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users/:id", wp4_noop_handler)

	// The captured value must be a VIEW over the request path, not a copy: it
	// is request-lifetime data and copying it would be a per-request allocation
	// the hot path does not need.
	path := make([]u8, len("/users/42"))
	defer delete_slice(path)
	copy(path, transmute([]u8)string("/users/42"))

	ctx: Context
	wp4_run(&a, &ctx, .GET, string(path))
	testing.expect_value(t, ctx.private.param.value, "42")

	slice.fill(path, '#')
	testing.expect(
		t,
		ctx.private.param.value != "42",
		"the captured parameter must be a view over the request path, not a copy",
	)
}

@(test)
wp4_static_route_captures_no_parameter :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/health", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/health")

	testing.expect(t, !ctx.private.param.found, "a static match captures nothing")
	testing.expect_value(t, ctx.private.param.name, "")
	testing.expect_value(t, ctx.private.param.value, "")
}

// ---------------------------------------------------------------------------
// 4. Static beats parametric — in BOTH registration orders.
//
//    Precedence is decided by pattern shape, never by insertion order. This is
//    the property that lets Phase 3 replace the table with a radix tree without
//    changing observable behavior.
// ---------------------------------------------------------------------------

@(test)
wp4_static_beats_param_when_static_registered_first :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users/me", wp4_static_handler)
	get(&a, "/users/:id", wp4_param_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/me")

	// Only one handler runs per dispatch, so the committed body names the
	// winner. Reading it from this test's own Context keeps the assertion free
	// of any state shared with the parallel sibling test below.
	testing.expect_value(t, string(ctx.private.response.body), "static")
}

@(test)
wp4_static_beats_param_when_param_registered_first :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// The reverse order. A table that simply returned its first match would
	// pass the previous test and fail this one.
	get(&a, "/users/:id", wp4_param_handler)
	get(&a, "/users/me", wp4_static_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/me")

	testing.expect_value(t, string(ctx.private.response.body), "static")

	// A path the static route does not cover still reaches the parametric one,
	// so the static-first scan does not simply hide parametric routes.
	ctx2: Context
	wp4_run(&a, &ctx2, .GET, "/users/42")
	testing.expect_value(t, string(ctx2.private.response.body), "param")
}

// ---------------------------------------------------------------------------
// 5. `web.app()` commits a consistent 404 on a path miss.
// ---------------------------------------------------------------------------

@(test)
wp4_app_commits_404_on_path_miss :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/health", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/nope")

	testing.expect(t, ctx.private.response.committed, "app() must commit a 404")
	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)

	// AMENDED IN WP6. WP4 committed an EMPTY body because the standardized
	// envelope was not yet owned by any shipped work package; WP6 supplies it as
	// a static constant. The routing DECISION under test — that a path miss is a
	// 404 — is unchanged.
	testing.expect_value(
		t,
		string(ctx.private.response.body),
		`{"error":{"code":"not_found","message":"Route not found"}}`,
	)
	testing.expect_value(t, len(ctx.private.response.headers), 1)
	testing.expect_value(t, ctx.private.response.headers[0].name, "Content-Type")
}

@(test)
wp4_app_with_no_routes_at_all_commits_404 :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/anything")

	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
}

// ---------------------------------------------------------------------------
// 6. A path known under another method is a 405, not a 404.
// ---------------------------------------------------------------------------

@(test)
wp4_app_commits_405_when_path_exists_under_another_method :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .DELETE, "/users")

	testing.expect_value(t, ctx.private.response.status, Status.Method_Not_Allowed)

	// AMENDED IN WP6: the 405 body is now the standardized envelope.
	testing.expect_value(
		t,
		string(ctx.private.response.body),
		`{"error":{"code":"method_not_allowed","message":"Method not allowed"}}`,
	)
}

@(test)
wp4_405_also_applies_to_a_parametric_path :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users/:id", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .POST, "/users/42")

	testing.expect_value(t, ctx.private.response.status, Status.Method_Not_Allowed)
	testing.expect_value(t, ctx.private.response.headers[0].value, "GET")
}

// ---------------------------------------------------------------------------
// 7. `Allow` is named exactly `Allow`, comes FIRST, and lists methods in the
//    canonical order GET, POST, PUT, PATCH, DELETE.
//
//    AMENDED IN WP6: a 405 now also carries `Content-Type`, so there are two
//    headers and `Allow` is the first of them (WP6 D3). The `Allow` value
//    itself is unchanged.
// ---------------------------------------------------------------------------

@(test)
wp4_allow_is_the_first_header_with_the_exact_name :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .PUT, "/users")

	testing.expect_value(t, ctx.private.response.status, Status.Method_Not_Allowed)
	testing.expect_value(t, len(ctx.private.response.headers), 2)

	// The name is exactly `Allow` — not `allow`, not `ALLOW` — and it is FIRST.
	testing.expect_value(t, ctx.private.response.headers[0].name, "Allow")
	testing.expect_value(t, ctx.private.response.headers[0].value, "GET")
	testing.expect_value(t, ctx.private.response.headers[1].name, "Content-Type")
}

@(test)
wp4_allow_uses_the_canonical_method_order :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// Registered in a deliberately scrambled order. The `Allow` value must
	// still come out in the canonical order, because the order is a property of
	// the framework and not of the application's registration sequence.
	delete(&a, "/r", wp4_noop_handler)
	post(&a, "/r", wp4_noop_handler)
	patch(&a, "/r", wp4_noop_handler)
	get(&a, "/r", wp4_noop_handler)
	put(&a, "/r", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .UNKNOWN, "/r")

	testing.expect_value(t, ctx.private.response.status, Status.Method_Not_Allowed)
	testing.expect_value(t, len(ctx.private.response.headers), 2)
	testing.expect_value(t, ctx.private.response.headers[0].name, "Allow")
	testing.expect_value(
		t,
		ctx.private.response.headers[0].value,
		"GET, POST, PUT, PATCH, DELETE",
	)
}

@(test)
wp4_allow_lists_only_registered_methods :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	post(&a, "/two", wp4_noop_handler)
	patch(&a, "/two", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/two")

	testing.expect_value(t, ctx.private.response.headers[0].value, "POST, PATCH")
}

// ---------------------------------------------------------------------------
// 8. Several registrations of the same method+path produce ONE `Allow` entry,
//    with no duplicates.
// ---------------------------------------------------------------------------

@(test)
wp4_allow_has_no_duplicates :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// Duplicate registrations are not rejected in WP4 — definitive conflict
	// diagnostics are Phase 3 (D5) — but they must not produce "GET, GET".
	get(&a, "/dup", wp4_noop_handler)
	get(&a, "/dup", wp4_noop_handler)
	post(&a, "/dup", wp4_noop_handler)
	post(&a, "/dup", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .PUT, "/dup")

	testing.expect_value(t, len(ctx.private.response.headers), 2)
	testing.expect_value(t, ctx.private.response.headers[0].value, "GET, POST")
}

@(test)
wp4_allow_does_not_duplicate_across_static_and_param_routes :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// Two GET routes both match "/users/me": the static one and the parametric
	// one. `Allow` must still name GET exactly once.
	get(&a, "/users/me", wp4_noop_handler)
	get(&a, "/users/:id", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .DELETE, "/users/me")

	testing.expect_value(t, ctx.private.response.headers[0].value, "GET")
}

// ---------------------------------------------------------------------------
// 9. `.UNKNOWN` follows the ordinary 404/405 rules. It NEVER becomes a 501.
//
//    A method outside the Phase-1 set is a valid HTTP request the framework
//    gives no public meaning to (RFC 9110 §9.1); inventing a 501 here would be
//    a response policy WP4 has no mandate to freeze.
// ---------------------------------------------------------------------------

@(test)
wp4_unknown_method_on_a_known_path_is_405 :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .UNKNOWN, "/users")

	testing.expect_value(t, ctx.private.response.status, Status.Method_Not_Allowed)
	testing.expect(
		t,
		ctx.private.response.status != Status.Internal_Server_Error,
		"an unknown method must never become a 501/500",
	)
}

@(test)
wp4_unknown_method_on_an_unknown_path_is_404 :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .UNKNOWN, "/absent")

	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
}

@(test)
wp4_unknown_method_is_never_registrable :: proc(t: ^testing.T) {
	// There is no public registration procedure for `.UNKNOWN`, so it can never
	// own a route and can never appear in an `Allow` value.
	a := app()
	defer destroy(&a)

	get(&a, "/x", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .UNKNOWN, "/x")
	testing.expect_value(t, ctx.private.response.headers[0].value, "GET")
}

// ---------------------------------------------------------------------------
// 10. `web.bare()` dispatches registered routes but installs NO automatic
//     404/405. A miss stays uncommitted.
//
//     This makes the already-documented app()/bare() distinction real, without
//     inventing middleware (D4).
// ---------------------------------------------------------------------------

@(test)
wp4_bare_dispatches_registered_routes :: proc(t: ^testing.T) {
	a := bare()
	defer destroy(&a)

	before := wp4_bare_hits
	get(&a, "/health", wp4_bare_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/health")

	testing.expect_value(t, wp4_bare_hits - before, 1)
	testing.expect_value(t, ctx.private.response.status, Status.OK)
}

@(test)
wp4_bare_injects_no_404 :: proc(t: ^testing.T) {
	a := bare()
	defer destroy(&a)

	get(&a, "/health", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/nope")

	testing.expect(
		t,
		!ctx.private.response.committed,
		"bare() must not install the automatic 404",
	)
	zero: Status
	testing.expect_value(t, ctx.private.response.status, zero)
}

@(test)
wp4_bare_injects_no_405 :: proc(t: ^testing.T) {
	a := bare()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .POST, "/users")

	testing.expect(
		t,
		!ctx.private.response.committed,
		"bare() must not install the automatic 405",
	)
	testing.expect_value(t, len(ctx.private.response.headers), 0)
}

// ---------------------------------------------------------------------------
// 11. An automatic response can never overwrite one that is already committed.
//
//     The single-commit guard (ADR-008) is what makes this true, and WP4 must
//     go through it rather than assigning the response fields directly.
// ---------------------------------------------------------------------------

@(test)
wp4_automatic_404_cannot_overwrite_a_committed_response :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// A response committed before dispatch — the shape a future middleware or
	// an extractor failure produces.
	ctx: Context
	testing.expect(
		t,
		response_commit(
			&ctx.private.response,
			.Bad_Request,
			nil,
			transmute([]u8)string("envelope"),
		),
	)

	// Dispatch finds no route and tries to commit its 404.
	wp4_run(&a, &ctx, .GET, "/nope")

	testing.expect_value(t, ctx.private.response.status, Status.Bad_Request)
	testing.expect_value(t, string(ctx.private.response.body), "envelope")
}

@(test)
wp4_automatic_405_cannot_overwrite_a_committed_response :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	ctx: Context
	testing.expect(
		t,
		response_commit(&ctx.private.response, .OK, nil, transmute([]u8)string("first")),
	)

	wp4_run(&a, &ctx, .POST, "/users")

	testing.expect_value(t, ctx.private.response.status, Status.OK)
	testing.expect_value(t, string(ctx.private.response.body), "first")
	testing.expect_value(t, len(ctx.private.response.headers), 0)
}

@(test)
wp4_a_handler_response_survives_dispatch :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/health", wp4_static_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/health")

	// The framework does not append a 404/405 after a handler responded.
	testing.expect_value(t, ctx.private.response.status, Status.OK)
	testing.expect_value(t, string(ctx.private.response.body), "static")
}

// ---------------------------------------------------------------------------
// 12. The registered pattern is APP-OWNED: it survives mutation of the
//     caller's buffer.
//
//     Silently retaining a caller-supplied view would make every route in the
//     table a dangling reference the moment the caller reused its storage.
// ---------------------------------------------------------------------------

@(test)
wp4_pattern_is_app_owned_and_survives_source_mutation :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	pattern := make([]u8, len("/users/:id"))
	defer delete_slice(pattern)
	copy(pattern, transmute([]u8)string("/users/:id"))

	get(&a, string(pattern), wp4_noop_handler)

	// The caller reuses its buffer. The App must hold its own copy.
	slice.fill(pattern, '#')

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/42")

	testing.expect(
		t,
		ctx.private.param.found,
		"the App must own its pattern copy; the route matched a mutated view",
	)
	testing.expect_value(t, ctx.private.param.name, "id")
	testing.expect_value(t, ctx.private.param.value, "42")
}

@(test)
wp4_static_pattern_is_app_owned_too :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	pattern := make([]u8, len("/health"))
	defer delete_slice(pattern)
	copy(pattern, transmute([]u8)string("/health"))

	get(&a, string(pattern), wp4_static_handler)
	slice.fill(pattern, '#')

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/health")

	// The route still matched, so the App kept its own copy of "/health"
	// instead of a view that now reads "#######".
	testing.expect_value(t, string(ctx.private.response.body), "static")
	testing.expect_value(t, ctx.private.response.status, Status.OK)
}

// ---------------------------------------------------------------------------
// 13. `destroy` releases the table exactly once: no leak, no double free.
// ---------------------------------------------------------------------------

@(test)
wp4_destroy_releases_the_table_exactly_once :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	context.allocator = mem.tracking_allocator(&track)

	a := app()
	get(&a, "/users/:id", wp4_noop_handler)
	post(&a, "/users", wp4_noop_handler)
	delete(&a, "/users/:id", wp4_noop_handler)

	testing.expect(
		t,
		len(track.allocation_map) > 0,
		"registration must have allocated the App-owned table and patterns",
	)

	destroy(&a)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)

	// A second destroy frees nothing and reports no bad free.
	destroy(&a)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
wp4_an_app_with_no_routes_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	context.allocator = mem.tracking_allocator(&track)

	// The table is LAZY, exactly like the WP3 test-support state: an App that
	// registers no route allocates no table.
	a := app()
	testing.expect_value(t, len(track.allocation_map), 0)

	destroy(&a)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
wp4_dispatch_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	context.allocator = mem.tracking_allocator(&track)

	a := app()
	defer destroy(&a)

	get(&a, "/users/:id", wp4_noop_handler)
	post(&a, "/users/:id", wp4_noop_handler)

	after_registration := len(track.allocation_map)

	// Matching, parameter capture, the 404 path, and the 405 + `Allow` path all
	// use request-local fixed storage. None of them may allocate.
	ctx1: Context
	wp4_run(&a, &ctx1, .GET, "/users/42")
	ctx2: Context
	wp4_run(&a, &ctx2, .GET, "/absent")
	ctx3: Context
	wp4_run(&a, &ctx3, .PUT, "/users/42")

	testing.expect_value(t, ctx3.private.response.headers[0].value, "GET, POST")
	testing.expect_value(t, len(track.allocation_map), after_registration)
}

// ---------------------------------------------------------------------------
// 14. Path semantics are exactly what WP4 proves — and nothing more (D5).
//
//     WP4 normalizes NOTHING. Pinning that here keeps a Phase-3 normalization
//     policy from being pre-decided by an accident of this interim matcher.
// ---------------------------------------------------------------------------

@(test)
wp4_root_path_is_matchable :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	before := wp4_root_hits
	get(&a, "/", wp4_root_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/")

	testing.expect_value(t, wp4_root_hits - before, 1)
	testing.expect_value(t, ctx.private.response.status, Status.OK)
}

@(test)
wp4_trailing_slash_is_not_normalized :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users", wp4_noop_handler)

	// `/users/` is a DIFFERENT path. WP4 makes no normalization promise, in
	// either direction; Phase 3 owns the policy.
	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/")

	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
}

@(test)
wp4_param_does_not_match_across_a_segment_boundary :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users/:id", wp4_noop_handler)

	// A `:param` occupies exactly ONE segment: it must not swallow "42/posts".
	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/42/posts")

	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
}

// WP4 deliberately does NOT pin whether a `:param` may capture an EMPTY segment
// (`/users/` against `/users/:id`). Whether an empty capture means "absent",
// "invalid", or a legitimate empty value interacts with WP5 extraction
// (`web.path`/`web.path_int`) and with the Phase-3 normalization policy, and
// neither is decided yet. An assertion here would freeze that answer as a
// side effect of this interim matcher, so there is none — the behavior exists,
// it is simply not a promise.

// ---------------------------------------------------------------------------
// 15. A pattern this interim dispatcher cannot interpret NEVER matches, and
//     never makes a path look "known under another method".
//
//     D5 allows at most one `:param` per pattern. The dangerous outcome is not
//     rejection but SILENT ACCEPTANCE: a two-param pattern that matches while
//     discarding a segment, or an unnamed `:` that captures under a name no
//     `web.path(ctx, name)` call could ever retrieve. Both are refused.
//
//     Registration still reports nothing — a public registration-error API is
//     Phase-3 scope (D5). "Never wins a match" is the whole contract.
// ---------------------------------------------------------------------------

@(test)
wp4_pattern_with_two_params_never_matches :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/a/:first/:second", wp4_static_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/a/x/y")

	// Not a handler call, and specifically not a match that quietly kept only
	// `first` and threw `y` away.
	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
	testing.expect(t, !ctx.private.param.found, "an uninterpretable pattern captures nothing")
}

@(test)
wp4_pattern_with_an_unnamed_param_never_matches :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/users/:", wp4_static_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/42")

	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
	testing.expect(t, !ctx.private.param.found)
}

@(test)
wp4_pattern_without_a_leading_slash_never_matches :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "users", wp4_static_handler)

	for path in ([]string{"/users", "users", "/"}) {
		ctx: Context
		wp4_run(&a, &ctx, .GET, path)
		testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
	}
}

@(test)
wp4_uninterpretable_pattern_does_not_contribute_to_allow :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// A pattern that can never match must not turn a 404 into a 405 that
	// advertises a method which could never have served the request.
	get(&a, "/a/:first/:second", wp4_noop_handler)

	ctx: Context
	wp4_run(&a, &ctx, .DELETE, "/a/x/y")

	testing.expect_value(t, ctx.private.response.status, Status.Not_Found)

	// AMENDED IN WP6: a 404 carries a Content-Type, but still no `Allow` — the
	// property under test is that an uninterpretable pattern contributes no
	// method, and that is unchanged.
	testing.expect_value(t, len(ctx.private.response.headers), 1)
	testing.expect_value(t, ctx.private.response.headers[0].name, "Content-Type")
}

@(test)
wp4_uninterpretable_patterns_do_not_disturb_valid_ones :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	// The invalid entries stay in the table; they are skipped, not removed, and
	// they must not shadow or displace the routes around them.
	get(&a, "/users/:a/:b", wp4_param_handler)
	get(&a, "/users/:id", wp4_param_handler)
	get(&a, "/users/me", wp4_static_handler)
	get(&a, "bad", wp4_param_handler)

	ctx: Context
	wp4_run(&a, &ctx, .GET, "/users/me")
	testing.expect_value(t, string(ctx.private.response.body), "static")

	ctx2: Context
	wp4_run(&a, &ctx2, .GET, "/users/42")
	testing.expect_value(t, string(ctx2.private.response.body), "param")
	testing.expect_value(t, ctx2.private.param.name, "id")
	testing.expect_value(t, ctx2.private.param.value, "42")

	// And the still-valid GET route is what `Allow` reports.
	ctx3: Context
	wp4_run(&a, &ctx3, .POST, "/users/42")
	testing.expect_value(t, ctx3.private.response.status, Status.Method_Not_Allowed)
	testing.expect_value(t, ctx3.private.response.headers[0].value, "GET")
}

@(test)
wp4_uninterpretable_patterns_are_still_owned_and_freed :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	context.allocator = mem.tracking_allocator(&track)

	// An invalid pattern is still cloned and still owned, so teardown must
	// release it exactly like any other.
	a := app()
	get(&a, "/a/:x/:y", wp4_noop_handler)
	post(&a, "no-slash", wp4_noop_handler)
	put(&a, "/ok/:id", wp4_noop_handler)

	testing.expect(t, len(track.allocation_map) > 0)

	destroy(&a)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

@(test)
wp4_segment_count_must_match_exactly :: proc(t: ^testing.T) {
	a := app()
	defer destroy(&a)

	get(&a, "/a/b", wp4_noop_handler)

	for path in ([]string{"/a", "/a/b/c", "/a/bb", "/aa/b", ""}) {
		ctx: Context
		wp4_run(&a, &ctx, .GET, path)
		testing.expect_value(t, ctx.private.response.status, Status.Not_Found)
	}
}
