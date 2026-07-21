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
// The odin-http adapter implements `serve` and `request_stop` behind these
// types; see `odin_http_adapter.odin`.
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

// Config is what `web.serve` hands the adapter. `on_ready`, when set, is called
// once after the listen succeeds (used by tests to synchronize without a fixed
// sleep).
//
// THE THREE BYTE BUDGETS ARE RESOLVED NUMBERS, and that is the boundary's whole
// contribution to WP36: the core validates a `web.Limits` once, at boot, and
// hands the adapter integers. No `Limits` type crosses this line — the adapter
// would then have to know about a public `web` type, which is the back-edge
// ADR-009 forbids — and nothing on the read path re-derives a budget.
Config :: struct {
	port:             int,
	// The byte cap the adapter enforces while reading the body.
	max_body:         int,
	// The request-line and header-block caps the BACKEND enforces. They are
	// passed through rather than checked here: the adapter's job is to hand the
	// backend its own options, not to reimplement its parser's limits.
	max_request_line: int,
	max_headers:      int,
	// WP46 — the request read deadline in NANOSECONDS. The core may not import
	// `core:time` (FINDING-B), so the neutral boundary carries a plain integer
	// and the adapter converts, on the side of the line where a clock is
	// already linked. Zero disables it.
	max_request_time: i64,
	dispatch:         Dispatch_Proc,
	user:             rawptr,
	on_ready:         proc(user: rawptr),
}

// Serve_Error is the neutral outcome of a serve attempt.
Serve_Error :: enum {
	None,
	Invalid_Port,
	Listen_Failed,
}

// `serve`, `request_stop` and `copy_response` are implemented in
// `odin_http_adapter.odin`, the one file that names the backend.
