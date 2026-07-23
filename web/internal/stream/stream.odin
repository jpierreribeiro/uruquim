// Private detached-stream lifecycle — implemented by WP88 (registry,
// stale-safe identity) and WP89 (cross-lane bounded delivery) against the
// contract the WP87 corpus committed RED.
//
// Shape selected by WP86 (candidate C) and bound by ADR-044:
//   - contiguous slots, an explicit free list and a generation counter —
//     never a pointer graph; a Token is a value that cannot expose registry
//     memory or an adapter handle;
//   - try_send may run on ANY Handler lane or approved application thread:
//     validate generation → reserve bounded capacity → copy into
//     stream-owned storage → publish → wake the owner → return a closed
//     typed result. It never blocks and never touches a socket;
//   - close travels on reserved control capacity (accepted against a full
//     queue), is idempotent, and invalidates the generation BEFORE queued
//     items are released;
//   - the wakeup is executor-agnostic (phase-7-spec.md §6.3): a procedure
//     value installed at init, so nothing here assumes the producer or the
//     owner is a Handler lane;
//   - capacities are the §4.1 pre-registered defaults; zero selects them.
//
// Still not imported by `web` (that wiring is WP90); a buffered-only binary
// links none of this, and no name here is a ledger candidate (WP101).
package uruquim_internal_stream

import "core:mem"
import "core:sync"

// The closed result of a bounded cross-thread send.
Send_Result :: enum {
	Unimplemented, // retained for ABI stability with the WP87 corpus; no code path returns it since WP89
	Sent,
	Full,
	Closed,
	Stale,
}

// The typed outcome of opening a detached stream at the registry.
Open_Result :: enum {
	Unimplemented, // as above: kept, never returned since WP88
	Opened,
	At_Capacity,
	Draining,
}

// A value token: never a pointer into registry memory (ADR-044). A delayed
// holder of an old token must be refused after slot reuse.
Token :: struct {
	slot:       i32,
	generation: u64,
}

// Pre-registered capacity contract (phase-7-spec.md §4.1). Zero means "use
// the registered default", mirroring the Limits convention.
Capacity :: struct {
	max_streams:       int,
	max_events_stream: int,
	max_bytes_stream:  int,
	max_bytes_total:   int,
	tick_progress:     int,
}

// §4.1 registered defaults.
DEFAULT_MAX_STREAMS :: 1024
DEFAULT_MAX_EVENTS_STREAM :: 64
DEFAULT_MAX_BYTES_STREAM :: 256 * 1024
DEFAULT_MAX_BYTES_TOTAL :: 16 * 1024 * 1024
DEFAULT_TICK_PROGRESS :: 64 * 1024

// The executor-agnostic wakeup hook: installed at init, called after publish.
Wake_Proc :: proc(user: rawptr)

@(private)
Slot_State :: enum u8 {
	Free,
	Open,
	Closing,
}

// One queued event: an (offset, len) view into the slot's ring storage.
@(private)
Event :: struct {
	offset: int,
	len:    int,
}

@(private)
Slot :: struct {
	mu:              sync.Mutex,
	generation:      u64,
	state:           Slot_State,
	connection_id:   u64,
	close_requested: bool,
	// Bounded FIFO of events over a circular byte store, both allocated once
	// at init. `bytes_head` is where the oldest event's bytes begin.
	events:          []Event,
	events_head:     int,
	events_count:    int,
	store:           []u8,
	store_head:      int,
	store_used:      int, // includes wrap gaps, so reservation stays honest
}

Registry :: struct {
	slots:        []Slot,
	free_list:    []i32,
	free_top:     int,
	free_mu:      sync.Mutex,
	live:         int, // guarded by free_mu; corpus-observable
	total_bytes:  int, // atomic: process-wide queued-byte reservation
	draining:     bool, // atomic
	cap:          Capacity,
	wake:         Wake_Proc,
	wake_user:    rawptr,
	allocator:    mem.Allocator,
	initialized:  bool,
}

resolve :: proc(cap: Capacity) -> Capacity {
	c := cap
	if c.max_streams <= 0 {c.max_streams = DEFAULT_MAX_STREAMS}
	if c.max_events_stream <= 0 {c.max_events_stream = DEFAULT_MAX_EVENTS_STREAM}
	if c.max_bytes_stream <= 0 {c.max_bytes_stream = DEFAULT_MAX_BYTES_STREAM}
	if c.max_bytes_total <= 0 {c.max_bytes_total = DEFAULT_MAX_BYTES_TOTAL}
	if c.tick_progress <= 0 {c.tick_progress = DEFAULT_TICK_PROGRESS}
	return c
}

registry_init :: proc(r: ^Registry, cap: Capacity, wake: Wake_Proc = nil, wake_user: rawptr = nil) -> bool {
	if r.initialized {
		return false
	}
	c := resolve(cap)
	r.allocator = context.allocator
	slots, s_err := make([]Slot, c.max_streams, r.allocator)
	if s_err != nil {
		return false
	}
	free_list, f_err := make([]i32, c.max_streams, r.allocator)
	if f_err != nil {
		delete(slots, r.allocator)
		return false
	}
	for &s, i in slots {
		events, e_err := make([]Event, c.max_events_stream, r.allocator)
		store, b_err := make([]u8, c.max_bytes_stream, r.allocator)
		if e_err != nil || b_err != nil {
			// Unwind whatever was allocated; init is all-or-nothing.
			if e_err == nil {delete(events, r.allocator)}
			if b_err == nil {delete(store, r.allocator)}
			for j in 0 ..< i {
				delete(slots[j].events, r.allocator)
				delete(slots[j].store, r.allocator)
			}
			delete(slots, r.allocator)
			delete(free_list, r.allocator)
			return false
		}
		s.events = events
		s.store = store
	}
	// Explicit free list, filled so the LOWEST slot is handed out first —
	// deterministic reuse, which the forced-tiny-capacity tests rely on.
	for i in 0 ..< c.max_streams {
		free_list[i] = i32(c.max_streams - 1 - i)
	}
	r.slots = slots
	r.free_list = free_list
	r.free_top = c.max_streams
	r.live = 0
	r.total_bytes = 0
	r.draining = false
	r.cap = c
	r.wake = wake
	r.wake_user = wake_user
	r.initialized = true
	return true
}

registry_destroy :: proc(r: ^Registry) {
	if !r.initialized {
		return
	}
	for &s in r.slots {
		delete(s.events, r.allocator)
		delete(s.store, r.allocator)
	}
	delete(r.slots, r.allocator)
	delete(r.free_list, r.allocator)
	r^ = Registry{}
}

// open runs on the connection-owning lane, during dispatch (WP90 wires it).
open :: proc(r: ^Registry, connection_id: u64) -> (Token, Open_Result) {
	if !r.initialized {
		return Token{slot = -1}, .At_Capacity
	}
	if sync.atomic_load(&r.draining) {
		return Token{slot = -1}, .Draining
	}
	sync.mutex_lock(&r.free_mu)
	if r.free_top == 0 {
		sync.mutex_unlock(&r.free_mu)
		return Token{slot = -1}, .At_Capacity
	}
	r.free_top -= 1
	idx := r.free_list[r.free_top]
	r.live += 1
	sync.mutex_unlock(&r.free_mu)

	s := &r.slots[idx]
	sync.mutex_lock(&s.mu)
	s.state = .Open
	s.connection_id = connection_id
	s.close_requested = false
	s.events_head = 0
	s.events_count = 0
	s.store_head = 0
	s.store_used = 0
	tok := Token{slot = idx, generation = s.generation}
	sync.mutex_unlock(&s.mu)
	return tok, .Opened
}

// try_send: the WP89 six-step contract. Any thread; never blocks; never
// touches the socket; no mutex is held during any socket write because no
// socket write happens here at all — the owner lane drains separately.
try_send :: proc(r: ^Registry, tok: Token, data: []u8) -> Send_Result {
	if !r.initialized || tok.slot < 0 || int(tok.slot) >= len(r.slots) {
		return .Stale
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	// 1. validate the generation while holding the slot.
	if s.generation != tok.generation {
		sync.mutex_unlock(&s.mu)
		return .Stale
	}
	if s.state != .Open || s.close_requested || sync.atomic_load(&r.draining) {
		sync.mutex_unlock(&s.mu)
		return .Closed
	}
	// 2. reserve bounded capacity: event slot, per-stream bytes, then the
	//    process-wide byte budget (reserve-then-check keeps it atomic).
	if s.events_count >= len(s.events) {
		sync.mutex_unlock(&s.mu)
		return .Full
	}
	needed, gap := store_reserve(s, len(data))
	if needed < 0 {
		sync.mutex_unlock(&s.mu)
		return .Full
	}
	if sync.atomic_add(&r.total_bytes, needed) + needed > r.cap.max_bytes_total {
		sync.atomic_sub(&r.total_bytes, needed)
		sync.mutex_unlock(&s.mu)
		return .Full
	}
	// 3. copy into stream-owned storage. When a wrap gap was reserved, the
	// modular arithmetic lands the event exactly at the store's origin:
	// tail + gap ≡ 0 (mod len).
	offset := (s.store_head + s.store_used + gap) % len(s.store)
	copy(s.store[offset:offset + len(data)], data)
	// 4. publish to the owner lane's FIFO.
	e := &s.events[(s.events_head + s.events_count) % len(s.events)]
	e.offset = offset
	e.len = len(data)
	s.events_count += 1
	s.store_used += needed
	sync.mutex_unlock(&s.mu)
	// 5. wake the owner (outside the lock).
	if r.wake != nil {
		r.wake(r.wake_user)
	}
	// 6. a closed typed result.
	return .Sent
}

// store_reserve computes how many ring bytes an event of `size` needs
// (payload plus any wrap gap) without mutating the slot, returning -1 when
// the per-stream byte cap refuses. Caller holds s.mu.
@(private)
store_reserve :: proc(s: ^Slot, size: int) -> (needed: int, gap: int) {
	if size > len(s.store) {
		return -1, 0
	}
	tail := (s.store_head + s.store_used) % len(s.store)
	gap = 0
	if tail + size > len(s.store) {
		// Not enough contiguous space at the tail: skip to the origin.
		gap = len(s.store) - tail
	}
	needed = size + gap
	if s.store_used + needed > len(s.store) {
		return -1, 0
	}
	return needed, gap
}

// close: reserved control capacity — accepted against a full queue, safe to
// repeat. The generation advances the moment close is accepted, BEFORE any
// queued item is released (ADR-044 §3): from that instant the old token is
// stale everywhere.
close :: proc(r: ^Registry, tok: Token) -> bool {
	if !r.initialized || tok.slot < 0 || int(tok.slot) >= len(r.slots) {
		return false
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	if s.generation != tok.generation {
		// Already closed under this token (idempotent) — or a genuinely
		// foreign token. Idempotence wins: a repeated close of a slot this
		// token once owned must be a safe no-op, and a foreign token cannot
		// distinguish itself from history without exposing registry memory.
		sync.mutex_unlock(&s.mu)
		return true
	}
	if s.state == .Free {
		sync.mutex_unlock(&s.mu)
		return true
	}
	s.generation += 1 // stale-safety first…
	s.close_requested = true
	s.state = .Closing
	released := release_queued(r, s) // …then release, exactly once
	s.state = .Free
	s.close_requested = false
	sync.mutex_unlock(&s.mu)

	sync.mutex_lock(&r.free_mu)
	r.free_list[r.free_top] = tok.slot
	r.free_top += 1
	r.live -= 1
	sync.mutex_unlock(&r.free_mu)

	_ = released
	if r.wake != nil {
		r.wake(r.wake_user)
	}
	return true
}

// release_queued drops every queued event and returns the byte total handed
// back to the process budget. Caller holds s.mu. This is the single release
// path close, drain and (later) adapter-error teardown share — exactly once
// by construction, because the queue is emptied under the lock.
@(private)
release_queued :: proc(r: ^Registry, s: ^Slot) -> int {
	freed := s.store_used
	s.events_head = 0
	s.events_count = 0
	s.store_head = 0
	s.store_used = 0
	if freed > 0 {
		sync.atomic_sub(&r.total_bytes, freed)
	}
	return freed
}

// drain_begin stops admission and refuses further output; WP95 wires it into
// the process lifecycle so `max_drain_time` stays the only deadline.
drain_begin :: proc(r: ^Registry) {
	if !r.initialized {
		return
	}
	sync.atomic_store(&r.draining, true)
	if r.wake != nil {
		r.wake(r.wake_user)
	}
}

// --- owner-lane consumption (WP90 wires the real writer to these) ----------

// next_event exposes the oldest queued event's bytes to the OWNER LANE ONLY.
// The view is valid until complete_event; no lock is held by the caller
// between the two, but only the owner lane may call them, which is the
// single-writer contract (G7-2) — enforced by construction in the adapter.
next_event :: proc(r: ^Registry, tok: Token) -> (data: []u8, ok: bool) {
	if !r.initialized || tok.slot < 0 || int(tok.slot) >= len(r.slots) {
		return nil, false
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation || s.events_count == 0 {
		return nil, false
	}
	e := s.events[s.events_head]
	return s.store[e.offset:e.offset + e.len], true
}

// complete_event releases the oldest event after the owner lane wrote it.
complete_event :: proc(r: ^Registry, tok: Token) -> bool {
	if !r.initialized || tok.slot < 0 || int(tok.slot) >= len(r.slots) {
		return false
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation || s.events_count == 0 {
		return false
	}
	e := s.events[s.events_head]
	// Advance the byte head past the event, absorbing any wrap gap the
	// reservation inserted before it.
	consumed := e.len
	if e.offset == 0 && s.store_head != 0 {
		consumed += len(s.store) - s.store_head // the gap that forced the wrap
	}
	s.store_head = (e.offset + e.len) % len(s.store)
	s.store_used -= consumed
	if s.store_used == 0 {
		s.store_head = 0
	}
	s.events_head = (s.events_head + 1) % len(s.events)
	s.events_count -= 1
	sync.atomic_sub(&r.total_bytes, consumed)
	return true
}

// --- corpus-observable state ------------------------------------------------

queued_events :: proc(r: ^Registry, tok: Token) -> int {
	if !r.initialized || tok.slot < 0 || int(tok.slot) >= len(r.slots) {
		return -1
	}
	s := &r.slots[tok.slot]
	sync.mutex_lock(&s.mu)
	defer sync.mutex_unlock(&s.mu)
	if s.generation != tok.generation {
		return -1
	}
	return s.events_count
}

live_streams :: proc(r: ^Registry) -> int {
	if !r.initialized {
		return -1
	}
	sync.mutex_lock(&r.free_mu)
	defer sync.mutex_unlock(&r.free_mu)
	return r.live
}
