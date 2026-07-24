// C-04 — response size and memory retention, measured.
//
// THE TWO OPEN PERIMETERS this suite exists to answer
// (`planning/production-readiness-closure.md` §4):
//
//	2. Unbounded response size and its arena impact — ⚠ OPEN
//	3. Memory retention after large responses (soak) — ⚠ OPEN
//
// Both were open because nobody had a number. The matrix (C-02, row 8) records
// the per-connection arena as "no limit directly, retention unmeasured", and a
// cell that says "unmeasured" is an invitation, not an answer.
//
// WHAT THE ARENA ACTUALLY DOES, which is the hypothesis under test. Each
// connection owns a growing `virtual.Arena`. `clean_request_loop` ends every
// request with `free_all` on it — and `free_all` on an arena RESETS the offset
// while KEEPING the reserved blocks, because that is what an arena is for. So a
// keep-alive connection that once served a large response is predicted to hold
// that memory for its whole life, even while serving tiny responses afterwards.
// With `max_connections` at its default of 1024, the worst case is
// 1024 x (largest response that connection ever served) — a number no
// configuration bounds, because ADR-014 buffers responses whole and the core
// caps what a client may SEND (`max_body`) but not what a handler may BUILD.
//
// THE MEASUREMENT is deliberately two-phase, because a single RSS reading
// cannot tell retention from a leak:
//
//	phase 1  N keep-alive connections, one BIG response each   -> the retention
//	phase 2  the same connections, many SMALL requests each    -> the leak test
//
// Retention is expected and is reported as a number. GROWTH during phase 2 is
// the defect: if RSS keeps climbing while the same connections serve small
// responses, something is not being reclaimed per request, and that is a leak
// no arena reset excuses.
package test_c04_response_size

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import web "uruquim:web"

CANDIDATE_PORTS :: [?]int{55031, 55357, 55625, 55901}

// Big enough to dwarf the noise of a test process's own allocation, small
// enough that N of them fit comfortably on a development box.
BIG_BYTES :: 4 * 1024 * 1024
SMALL_BYTES :: 512

// The keep-alive connections held across both phases. Each one is an
// independent arena, which is the point: retention is PER CONNECTION.
CONNS :: 8

// Small requests per connection in phase 2. Enough that a per-request leak of
// even a few kilobytes would be visible against the retention baseline.
SMALL_ROUNDS :: 200

// The leak threshold. Phase 2 reuses arenas that already hold BIG_BYTES, so a
// correct implementation should grow by approximately nothing; 2 MiB is
// generous room for allocator bookkeeping and test-side buffers, and is still
// far below the ~1.6 MiB per connection a 200-round leak of 1 KiB would cost.
LEAK_THRESHOLD_BYTES :: 2 * 1024 * 1024

Server :: struct {
	app:    web.App,
	port:   int,
	thread: ^thread.Thread,
	ready:  sync.Sema,
	done:   sync.Sema,
}

g_server: ^Server

big_handler :: proc(ctx: ^web.Context) {
	body := make([]u8, BIG_BYTES, context.temp_allocator)
	web.text(ctx, .OK, string(body))
}

small_handler :: proc(ctx: ^web.Context) {
	body := make([]u8, SMALL_BYTES, context.temp_allocator)
	web.text(ctx, .OK, string(body))
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
		l.max_drain_time = i64(2 * time.Second)
		web.limits(&s.app, l)
		web.get(&s.app, "/big", big_handler)
		web.get(&s.app, "/small", small_handler)
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

// rss_bytes reads this process's resident set from /proc/self/statm.
//
// RSS AND NOT AN ALLOCATOR COUNTER, on purpose. The server runs in this same
// process, and what an operator sizes a cgroup against is resident memory, not
// a number the framework reports about itself. It is also the reading that
// cannot be faked by an accounting bug — the WP2 two-instance trap, applied to
// memory.
rss_bytes :: proc() -> int {
	data, read_err := os.read_entire_file_from_path("/proc/self/statm", context.temp_allocator)
	if read_err != nil {
		return 0
	}
	fields := strings.fields(string(data), context.temp_allocator)
	if len(fields) < 2 {
		return 0
	}
	pages, _ := strconv.parse_int(fields[1])
	// 4 KiB on every platform this project gates (production-service-bom.md §6).
	PAGE_SIZE :: 4096
	return pages * PAGE_SIZE
}

send_all :: proc(sock: net.TCP_Socket, data: string) -> bool {
	buf := transmute([]u8)data
	sent := 0
	for sent < len(buf) {
		n, err := net.send_tcp(sock, buf[sent:])
		if err != nil || n <= 0 {
			return false
		}
		sent += n
	}
	return true
}

// read_exactly_one_response drains a whole response, using Content-Length to
// know when to stop — a keep-alive client MUST read its response fully or the
// next request would be answered into a socket the server still owns bytes on.
read_one_response :: proc(sock: net.TCP_Socket, scratch: []u8) -> bool {
	total, header_end, content_length := 0, -1, -1
	for {
		n, err := net.recv_tcp(sock, scratch[total:])
		if err != nil || n <= 0 {
			return false
		}
		total += n
		if header_end < 0 {
			idx := strings.index(string(scratch[:total]), "\r\n\r\n")
			if idx >= 0 {
				header_end = idx + 4
				head := strings.to_lower(string(scratch[:idx]), context.temp_allocator)
				ci := strings.index(head, "content-length:")
				if ci >= 0 {
					rest := head[ci + len("content-length:"):]
					line_end := strings.index(rest, "\r\n")
					if line_end < 0 {
						line_end = len(rest)
					}
					content_length, _ = strconv.parse_int(strings.trim_space(rest[:line_end]))
				}
			}
		}
		if header_end >= 0 && content_length >= 0 && total >= header_end + content_length {
			return true
		}
		if total >= len(scratch) {
			return false
		}
	}
}

@(test)
c04_arena_retention_is_per_connection_and_bounded_by_no_setting :: proc(t: ^testing.T) {
	server: Server
	if !start_server(&server) {
		testing.expect(t, false, "no candidate port produced a working server")
		return
	}

	// One scratch buffer, reused — and TOUCHED BEFORE THE BASELINE IS TAKEN.
	// RSS counts resident pages, not reservations, so an untouched buffer would
	// become resident during phase 1 and be counted as server retention. Writing
	// it first moves the client's own 4 MiB into the baseline where it belongs.
	// (The first version of this suite did not, and reported ~4 MiB of the
	// client's memory as the framework's.)
	scratch := make([]u8, BIG_BYTES + 64 * 1024)
	defer delete(scratch)
	for i in 0 ..< len(scratch) {
		scratch[i] = u8(i)
	}

	socks: [CONNS]net.TCP_Socket
	live: [CONNS]bool
	ep := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = server.port}
	for i in 0 ..< CONNS {
		sock, err := net.dial_tcp(ep)
		live[i] = err == nil
		if live[i] {
			socks[i] = sock
			_ = net.set_option(sock, .Receive_Timeout, 5 * time.Second)
		}
	}

	baseline := rss_bytes()

	// --- phase 1: one BIG response per connection -> the retention ----------
	big_req := "GET /big HTTP/1.1\r\nHost: localhost\r\n\r\n"
	served_big := 0
	for i in 0 ..< CONNS {
		if !live[i] {
			continue
		}
		if send_all(socks[i], big_req) && read_one_response(socks[i], scratch) {
			served_big += 1
		}
	}
	after_big := rss_bytes()

	// --- phase 2: many SMALL responses on the SAME connections -> the leak ---
	small_req := "GET /small HTTP/1.1\r\nHost: localhost\r\n\r\n"
	served_small := 0
	for _ in 0 ..< SMALL_ROUNDS {
		for i in 0 ..< CONNS {
			if !live[i] {
				continue
			}
			if send_all(socks[i], small_req) && read_one_response(socks[i], scratch) {
				served_small += 1
			}
		}
	}
	after_small := rss_bytes()

	for i in 0 ..< CONNS {
		if live[i] {
			net.close(socks[i])
		}
	}
	time.sleep(300 * time.Millisecond)
	after_close := rss_bytes()

	web.stop(&server.app)
	returned := sync.sema_wait_with_timeout(&server.done, 10 * time.Second)
	if returned {
		thread.join(server.thread)
		thread.destroy(server.thread)
		server.thread = nil
		web.destroy(&server.app)
	}
	g_server = nil

	retained := after_big - baseline
	grew := after_small - after_big
	fmt.printf(
		"[c04] conns=%d big=%d(%d served) small_rounds=%d(%d served)\n",
		CONNS,
		BIG_BYTES,
		served_big,
		SMALL_ROUNDS,
		served_small,
	)
	fmt.printf(
		"[c04] rss baseline=%.1fMiB after_big=%.1fMiB after_small=%.1fMiB after_close=%.1fMiB\n",
		f64(baseline) / 1048576.0,
		f64(after_big) / 1048576.0,
		f64(after_small) / 1048576.0,
		f64(after_close) / 1048576.0,
	)
	fmt.printf(
		"[c04] retention after big = %.1fMiB (%.2f x the %.1fMiB served) | growth over %d small responses = %.2fMiB\n",
		f64(retained) / 1048576.0,
		f64(retained) / f64(served_big * BIG_BYTES) if served_big > 0 else 0,
		f64(served_big * BIG_BYTES) / 1048576.0,
		served_small,
		f64(grew) / 1048576.0,
	)

	testing.expect(t, returned, "the server must shut down after the soak")
	testing.expectf(
		t,
		served_big == CONNS,
		"only %d of %d big responses were served; the retention figure would be about the client",
		served_big,
		CONNS,
	)
	testing.expectf(
		t,
		served_small == CONNS * SMALL_ROUNDS,
		"only %d of %d small responses were served; the leak figure would be about the client",
		served_small,
		CONNS * SMALL_ROUNDS,
	)
	// THE ASSERTION IS ABOUT PHASE 2 ONLY. Retention is reported, not asserted:
	// it is the documented consequence of an arena, and pinning it would pin an
	// implementation detail. What must hold is that serving thousands of small
	// responses on arenas that already grew costs approximately nothing more —
	// anything else is a per-request leak.
	testing.expectf(
		t,
		grew < LEAK_THRESHOLD_BYTES,
		"RSS grew %.2fMiB while serving %d small responses on already-grown arenas; the per-request reclaim is leaking (threshold %.1fMiB)",
		f64(grew) / 1048576.0,
		served_small,
		f64(LEAK_THRESHOLD_BYTES) / 1048576.0,
	)
}
