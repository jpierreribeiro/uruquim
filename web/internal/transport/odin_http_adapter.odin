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
import "core:time"
import "core:slice"
import "core:strings"

// WP43 — PER-SERVER STATE. The config no longer lives in a package global.
//
// WHY THIS MATTERS AND IS NOT TIDYING. `web.serve` used to write its `Config`
// into `g_config`, which the backend's handler read on every request. That is
// fine for exactly one server per process and becomes a silent cross-wire the
// moment there are two: the second `serve` overwrites the first's dispatch
// pointer, and requests to server A run server B's application. Nothing
// diagnoses it, because nothing is wrong from either server's point of view.
//
// The backend's `Handler` already carries a `user_data: rawptr`, so the config
// travels WITH the handler rather than beside it. No vendored change was needed
// — the capability was there and unused.
//
// WHAT IS STILL A GLOBAL, and it is stated rather than hidden: `g_server`, read
// by `request_stop`. That one is a genuinely process-wide question today
// ("stop the running server") and it is WP44 that gives it a proper answer, by
// making a server a thing a caller HOLDS. Removing it here would mean inventing
// half of WP44's public surface in an internal package — and ADR-030's
// single-threaded decision means one loop, so the residual risk is a second
// `serve` in one process, which is already unsupported and already documented.
@(private)
g_server: ^http.Server

// Server_Runtime is the per-server state the handler needs. It lives in
// `serve`'s frame and is reached through the backend handler's `user_data`, so
// its lifetime is exactly the server's — no allocation, no teardown, and no way
// for a second server to overwrite the first's.
@(private)
Server_Runtime :: struct {
	config: Config,
}

// Exchange is the per-request state threaded through the async body read. It
// lives in the connection's temp allocator, which the backend owns for the
// duration of the request.
//
// WP43: it now also carries the runtime, because `on_body` is a plain callback
// with no other way to reach it.
@(private)
Exchange :: struct {
	req:     ^http.Request,
	res:     ^http.Response,
	runtime: ^Server_Runtime,
}

// serve runs the backend event loop and blocks until the server is stopped.
serve :: proc(cfg: Config) -> Serve_Error {
	// The runtime lives here, in this frame, for exactly as long as the server
	// does. Two concurrent `serve` calls would have two runtimes rather than
	// one shared slot — which is the whole point of WP43.
	runtime := Server_Runtime {
		config = cfg,
	}

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
	// WP46 / ADR-031: the request read deadline. The conversion to
	// `time.Duration` happens HERE because this is the side of the boundary
	// where a clock is already linked — `package web` may not import one.
	opts.request_read_timeout = time.Duration(cfg.max_request_time)
	opts.max_connections = cfg.max_connections
	opts.reserved_connections = cfg.reserved_conns
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

	// The runtime travels WITH the handler through the backend's own
	// `user_data`, rather than beside it in a package global.
	handler := runtime_handler(&runtime)
	http.serve(&s, handler)

	g_server = nil
	return .None
}

// _refused_connections reads the running server's admission-refusal total.
//
// Through `g_server` — the one named global exception (WP43) — because the
// count belongs to the SERVER rather than to any request, and there is no
// request in hand when an operator asks for it.
@(private)
_refused_connections :: proc() -> int {
	server := g_server
	if server == nil {
		return 0
	}
	return server.refused_total
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
// runtime_handler builds the backend handler with the runtime attached.
//
// `http.handler` stores a PROCEDURE in `user_data`; this stores the runtime
// instead and calls `catch_all` explicitly, which is the same shape the vendored
// helper uses and the reason no vendored change was needed.
@(private)
runtime_handler :: proc(runtime: ^Server_Runtime) -> http.Handler {
	h: http.Handler
	h.user_data = rawptr(runtime)
	h.handle = proc(h: ^http.Handler, req: ^http.Request, res: ^http.Response) {
		catch_all((^Server_Runtime)(h.user_data), req, res)
	}
	return h
}

@(private)
catch_all :: proc(runtime: ^Server_Runtime, req: ^http.Request, res: ^http.Response) {
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
	exchange.runtime = runtime

	// The backend enforces the cap as it reads: an over-length body never gets
	// buffered, and `on_body` is told with `.Too_Long`.
	http.body(req, runtime.config.max_body, exchange, on_body)
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
		// WP48: the peer, from the accepted connection rather than from any
		// header. Rendered into the request's own temp allocator, so it lives
		// exactly as long as every other request-scoped view.
		peer       = net.address_to_string(req.client.address, context.temp_allocator),
		over_limit = err == .Too_Long,
	}
	if !inbound.over_limit {
		inbound.body = transmute([]u8)string(body)
	}

	// The core builds its context, dispatches, copies the response into the
	// connection allocator, and tears down its request-local state — all before
	// returning (WP8 D2/D4).
	out: Outbound
	cfg := exchange.runtime.config
	cfg.dispatch(cfg.user, inbound, &out, context.temp_allocator)

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
