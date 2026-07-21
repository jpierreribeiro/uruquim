// WP44 — LIFECYCLE: `stop`.
//
// ONE SYMBOL, and the deadline is a `Limits` FIELD rather than a second name.
// The Phase-4 plan gave this package a budget of two concepts (the WP38 usage
// lab measured 23 of 25), and this spends one on the verb and one on a field
// that costs no name at all — the WP46 precedent, for the same reason: a public
// options struct already exists, and a second way to configure a bound would be
// a second answer to one question (G-01).
//
// WHAT `stop` DOES, in the vocabulary the WP39 spec fixed:
//
//	Serving  →  Draining  →  Stopped
//
// Admission ceases immediately; work already in flight is allowed to finish;
// and when `Limits.max_drain_time` passes, whatever is left is closed anyway.
// **"Wait forever" is not a deadline**, and waiting forever is precisely what
// the vendored server did before this package — its drain loop waits on active
// connections with no bound, so one handler that never returns held the process
// open and the only shutdown was a kill.
//
// WHAT IT DELIBERATELY IS NOT. There is no `pause`, no `resume`, and no
// `Draining → Serving`: a client refused during the drain has already gone
// elsewhere, and an operator who asked for a stop meant it. There is also no
// public way to READ the state. An application that needs to know whether it is
// draining is asking a question the framework answers by refusing its requests,
// and a readable state invites a poll loop where a supervisor belongs.
package web
// uruquim:file application

import transport "uruquim:web/internal/transport"

// stop asks the running server to stop serving.
//
// It returns IMMEDIATELY. `stop` is a request, not a join: the drain happens on
// the server's own event loop, and the call that is blocked in `web.serve`
// returns when the drain completes. **That is the shape a signal handler needs**
// — a stop that blocked could not be called from one — and it is why the
// obvious alternative, making this wait, would make it unusable for the case it
// exists to serve.
//
// SAFE FROM ANOTHER THREAD, and safe to call twice. The backend's shutdown is
// an atomic flag plus an event-loop wake-up, so a second `stop` while the first
// is draining is a no-op rather than a second drain — which is what makes
// "cleanup runs exactly once" true rather than hoped for (spec §1.3 obligation
// 4). Calling it when no server is running is also a no-op.
//
// IT DOES NOT DESTROY THE APP. `stop` ends the server; `destroy` releases the
// application's storage, exactly as it always did, and the two are separate for
// the reason they have always been separate: an App outlives a `serve` call, and
// merging them would make `stop` a teardown you cannot call from a signal
// handler.
stop :: proc(a: ^App) {
	// The App is taken by pointer for symmetry with every other operation and
	// for what it makes possible later — a process may run one server today
	// (R-10), but a `stop` that ignored its App could never become per-server
	// without changing its signature, and a frozen signature cannot change.
	_ = a
	transport.request_stop()
}
