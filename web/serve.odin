// WP8 — CANONICAL SERVER ENTRY POINT AND THE RESPONSE DRIVER FINALIZATION.
//
// `serve` runs the real bootstrap HTTP server behind the private transport
// boundary. `serve_with` and `serve_transport` are Advanced API and remain
// absent from Phase 1.
package web

// serve runs the application's HTTP server on the given port.
//
// This is the canonical entry point. Transport selection is resolved inside
// the framework and is never part of the public API, which is what keeps the
// eventual move to the future official `core:net/http` package invisible to
// applications.
//
// WP8 RED STUB: still returns immediately and serves nothing. The bootstrap
// adapter is wired in the BOOTSTRAP commit.
serve :: proc(a: ^App, port: int) {
}

// driver_finalize guarantees a response driver never emits a zero status
// (WP8 D5).
//
// A dispatch can return with NOTHING committed: a handler that forgot to
// respond, or `bare()`'s deliberate no-policy on an unmatched route. HTTP has
// no zero status, so the DRIVER — `serve` and `test_request`, never a handler —
// turns that into a logged `internal_error`/500. This is a validity guarantee
// of the driver, not middleware and not an automatic route response: the core
// still installs no 404/405 under `bare()`.
//
// WP8 RED STUB: does nothing, so an uncommitted response stays uncommitted.
@(private)
driver_finalize :: proc(ctx: ^Context) {
}
