// WP8 — ODIN-HTTP BOOTSTRAP ADAPTER.
//
// This is the ONLY file that imports the vendored backend. It converts a
// backend request into a neutral `Inbound`, enforces the body cap WHILE
// READING, drives the core through the `Dispatch_Proc` callback, and writes the
// neutral `Outbound` back to the wire. It names no `web` type.
//
// EXECUTION (WP8 D6): a single catch-all handler feeds the Uruquim dispatcher —
// the backend router is NOT used — with `thread_count = 1` and
// `redirect_head_to_get = false`, so HEAD stays HEAD (the core maps it to an
// unknown method) and the backend never rewrites a method. Concurrency,
// timeouts and graceful-shutdown deadlines are later phases.
package transport

import http "uruquim:vendor/odin-http"
import "core:mem"
import "core:net"
import "core:slice"
import "core:strings"

// The running server and the active config. thread_count is 1 and only one
// server runs at a time in the Phase-1 bootstrap, so package-level state is
// enough; `request_stop` reads `g_server` to signal a shutdown from another
// thread (the backend's shutdown is built for exactly that).
@(private)
g_server: ^http.Server

@(private)
g_config: Config

// Exchange is the per-request state threaded through the async body read. It
// lives in the connection's temp allocator, which the backend owns for the
// duration of the request.
@(private)
Exchange :: struct {
	req: ^http.Request,
	res: ^http.Response,
}

// serve runs the backend event loop and blocks until the server is stopped.
serve :: proc(cfg: Config) -> Serve_Error {
	g_config = cfg

	s: http.Server
	g_server = &s

	opts := http.Default_Server_Opts
	opts.thread_count = 1
	opts.redirect_head_to_get = false
	// WP36: the caller's resolved text budgets replace the backend's own
	// defaults. `Default_Server_Opts` is a mutable package VARIABLE in the
	// vendored server — assigning to it would change the defaults for anything
	// else in the process — so the copy above is taken first and only the copy
	// is written to.
	opts.limit_request_line = cfg.max_request_line
	opts.limit_headers = cfg.max_headers
	// WP9 D5: Phase 1 implements no interim-response flow. Leaving the backend's
	// automatic continue on made it answer "100 Continue" and then WAIT for a
	// body the client may never send. `Expect` is refused with 417 in
	// `catch_all` instead, and the connection closes.
	opts.auto_expect_continue = false

	endpoint := net.Endpoint {
		address = net.IP4_Address{0, 0, 0, 0},
		port    = cfg.port,
	}

	if err := http.listen(&s, endpoint, opts); err != nil {
		g_server = nil
		return .Listen_Failed
	}

	// The listen succeeded: signal readiness (tests synchronize on this instead
	// of a fixed sleep) and start the blocking loop.
	if cfg.on_ready != nil {
		cfg.on_ready(cfg.user)
	}

	handler := http.handler(catch_all)
	http.serve(&s, handler)

	g_server = nil
	return .None
}

// request_stop asks the running server to stop. Idempotent and thread-safe: the
// backend's shutdown is an atomic flag plus an event-loop wake-up, and calling
// it when no server is running is a no-op.
request_stop :: proc() {
	server := g_server
	if server != nil {
		http.server_shutdown(server)
	}
}

// catch_all is the single backend handler. It starts the capped, buffered body
// read; everything else happens in `on_body` once the body is available.
@(private)
catch_all :: proc(req: ^http.Request, res: ^http.Response) {
	// WP9 D5 — `Expect: 100-continue` is refused before anything is read. This
	// is a PROTOCOL error handled by the adapter rather than by the core (D6):
	// there is no framework-owned request yet, so there is no envelope to write.
	// The handler never runs and the server never waits for a body.
	if expect, ok := http.headers_get_unsafe(req.headers, "expect"); ok && len(expect) > 0 {
		http.headers_set_close(&res.headers)
		res.status = http.Status.Expectation_Failed
		http.respond(res)
		return
	}

	exchange := new(Exchange, context.temp_allocator)
	exchange.req = req
	exchange.res = res

	// The backend enforces the cap as it reads: an over-length body never gets
	// buffered, and `on_body` is told with `.Too_Long`.
	http.body(req, g_config.max_body, exchange, on_body)
}

// on_body runs once the body has been read (or rejected for length). It builds
// the neutral request, drives the core, and writes the response.
@(private)
on_body :: proc(user_data: rawptr, body: http.Body, err: http.Body_Error) {
	exchange := (^Exchange)(user_data)
	req := exchange.req
	res := exchange.res

	rline := req.line.(http.Requestline)

	inbound := Inbound {
		// WP9 D7 — the ORIGINAL token. A valid but non-Phase-1 method
		// (PROPFIND) reaches the core, which maps it to its own `.UNKNOWN` and
		// applies the ratified 404/405 policy. The backend no longer answers
		// 501 on its own.
		method     = rline.method_raw,
		path       = req.url.path,
		query      = req.url.query,
		headers    = neutral_headers(req, context.temp_allocator),
		over_limit = err == .Too_Long,
	}
	if !inbound.over_limit {
		inbound.body = transmute([]u8)string(body)
	}

	// The core builds its context, dispatches, copies the response into the
	// connection allocator, and tears down its request-local state — all before
	// returning (WP8 D2/D4).
	out: Outbound
	g_config.dispatch(g_config.user, inbound, &out, context.temp_allocator)

	write_response(res, out)
	http.respond(res)
}

// neutral_headers copies the backend request headers into neutral pairs. The
// copies live in `allocator` (the connection arena), valid for the exchange.
@(private)
neutral_headers :: proc(req: ^http.Request, allocator: mem.Allocator) -> []Header {
	count := len(req.headers._kv)
	if count == 0 {
		return nil
	}
	out := make([]Header, count, allocator)
	i := 0
	for k, v in req.headers._kv {
		out[i] = Header{name = k, value = v}
		i += 1
	}
	return out
}

// write_response writes the neutral `Outbound` to the backend response. Status
// crosses as its integer, including the private 413. Headers are set before the
// body, because writing the body flushes the status line and headers.
@(private)
write_response :: proc(res: ^http.Response, out: Outbound) {
	res.status = http.Status(out.status)
	for header in out.headers {
		http.headers_set(&res.headers, header.name, header.value)
	}
	http.body_set_bytes(res, out.body)
}

// The core copies its committed response into these before its own teardown, so
// the adapter owns the bytes it sends. Kept next to the adapter because it is
// the adapter's ownership contract, exercised by the boundary tests.
copy_response :: proc(out: ^Outbound, status: int, headers: []Header, body: []u8, allocator: mem.Allocator) {
	out.status = status

	if len(headers) > 0 {
		copied := make([]Header, len(headers), allocator)
		for header, i in headers {
			copied[i] = Header {
				name  = strings.clone(header.name, allocator),
				value = strings.clone(header.value, allocator),
			}
		}
		out.headers = copied
	} else {
		out.headers = nil
	}

	if len(body) > 0 {
		out.body = slice.clone(body, allocator)
	} else {
		out.body = nil
	}
}
