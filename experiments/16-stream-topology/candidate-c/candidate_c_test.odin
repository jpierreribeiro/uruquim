// Experiment 16, candidate C — detached stream with a stale-safe value token.
//
// The Handler opens a stream and RETURNS; later code enqueues bounded output
// from any thread; only the owner lane touches the sink (standing for the
// socket). DISPOSABLE PROTOTYPE (WP86): never imported by `web`, no public
// surface, thresholds deliberately tiny so refusal paths are exercised rather
// than hypothetical.
//
// What this prototype must prove or refuse (phase-7-spec.md §3.1, ADR-044):
//   - cross-thread enqueue with a closed typed result {sent, full, closed, stale};
//   - copy-on-enqueue, zero dynamic allocation on the send path;
//   - generation invalidated on close BEFORE queued items are released;
//   - a stale token cannot touch a reused slot's new occupant;
//   - close travels on reserved control capacity a full queue cannot block;
//   - per-tick write progress is capped, so one stream cannot monopolize a tick;
//   - concurrent producers racing the final queue slot produce exactly one Sent.
package wp86_candidate_c

import "core:sync"
import "core:thread"
import "core:testing"
import "core:time"

SLOT_COUNT       :: 2 // forced tiny: slot reuse is exercised, not simulated
QUEUE_EVENTS     :: 8
QUEUE_BYTES      :: 512
EVENT_BYTES      :: 64
TICK_PROGRESS    :: 2 // events written per stream per owner-lane tick

Send_Result :: enum {
	Sent,
	Full,
	Closed,
	Stale,
}

Event :: struct {
	len:  int,
	data: [EVENT_BYTES]u8,
}

Slot_State :: enum {
	Free,
	Open,
	Closing,
}

Slot :: struct {
	mu:              sync.Mutex,
	generation:      u64,
	state:           Slot_State,
	queue:           [QUEUE_EVENTS]Event,
	head:            int,
	count:           int,
	queued_bytes:    int,
	close_requested: bool, // reserved control signal: set even when the queue is full
	// The sink stands for the socket. Only the owner lane appends.
	sink:            [dynamic]u8,
	sink_events:     int,
	released_events: int, // queued items discarded by close — exactly-once accounting
}

Registry :: struct {
	slots: [SLOT_COUNT]Slot,
	wake:  sync.Sema,
	lane:  ^thread.Thread,
	stop:  bool, // written via atomic only
}

Token :: struct {
	slot:       int,
	generation: u64,
}

// --- open runs on the connection-owning lane (test setup stands in for it) ---

open_stream :: proc(r: ^Registry) -> (Token, bool) {
	for &s, i in r.slots {
		sync.mutex_lock(&s.mu)
		if s.state == .Free {
			s.state = .Open
			s.close_requested = false
			s.head = 0
			s.count = 0
			s.queued_bytes = 0
			tok := Token{slot = i, generation = s.generation}
			sync.mutex_unlock(&s.mu)
			return tok, true
		}
		sync.mutex_unlock(&s.mu)
	}
	return Token{slot = -1}, false // typed refusal at the open cap
}

// --- try_send may run on ANY thread: copy on enqueue, never block ---

try_send :: proc(r: ^Registry, tok: Token, data: []u8) -> Send_Result {
	if tok.slot < 0 || tok.slot >= SLOT_COUNT {
		return .Stale
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation {
		return .Stale
	}
	if s.state != .Open || s.close_requested {
		return .Closed
	}
	if s.count >= QUEUE_EVENTS || s.queued_bytes + len(data) > QUEUE_BYTES {
		return .Full // the canonical full result is refusal; nothing waits
	}
	e := &s.queue[(s.head + s.count) % QUEUE_EVENTS]
	e.len = min(len(data), EVENT_BYTES)
	copy(e.data[:e.len], data[:e.len])
	s.count += 1
	s.queued_bytes += e.len
	sync.sema_post(&r.wake)
	return .Sent
}

// --- close is control capacity: it succeeds even against a full queue ---

request_close :: proc(r: ^Registry, tok: Token) -> bool {
	if tok.slot < 0 || tok.slot >= SLOT_COUNT {
		return false
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation {
		return false // stale close is refused, and idempotent for the caller
	}
	if s.state == .Open {
		s.close_requested = true
		// Generation is invalidated the moment close is accepted — BEFORE the
		// owner lane releases queued items (ADR-044 §3). From this instant no
		// producer holding the old token can reach the slot.
		s.generation += 1
		sync.sema_post(&r.wake)
	}
	return true
}

// --- the owner lane is the only writer ---

lane_tick :: proc(r: ^Registry) {
	for &s in r.slots {
		sync.mutex_lock(&s.mu)
		progress := 0
		for s.count > 0 && progress < TICK_PROGRESS {
			e := &s.queue[s.head]
			if s.close_requested {
				// Close policy in this prototype: queued user items are
				// discarded, counted exactly once.
				s.released_events += 1
			} else {
				append(&s.sink, ..e.data[:e.len])
				s.sink_events += 1
			}
			s.queued_bytes -= e.len
			s.head = (s.head + 1) % QUEUE_EVENTS
			s.count -= 1
			progress += 1
		}
		if s.close_requested && s.count == 0 && s.state != .Free {
			s.state = .Free // generation already bumped at close-accept
			s.close_requested = false
		}
		sync.mutex_unlock(&s.mu)
	}
}

lane_main :: proc(r: ^Registry) {
	for !sync.atomic_load(&r.stop) {
		_ = sync.sema_wait_with_timeout(&r.wake, 5 * time.Millisecond)
		lane_tick(r)
	}
	lane_tick(r) // final drain pass
}

start :: proc(r: ^Registry) {
	r.lane = thread.create_and_start_with_poly_data(r, lane_main)
}

stop :: proc(r: ^Registry) {
	sync.atomic_store(&r.stop, true)
	sync.sema_post(&r.wake)
	if r.lane != nil {
		thread.join(r.lane)
		thread.destroy(r.lane)
		r.lane = nil
	}
	for &s in r.slots {
		delete(s.sink)
	}
}

// ---------------------------------------------------------------------------

Producer_Job :: struct {
	r:      ^Registry,
	tok:    Token,
	base:   u8,
	sent:   int,
	full:   int,
	thread: ^thread.Thread,
}

producer_main :: proc(j: ^Producer_Job) {
	// Ten updates per producer — the shared workload of every candidate.
	for i in 0 ..< 10 {
		msg := [2]u8{j.base, u8('0' + i)}
		for {
			switch try_send(j.r, j.tok, msg[:]) {
			case .Sent:
				j.sent += 1
			case .Full:
				j.full += 1
				time.sleep(time.Millisecond) // producer's own retry policy, never the framework blocking
				continue
			case .Closed, .Stale:
			}
			break
		}
	}
}

@(test)
ten_updates_per_stream_cross_thread_arrive_in_order :: proc(t: ^testing.T) {
	r := new(Registry)
	defer free(r)
	start(r)
	defer stop(r)

	toks: [SLOT_COUNT]Token
	jobs: [SLOT_COUNT]Producer_Job
	for i in 0 ..< SLOT_COUNT {
		ok: bool
		toks[i], ok = open_stream(r)
		testing.expect(t, ok, "open within the cap must succeed")
	}
	for i in 0 ..< SLOT_COUNT {
		jobs[i] = Producer_Job{r = r, tok = toks[i], base = u8('a' + i)}
		jobs[i].thread = thread.create_and_start_with_poly_data(&jobs[i], producer_main)
	}
	for i in 0 ..< SLOT_COUNT {
		thread.join(jobs[i].thread)
		thread.destroy(jobs[i].thread)
	}
	deadline := time.tick_now()
	for {
		done := true
		for i in 0 ..< SLOT_COUNT {
			s := &r.slots[i]
			sync.mutex_lock(&s.mu)
			if s.sink_events < 10 {done = false}
			sync.mutex_unlock(&s.mu)
		}
		if done {break}
		testing.expect(t, time.tick_since(deadline) < 2 * time.Second, "owner lane must drain ten updates")
		if time.tick_since(deadline) >= 2 * time.Second {return}
		time.sleep(time.Millisecond)
	}
	for i in 0 ..< SLOT_COUNT {
		s := &r.slots[i]
		sync.mutex_lock(&s.mu)
		testing.expect_value(t, s.sink_events, 10)
		testing.expect_value(t, len(s.sink), 20)
		in_order := true
		for e in 0 ..< 10 {
			if s.sink[e * 2] != u8('a' + i) || s.sink[e * 2 + 1] != u8('0' + e) {
				in_order = false
			}
		}
		sync.mutex_unlock(&s.mu)
		testing.expect(t, in_order, "per-producer order must be preserved on the wire")
	}
}

@(test)
full_queue_returns_typed_result_without_blocking :: proc(t: ^testing.T) {
	r := new(Registry)
	defer free(r)
	// Owner lane deliberately NOT started: the queue cannot drain.
	tok, ok := open_stream(r)
	testing.expect(t, ok)
	payload := [8]u8{}
	sent := 0
	began := time.tick_now()
	for _ in 0 ..< QUEUE_EVENTS {
		if try_send(r, tok, payload[:]) == .Sent {sent += 1}
	}
	testing.expect_value(t, sent, QUEUE_EVENTS)
	testing.expect_value(t, try_send(r, tok, payload[:]), Send_Result.Full)
	testing.expect(t, time.tick_since(began) < 100 * time.Millisecond, "refusal must be immediate, never a wait")
	for &s in r.slots {delete(s.sink)}
}

@(test)
stale_token_after_close_and_slot_reuse_refuses :: proc(t: ^testing.T) {
	r := new(Registry)
	defer free(r)
	start(r)
	defer stop(r)

	old_tok, ok := open_stream(r)
	testing.expect(t, ok)
	blocker, blocker_ok := open_stream(r) // occupy every other slot so reuse hits the SAME slot
	testing.expect(t, blocker_ok)
	testing.expect(t, request_close(r, old_tok))

	// Wait for the slot to be reusable, then take it again.
	new_tok: Token
	reopened := false
	for _ in 0 ..< 200 {
		if nt, nok := open_stream(r); nok {
			new_tok = nt
			reopened = true
			break
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, reopened, "closed slot must become reusable")
	testing.expect_value(t, new_tok.slot, old_tok.slot)
	testing.expect(t, new_tok.generation > old_tok.generation, "reuse must carry a new generation")
	_ = blocker

	payload := [4]u8{'l', 'a', 't', 'e'}
	testing.expect_value(t, try_send(r, old_tok, payload[:]), Send_Result.Stale)

	// The new stream is untouched by the stale attempt.
	fresh := [4]u8{'f', 'r', 's', 'h'}
	testing.expect_value(t, try_send(r, new_tok, fresh[:]), Send_Result.Sent)
	ok_drained := false
	for _ in 0 ..< 200 {
		s := &r.slots[new_tok.slot]
		sync.mutex_lock(&s.mu)
		if s.sink_events == 1 && len(s.sink) == 4 && s.sink[0] == 'f' {ok_drained = true}
		sync.mutex_unlock(&s.mu)
		if ok_drained {break}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, ok_drained, "the new occupant receives exactly its own bytes")
}

@(test)
close_succeeds_against_a_full_queue :: proc(t: ^testing.T) {
	r := new(Registry)
	defer free(r)
	tok, ok := open_stream(r)
	testing.expect(t, ok)
	payload := [8]u8{}
	for _ in 0 ..< QUEUE_EVENTS {
		_ = try_send(r, tok, payload[:])
	}
	testing.expect_value(t, try_send(r, tok, payload[:]), Send_Result.Full)
	// Control capacity: close is accepted although no user slot remains.
	testing.expect(t, request_close(r, tok), "a full queue must never block close")
	start(r)
	defer stop(r)
	freed := false
	for _ in 0 ..< 200 {
		s := &r.slots[tok.slot]
		sync.mutex_lock(&s.mu)
		if s.state == .Free {
			testing.expect_value(t, s.released_events, QUEUE_EVENTS)
			freed = true
		}
		sync.mutex_unlock(&s.mu)
		if freed {break}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, freed, "close must terminate and release queued items exactly once")
}

Racer :: struct {
	r:      ^Registry,
	tok:    Token,
	go_sem: ^sync.Sema,
	sent:   bool,
	thread: ^thread.Thread,
}

racer_main :: proc(x: ^Racer) {
	sync.sema_wait(x.go_sem)
	payload := [8]u8{}
	x.sent = try_send(x.r, x.tok, payload[:]) == .Sent
}

@(test)
producers_racing_the_final_slot_yield_exactly_one_sent :: proc(t: ^testing.T) {
	r := new(Registry)
	defer free(r)
	tok, ok := open_stream(r)
	testing.expect(t, ok)
	payload := [8]u8{}
	for _ in 0 ..< QUEUE_EVENTS - 1 {
		_ = try_send(r, tok, payload[:])
	}
	go_sem: sync.Sema
	racers: [4]Racer
	for &x in racers {
		x = Racer{r = r, tok = tok, go_sem = &go_sem}
		x.thread = thread.create_and_start_with_poly_data(&x, racer_main)
	}
	sync.sema_post(&go_sem, len(racers))
	winners := 0
	for &x in racers {
		thread.join(x.thread)
		thread.destroy(x.thread)
		if x.sent {winners += 1}
	}
	testing.expect_value(t, winners, 1)
	for &s in r.slots {delete(s.sink)}
}
