#+private
package http

import "core:mem/virtual"
import "base:intrinsics"

import "core:bufio"
import "core:nbio"
import "core:net"

Scan_Callback :: #type proc(user_data: rawptr, token: string, err: bufio.Scanner_Error)
Split_Proc    :: #type proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool)

scan_lines :: proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
	return bufio.scan_lines(data, at_eof)
}

scan_num_bytes :: proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
	assert(split_data != nil)
	n := int(uintptr(split_data))
	assert(n >= 0)

	if at_eof && len(data) < n {
		return
	}

	if len(data) < n {
		return
	}

	return n, data[:n], nil, false
}

// A callback based scanner over the connection based on nbio.
Scanner :: struct /* #no_copy */ {
	connection:                   ^Connection,
	split:                        Split_Proc,
	split_data:                   rawptr,
	buf:                          [dynamic]byte,
	max_token_size:               int,
	start:                        int,
	end:                          int,
	token:                        []byte,
	_err:                         bufio.Scanner_Error,
	consecutive_empty_reads:      int,
	max_consecutive_empty_reads:  int,
	successive_empty_token_count: int,
	done:                         bool,
	could_be_too_short:           bool,
	user_data:                    rawptr,
	callback:                     Scan_Callback,

	// URUQUIM PATCH 9 (WP59) — BRIDGE. The outstanding `recv`, kept so it can be
	// cancelled.
	//
	// Upstream discards the `^nbio.Operation` that `recv_poly` returns (see
	// `scanner_read` below, and upstream's own `// TODO: some kinda timeout on
	// this` beside it). Discarding it makes the operation unreachable, and an
	// unreachable operation cannot be cancelled — which is the whole of the
	// shutdown problem:
	//
	//   1. `connection_close` frees the `^Connection` while this `recv` is still
	//      outstanding. When it later completes, `scanner_on_read` dereferences
	//      `s.connection` for its arena and touches freed memory. WP58 measured
	//      it: `free(): invalid pointer`.
	//   2. `nbio.run()` at the end of `_server_thread_shutdown` waits for every
	//      outstanding operation. One orphaned `recv` per idle keep-alive
	//      connection is enough for a drain that never ends.
	//
	// Both are the same missing capability, so both are fixed by keeping the
	// handle. `nbio.remove` needs the pointer and nothing else did.
	//
	// BRIDGE, per `vendor-policy.md` §8: this goes away with the vendored server
	// when `core:net/http` lands.
	pending_recv:                 ^nbio.Operation,

	// URUQUIM PATCH 23 (WP7.5-C1) — BRIDGE. Streaming-body buffer reclamation.
	//
	// Upstream never compacts `buf`: `start` advances as tokens are consumed but
	// the buffer only ever grows (see the `// TODO: write over the part of the
	// buffer already used` at the resize site below). For a header scan or a
	// buffered body that is fine — the whole thing is wanted contiguously. But a
	// STREAMED body read one bounded window at a time would still grow `buf` to
	// the body's full length, defeating the point. When this flag is set the
	// scanner shifts the unconsumed tail down to offset 0 before it would grow,
	// so a body of any size costs one window of buffer. Off by default: the
	// buffered path (`http.body`) is byte-for-byte upstream. Set only by
	// `http.body_stream`; cleared by `scanner_reset`.
	//
	// BRIDGE, per `vendor-policy.md` §8: goes away with the vendored server when
	// `core:net/http` lands.
	stream_compact:               bool,
}

INIT_BUF_SIZE :: 1024
DEFAULT_MAX_CONSECUTIVE_EMPTY_READS :: 128

scanner_init :: proc(s: ^Scanner, c: ^Connection, buf_allocator := context.allocator) {
	s.connection     = c
	s.split          = scan_lines
	s.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
	s.buf.allocator  = buf_allocator
}

scanner_destroy :: proc(s: ^Scanner) {
	delete(s.buf)
}

scanner_reset :: proc(s: ^Scanner) {
	remove_range(&s.buf, 0, s.start)
	s.end   -= s.start
	s.start  = 0

	s.split                        = scan_lines
	s.split_data                   = nil
	s.max_token_size               = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
	s.token                        = nil
	s._err                         = nil
	s.consecutive_empty_reads      = 0
	s.max_consecutive_empty_reads  = DEFAULT_MAX_CONSECUTIVE_EMPTY_READS
	s.successive_empty_token_count = 0
	s.done                         = false
	s.could_be_too_short           = false
	s.user_data                    = nil
	s.callback                     = nil
	// URUQUIM PATCH 23 (WP7.5-C1) — BRIDGE. A reused connection scans the next
	// request's headers on the buffered path; the streaming flag must not leak.
	s.stream_compact               = false
}

scanner_scan :: proc(
	s: ^Scanner,
	user_data: rawptr,
	callback: proc(user_data: rawptr, token: string, err: bufio.Scanner_Error),
) {
	set_err :: proc(s: ^Scanner, err: bufio.Scanner_Error) {
		switch s._err {
		case nil, .EOF:
			s._err = err
		}
	}

	if s.done {
		callback(user_data, "", .EOF)
		return
	}

	// Check if a token is possible with what is available
	// Allow the split procedure to recover if it fails
	if s.start < s.end || s._err != nil {
		advance, token, err, final_token := s.split(s.split_data, s.buf[s.start:s.end], s._err != nil)
		if final_token {
			s.token = token
			s.done = true
			callback(user_data, "", .EOF)
			return
		}
		if err != nil {
			set_err(s, err)
			callback(user_data, "", s._err)
			return
		}

		// Do advance
		if advance < 0 {
			set_err(s, .Negative_Advance)
			callback(user_data, "", s._err)
			return
		}
		if advance > s.end - s.start {
			set_err(s, .Advanced_Too_Far)
			callback(user_data, "", s._err)
			return
		}
		s.start += advance

		s.token = token
		if s.token != nil {
			if s._err == nil || advance > 0 {
				s.successive_empty_token_count = 0
			} else {
				s.successive_empty_token_count += 1

				if s.successive_empty_token_count > s.max_consecutive_empty_reads {
					set_err(s, .No_Progress)
					callback(user_data, "", s._err)
					return
				}
			}

			s.consecutive_empty_reads = 0
			s.callback = nil
			s.user_data = nil
			callback(user_data, string(token), s._err)
			return
		}
	}

	// If an error is hit, no token can be created
	if s._err != nil {
		s.start = 0
		s.end = 0
		callback(user_data, "", s._err)
		return
	}

	could_be_too_short := false

	// URUQUIM PATCH 23 (WP7.5-C1) — BRIDGE. Reclaim the consumed prefix before
	// deciding whether the buffer must grow, so a streamed body of any size costs
	// one window of buffer rather than its full length. Only on the streaming
	// path (`stream_compact`); the buffered path never sets it and is unchanged.
	// The previous token was already handed to — and copied by — the synchronous
	// consumer before this re-arm, so shifting the tail invalidates nothing live.
	if s.stream_compact && s.start > 0 {
		if s.end > s.start {
			copy(s.buf[:], s.buf[s.start:s.end])
		}
		s.end -= s.start
		s.start = 0
	}

	// Resize the buffer if full
	if s.end == len(s.buf) {
		if s.max_token_size <= 0 {
			s.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
		}

		if s.end - s.start >= s.max_token_size {
			set_err(s, .Too_Long)
			callback(user_data, "", s._err)
			return
		}

		// TODO: write over the part of the buffer already used

		// overflow check
		new_size := INIT_BUF_SIZE
		if len(s.buf) > 0 {
			overflowed: bool
			if new_size, overflowed = intrinsics.overflow_mul(len(s.buf), 2); overflowed {
				set_err(s, .Too_Long)
				callback(user_data, "", s._err)
				return
			}
		}

		old_size := len(s.buf)
		resize(&s.buf, new_size)

		could_be_too_short = old_size >= len(s.buf)

	}

	// Read data into the buffer
	s.consecutive_empty_reads += 1
	s.user_data = user_data
	s.callback = callback
	s.could_be_too_short = could_be_too_short

	assert_has_td()
	// URUQUIM PATCH 9 (WP59) — BRIDGE. Keep the handle; see `pending_recv`.
	s.pending_recv = nbio.recv_poly(
		s.connection.socket,
		{s.buf[s.end:len(s.buf)]},
		s,
		scanner_on_read,
	)
}

scanner_on_read :: proc(op: ^nbio.Operation, s: ^Scanner) {
	// URUQUIM PATCH 9 (WP59) — BRIDGE. The operation has fired, so the handle is
	// dead: `nbio.remove` on an operation whose callback has run is itself a use
	// after free, and the library says so. Cleared FIRST, before any early
	// return below can skip it.
	s.pending_recv = nil

	context.temp_allocator = virtual.arena_allocator(&s.connection.temp_allocator)

	defer scanner_scan(s, s.user_data, s.callback)

	if op.recv.err != nil {
		#partial switch op.recv.err.(net.TCP_Recv_Error) {
		case .Connection_Closed, .Invalid_Argument:
			// EBADF (bad file descriptor) happens when OS closes socket.
			s._err = .EOF
			return
		}

		s._err = .Unknown
		return
	}

	// When n == 0, connection is closed or buffer is of length 0.
	if op.recv.received == 0 {
		s._err = .EOF
		return
	}

	if op.recv.received < 0 || len(s.buf) - s.end < op.recv.received {
		s._err = .Bad_Read_Count
		return
	}

	s.end += op.recv.received
	if op.recv.received > 0 {
		s.successive_empty_token_count = 0
		return
	}
}
