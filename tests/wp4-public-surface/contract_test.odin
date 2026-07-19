// WP4 public-surface contract, from OUTSIDE the package.
//
// This package is an EXTERNAL consumer of `uruquim:web`. It proves the part of
// the WP4 contract an application can actually observe, through the ratified
// public surface only:
//
//   - registration via `web.get/post/put/patch/delete` really routes;
//   - a matched handler runs exactly once;
//   - `web.test_request` now returns REAL routed results, still with no socket;
//   - `web.app()` produces a consistent 404 and a 405;
//   - `web.bare()` routes but installs neither.
//
// WP4 ADDS NO PUBLIC SYMBOL. Everything below is written with the same 34
// symbols that existed before it (32 application + 2 test-support), which is
// itself part of the contract: a routing work package that needed a new export
// would have failed its own gate.
//
// What is deliberately NOT here:
//
//   - the exact `Allow` header — `Recorded_Response` has no public `headers`
//     field and Phase 1 ratifies no header accessor (D4), so `Allow` is pinned
//     by the internal test in tests/wp4-internal/;
//   - a routed 200 with a JSON body — the public responders are inert stubs
//     until WP6. A handler here therefore commits NOTHING, which is exactly why
//     the "framework never fabricates a 200" assertions below are meaningful.
//
// These tests are written against OBSERVABLE BEHAVIOR, not against the table.
// Phase 3 replaces the linear table with a radix tree; every assertion in this
// file must still hold unchanged.
package wp4_public_surface

import "core:testing"
import web "uruquim:web"

// The standardized envelopes WP6 attached to the automatic responses. WP4
// committed empty bodies and said so; WP6 supplies the contract WP4 deferred.
// The routing DECISIONS these tests exist to pin — which status a request gets
// — are unchanged.
WP6_NOT_FOUND_ENVELOPE :: `{"error":{"code":"not_found","message":"Route not found"}}`
WP6_METHOD_NOT_ALLOWED_ENVELOPE ::
	`{"error":{"code":"method_not_allowed","message":"Method not allowed"}}`

// --- handlers: they record that they ran, and respond with nothing ---
//
// The public responders do not work yet (WP6), so a handler cannot commit a
// response from outside the package. A side-effect counter is therefore the
// honest way to observe that dispatch reached the handler.
//
// Each counter belongs to EXACTLY ONE test. The pinned runner executes tests in
// parallel, so a counter shared by two of them would make both their deltas
// race — and a routing test that is flaky under parallelism is worse than no
// routing test, because it teaches the next reader to re-run until green.

wp4_once_hits: int

wp4_once_handler :: proc(ctx: ^web.Context) {
	wp4_once_hits += 1
}

wp4_iso_get_hits: int
wp4_iso_post_hits: int

wp4_iso_get_handler :: proc(ctx: ^web.Context) {
	wp4_iso_get_hits += 1
}

wp4_iso_post_handler :: proc(ctx: ^web.Context) {
	wp4_iso_post_hits += 1
}

wp4_param_hits: int

wp4_param_handler :: proc(ctx: ^web.Context) {
	wp4_param_hits += 1
}

wp4_bare_hits: int

wp4_bare_handler :: proc(ctx: ^web.Context) {
	wp4_bare_hits += 1
}

wp4_owned_hits: int

wp4_owned_handler :: proc(ctx: ^web.Context) {
	wp4_owned_hits += 1
}

wp4_unsupported_hits: int

wp4_unsupported_handler :: proc(ctx: ^web.Context) {
	wp4_unsupported_hits += 1
}

wp4_silent_handler :: proc(ctx: ^web.Context) {
}

// ---------------------------------------------------------------------------
// 1. A registered static route is reached through `web.test_request`, in
//    memory, exactly once.
// ---------------------------------------------------------------------------

@(test)
wp4_registered_route_is_reached_exactly_once :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	before := wp4_once_hits
	web.get(&app, "/health", wp4_once_handler)

	res := web.test_request(&app, .GET, "/health")

	testing.expect_value(t, wp4_once_hits - before, 1)

	// The handler responded with nothing, so the response stays UNCOMMITTED:
	// zero status, empty body. The framework does not invent a 200 for a
	// handler that did not respond.
	zero: web.Status
	testing.expect_value(t, res.status, zero)
	testing.expect_value(t, res.body, "")
}

// ---------------------------------------------------------------------------
// 2. Methods are isolated through the public registration procedures.
// ---------------------------------------------------------------------------

@(test)
wp4_methods_are_isolated_publicly :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	before_get := wp4_iso_get_hits
	before_post := wp4_iso_post_hits

	web.get(&app, "/users", wp4_iso_get_handler)
	web.post(&app, "/users", wp4_iso_post_handler)

	web.test_request(&app, .GET, "/users")
	testing.expect_value(t, wp4_iso_get_hits - before_get, 1)
	testing.expect_value(t, wp4_iso_post_hits - before_post, 0)

	web.test_request(&app, .POST, "/users")
	testing.expect_value(t, wp4_iso_get_hits - before_get, 1)
	testing.expect_value(t, wp4_iso_post_hits - before_post, 1)
}

@(test)
wp4_every_verb_registers :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	// All five Phase-1 verbs exist and route. A verb whose registration was
	// discarded would produce a 405 here instead of an uncommitted response.
	web.get(&app, "/r", wp4_silent_handler)
	web.post(&app, "/r", wp4_silent_handler)
	web.put(&app, "/r", wp4_silent_handler)
	web.patch(&app, "/r", wp4_silent_handler)
	web.delete(&app, "/r", wp4_silent_handler)

	zero: web.Status
	for m in ([]web.Method{.GET, .POST, .PUT, .PATCH, .DELETE}) {
		res := web.test_request(&app, m, "/r")
		testing.expect_value(t, res.status, zero)
	}
}

// ---------------------------------------------------------------------------
// 3. A `:param` route matches. The captured value is NOT publicly readable in
//    Phase 1 — `web.path` is WP5 — so what is observable here is that the
//    route matched at all.
// ---------------------------------------------------------------------------

@(test)
wp4_param_route_matches :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	before := wp4_param_hits
	web.get(&app, "/users/:id", wp4_param_handler)

	web.test_request(&app, .GET, "/users/42")
	testing.expect_value(t, wp4_param_hits - before, 1)

	web.test_request(&app, .GET, "/users/anything-else")
	testing.expect_value(t, wp4_param_hits - before, 2)
}

// ---------------------------------------------------------------------------
// 4. `web.app()` produces a consistent 404 for an unknown path.
// ---------------------------------------------------------------------------

@(test)
wp4_app_returns_404_for_an_unknown_path :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/health", wp4_silent_handler)

	res := web.test_request(&app, .GET, "/nope")

	testing.expect_value(t, res.status, web.Status.Not_Found)

	// AMENDED IN WP6, which supplies the standardized envelope WP4 deliberately
	// left empty.
	testing.expect_value(t, res.body, WP6_NOT_FOUND_ENVELOPE)
}

@(test)
wp4_app_with_no_routes_returns_404 :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	res := web.test_request(&app, .GET, "/users/42")
	testing.expect_value(t, res.status, web.Status.Not_Found)
}

// ---------------------------------------------------------------------------
// 5. A path that exists under another method is a 405, not a 404.
// ---------------------------------------------------------------------------

@(test)
wp4_app_returns_405_for_a_known_path_under_another_method :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/users", wp4_silent_handler)

	res := web.test_request(&app, .DELETE, "/users")

	testing.expect_value(t, res.status, web.Status.Method_Not_Allowed)
	testing.expect_value(t, res.body, WP6_METHOD_NOT_ALLOWED_ENVELOPE)

	// The `Allow` header is real, but `Recorded_Response` deliberately exposes
	// no headers (D4). Its exact value is pinned by tests/wp4-internal/.
}

@(test)
wp4_unknown_method_follows_404_and_405_never_501 :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/users", wp4_silent_handler)

	// `.UNKNOWN` is a valid HTTP method the framework gives no public meaning
	// to. It follows the ordinary rules and never becomes a 501.
	known := web.test_request(&app, .UNKNOWN, "/users")
	testing.expect_value(t, known.status, web.Status.Method_Not_Allowed)

	absent := web.test_request(&app, .UNKNOWN, "/absent")
	testing.expect_value(t, absent.status, web.Status.Not_Found)
}

// ---------------------------------------------------------------------------
// 6. `web.bare()` routes, but installs neither default.
//
//    This is the first work package in which `app()` and `bare()` are
//    observably different — the distinction the documentation already claimed.
// ---------------------------------------------------------------------------

@(test)
wp4_bare_dispatches_but_installs_no_defaults :: proc(t: ^testing.T) {
	app := web.bare()
	defer web.destroy(&app)

	before := wp4_bare_hits
	web.get(&app, "/health", wp4_bare_handler)

	// Registered routes still dispatch.
	web.test_request(&app, .GET, "/health")
	testing.expect_value(t, wp4_bare_hits - before, 1)

	zero: web.Status

	// A miss stays UNCOMMITTED: no automatic 404 ...
	miss := web.test_request(&app, .GET, "/nope")
	testing.expect_value(t, miss.status, zero)

	// ... and no automatic 405.
	other := web.test_request(&app, .POST, "/health")
	testing.expect_value(t, other.status, zero)
}

// ---------------------------------------------------------------------------
// 7. The WP3 lifetime contract still holds with routing wired in: consecutive
//    recorded responses all stay readable until `web.destroy`.
// ---------------------------------------------------------------------------

@(test)
wp4_consecutive_recorded_responses_survive_until_destroy :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/users", wp4_silent_handler)

	first := web.test_request(&app, .GET, "/missing")
	second := web.test_request(&app, .POST, "/users")
	third := web.test_request(&app, .GET, "/users")

	// Each result still reads what it recorded, after two later exchanges.
	testing.expect_value(t, first.status, web.Status.Not_Found)
	testing.expect_value(t, second.status, web.Status.Method_Not_Allowed)

	zero: web.Status
	testing.expect_value(t, third.status, zero)

	testing.expect_value(t, first.body, WP6_NOT_FOUND_ENVELOPE)
	testing.expect_value(t, second.body, WP6_METHOD_NOT_ALLOWED_ENVELOPE)
}

// ---------------------------------------------------------------------------
// 8. Registration takes a pattern the caller may reuse: the App owns its copy.
// ---------------------------------------------------------------------------

@(test)
wp4_app_owns_its_pattern_copy :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	pattern := make([]u8, len("/users/:id"))
	defer delete(pattern)
	copy(pattern, transmute([]u8)string("/users/:id"))

	before := wp4_owned_hits
	web.get(&app, string(pattern), wp4_owned_handler)

	// The caller reuses its buffer immediately after registering. An App that
	// silently retained the caller's view would now hold a dangling pattern.
	for i in 0 ..< len(pattern) {
		pattern[i] = '#'
	}

	web.test_request(&app, .GET, "/users/42")
	testing.expect_value(t, wp4_owned_hits - before, 1)
}

// ---------------------------------------------------------------------------
// 8b. A pattern Phase 1 does not support never matches, from the outside too.
// ---------------------------------------------------------------------------

@(test)
wp4_unsupported_pattern_never_routes :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	before := wp4_unsupported_hits

	// At most ONE :param per pattern in Phase 1. A pattern with two is not
	// rejected at registration — Phase 1 freezes no registration-error API —
	// but it must never match, and never make the path look "known".
	web.get(&app, "/a/:first/:second", wp4_unsupported_handler)

	res := web.test_request(&app, .GET, "/a/x/y")
	testing.expect_value(t, res.status, web.Status.Not_Found)
	testing.expect_value(t, wp4_unsupported_hits - before, 0)

	// Not a 405 either: a route that can never match must not advertise a
	// method that could never have served the request.
	other := web.test_request(&app, .DELETE, "/a/x/y")
	testing.expect_value(t, other.status, web.Status.Not_Found)
}

// ---------------------------------------------------------------------------
// 9. No transport type appears anywhere in this file.
//
//    Everything above is expressed with `web.App`, `web.Context`, `web.Method`,
//    `web.Status` and `web.Recorded_Response`. There is no socket, no port, no
//    adapter, and no backend name — which is the cross-phase invariant WP4 must
//    not be the work package to break.
// ---------------------------------------------------------------------------

@(test)
wp4_routing_is_expressible_with_the_ratified_surface_only :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	handler: web.Handler = wp4_silent_handler
	web.get(&app, "/typed", handler)

	res: web.Recorded_Response = web.test_request(&app, .GET, "/typed")

	zero: web.Status
	testing.expect_value(t, res.status, zero)
}
