// WP9 — THE RAW-WIRE CORPUS.
//
// Backend-agnostic DATA: exact bytes to send, and what a safe HTTP/1 adapter is
// allowed to do with them. It imports no backend, so a future adapter (or the
// eventual `core:net/http`) can be held to the same corpus without touching it.
//
// It runs ONLY against real adapters. The in-memory transport has no TCP parser
// and cannot prove framing safety, so pointing this corpus at it would produce
// meaningless green.
//
// THE SAFETY SHAPE. For every ambiguous or malformed case the assertion is not
// "some particular status" but the three properties that actually prevent
// request smuggling and connection desynchronization:
//
//	handler_runs      — did application code see a partial/ambiguous request?
//	connection_closes — is the connection retired rather than reused?
//	smuggled_runs     — did trailing bytes become a SECOND request?
//
// A case is safe when a malformed request runs no handler, closes the
// connection, and never lets following bytes execute. The exact status is
// allowed to vary (400, 417, or a bare close), because a protocol error before
// a framework-owned request exists may legitimately be answered by the adapter
// or by closing (WP9 D6).
package transport_conformance

// Wire_Outcome is what the corpus permits for one case.
Wire_Outcome :: enum {
	// A complete, valid exchange: the handler runs and answers.
	Ok,
	// The request is rejected. A status response is allowed but not required;
	// an immediate close is equally acceptable (WP9 D6).
	Rejected,
}

// Wire_Case is one raw-wire scenario.
//
// `bytes` is sent verbatim. `allowed_status` lists the status codes a compliant
// adapter may answer with; an empty list means "any status, or none at all"
// (a bare close). `expect_second_request` is the smuggling probe: when a case
// appends bytes that LOOK like a follow-up request, this says whether that
// follow-up is permitted to execute.
Wire_Case :: struct {
	name:                  string,
	bytes:                 string,
	outcome:               Wire_Outcome,
	allowed_status:        []int,
	handler_must_run:      bool,
	connection_must_close: bool,
	// True only for the legitimate keep-alive case: a second request on the
	// same connection is expected to be served.
	expect_second_request: bool,
	// True when the case appends bytes that a vulnerable adapter might execute
	// as a smuggled request. It must NEVER run.
	has_smuggled_request:  bool,
	notes:                 string,
}

// The fixture routes the wire suite serves are `GET /ping` (200 "pong") and
// `POST /echo` (binds a JSON body, 201). `/smuggled` is registered so that a
// smuggled request WOULD be observable if the adapter executed it — which is
// exactly what must not happen.

// Package-level for the same reason as the semantic table: a slice of a local
// array literal would dangle once the accessor returned.
@(private)
corpus_storage := []Wire_Case{
		// --- 1-4: legitimate traffic ---------------------------------------
		{
			name = "valid GET",
			bytes = "GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
			outcome = .Ok,
			allowed_status = {200},
			handler_must_run = true,
			connection_must_close = true,
		},
		{
			name = "keep-alive serves two requests",
			bytes = "GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n" +
			"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
			outcome = .Ok,
			allowed_status = {200},
			handler_must_run = true,
			connection_must_close = true,
			expect_second_request = true,
		},
		{
			name = "Connection: close closes after the response",
			bytes = "GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
			outcome = .Ok,
			allowed_status = {200},
			handler_must_run = true,
			connection_must_close = true,
		},
		{
			name = "valid Content-Length body",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n" +
			"Content-Length: 16\r\nConnection: close\r\n\r\n" + `{"name":"grace"}`,
			outcome = .Ok,
			allowed_status = {201},
			handler_must_run = true,
			connection_must_close = true,
		},

		// --- 5-10: ambiguous or invalid Content-Length ----------------------
		{
			name = "CL+TE is rejected (smuggling vector)",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 6\r\n" +
			"Transfer-Encoding: chunked\r\n\r\n" + "0\r\n\r\n" +
			"GET /smuggled HTTP/1.1\r\nHost: localhost\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
			has_smuggled_request = true,
			notes = "RFC 9112 6.1: CL+TE must be treated as an unrecoverable error.",
		},
		{
			name = "duplicate identical Content-Length is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n" +
			"Content-Length: 2\r\nConnection: close\r\n\r\n" + "{}",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
			notes = "WP9 D2 is deliberately stricter than RFC-minimum: refuse, do not normalize.",
		},
		{
			name = "duplicate differing Content-Length is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n" +
			"Content-Length: 40\r\nConnection: close\r\n\r\n" + "{}",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},
		{
			name = "comma-list Content-Length is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2, 2\r\n" +
			"Connection: close\r\n\r\n" + "{}",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},
		{
			name = "negative Content-Length is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: -1\r\n" +
			"Connection: close\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},
		{
			name = "signed and overflowing Content-Length is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\n" +
			"Content-Length: +99999999999999999999\r\nConnection: close\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},

		// --- 11-17: chunked -------------------------------------------------
		{
			name = "valid chunked body",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n" +
			"Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n" +
			"10\r\n" + `{"name":"grace"}` + "\r\n0\r\n\r\n",
			outcome = .Ok,
			allowed_status = {201},
			handler_must_run = true,
			connection_must_close = true,
		},
		{
			name = "non-hex chunk size is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n" +
			"zz\r\n{}\r\n0\r\n\r\n",
			outcome = .Rejected,
			connection_must_close = true,
		},
		{
			name = "truncated chunk is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n" +
			"20\r\n{}\r\n",
			outcome = .Rejected,
			connection_must_close = true,
			notes = "declares 0x20 bytes then ends: the handler must not see a partial body.",
		},
		{
			name = "chunk without CRLF is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n" +
			"2\r\n{}0\r\n\r\n",
			outcome = .Rejected,
			connection_must_close = true,
		},
		{
			name = "missing zero terminator is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n" +
			"2\r\n{}\r\n",
			outcome = .Rejected,
			connection_must_close = true,
		},
		{
			name = "unsupported Transfer-Encoding is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: gzip\r\n" +
			"Connection: close\r\n\r\n" + "{}",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},
		{
			name = "chunked that is not the final coding is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\n" +
			"Transfer-Encoding: chunked, gzip\r\nConnection: close\r\n\r\n" + "0\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},

		// --- 18-21: truncation and malformed syntax -------------------------
		{
			name = "truncated fixed body is rejected",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 40\r\n\r\n" + "{}",
			outcome = .Rejected,
			connection_must_close = true,
			notes = "connection ends before the declared length: no handler, no second request.",
		},
		{
			name = "whitespace before the header colon is rejected",
			bytes = "GET /ping HTTP/1.1\r\nHost : localhost\r\nConnection: close\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {400},
			connection_must_close = true,
		},
		{
			name = "obs-fold header continuation is rejected",
			bytes = "GET /ping HTTP/1.1\r\nHost: localhost\r\nX-Fold: a\r\n b\r\n" +
			"Connection: close\r\n\r\n",
			outcome = .Rejected,
			connection_must_close = true,
		},
		{
			name = "invalid request line is rejected",
			bytes = "GET/ping HTTP/1.1\r\nHost: localhost\r\n\r\n",
			outcome = .Rejected,
			connection_must_close = true,
		},

		// --- 22-23: unread body and smuggling -------------------------------
		{
			name = "unread body does not desynchronize a following request",
			bytes = "POST /ping HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n" + "{}" +
			"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
			outcome = .Ok,
			handler_must_run = true,
			connection_must_close = true,
			expect_second_request = true,
			notes = "the handler never calls web.body; the adapter still consumed it, so the " +
			"next request parses cleanly rather than starting mid-body.",
		},
		{
			name = "over-limit body is 413 and its bytes are never a second request",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4194305\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {413},
			connection_must_close = true,
			has_smuggled_request = true,
			notes = "declares over 4 MiB; rejected during the read, handler never runs.",
		},

		// --- 24-25: Expect and unknown methods ------------------------------
		{
			name = "Expect: 100-continue is refused with 417",
			bytes = "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n" +
			"Expect: 100-continue\r\n\r\n",
			outcome = .Rejected,
			allowed_status = {417},
			connection_must_close = true,
			notes = "WP9 D5: Phase 1 implements no interim response; refuse and close, " +
			"never block waiting for a body.",
		},
		{
			name = "valid unknown method reaches the core, not a backend 501",
			bytes = "PROPFIND /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
			outcome = .Ok,
			allowed_status = {405},
			handler_must_run = false,
			connection_must_close = true,
			notes = "WP9 D7: the core's 404/405 policy decides, so 405 with Allow — never 501.",
		},
}

wire_corpus :: proc() -> []Wire_Case {
	return corpus_storage
}
