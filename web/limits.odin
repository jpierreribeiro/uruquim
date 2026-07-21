// WP36 — CONFIGURABLE LIMITS: `Limits`, `DEFAULT_LIMITS`, `limits`.
//
// THREE SYMBOLS, and the ledger moves 47 → 50. This is the least reversible
// change in Phase 3 and the file says so at the top: a public struct is a
// promise per FIELD. Once an application writes `max_body`, removing or
// renaming that field breaks its build, and tightening a DEFAULT breaks its
// traffic without breaking its build — which is worse. Adding a field later is
// cheap. That asymmetry is the entire argument for the size of this struct.
//
// THE SHAPE IS `core:net`'s. An options struct plus a package default
// CONSTANT — `DEFAULT_TCP_OPTIONS` is the precedent — and not a builder, not a
// setter per field, not a general system specification. The vendored backend's
// own `Default_Server_Opts` is a mutable package VARIABLE, and that is the
// counter-example rather than the model: a global anyone can assign is a
// setting whose value depends on who ran last.
//
// WHY IT ATTACHES TO THE APP AND NOT TO `serve`. `test_request` never calls
// `serve`, and R-10 is the property both transports exist to keep. If the body
// cap lived on `serve`, an in-memory test would answer 200 where a socket
// answers 413 — on exactly the boundary a test suite is supposed to prove. The
// limits therefore travel with the application, and `serve` DERIVES the
// backend's options from them.
//
// AMENDED BY WP46 (2026-07-21): THE REQUEST DEADLINE NOW EXISTS.
//
// WP36 shipped this struct with three byte budgets and no time budget, and said
// why: the vendored server had no deadline to configure, and a field that
// silently did nothing would have been a lie with a version number on it. That
// was true and it was a hole — WP41's fault laboratory then DEMONSTRATED it,
// holding a connection open indefinitely with one trickling client.
//
// `max_request_time` closes it. ADR-031 fixed the requirement; ADR-033 left the
// mechanism to this package; and the mechanism turned out to be a single
// vendored patch — a periodic sweep beside the server's existing date tick —
// governed by WP51's policy, which is why that package moved ahead of this one.
//
// STILL NOT HERE, and stated so nobody infers it: a WRITE deadline, and any
// bound on a slow HANDLER. The first is a smaller version of the same patch and
// is deliberately not bundled with a security fix; the second is not a deadline
// the framework should own, because a slow handler is the application's own
// time and killing its connection turns a slow page into a broken one.
package web
// uruquim:file application

// Limits is the application's byte budget for one request.
//
// It bounds URUQUIM'S OWN per-request working memory. It does NOT bound the
// server: connections, accept backlog, the number of inbound headers and total
// process memory are the transport's and the operating system's, and no
// document may say otherwise because this type exists.
//
// EVERY FIELD IS A PROMISE. There are six, and each is here because something
// downstream already enforces it — not because a tuning surface felt
// incomplete. A field with no enforcement behind it would be a knob that lies.
Limits :: struct {
	// The largest request body `web.body` will decode, in bytes. Exactly this
	// many is allowed; a strictly larger body is answered 413 and never reaches
	// the arena or the parser. Enforced on the SHARED request path, so the
	// in-memory transport and the socket agree by construction (R-10).
	max_body:         int,

	// The largest request line — the first line, carrying the method, target
	// and version. RFC 7230 §3.1.1 recommends supporting at least 8000 octets
	// and specifies no maximum; the backend enforces this one.
	max_request_line: int,

	// The largest header block, in bytes. Same status as the request line: a
	// practical limit the spec declines to set, enforced by the backend.
	max_headers:      int,

	// WP46 / ADR-031 — how long ONE request may take to ARRIVE, from its first
	// byte to its last, in nanoseconds. Zero means no deadline.
	//
	// A REQUEST deadline, not an idle timeout, and the difference is the whole
	// defence: an idle timer is reset by every byte, so a client trickling one
	// byte per second resets it forever. This bounds the total time a request
	// may take to arrive, which is what makes slowloris finite.
	//
	// IT DOES NOT BOUND A HANDLER. A slow handler is the application's own
	// time, and killing its connection would turn a slow page into a broken
	// one. The clock starts when a request begins arriving and stops when it
	// has arrived.
	//
	// The type is `i64` nanoseconds rather than `time.Duration` for a measured
	// reason: `package web` may not import `core:time` (FINDING-B — an
	// application would link a clock because the framework configures one), and
	// `time.Duration` is that package's type. The transport converts at the
	// boundary, where a clock is already linked.
	max_request_time: i64,

	// WP47 — the maximum number of concurrent connections the server will hold.
	// Zero means unbounded, which is what shipped before this field existed.
	//
	// WITHOUT IT, connections are bounded only by the operating system's
	// file-descriptor limit — and reaching that limit is not a graceful
	// degradation. It is an `accept` failing for a reason the server did not
	// choose, at a moment it did not choose. **A server that refuses a
	// connection is degraded and honest; one that accepts everything until the
	// kernel stops it has a failure mode that is an accident.**
	max_connections:  int,

	// WP47 / WP40 — connection slots held back from ADMISSION so that a
	// shutdown always has room to work in.
	//
	// **Admission is refused at or below `max_connections - reserved_conns`,
	// never at zero**, and that inequality is the whole reservation rule: the
	// fatal failure is not running out of capacity, it is running out and
	// having none left to shut down with. A server that is full and cannot
	// drain is a process an operator must kill.
	//
	// Ignored when `max_connections` is zero — there is nothing to reserve from
	// an unbounded pool.
	reserved_conns:   int,
}

// DEFAULT_LIMITS is what every application gets without asking.
//
// The values are the SHIPPED ones, not new opinions: 4 MiB is the body cap
// Phase 1 fixed and the capacity ledger has recorded since, and 8000 is the
// vendored backend's own default for both text limits. This constant therefore
// changes nothing for an application that never mentions it — which is the
// property that makes shipping it safe.
//
// It is a CONSTANT. Assigning to it is a compile error, so a library cannot
// change another library's defaults, and two applications in one process cannot
// disagree about what "default" means.
DEFAULT_LIMITS :: Limits {
	max_body         = BODY_LIMIT,
	max_request_line = REQUEST_LINE_LIMIT,
	max_headers      = HEADER_BLOCK_LIMIT,
	max_request_time = REQUEST_TIME_LIMIT,
	max_connections  = CONNECTION_LIMIT,
	reserved_conns   = RESERVED_CONNECTION_LIMIT,
}

// REQUEST_LINE_LIMIT and HEADER_BLOCK_LIMIT are the vendored backend's own
// defaults, restated here so `DEFAULT_LIMITS` does not silently inherit a
// number from a package the public surface must never name (G-06).
@(private)
REQUEST_LINE_LIMIT :: 8000

@(private)
HEADER_BLOCK_LIMIT :: 8000

// REQUEST_TIME_LIMIT is thirty seconds, in nanoseconds.
//
// THE NUMBER IS JUDGEMENT AND IS RECORDED AS SUCH (the C-5 honesty rule): no
// specification sets it, and the sources that discuss slowloris name the
// technique and no figure. Thirty seconds is chosen to be far longer than any
// legitimate client needs to send a request over a working network — a large
// upload is bounded by `max_body`, not by this — and far shorter than the
// "forever" that shipped before WP46.
//
// It is the first default in this framework that CHANGES BEHAVIOUR for an
// application that never mentions limits: a connection that would previously
// have been held open indefinitely is now closed. That is the point, it is a
// security fix rather than a tuning knob, and the capacity ledger records it.
@(private)
REQUEST_TIME_LIMIT :: i64(30 * 1_000_000_000)

// CONNECTION_LIMIT and RESERVED_CONNECTION_LIMIT are the admission budget.
//
// JUDGEMENT, RECORDED AS SUCH. 1024 sits comfortably below a typical default
// file-descriptor limit — and the process needs descriptors for more than
// sockets — so the framework's own refusal arrives BEFORE the kernel's. That
// ordering is the entire point of having a limit rather than inheriting one.
//
// 16 reserved is small on purpose: enough for a drain to close what is open and
// write final responses, large enough not to be a rounding error. It is a slot
// count, not a rate.
@(private)
CONNECTION_LIMIT :: 1024

@(private)
RESERVED_CONNECTION_LIMIT :: 16



// LIMITS_MIN_BODY, LIMITS_MIN_TEXT are the floors validation enforces.
//
// They are ONE, not a taste. A zero or negative budget is not a strict
// configuration, it is an application that answers 413 to every request with a
// body — and an operator who typed `Limits{max_body = 1024}` deserves that
// value, while one who left a field at its zero value has almost certainly
// forgotten it. The struct has no "unset" state to distinguish those, so the
// zero value is refused rather than guessed at.
@(private)
LIMITS_MIN_BODY :: 1

@(private)
LIMITS_MIN_TEXT :: 1

// limits sets the application's byte budget.
//
// Call it BEFORE the first request; after that the application is rejected
// fail-closed. Registration order relative to routes and middleware does not
// matter — a limit protects every route equally, so there is no ordering
// hazard of the kind ADR-019 exists for.
//
// THE CONCURRENCY DECISION, recorded here because this is where the snapshot is
// taken. Limits are read on the request path, so a change during serving would
// be a data race and, worse, a request-dependent one: two clients could get two
// different answers to the same body. Rather than make that impossible by
// construction — which would mean a second immutable App type — this REJECTS
// it, through the mechanism ADR-019 and ADR-023 already use. The snapshot model
// therefore SITS BESIDE those guards and does not replace them: `use()` after
// the first dispatch is still refused for its own reason, and this refusal adds
// a second offence rather than subsuming the first. Nothing shipped becomes
// weaker.
//
// A ZERO OR NEGATIVE FIELD IS REJECTED the same way. It allocates nothing and
// stores three integers.
limits :: proc(a: ^App, l: Limits) {
	if a.private.poisoned {
		// Already rejected and already reported; the first diagnosis stands.
		return
	}
	if a.private.dispatched {
		limits_poison(a, FRAMEWORK_MESSAGE_LIMITS_AFTER_DISPATCH)
		return
	}
	// `max_request_time` is validated as NON-NEGATIVE rather than positive,
	// because zero has a meaning here that the byte budgets do not have: no
	// deadline. An operator who wants the old behaviour must be able to ask for
	// it explicitly — and asking explicitly is exactly the difference between a
	// deliberate choice and a forgotten field.
	// Negative is refused everywhere; zero means "unbounded" for the admission
	// fields, as it does for the deadline.
	if l.max_connections < 0 || l.reserved_conns < 0 {
		limits_poison(a, FRAMEWORK_MESSAGE_LIMITS_INVALID)
		return
	}
	// A reservation that swallows its own budget would refuse EVERY connection
	// while looking like a configuration. Caught at BOOT, where an operator is
	// watching, rather than at 3 a.m. as a server that accepts nothing.
	if l.max_connections > 0 && l.reserved_conns >= l.max_connections {
		limits_poison(a, FRAMEWORK_MESSAGE_LIMITS_RESERVATION)
		return
	}
	if l.max_request_time < 0 {
		limits_poison(a, FRAMEWORK_MESSAGE_LIMITS_INVALID)
		return
	}
	if l.max_body < LIMITS_MIN_BODY ||
	   l.max_request_line < LIMITS_MIN_TEXT ||
	   l.max_headers < LIMITS_MIN_TEXT {
		limits_poison(a, FRAMEWORK_MESSAGE_LIMITS_INVALID)
		return
	}

	a.private.limits = l
}

// limits_poison rejects the application with a static diagnostic, reusing the
// WP17/WP18 mechanism rather than inventing a second one.
@(private)
limits_poison :: proc(a: ^App, message: string, loc := #caller_location) {
	a.private.poisoned = true

	logger := context.logger
	if logger.procedure == nil {
		return
	}
	logger.procedure(logger.data, .Error, message, logger.options, loc)
}
