// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the canonical server entry point. It opens no socket,
// selects no transport, and runs no event loop. `serve_with` and
// `serve_transport` are Advanced API and are deliberately absent from Phase 1.
package web

// serve runs the application's HTTP server on the given port.
//
// This is the canonical entry point. Transport selection is resolved inside
// the framework and is never part of the public API, which is what keeps the
// eventual move to the future official `core:net/http` package invisible to
// applications.
//
// WP1 STUB: RETURNS IMMEDIATELY AND SERVES NOTHING. No port is bound, no
// connection is accepted, and no request is dispatched. WP8 introduces the
// bootstrap transport adapter behind the internal boundary; WP3 provides the
// in-memory test transport used before then.
serve :: proc(a: ^App, port: int) {
}
