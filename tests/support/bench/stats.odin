// WP26 benchmark harness — the statistics half.
//
// This package is TEST SUPPORT. It lives under `tests/` for one measured
// reason (FINDING-B): WP6 measured `core:log` at ~37 KiB added to every
// application, referenced or not, because Odin links an imported package
// whether it is used or not. `core:time` would cost the same. A benchmark that
// made every application carry a clock would have changed the thing it exists
// to measure, so the harness can never live in `package web`.
//
// WHAT THIS FILE REFUSES TO DO, and why it matters more than what it does:
//
// It never reports a single number for a timing. FINDING-A measured five
// builds of an IDENTICAL source tree producing five different binaries, because
// the vendored `nbio` emits polymorphic instantiations whose mangled parameter
// names vary between runs. If the LINKER is nondeterministic then code layout
// is too, and layout moves branch prediction and cache behaviour. A single
// "X is 8% faster" reading on this toolchain is not evidence.
//
// So every timing here is a DISTRIBUTION — p50, p95, p99, min, max and n — and
// the tolerance a later work package regresses against is DERIVED from the
// machine (see `spread`, and `planning/benchmark-methodology.md`) rather than
// chosen by taste.
package bench_support

import "core:slice"

// Samples collects per-operation durations in nanoseconds.
//
// OWNERSHIP: the caller creates it, the caller destroys it. `ns` is owned by
// this struct and freed by `samples_destroy` exactly once. Copying a Samples
// value would alias the backing array and double-free; take a pointer, the way
// the framework's own App contract requires.
//
// CAPACITY: `ns` grows by ordinary `append` and is NOT bounded. That is
// deliberate and safe here — a benchmark run has a known iteration count and
// `samples_init` reserves it up front, so the measured loop performs no
// allocation. If a caller adds more samples than it reserved, the array grows
// and that growth lands inside the measured region. `samples_init` therefore
// takes the count rather than guessing it.
Samples :: struct {
	ns: [dynamic]i64,
}

// samples_init reserves capacity for exactly `expected` samples.
//
// Reserving is not an optimisation, it is a correctness requirement: an
// `append` that reallocates inside the timed loop would be measured as part of
// the operation under test.
samples_init :: proc(s: ^Samples, expected: int) -> bool {
	ns, err := make([dynamic]i64, 0, expected)
	if err != nil {
		return false
	}
	s.ns = ns
	return true
}

samples_destroy :: proc(s: ^Samples) {
	delete(s.ns)
	s.ns = nil
}

samples_add :: proc(s: ^Samples, ns: i64) {
	append(&s.ns, ns)
}

samples_count :: proc(s: ^Samples) -> int {
	return len(s.ns)
}

// Summary is the only shape in which this harness reports a timing.
//
// There is no `mean` field, and that is a decision rather than an omission: a
// mean hides the tail, and the tail is the entire question for a request
// pipeline. p99 is what an operator feels.
Summary :: struct {
	n:   int,
	min: i64,
	p50: i64,
	p95: i64,
	p99: i64,
	max: i64,
}

// summarize sorts `s` in place and returns its distribution.
//
// Sorting in place is documented rather than hidden: the caller's sample order
// is destroyed, and no caller in this harness needs it afterwards.
summarize :: proc(s: ^Samples) -> (summary: Summary, ok: bool) {
	if len(s.ns) == 0 {
		return {}, false
	}
	slice.sort(s.ns[:])
	return Summary {
			n = len(s.ns),
			min = s.ns[0],
			p50 = percentile_sorted(s.ns[:], 50),
			p95 = percentile_sorted(s.ns[:], 95),
			p99 = percentile_sorted(s.ns[:], 99),
			max = s.ns[len(s.ns) - 1],
		},
		true
}

// percentile_sorted returns the p-th percentile of an ALREADY SORTED slice,
// using nearest-rank.
//
// Nearest-rank is chosen over interpolation because it always returns a value
// that was actually observed. An interpolated p99 is a number the machine never
// produced, and this project does not report those.
percentile_sorted :: proc(sorted: []i64, p: int) -> i64 {
	if len(sorted) == 0 {
		return 0
	}
	// Nearest-rank: ceil(p/100 * n), clamped into range, then zero-indexed.
	rank := (p * len(sorted) + 99) / 100
	if rank < 1 {
		rank = 1
	}
	if rank > len(sorted) {
		rank = len(sorted)
	}
	return sorted[rank - 1]
}

// spread returns the observed range of a statistic across repeated runs, in
// basis points of the smallest run (1 bp = 0.01%).
//
// THIS IS THE TOLERANCE DERIVATION, and it is the reason this procedure exists
// rather than a constant somewhere. WP26's rule: run the unchanged baseline at
// least ten times in alternating order and take the observed p95 spread as the
// tolerance floor. A later change counts as a regression only when it exceeds
// that floor.
//
// The number therefore comes from the machine, and it is RE-DERIVED rather than
// inherited whenever the hardware changes. An earlier draft of the plan said
// the tolerance was "measured, not chosen" without saying how, which in
// practice is an instruction to pick a number and call it measured.
//
// Basis points rather than nanoseconds because the floor must survive a move to
// a faster machine, where every absolute figure changes and the relative noise
// largely does not.
spread :: proc(values: []i64) -> (bp: i64, ok: bool) {
	if len(values) < 2 {
		return 0, false
	}
	lo := values[0]
	hi := values[0]
	for v in values[1:] {
		if v < lo {
			lo = v
		}
		if v > hi {
			hi = v
		}
	}
	if lo <= 0 {
		return 0, false
	}
	return ((hi - lo) * 10_000) / lo, true
}
