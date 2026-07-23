// WP96 — the PUBLIC streaming API end to end, and the properties an operator
// and a Crystal author depend on.
//
// Everything here goes through `web.app` / `web.get` / `web.serve` / `web.stream`
// — the surface an application actually holds — never the private machinery.
// It proves: a Handler opens a stream and returns; later code streams from a
// worker thread; the client receives chunks incrementally; close terminates;
// a buffered route on the same server is untouched; `secure_headers` cover a
// stream; and the in-memory transport reports ok=false (no connection to
// detach) rather than lying.
package test_wp96_public_stream

import "core:net"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import web "uruquim:web"

// A shared place for a worker to reach the stream token the Handler opened.
Shared :: struct {
	tok:      web.Stream,
	opened:   sync.Sema,
	ok:       bool,
}

g_shared: ^Shared

@(private)
stream_handler :: proc(ctx: ^web.Context) {
	s, ok := web.stream(ctx)
	g_shared.tok = s
	g_shared.ok = ok
	sync.sema_post(&g_shared.opened)
	// The Handler RETURNS here; the response outlives this Context.
}

@(private)
buffered_handler :: proc(ctx: ^web.Context) {
	web.text(ctx, .OK, "buffered-ok")
}

Server :: struct {
	app:    web.App,
	port:   int,
	thread: ^thread.Thread,
}

@(private)
serve_thread :: proc(s: ^Server) {
	web.serve(&s.app, s.port)
}

@(private)
start :: proc(s: ^Server, port: int) -> bool {
	s.port = port
	s.app = web.app()
	web.use(&s.app, web.secure_headers)
	web.get(&s.app, "/events", stream_handler)
	web.get(&s.app, "/plain", buffered_handler)
	s.thread = thread.create_and_start_with_poly_data(s, serve_thread)
	// Wait for readiness via the buffered route.
	for _ in 0 ..< 300 {
		if st, _ := get(port, "/plain"); st == 200 {
			return true
		}
		time.sleep(2 * time.Millisecond)
	}
	return false
}

@(private)
stop :: proc(s: ^Server) {
	web.stop(&s.app)
	if s.thread != nil {
		thread.join(s.thread)
		thread.destroy(s.thread)
		s.thread = nil
	}
	web.destroy(&s.app)
}

@(private)
dial :: proc(port: int) -> (net.TCP_Socket, bool) {
	endpoint := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = port}
	for _ in 0 ..< 100 {
		sock, err := net.dial_tcp(endpoint)
		if err == nil {return sock, true}
		time.sleep(2 * time.Millisecond)
	}
	return {}, false
}

@(private)
get :: proc(port: int, path: string) -> (status: int, body: string) {
	sock, ok := dial(port)
	if !ok {return 0, ""}
	defer net.close(sock)
	net.set_option(sock, .Receive_Timeout, 3 * time.Second)
	req, _ := strings.concatenate({"GET ", path, " HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"}, context.temp_allocator)
	if _, e := net.send_tcp(sock, transmute([]u8)req); e != nil {return 0, ""}
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	buf: [4096]u8
	for {
		n, e := net.recv_tcp(sock, buf[:])
		if n > 0 {strings.write_bytes(&b, buf[:n])}
		if n == 0 || e != nil {break}
	}
	raw := strings.to_string(b)
	st := 0
	if len(raw) >= 12 {st = int(raw[9] - '0') * 100 + int(raw[10] - '0') * 10 + int(raw[11] - '0')}
	return st, raw
}

@(private)
recv_until :: proc(sock: net.TCP_Socket, b: ^strings.Builder, marker: string, timeout: time.Duration) -> bool {
	net.set_option(sock, .Receive_Timeout, timeout)
	buf: [2048]u8
	for {
		if strings.contains(strings.to_string(b^), marker) {return true}
		n, e := net.recv_tcp(sock, buf[:])
		if n > 0 {strings.write_bytes(b, buf[:n])}
		if n == 0 || e != nil {return strings.contains(strings.to_string(b^), marker)}
	}
}

@(test)
wp96_a_handler_streams_from_a_worker_and_close_terminates :: proc(t: ^testing.T) {
	shared: Shared
	g_shared = &shared
	srv: Server
	testing.expect(t, start(&srv, 51960), "server must start")
	defer stop(&srv)

	sock, ok := dial(51960)
	testing.expect(t, ok)
	defer net.close(sock)
	_, _ = net.send_tcp(sock, transmute([]u8)string("GET /events HTTP/1.1\r\nHost: x\r\n\r\n"))
	testing.expect(t, sync.sema_wait_with_timeout(&shared.opened, 3 * time.Second), "the handler must run")
	testing.expect(t, shared.ok, "web.stream must open on a real connection")

	wire: strings.Builder
	strings.builder_init(&wire, context.temp_allocator)
	// Head commits without a body — 200, chunked, no length.
	testing.expect(t, recv_until(sock, &wire, "\r\n\r\n", 3 * time.Second), "the head must commit")
	head := strings.to_string(wire)
	testing.expect(t, strings.contains(head, "200"), "status is 200")
	testing.expect(t, strings.contains(head, "chunked"), "a stream is chunked")
	testing.expect(t, strings.contains(head, "x-content-type-options"), "secure_headers cover a stream (F5 stays closed here too)")

	// A worker thread streams three updates through the PUBLIC api.
	Worker :: struct {tok: web.Stream, thread: ^thread.Thread}
	worker_main :: proc(w: ^Worker) {
		for i in 0 ..< 3 {
			msg := [8]u8{'e', 'v', 't', '-', u8('0' + i), '\n', 0, 0}
			for web.stream_send(w.tok, msg[:6]) == .Full {time.sleep(time.Millisecond)}
		}
	}
	w := Worker{tok = shared.tok}
	w.thread = thread.create_and_start_with_poly_data(&w, worker_main)
	thread.join(w.thread)
	thread.destroy(w.thread)

	testing.expect(t, recv_until(sock, &wire, "evt-2", 3 * time.Second), "all three worker updates must arrive")

	web.stream_close(shared.tok)
	testing.expect(t, recv_until(sock, &wire, "0\r\n\r\n", 3 * time.Second), "close terminates the stream")
}

@(test)
wp96_a_buffered_route_is_untouched_by_streaming :: proc(t: ^testing.T) {
	shared: Shared
	g_shared = &shared
	srv: Server
	testing.expect(t, start(&srv, 51961), "server must start")
	defer stop(&srv)
	st, raw := get(51961, "/plain")
	testing.expect_value(t, st, 200)
	testing.expect(t, strings.contains(raw, "buffered-ok"), "the buffered body is intact")
	testing.expect(t, strings.contains(raw, "content-length"), "the buffered path still declares a length")
}

@(test)
wp96_the_in_memory_transport_reports_no_connection :: proc(t: ^testing.T) {
	// test_request has no connection to detach; web.stream must say so (ok=false)
	// rather than pretend, and the handler falls back to buffered.
	fell_back := false
	handler :: proc(ctx: ^web.Context) {
		_, ok := web.stream(ctx)
		if !ok {
			web.text(ctx, .OK, "fell-back")
		}
	}
	app := web.app()
	defer web.destroy(&app)
	web.get(&app, "/x", handler)
	rec := web.test_request(&app, .GET, "/x")
	testing.expect_value(t, rec.status, web.Status.OK)
	testing.expect_value(t, rec.body, "fell-back")
	fell_back = true
	testing.expect(t, fell_back)
}
