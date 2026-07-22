// Real-socket synchronous-Handler liveness instrument for WP71/WP72.
package web_blocking_lab

import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import web "uruquim:web"

Observation_Window :: 250 * time.Millisecond
Baseline_Ceiling :: 25 * time.Millisecond

State :: struct {
	entered: sync.Sema,
	release: sync.Sema,
}

Server :: struct {
	state:  State,
	app:    web.App,
	port:   int,
	thread: ^thread.Thread,
}

Call :: struct {
	port:    int,
	path:    string,
	thread:  ^thread.Thread,
	done:    sync.Sema,
	ok:      bool,
	status:  int,
	elapsed: time.Duration,
}

@(private)
handler :: proc(ctx: ^web.Context) {
	state := web.state(ctx, State)
	if ctx.request.path == "/block" {
		sync.sema_post(&state.entered)
		sync.sema_wait(&state.release)
	}
	web.text(ctx, .OK, "ok")
}

@(private)
server_thread :: proc(s: ^Server) {
	web.serve(&s.app, s.port)
}

@(private)
start :: proc(s: ^Server, port: int, limits: web.Limits) -> bool {
	s^ = {}
	s.port = port
	s.app = web.app_with_state(&s.state)
	web.get(&s.app, "/health", handler)
	web.get(&s.app, "/block", handler)
	web.limits(&s.app, limits)
	s.thread = thread.create_and_start_with_poly_data(s, server_thread)
	for _ in 0 ..< 200 {
		status, _, ok := Request(port, "/health")
		if ok && status == 200 {
			return true
		}
		time.sleep(2 * time.Millisecond)
	}
	return false
}

Start :: proc(s: ^Server, port: int, max_handlers: int) -> bool {
	limits := web.DEFAULT_LIMITS
	limits.max_handlers = max_handlers
	return start(s, port, limits)
}

Start_With_Admission :: proc(
	s: ^Server,
	port, max_handlers, max_connections, reserved_conns: int,
) -> bool {
	limits := web.DEFAULT_LIMITS
	limits.max_handlers = max_handlers
	limits.max_connections = max_connections
	limits.reserved_conns = reserved_conns
	limits.max_request_time = 0
	return start(s, port, limits)
}

Stop :: proc(s: ^Server) {
	sync.sema_post(&s.state.release, 64)
	web.stop(&s.app)
	if s.thread != nil {
		thread.join(s.thread)
		thread.destroy(s.thread)
		s.thread = nil
	}
	web.destroy(&s.app)
}

Wait_Entered :: proc(s: ^Server, timeout := 2 * time.Second) -> bool {
	return sync.sema_wait_with_timeout(&s.state.entered, timeout)
}

Release :: proc(s: ^Server, count: int) {
	if count > 0 {
		sync.sema_post(&s.state.release, count)
	}
}

@(private)
parse_status :: proc(raw: string) -> int {
	if len(raw) < 12 {return 0}
	value, ok := strconv.parse_int(raw[9:12], 10)
	return value if ok else 0
}

Request :: proc(port: int, path: string) -> (status: int, elapsed: time.Duration, ok: bool) {
	started := time.now()
	endpoint := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = port}
	sock: net.TCP_Socket
	connected := false
	for _ in 0 ..< 100 {
		err: net.Network_Error
		sock, err = net.dial_tcp(endpoint)
		if err == nil {
			connected = true
			break
		}
		time.sleep(2 * time.Millisecond)
	}
	if !connected {return 0, time.since(started), false}
	defer net.close(sock)
	net.set_option(sock, .Receive_Timeout, 3 * time.Second)

	request, err := strings.concatenate({"GET ", path, " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"})
	if err != nil {return 0, time.since(started), false}
	defer delete(request)
	if _, send_err := net.send_tcp(sock, transmute([]u8)request); send_err != nil {
		return 0, time.since(started), false
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	buffer: [4096]u8
	for {
		n, recv_err := net.recv_tcp(sock, buffer[:])
		if n > 0 {strings.write_bytes(&builder, buffer[:n])}
		if n == 0 || recv_err != nil {break}
	}
	status = parse_status(strings.to_string(builder))
	return status, time.since(started), status != 0
}

Open_Idle :: proc(port: int) -> (net.TCP_Socket, bool) {
	endpoint := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = port}
	for _ in 0 ..< 100 {
		sock, err := net.dial_tcp(endpoint)
		if err == nil {
			return sock, true
		}
		time.sleep(2 * time.Millisecond)
	}
	return {}, false
}

@(private)
call_thread :: proc(c: ^Call) {
	c.status, c.elapsed, c.ok = Request(c.port, c.path)
	sync.sema_post(&c.done)
}

Start_Call :: proc(c: ^Call, port: int, path: string) {
	c^ = {}
	c.port = port
	c.path = path
	c.thread = thread.create_and_start_with_poly_data(c, call_thread)
}

Wait_Call :: proc(c: ^Call, timeout: time.Duration) -> bool {
	return sync.sema_wait_with_timeout(&c.done, timeout)
}

Join_Call :: proc(c: ^Call) {
	if c.thread != nil {
		thread.join(c.thread)
		thread.destroy(c.thread)
		c.thread = nil
	}
}
