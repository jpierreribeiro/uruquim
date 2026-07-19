// WP3 — PUBLIC TEST-SUPPORT FACADE (package `web`).
//
// This file adds the ONLY two public test-support symbols: `Recorded_Response`
// and `test_request`. They are a SEPARATE ledger (planning/15 G-11): public,
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
// WP3 ships no router: the private `dispatch` stub commits nothing, so the
// returned `Recorded_Response` carries the ZERO status and an EMPTY body. That
// is intentional — there is no fabricated 200 and no echoed path. WP4 fills in
// `dispatch` and this same procedure begins returning real routed responses.
//
// The App's test-support state is created LAZILY here, on the first call, using
// `context.allocator`. An application that never calls `test_request` allocates
// no recorder and runs no initializer. Every copy the recorder makes is released
// by `web.destroy(&app)`.
test_request :: proc(a: ^App, method: Method, path: string) -> Recorded_Response {
	transport := &a.private.test_transport

	// 1. The machinery constructs the neutral inbound request.
	req := testing.build_request(method_token(method), path)

	// 2. The facade converts the neutral request into a framework Context.
	ctx: Context
	ctx.request = Request {
		method = method_from_token(req.method),
		path   = req.path,
	}

	// 3. The core-private dispatch stub. WP3 has no routing, so it commits
	//    nothing and the response stays uncommitted.
	dispatch(&ctx)

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

	// 5. The facade returns the public shape.
	return Recorded_Response{status = Status(status_int), body = body}
}

// method_token converts a `Method` back to its on-the-wire token for the neutral
// request builder. It is the inverse of `method_from_token` for the Phase-1 set;
// `.UNKNOWN` maps to the empty token, which converts back to `.UNKNOWN`.
@(private)
method_token :: proc(method: Method) -> string {
	switch method {
	case .GET:
		return "GET"
	case .POST:
		return "POST"
	case .PUT:
		return "PUT"
	case .PATCH:
		return "PATCH"
	case .DELETE:
		return "DELETE"
	case .UNKNOWN:
		return ""
	}
	return ""
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
