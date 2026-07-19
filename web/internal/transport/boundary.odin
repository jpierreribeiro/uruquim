// WP8 — NEUTRAL TRANSPORT BOUNDARY.
//
// This package is the one-way boundary between the framework core and a real
// HTTP backend (ADR-009). It is IMPORTED BY `web` and imports the vendored
// backend; it NEVER imports `web`. It names no `web` type — `App`, `Context`,
// `Request`, `Response`, `Status`, `Handler` are all unknown here. Data crosses
// as the neutral records below, and the core is driven through a callback.
//
// Only the CONCEPTUAL contract is frozen (ADR-009): accept -> dispatch ->
// commit -> stop. The record shapes here are private and may change freely when
// a second adapter lands.
//
// WP8 RED: the types exist and `serve`/`request_stop` are stubs. The odin-http
// adapter and the real event loop arrive with the VENDOR and BOOTSTRAP commits.
package transport

import "core:mem"

// Header is a neutral name/value pair. Both are views over storage owned by the
// caller for the duration of one exchange.
Header :: struct {
	name:  string,
	value: string,
}

// Inbound is the neutral inbound request handed to the core's dispatch callback.
//
// `method` is the on-the-wire token ("GET", "POST", ...); the core maps it to
// its own method set. `over_limit` is set by the adapter when the request body
// exceeded the maximum it agreed to read, in which case `body` is empty and the
// core produces the 413 envelope WITHOUT running a handler (WP8 D3).
//
// Every field is a VIEW valid only for the duration of the dispatch call.
Inbound :: struct {
	method:     string,
	path:       string,
	query:      string,
	headers:    []Header,
	body:       []u8,
	over_limit: bool,
}

// Outbound is the neutral response the core's callback fills. The adapter copies
// it to the backend and sends it; the copies live in the `allocator` the core
// was given, which the adapter owns for the exchange.
//
// `status` is the raw HTTP status integer, including a value the core's public
// enum does not name (the private 413).
Outbound :: struct {
	status:  int,
	headers: []Header,
	body:    []u8,
}

// Dispatch_Proc is how the adapter drives the core. The core builds its context
// from `inbound`, runs dispatch, COPIES the response into `out` using
// `allocator`, and performs its own request teardown before returning. After it
// returns the adapter owns `out` and writes it to the wire.
Dispatch_Proc :: #type proc(user: rawptr, inbound: Inbound, out: ^Outbound, allocator: mem.Allocator)

// Config is what `web.serve` hands the adapter. `max_body` is the byte cap the
// adapter enforces while reading; `on_ready`, when set, is called once after the
// listen succeeds (used by tests to synchronize without a fixed sleep).
Config :: struct {
	port:     int,
	max_body: int,
	dispatch: Dispatch_Proc,
	user:     rawptr,
	on_ready: proc(user: rawptr),
}

// Serve_Error is the neutral outcome of a serve attempt.
Serve_Error :: enum {
	None,
	Invalid_Port,
	Listen_Failed,
}

// `serve`, `request_stop` and `copy_response` are implemented in
// `odin_http_adapter.odin`, the one file that names the backend.
