// WP3 — PUBLIC TEST-SUPPORT FACADE (package `web`).
//
// This file adds the ONLY two public test-support symbols: `Recorded_Response`
// and `test_request`. They are a SEPARATE ledger (planning/public-api-guardrails.md G-11): public,
// documented, and behavior-tested exactly like the application surface, but
// tracked apart from the frozen 32-symbol application count. Total exported
// after WP3: 34 = 32 application + 2 test-support.
//
// The facade is thin. It converts `App`/`Method` and the captured internal
// `Response` across the boundary to the neutral machinery in `web/testing`,
// which owns the request/response representation and the response copies. The
// machinery never names a `web` type, so `web -> web/testing` stays one-way (the
// back-edge is a compile cycle, ratified as probe C5).
package web

import testing "uruquim:web/testing"

// Recorded_Response is the read-only result of `web.test_request`.
//
// It exposes exactly two fields in Phase 1:
//
//   - `status`: the response status, COPIED BY VALUE;
//   - `body`:   a string VIEW over a copy owned by the App's test-support state,
//               valid until `web.destroy(&app)`.
//
// There is deliberately NO public `headers`, `committed`, allocator or transport
// field. The recorder copies response headers internally for the future WP4
// tests (405 + `Allow`), but Phase 1 ratifies no public abstraction for reading
// response headers, and adding a field here would freeze one prematurely.
//
// LIFETIME: `body` remains readable, alongside every other response returned by
// the same App, until `web.destroy(&app)` frees the App's test-support state.
// There is no per-response cleanup. Do not retain a `Recorded_Response.body`
// past `destroy`.
Recorded_Response :: struct {
	status: Status,
	body:   string,
}

// test_request drives one in-memory request through dispatch and returns the
// recorded response, WITHOUT binding a socket or port.
//
// WP4 wired routing, so this now returns REAL routed results: a registered
// route's handler runs, an unknown path on `web.app()` produces a 404, and a
// path registered under another method produces a 405. Only `web.destroy` and
// the recorder stand between the caller and the framework's own dispatch.
//
// A handler that responds with nothing still yields the ZERO status and an
// EMPTY body — the framework does not fabricate a 200 on a handler's behalf.
// The public responders that would fill in a body are WP6.
//
// The App's test-support state is created LAZILY here, on the first call, using
// `context.allocator`. An application that never calls `test_request` allocates
// no recorder, runs no initializer, and does not even LINK the recorder
// teardown — this procedure registers it, so eliminating this procedure
// eliminates it too (planning/public-api-guardrails.md G-11). Every copy the
// recorder makes is released by `web.destroy(&app)`.
test_request :: proc(a: ^App, method: Method, path: string) -> Recorded_Response {
	transport := &a.private.test_transport

	// Register the teardown on first use. This assignment is the ONLY reference
	// to `testing.destroy` in the whole package, which is precisely the point:
	// an application that never calls `test_request` never mentions the
	// machinery teardown, so the linker drops it along with this procedure
	// (planning/public-api-guardrails.md G-11). `web.destroy` calls through the
	// pointer and does nothing when it is nil.
	a.private.test_teardown = testing.destroy

	// 1. The machinery constructs the neutral inbound request.
	req := testing.build_request(method_token(method), path)

	// 2. The facade converts the neutral request into a framework Context.
	ctx: Context
	ctx.request = Request {
		method = method_from_token(req.method),
		path   = req.path,
	}

	// 3. The core-private dispatcher. It takes the App explicitly, because the
	//    route table is owned by the App and the Context holds no back-pointer
	//    to it.
	dispatch(a, &ctx)

	// 4. The facade hands the internal Response to the recorder as neutral
	//    values. The header conversion is transient (temp allocator); the
	//    recorder makes its own owned copies with context.allocator.
	res := &ctx.private.response
	neutral_headers := response_headers_neutral(res.headers)

	status_int, body := testing.capture(
		transport,
		context.allocator,
		int(res.status),
		res.body,
		neutral_headers,
	)

	// 5. WP6 — this facade is the response DRIVER, so it releases the rendered
	//    body once the recorder has copied it (ADR-014). The ORDER matters: the
	//    recorder makes owned copies of status, body and headers above, and only
	//    after that does the response's own allocation become releasable. Tearing
	//    down first would hand the recorder a freed buffer to copy.
	//
	//    A borrowed body — a static envelope constant, or the fixed request-local
	//    buffer the WP5 extractor errors use — is left alone; `response_destroy`
	//    frees only what the Response actually owns.
	response_destroy(res)

	// 6. The facade returns the public shape. `body` is the recorder's own copy,
	//    valid until `web.destroy(&app)`, so it is unaffected by the teardown
	//    above.
	return Recorded_Response{status = Status(status_int), body = body}
}

// response_headers_neutral converts the framework's private header pairs into
// neutral `testing.Header` values for the recorder. The result is transient
// (temp allocator) and is consumed synchronously by the recorder, which makes
// its own owned copies — this slice never backs a returned `Recorded_Response`.
@(private)
response_headers_neutral :: proc(pairs: []Header_Pair) -> []testing.Header {
	out := make([]testing.Header, len(pairs), context.temp_allocator)
	for pair, i in pairs {
		out[i] = testing.Header{name = pair.name, value = pair.value}
	}
	return out
}
