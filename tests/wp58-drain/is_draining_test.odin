// WP-6.5.3 — `is_draining`, the one readable bit of the lifecycle.
//
// A pure in-memory test: `stop` sets the drain bit even with no server running
// (the transport request is a no-op then, but the framework's own bit still
// flips), so the readiness contract can be proved without a socket. The socket
// side of shutdown is the rest of this package.
package wp58_drain

import "core:testing"
import web "uruquim:web"

@(test)
wp65_is_draining_is_false_until_stop :: proc(t: ^testing.T) {
	app := web.app()
	defer web.destroy(&app)

	// Before stop: a fresh application is ready, not draining.
	testing.expect(t, !web.is_draining(&app), "a fresh app must not report draining")

	web.stop(&app)

	// After stop: draining, so a readiness handler answers not-ready.
	testing.expect(t, web.is_draining(&app), "after stop the app must report draining")

	// Idempotent: a second stop does not change the answer, and never flips back.
	web.stop(&app)
	testing.expect(t, web.is_draining(&app), "draining must never return to false")
}
