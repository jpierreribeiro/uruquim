// WP2 — INTERNAL RESPONSE MODEL AND SINGLE-COMMIT GUARD.
//
// Nothing in this file is public. There is no public `Response` type, no
// public commit state, and no `ctx.response` field: applications respond
// exclusively through `web.json`, `web.ok`, `web.created`, `web.text`,
// `web.no_content` and the error helpers (ADR-008, planning/18 P-1).
//
// WP2 delivers the STORAGE and the GUARD only. It renders nothing: no JSON
// marshalling, no error envelope, no response headers, and no automatic status
// decision. Wiring the public responders onto this primitive is WP6; automatic
// 404/405/501 belongs to WP4/WP9.
package web

// Response is the package-internal response state for one request.
//
// It holds exactly what the commit guard needs to be provable: the status,
// headers and body that were committed, and the flag that says a commit
// already happened.
//
// `headers` is WP2 state rather than deferred work because WP4 depends on it.
// WP4's ratified contract includes "405-when-other-method with exact `Allow`
// header" (planning/05 §WP4), and WP4 depends on WP2/WP3 — it lands BEFORE
// WP6. Without internal header storage, WP4 could not express or test its own
// contract.
//
// Neither `headers` nor `body` is OWNED by Response at this stage: both are
// views over storage owned by whoever called the commit primitive. WP6 defines
// the concrete allocation and lifetime of a rendered response, and may reshape
// this struct freely — nothing here is public API.
@(private)
Response :: struct {
	status:    Status,
	headers:   []Header_Pair,
	body:      []u8,
	committed: bool,
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
// SCOPE OF THE GUARANTEE (ADR-008, as amended by planning/18 P-3). This
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
