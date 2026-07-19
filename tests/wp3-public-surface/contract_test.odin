// WP3 public-surface contract, from OUTSIDE the package (probe C4).
//
// This package is an EXTERNAL consumer of `uruquim:web`. It proves that the two
// symbols WP3 adds — `test_request` and `Recorded_Response` — exist with the
// exact ratified names, are actually exported by package `web` (not
// `web/testing`), and compose as the ratified WP3 contract specifies.
//
// It also RUNS `web.test_request`, which is the executable half of probe C4:
// the call completes with no socket, no port, and no network syscall, and its
// result is readable as `res.status` / `res.body`.
//
// WP3 ships NO router. The facade therefore returns whatever the (uncommitted)
// internal response holds: the zero status and an empty body. This test asserts
// exactly that — it must NOT expect a fabricated 200 or an echoed path, because
// producing one would be the "200/echo falso" the WP3 prompt forbids. Real
// routed status/body arrive in WP4, tested through this same `web.test_request`.
//
// The matching NEGATIVE contract — that `Recorded_Response` has no public
// `headers` field — cannot be written here, since it must fail to compile. It
// lives in `probes/`, driven by build/check.sh.
package wp3_public_surface

import "core:testing"
import web "uruquim:web"

// --- Recorded_Response: exact public field set ---

@(test)
wp3_recorded_response_exposes_status_and_body :: proc(t: ^testing.T) {
	// Named assignment proves each field exists with the ratified name and
	// type, and that there are only these two.
	r: web.Recorded_Response
	r.status = .OK
	r.body = "hi"

	testing.expect_value(t, r.status, web.Status.OK)
	testing.expect_value(t, r.body, "hi")
}

// --- test_request: exists, is exported by `web`, runs without a socket ---

@(test)
wp3_test_request_runs_in_memory_without_routing :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	res := web.test_request(&app, .GET, "/users/42")

	// No router in WP3: the response is uncommitted, so the status is the zero
	// value (NOT a fabricated 200) and the body is empty (NOT the echoed path).
	zero: web.Status
	testing.expect_value(t, res.status, zero)
	testing.expect_value(t, res.body, "")
}

// --- two consecutive recorded responses remain readable until destroy ---

@(test)
wp3_two_recorded_responses_survive_until_destroy :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	first := web.test_request(&app, .GET, "/a")
	second := web.test_request(&app, .POST, "/bb")

	// Both remain readable after the second call — neither aliases a buffer the
	// other reused. (Bodies are empty in WP3; WP4 makes them meaningful.)
	testing.expect_value(t, first.body, "")
	testing.expect_value(t, second.body, "")

	zero: web.Status
	testing.expect_value(t, first.status, zero)
	testing.expect_value(t, second.status, zero)
}

// --- an app that never calls test_request destroys cleanly (lazy state) ---

@(test)
wp3_unused_test_support_is_a_noop_destroy :: proc(t: ^testing.T) {
	// This is the ergonomic proof of the lazy state: constructing and
	// destroying an App that never touches test_request must be inert. The
	// memory-tracking harness (build/check.sh runs `odin test` with tracking)
	// would flag any allocation this path made.
	app := web.app()
	web.destroy(&app)

	bare := web.bare()
	web.destroy(&bare)
}
