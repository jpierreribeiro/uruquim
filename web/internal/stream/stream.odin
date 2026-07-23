// Private detached-stream contract — WP87 SENTINEL.
//
// This package fixes the SHAPE of the private streaming lifecycle selected by
// WP86 (candidate C: detached stream, stale-safe value token, bounded
// cross-lane delivery, owner-lane writer). Every procedure below is a
// deliberate `.Unimplemented` sentinel: the WP87 corpus compiles against this
// contract and fails RED for exactly that reason, under
// `build/check_wp87_controls.sh`. WP88 (registry), WP89 (cross-lane
// delivery) and WP95 (drain) replace bodies, never signatures, and flip the
// corpus green without editing a test.
//
// Nothing here is public surface: `web` does not import this package yet, so
// a buffered-only application links none of it (G7-8), and no name below is a
// ledger candidate (names freeze in WP101).
package uruquim_internal_stream

// The closed result of a bounded cross-thread send (phase-7-spec.md §3.1).
// `.Unimplemented` exists only while this sentinel does; the shipped enum
// loses it in WP89.
Send_Result :: enum {
	Unimplemented,
	Sent,
	Full,
	Closed,
	Stale,
}

// The typed outcome of opening a detached stream at the registry.
Open_Result :: enum {
	Unimplemented,
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
	max_streams:        int,
	max_events_stream:  int,
	max_bytes_stream:   int,
	max_bytes_total:    int,
	tick_progress:      int,
}

Registry :: struct {
	// Deliberately empty in the sentinel: WP88 owns the layout (contiguous
	// slots, explicit free list, generation — never a pointer graph).
	_reserved: int,
}

registry_init :: proc(r: ^Registry, cap: Capacity) -> bool {
	return false // sentinel: WP88
}

registry_destroy :: proc(r: ^Registry) {
	// sentinel: WP88
}

// open runs on the connection-owning lane, during dispatch.
open :: proc(r: ^Registry, connection_id: u64) -> (Token, Open_Result) {
	return Token{slot = -1}, .Unimplemented // sentinel: WP88
}

// try_send may run on any Handler lane or approved application thread. It
// validates the generation, reserves bounded capacity atomically, copies the
// bytes into stream-owned storage, publishes to the owner lane, wakes it and
// returns — never blocking, never touching the socket (WP89).
try_send :: proc(r: ^Registry, tok: Token, data: []u8) -> Send_Result {
	return .Unimplemented // sentinel: WP89
}

// close travels on reserved control capacity: it must be accepted even when
// every user slot is full, is idempotent, and invalidates the generation
// BEFORE queued items are released.
close :: proc(r: ^Registry, tok: Token) -> bool {
	return false // sentinel: WP88/WP89
}

// drain_begin stops admission (open refuses with .Draining) and signals every
// live stream through the control route; queued output is bounded by policy
// and `max_drain_time` stays the only process deadline (WP95).
drain_begin :: proc(r: ^Registry) {
	// sentinel: WP95
}

// Test-observable state, private to the corpus. The shipped implementation
// keeps these cheap (lane-owned or atomic reads); they never become public.
queued_events :: proc(r: ^Registry, tok: Token) -> int {
	return -1 // sentinel: WP88
}

live_streams :: proc(r: ^Registry) -> int {
	return -1 // sentinel: WP88
}
