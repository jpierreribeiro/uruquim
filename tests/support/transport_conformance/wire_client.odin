// WP9 — THE RAW-WIRE SOCKET CLIENT.
//
// A deliberately DUMB client: it sends exact bytes and reads back just enough
// to evaluate the corpus. It is not, and must never become, a production HTTP
// parser — the framework has no HTTP parser and WP9 does not introduce one.
//
// It uses only `core:net` on loopback: no curl, no Python, no netcat, no
// external service, and it works offline.
//
// A case destined for rejection may legitimately end in EOF with no response at
// all (WP9 D6). EOF is therefore an ACCEPTED outcome; a TIMEOUT never is, so
// every read is bounded and the harness reports a hang as a failure rather than
// hanging the gate.
package transport_conformance

import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

// Wire_Result is what the client observed for one case.
Wire_Result :: struct {
	raw:            string, // everything read, owned by the caller
	statuses:       [dynamic]int, // one per response found in the stream
	saw_eof:        bool,
	timed_out:      bool,
	dialed:         bool,
}

wire_result_destroy :: proc(r: ^Wire_Result) {
	delete(r.raw)
	delete(r.statuses)
}

// WIRE_READ_BUDGET bounds a single case so a misbehaving adapter fails the test
// instead of hanging the gate.
WIRE_READ_BUDGET :: 3 * time.Second

// wire_send sends `payload` verbatim and reads until the peer closes or the
// budget expires.
//
// Reading until close is what makes the corpus honest about connection
// lifetime: `saw_eof` is the evidence that the adapter retired the connection
// rather than leaving it reusable after a framing error.
wire_send :: proc(port: int, payload: string) -> Wire_Result {
	result: Wire_Result
	result.statuses = make([dynamic]int)

	endpoint := net.Endpoint {
		address = net.IP4_Address{127, 0, 0, 1},
		port    = port,
	}

	sock, dial_err := net.dial_tcp(endpoint)
	if dial_err != nil {
		return result
	}
	result.dialed = true
	defer net.close(sock)

	// A receive timeout keeps a stalled adapter from stalling the gate.
	net.set_option(sock, .Receive_Timeout, WIRE_READ_BUDGET)

	if len(payload) > 0 {
		// A rejected request may be answered and closed while we are still
		// writing; a short write is therefore not a failure by itself.
		net.send_tcp(sock, transmute([]u8)payload)
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	deadline := time.now()
	buf: [4096]u8
	for {
		n, recv_err := net.recv_tcp(sock, buf[:])
		if n > 0 {
			strings.write_bytes(&builder, buf[:n])
		}
		if n == 0 {
			result.saw_eof = true
			break
		}
		if recv_err != nil {
			// A timeout is a real failure signal; any other error means the
			// peer went away, which is a close.
			if time.since(deadline) >= WIRE_READ_BUDGET {
				result.timed_out = true
			} else {
				result.saw_eof = true
			}
			break
		}
		if time.since(deadline) >= WIRE_READ_BUDGET {
			result.timed_out = true
			break
		}
	}

	result.raw = strings.clone(strings.to_string(builder))
	collect_statuses(&result)
	return result
}

// collect_statuses finds every `HTTP/1.x NNN` status line in the stream. Two
// statuses mean two responses — which is how the keep-alive case is confirmed
// and how a smuggled request would betray itself.
@(private)
collect_statuses :: proc(r: ^Wire_Result) {
	rest := r.raw
	for {
		i := strings.index(rest, "HTTP/1.")
		if i < 0 {
			return
		}
		rest = rest[i:]
		// "HTTP/1.1 200 ..." -> the code starts 9 bytes in.
		if len(rest) < 12 {
			return
		}
		code, ok := strconv.parse_int(strings.trim_space(rest[9:12]), 10)
		if ok {
			append(&r.statuses, code)
		}
		rest = rest[9:]
	}
}

// status_allowed reports whether `status` is in the case's allowed set. An
// empty set means the case does not constrain the status (a bare close is fine).
status_allowed :: proc(allowed: []int, status: int) -> bool {
	if len(allowed) == 0 {
		return true
	}
	for a in allowed {
		if a == status {
			return true
		}
	}
	return false
}
