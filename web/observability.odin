// WP50 — OBSERVABILITY: `refused_connections`.
//
// ONE SYMBOL, and it exists because §3.5 of the redaction policy demands it
// rather than because a counter felt useful:
//
//	**The drop policy is observable.** Any component that can discard records
//	must count what it discarded and expose the count, because a metric that
//	silently stops being emitted is worse than no metric — it reads as
//	"nothing happened".
//
// WP47 gave the framework the ability to refuse a connection. That is a
// discard, and until this symbol existed it was an invisible one: a server
// under admission pressure looked, from outside, exactly like a server nobody
// was talking to.
//
// WHY THIS AND NOT A METRICS API. A framework that exports a metrics
// abstraction has chosen a metrics vendor for its users, and the shape of that
// choice outlives the reasons for it. An integer an application reads and hands
// to whatever it already uses is the smallest thing that discharges the
// obligation. `web.observe` already covers framework FAILURES; this covers the
// one thing that is not a failure and not a request.
//
// WHAT IT IS NOT: a rate, a gauge, a histogram, or a reset. It is a running
// total for the life of the server, which is the shape every counter-scraping
// system already knows how to difference.
package web
// uruquim:file application

import transport "uruquim:web/internal/transport"

// refused_connections reports how many connections this process has refused for
// admission (WP47's `Limits.max_connections`) since the server started.
//
// Zero when no server is running, and zero when nothing has been refused —
// those two are deliberately not distinguished, because a caller that needs to
// tell them apart is asking whether a server is running, which is a different
// question this framework does not answer (WP44: there is no readable state).
//
// It carries no request-derived byte, which is what places it inside the
// redaction policy's permitted set (§3.1) rather than at its edge.
//
// It allocates nothing and reads one integer.
refused_connections :: proc() -> int {
	return transport.refused_connections()
}
