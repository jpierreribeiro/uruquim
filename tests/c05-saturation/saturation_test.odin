// C-05 — the combined-saturation lab: WHICH QUEUE SATURATES FIRST.
//
// THE QUESTION, and it is the architecture backlog's, not a new one: a request
// passes through several bounded resources in series — the kernel's accept
// backlog, the server's admission budget (`max_connections` minus
// `reserved_conns`), a synchronous Handler lane, and process memory. Each has
// its own limit and its own refusal. Under rising load **one of them binds
// first**, and which one it is decides what an operator sees, what they should
// tune, and whether the degradation is honest.
//
// Nobody had measured it. `planning/closure-readiness-matrix.md` records every
// one of those resources with a limit and a saturation policy — that is C-02's
// job — but a matrix says what each resource does ALONE. This suite asks what
// they do TOGETHER.
//
// THE METHOD. Ramp concurrent clients against a server whose limits are set so
// the two framework-owned bounds are BOTH reachable on a test machine, and
// classify every single request by the outcome that identifies which resource
// refused it:
//
//	200                  served
//	503                  the HANDLER LANE refused (F-002's refuse-and-retry)
//	connected-then-EOF   the ADMISSION BUDGET refused (accepted, closed unread)
//	connect failed       the kernel BACKLOG or the fd table refused
//	timeout              nothing refused; something is merely slow
//
// The distinction between the middle two is the whole instrument, and it is the
// same one the C-03 RST-flood probe needed: an admission refusal accepts the
// TCP connection and then closes it with nothing written, so a client that only
// counts "errors" cannot tell it from a backlog drop. This suite counts them
// apart, which is why it can name the binding constraint instead of guessing.
//
// WHAT IT DELIBERATELY DOES NOT DO: it is not a benchmark. The numbers it
// prints are a RATIO between refusal kinds, not a throughput claim, and the
// assertions are about the SHAPE of the degradation — that the server keeps
// answering, that every refusal is a refusal the design names, and that nothing
// is answered with a truncated or malformed reply. A load figure from a shared
// development box would be a number about the box.
package test_c05_saturation

import "core:fmt"
import "core:net"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import web "uruquim:web"

CANDIDATE_PORTS :: [?]int{55037, 55363, 55631, 55907}

// The admission budget is set SMALL and the handler dwell LONG, so both bounds
// are reachable with a client count a test machine can produce. The point is
// the ordering of the two refusals, not the absolute numbers.
MAX_CONNECTIONS :: 24
RESERVED_CONNS :: 4 // budget = 20
WORK_DWELL :: 40 * time.Millisecond

// The ramp. Each level runs a fresh burst of concurrent clients.
LEVELS :: [?]int{4, 12, 24, 48}
MAX_CLIENTS :: 48

CLIENT_PATIENCE :: 3 * time.Second

Outcome :: enum {
	Served, // 200
	Lane_Refused, // 503 — the Handler lane said no
	Admission_Refused, // connected, then closed with nothing written
	Connect_Failed, // the backlog or the fd table said no
	Timed_Out, // slow, not refused
	Malformed, // a reply that is neither — the only real defect
}

Client :: struct {
	port:    int,
	outcome: Outcome,
}

Server :: struct {
	app:    web.App,
	port:   int,
	thread: ^thread.Thread,
	ready:  sync.Sema,
	done:   sync.Sema,
}

g_server: ^Server
g_clients: []Client
g_next: int

work_handler :: proc(ctx: ^web.Context) {
	// A synchronous dwell is the point: it occupies a Handler lane for a known
	// time, which is what makes lane saturation reachable and legible.
	time.sleep(WORK_DWELL)
	web.text(ctx, .OK, "done")
}

serve_thread :: proc() {
	s := g_server
	sync.post(&s.ready)
	web.serve(&s.app, s.port)
	sync.post(&s.done)
}

start_server :: proc(s: ^Server) -> bool {
	g_server = s
	for candidate in CANDIDATE_PORTS {
		s.app = web.app()
		l := web.DEFAULT_LIMITS
		l.max_connections = MAX_CONNECTIONS
		l.reserved_conns = RESERVED_CONNS
		l.max_drain_time = i64(3 * time.Second)
		web.limits(&s.app, l)
		web.get(&s.app, "/work", work_handler)
		s.port = candidate
		s.thread = thread.create_and_start(serve_thread)
		sync.wait(&s.ready)
		if wait_until_accepting(candidate) {
			return true
		}
		web.stop(&s.app)
		thread.join(s.thread)
		thread.destroy(s.thread)
		s.thread = nil
		web.destroy(&s.app)
	}
	return false
}

wait_until_accepting :: proc(port: int) -> bool {
	ep := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = port}
	for _ in 0 ..< 200 {
		sock, err := net.dial_tcp(ep)
		if err == nil {
			net.close(sock)
			return true
		}
		time.sleep(10 * time.Millisecond)
	}
	return false
}

REQ :: "GET /work HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"

one_request :: proc(port: int) -> Outcome {
	ep := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = port}
	sock, derr := net.dial_tcp(ep)
	if derr != nil {
		return .Connect_Failed
	}
	defer net.close(sock)
	_ = net.set_option(sock, .Receive_Timeout, CLIENT_PATIENCE)
	_ = net.set_option(sock, .Send_Timeout, CLIENT_PATIENCE)

	buf := transmute([]u8)string(REQ)
	sent := 0
	for sent < len(buf) {
		n, serr := net.send_tcp(sock, buf[sent:])
		if serr != nil || n <= 0 {
			// The peer went away mid-write: it accepted us and then closed,
			// which is the admission refusal seen from the write side.
			return .Admission_Refused
		}
		sent += n
	}

	reply: [512]u8
	n, rerr := net.recv_tcp(sock, reply[:])
	if rerr != nil {
		return .Timed_Out
	}
	if n == 0 {
		// Accepted, then closed with NOTHING written. This is the admission
		// refusal's signature, and telling it apart from a backlog drop is the
		// whole reason this suite can name a binding constraint.
		return .Admission_Refused
	}
	if n < 12 {
		return .Malformed
	}
	head := string(reply[:n])
	status := 0
	for i in 9 ..< 12 {
		c := head[i]
		if c < '0' || c > '9' {
			return .Malformed
		}
		status = status * 10 + int(c - '0')
	}
	switch status {
	case 200:
		return .Served
	case 503:
		return .Lane_Refused
	}
	return .Malformed
}

client_thread :: proc() {
	i := sync.atomic_add(&g_next, 1)
	if i >= len(g_clients) {
		return
	}
	c := &g_clients[i]
	c.outcome = one_request(c.port)
}

Tally :: [Outcome]int

run_level :: proc(port: int, clients: int) -> Tally {
	pool := make([]Client, clients)
	defer delete(pool)
	for &c in pool {
		c.port = port
	}
	g_clients = pool
	g_next = 0

	threads: [MAX_CLIENTS]^thread.Thread
	for i in 0 ..< clients {
		threads[i] = thread.create_and_start(client_thread)
	}
	for i in 0 ..< clients {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}
	g_clients = nil

	tally: Tally
	for c in pool {
		tally[c.outcome] += 1
	}
	return tally
}

@(test)
c05_the_binding_constraint_under_combined_saturation_is_named :: proc(t: ^testing.T) {
	server: Server
	if !start_server(&server) {
		testing.expect(t, false, "no candidate port produced a working server")
		return
	}

	fmt.printf(
		"[c05] budget=%d slots (max_connections=%d - reserved=%d), handler dwell=%v\n",
		MAX_CONNECTIONS - RESERVED_CONNS,
		MAX_CONNECTIONS,
		RESERVED_CONNS,
		WORK_DWELL,
	)

	total_malformed := 0
	first_refusal_kind := Outcome.Served
	first_refusal_level := 0

	for clients in LEVELS {
		tally := run_level(server.port, clients)
		fmt.printf(
			"[c05] clients=%d served=%d lane_503=%d admission=%d connect_fail=%d timeout=%d malformed=%d\n",
			clients,
			tally[.Served],
			tally[.Lane_Refused],
			tally[.Admission_Refused],
			tally[.Connect_Failed],
			tally[.Timed_Out],
			tally[.Malformed],
		)
		total_malformed += tally[.Malformed]

		// The FIRST level at which anything is refused names the binding
		// constraint — that is the measurement this suite exists to take.
		if first_refusal_kind == .Served {
			if tally[.Admission_Refused] > 0 {
				first_refusal_kind = .Admission_Refused
				first_refusal_level = clients
			} else if tally[.Lane_Refused] > 0 {
				first_refusal_kind = .Lane_Refused
				first_refusal_level = clients
			} else if tally[.Connect_Failed] > 0 {
				first_refusal_kind = .Connect_Failed
				first_refusal_level = clients
			}
		}
		// Let the server return to rest between levels, so each level measures
		// its own load rather than the previous level's tail.
		time.sleep(300 * time.Millisecond)
	}

	if first_refusal_kind == .Served {
		fmt.printf("[c05] no resource bound at any level up to %d clients\n", LEVELS[len(LEVELS) - 1])
	} else {
		fmt.printf(
			"[c05] FIRST BINDING CONSTRAINT: %v, at %d concurrent clients\n",
			first_refusal_kind,
			first_refusal_level,
		)
	}

	// A healthy request after the ramp: saturation must be transient.
	after := one_request(server.port)
	fmt.printf("[c05] after the ramp: %v\n", after)
	returned := false
	{
		web.stop(&server.app)
		stop_started := time.now()
		returned = sync.sema_wait_with_timeout(&server.done, 15 * time.Second)
		fmt.printf("[c05] stop returned=%v after %v\n", returned, time.since(stop_started))
		if returned {
			thread.join(server.thread)
			thread.destroy(server.thread)
			server.thread = nil
			web.destroy(&server.app)
		}
		g_server = nil
	}

	testing.expect(t, returned, "the server must shut down after the saturation ramp")
	// THE ONE HARD ASSERTION. Every outcome must be one the design NAMES.
	// A malformed or truncated reply means a resource ran out in a way nobody
	// chose — which is precisely the "failure mode is an accident" that the
	// admission bound (WP40 §2.5) exists to prevent.
	testing.expectf(
		t,
		total_malformed == 0,
		"%d requests got a reply that was neither 200, 503, nor a clean refusal; under saturation every outcome must be one the design names",
		total_malformed,
	)
	testing.expectf(
		t,
		after == .Served,
		"the server did not serve a normal request after the ramp (got %v); saturation must be transient",
		after,
	)
}
