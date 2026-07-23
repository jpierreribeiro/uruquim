// Private opt-in large-body ingest contract — WP87 SENTINEL.
//
// Shape selected by WP86's ingest arms: bounded spool (arm F's append loop
// under arm G's admission). Chunks are appended where they arrive, admission
// is capped below Handler-lane capacity with a typed refusal BEFORE any body
// byte is read, and the ordinary synchronous Handler runs only once the body
// is Ready, receiving an explicitly owned spool. Quotas, permissions, naming
// and terminal outcomes are pre-registered in phase-7-spec.md §4.2
// (OQ-20 Amendment 1).
//
// Every procedure is a `.Unimplemented`/failure sentinel: the WP87 corpus
// fails RED against it under `build/check_wp87_controls.sh`. WP93 (spec/RED
// detail), WP94 (spool implementation) and WP95 (drain) replace bodies, never
// signatures. `web` does not import this package yet; the buffered path is
// untouched (G7-10) and no name below is a ledger candidate.
package uruquim_internal_ingest

// Typed terminal results of an opt-in large-body ingest (§4.2: every path
// has a pre-registered outcome; none is a silent 200 or a hang).
Ingest_Result :: enum {
	Unimplemented,
	Ready,
	Refused_Admission,
	Quota_Exceeded,
	Process_Quota_Exceeded,
	Disk_Full,
	Disconnected,
	Timed_Out,
	Cancelled_By_Drain,
}

// Pre-registered bounds (§4.2). Zero selects the registered default; the
// temp directory has no default — opting in requires designating one.
Spool_Config :: struct {
	dir:                string,
	per_upload_quota:   i64,
	process_quota:      i64,
	max_concurrent:     int,
	memory_prefix_max:  int,
}

Spool :: struct {
	// WP94 owns the layout. The corpus only sees the contract below.
	_reserved: int,
}

Admission :: struct {
	_reserved: int,
}

admission_init :: proc(a: ^Admission, cfg: Spool_Config) -> bool {
	return false // sentinel: WP94
}

admission_destroy :: proc(a: ^Admission) {
	// sentinel: WP94
}

// admit reserves one bounded ingest slot, or refuses before any byte is read.
admit :: proc(a: ^Admission) -> Ingest_Result {
	return .Unimplemented // sentinel: WP94
}

// begin opens the spool file: generated unpredictable `uruquim-spool-` name,
// 0600, inside cfg.dir — never the client filename, never a silent /tmp.
begin :: proc(a: ^Admission, s: ^Spool) -> Ingest_Result {
	return .Unimplemented // sentinel: WP94
}

// append consumes one arriving chunk, enforcing both quotas mid-body.
append_chunk :: proc(s: ^Spool, chunk: []u8) -> Ingest_Result {
	return .Unimplemented // sentinel: WP94
}

// finish makes the body Ready and hands ownership to exactly one consumer.
finish :: proc(s: ^Spool) -> Ingest_Result {
	return .Unimplemented // sentinel: WP94
}

// cancel is the single cleanup path for disconnect, timeout, quota breach and
// drain: the partial file is deleted exactly once; calling it twice is safe.
cancel :: proc(s: ^Spool, reason: Ingest_Result) -> bool {
	return false // sentinel: WP94
}

// persist transfers ownership out of the spool namespace (an explicit rename)
// — the only path that leaves a file behind (§4.2).
persist :: proc(s: ^Spool, destination: string) -> bool {
	return false // sentinel: WP94
}

// Test-observable state, private to the corpus.
active_spools :: proc(a: ^Admission) -> int {
	return -1 // sentinel: WP94
}

spooled_bytes :: proc(s: ^Spool) -> i64 {
	return -1 // sentinel: WP94
}
