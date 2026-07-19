// WP2 — INTERNAL RESPONSE MODEL AND SINGLE-COMMIT GUARD.
//
// Nothing in this file is public. There is no public `Response` type, no
// public commit state, and no `ctx.response` field: applications respond
// exclusively through `web.json`, `web.ok`, `web.created`, `web.text`,
// `web.no_content` and the error helpers (ADR-008).
//
// WP2 delivers the STORAGE and the GUARD only. It renders nothing: no JSON
// marshalling, no error envelope, no response headers, and no automatic status
// decision. Wiring the public responders onto this primitive is WP6; automatic
// 404/405/501 belongs to WP4/WP9.
package web

import "core:mem"

// Response is the package-internal response state for one request.
//
// It holds exactly what the commit guard needs to be provable: the status,
// headers and body that were committed, and the flag that says a commit
// already happened.
//
// `headers` is WP2 state rather than deferred work because WP4 depends on it.
// WP4's ratified contract includes "405-when-other-method with exact `Allow`
// header" (planning/phase-1-plan.md §WP4), and WP4 depends on WP2/WP3 — it lands BEFORE
// WP6. Without internal header storage, WP4 could not express or test its own
// contract.
//
// OWNERSHIP (amended in WP6, ADR-014). `headers` is always BORROWED: every
// header name and value is a static string, and the pair array lives in
// request-local storage on the Context. `body` is EITHER borrowed — a static
// constant such as the automatic 404 envelope, or the fixed request-local
// buffer the WP5 extractor errors use — OR owned, when a responder rendered it
// dynamically. `owned_body` says which, and `body_allocator` records who made
// the allocation so the teardown cannot disagree with the renderer about how to
// release it.
//
// WP7 may replace this with the request-lifetime arena (ADR-006) without any
// public change: neither this struct, nor the flag, nor the teardown is
// exported.
@(private)
Response :: struct {
	status:    Status,
	headers:   []Header_Pair,
	body:      []u8,
	committed: bool,

	// WP6 — true when `body` is an allocation this Response must release.
	owned_body:     bool,
	body_allocator: mem.Allocator,
}

// response_commit records a response exactly once and reports whether it did.
//
// It returns `true` when this call produced the response, and `false` when a
// response had already been produced — in which case NOTHING is modified: the
// first status, the first headers and the first body all survive verbatim.
// This is the whole of ADR-008 option A, and it is what makes "an extractor's
// error response cannot be replaced by continued handler code" a testable
// property rather than a convention.
//
// The three are recorded ATOMICALLY. A guard that blocked the status while
// letting replacement headers through would still be a double-write, so a
// rejected attempt leaves all three exactly as the first commit left them.
//
// SCOPE OF THE GUARANTEE (ADR-008). This
// prevents the SUPPORTED `web.*` response paths from overwriting a response
// that was already produced. It is NOT a security boundary: the application
// and the framework share one program, `@(private)` hides a declaration's name
// rather than the reachability of fields, and per-field privacy is a syntax
// error in Odin. Code that deliberately assigns to the fields of this struct
// bypasses the guard, and that is accepted. Designs that add indirection —
// opaque handles, side tables — to resist deliberate tampering are REJECTED as
// useless complexity.
//
// It allocates nothing, retains `headers` and `body` as views, and never
// panics.
@(private)
response_commit :: proc(res: ^Response, status: Status, headers: []Header_Pair, body: []u8) -> bool {
	if res.committed {
		return false
	}

	res.status = status
	res.headers = headers
	res.body = body
	res.committed = true
	return true
}

// response_commit_owned records a response whose body is an ALLOCATION, and
// takes ownership of it.
//
// It is the WP6 counterpart of `response_commit` (ADR-014, plan D2), and the
// two differ in exactly one respect: what happens to `body`.
//
// OWNERSHIP IS ALWAYS RESOLVED. On success the allocation belongs to the
// Response and is released by `response_destroy`. On rejection — a response was
// already committed — the allocation is FREED HERE, immediately, because the
// caller rendered it before discovering the guard would refuse it and nothing
// else can own it afterwards. Returning false while leaving the buffer to the
// caller would leak on a path a handler triggers simply by responding twice.
//
// A caller must therefore treat `body` as CONSUMED by this call in both
// outcomes, and must never read or free it afterwards.
//
// A rejected attempt leaves status, headers, body and ownership exactly as the
// first commit left them, exactly like `response_commit`.
@(private)
response_commit_owned :: proc(
	res: ^Response,
	status: Status,
	headers: []Header_Pair,
	body: []u8,
	allocator: mem.Allocator,
) -> bool {
	if res.committed {
		delete_slice(body, allocator)
		return false
	}

	res.status = status
	res.headers = headers
	res.body = body
	res.committed = true
	res.owned_body = true
	res.body_allocator = allocator
	return true
}

// response_destroy releases an owned body exactly once and returns the response
// to its zero state.
//
// WHO CALLS IT. The response DRIVER, after the response has been captured or
// written — never the handler and never `dispatch`. Today the only driver is
// `web.test_request`, which calls this after the recorder has made its own
// owned copies; the WP8 transport adapter must do the same once it exists.
// There is deliberately NO public cleanup symbol: response lifetime is
// framework business, and an application that had to remember to free a
// response would be a worse API than one that cannot see the response at all.
//
// It is IDEMPOTENT. Zeroing clears `owned_body`, so a second call frees
// nothing. `web.destroy` is specified as call-once, but a teardown that
// corrupts the heap when called twice is a worse failure than one that does
// nothing.
//
// It never frees a BORROWED body — a static constant or the fixed request-local
// envelope buffer — because `owned_body` is false for those.
@(private)
response_destroy :: proc(res: ^Response) {
	if res.owned_body {
		delete_slice(res.body, res.body_allocator)
	}
	res^ = Response{}
}
