// Experiment 16, candidate D — an SSE-specific API with no generic stream.
//
// The API is protocol-shaped: open_sse / send_event(name, data) / close, and
// the framework formats `event:`/`data:` framing at enqueue. The finding this
// prototype records: D still needs EVERY piece of candidate C's machinery —
// slot registry, generation, bounded queue, owner-lane writer, wakeup — while
// surrendering generality (a binary progress download or chunked file cannot
// use it) and moving protocol text INTO the core, against CE-E3's direction
// (SSE belongs to a Crystal over a generic primitive).
//
// DISPOSABLE PROTOTYPE (WP86): never imported by `web`.
package wp86_candidate_d

import "core:sync"
import "core:thread"
import "core:testing"
import "core:time"

QUEUE_EVENTS :: 8
FRAME_BYTES  :: 96

Send_Result :: enum {
	Sent,
	Full,
	Closed,
	Stale,
}

Frame :: struct {
	len:  int,
	data: [FRAME_BYTES]u8,
}

// One slot, framed as SSE at enqueue — the registry/generation/queue shape is
// candidate C's, reproduced because D cannot exist without it.
Sse_Stream :: struct {
	mu:          sync.Mutex,
	generation:  u64,
	open:        bool,
	queue:       [QUEUE_EVENTS]Frame,
	head, count: int,
	sink:        [dynamic]u8,
	wake:        sync.Sema,
	stop:        bool,
	lane:        ^thread.Thread,
}

Token :: struct {
	generation: u64,
}

open_sse :: proc(s: ^Sse_Stream) -> Token {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	s.open = true
	return Token{generation = s.generation}
}

// The framework composes protocol text. This is the line CE-E3 exists to keep
// out of the core: `event: <name>\ndata: <data>\n\n`.
send_event :: proc(s: ^Sse_Stream, tok: Token, name: string, data: string) -> Send_Result {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation {
		return .Stale
	}
	if !s.open {
		return .Closed
	}
	if s.count >= QUEUE_EVENTS {
		return .Full
	}
	f := &s.queue[(s.head + s.count) % QUEUE_EVENTS]
	f.len = 0
	frame_append(f, "event: ")
	frame_append(f, name)
	frame_append(f, "\ndata: ")
	frame_append(f, data)
	frame_append(f, "\n\n")
	s.count += 1
	sync.sema_post(&s.wake)
	return .Sent
}

frame_append :: proc(f: ^Frame, text: string) {
	n := min(len(text), FRAME_BYTES - f.len)
	copy(f.data[f.len:f.len + n], text[:n])
	f.len += n
}

close_sse :: proc(s: ^Sse_Stream, tok: Token) {
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation {
		return
	}
	s.open = false
	s.generation += 1
	sync.sema_post(&s.wake)
}

lane_main :: proc(s: ^Sse_Stream) {
	for !sync.atomic_load(&s.stop) {
		_ = sync.sema_wait_with_timeout(&s.wake, 5 * time.Millisecond)
		sync.mutex_lock(&s.mu)
		for s.count > 0 {
			f := &s.queue[s.head]
			append(&s.sink, ..f.data[:f.len])
			s.head = (s.head + 1) % QUEUE_EVENTS
			s.count -= 1
		}
		sync.mutex_unlock(&s.mu)
	}
}

@(test)
ten_named_updates_arrive_with_sse_framing :: proc(t: ^testing.T) {
	s := new(Sse_Stream)
	defer free(s)
	s.lane = thread.create_and_start_with_poly_data(s, lane_main)
	defer {
		sync.atomic_store(&s.stop, true)
		sync.sema_post(&s.wake)
		thread.join(s.lane)
		thread.destroy(s.lane)
		delete(s.sink)
	}
	tok := open_sse(s)
	digits := "0123456789"
	for i in 0 ..< 10 {
		for {
			res := send_event(s, tok, "tick", digits[i:i + 1])
			if res == .Full {
				time.sleep(time.Millisecond)
				continue
			}
			testing.expect_value(t, res, Send_Result.Sent)
			break
		}
	}
	expected := "event: tick\ndata: 0\n\n"
	deadline := time.tick_now()
	for {
		sync.mutex_lock(&s.mu)
		done := len(s.sink) == 10 * len(expected)
		sync.mutex_unlock(&s.mu)
		if done {break}
		if time.tick_since(deadline) > 2 * time.Second {break}
		time.sleep(time.Millisecond)
	}
	sync.mutex_lock(&s.mu)
	testing.expect_value(t, len(s.sink), 10 * len(expected))
	head_ok := string(s.sink[:len(expected)]) == expected
	sync.mutex_unlock(&s.mu)
	testing.expect(t, head_ok, "the first frame must be exact SSE text")
}

@(test)
stale_token_refuses_after_close :: proc(t: ^testing.T) {
	s := new(Sse_Stream)
	defer free(s)
	defer delete(s.sink)
	tok := open_sse(s)
	close_sse(s, tok)
	testing.expect_value(t, send_event(s, tok, "late", "x"), Send_Result.Stale)
	// D needed the generation check too: protocol-specific surface saved none
	// of the lifecycle machinery.
}

@(test)
a_binary_progress_payload_cannot_use_this_api :: proc(t: ^testing.T) {
	// The negative finding as executable documentation: D's only send takes
	// (name, data) strings and injects SSE text. Binary chunked output — the
	// WP99 progress-download slice — has no representation here. A `data`
	// containing a newline would also corrupt framing unless the core learns
	// newline-splitting, MORE protocol knowledge. Generality lost, machinery
	// kept: D is C's cost without C's reach.
	s := new(Sse_Stream)
	defer free(s)
	defer delete(s.sink)
	tok := open_sse(s)
	raw := []u8{0x1f, 0x8b, '\n', 0x00} // gzip magic + newline: not SSE-safe
	res := send_event(s, tok, "chunk", string(raw))
	testing.expect_value(t, res, Send_Result.Sent) // it "works" —
	sync.mutex_lock(&s.mu)
	frame := s.queue[s.head]
	sync.mutex_unlock(&s.mu)
	corrupted := string(frame.data[:frame.len]) != "event: chunk\ndata: \x1f\x8b\ndata: \x00\n\n"
	testing.expect(t, corrupted, "raw bytes with a newline corrupt SSE framing unless the core learns to split — recorded as D's generality veto")
}
