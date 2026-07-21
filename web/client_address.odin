// WP48 — TRUSTED PROXIES: `client_ip` and `trust_proxies`.
//
// TWO SYMBOLS, and the pair is the point. ADR-013 accepted the fail-closed arm:
// **the effective address is the connected peer, and forwarding headers are
// ignored until trusted proxies are explicitly configured.** One symbol without
// the other would be either a value you cannot use behind a proxy, or a value
// you cannot trust.
//
// WHY THIS IS A SECURITY DECISION AND NOT AN ERGONOMIC ONE. `X-Forwarded-For`
// is a request header. Any client can send one. A framework that reads it by
// default hands every attacker a free choice of identity — and the things
// applications do with a client address are exactly the things you must not let
// an attacker choose: rate-limit buckets, audit logs, allow-lists, geo rules,
// abuse counters. **Trusting the header by default is not a convenience with a
// caveat; it is an authorization bypass with a default.**
//
// SO THE DEFAULT IS THE PEER, ALWAYS. An application deployed directly sees the
// truth. An application behind a proxy sees the proxy until it says which
// proxies it has, at which point it sees what those proxies report — and only
// then.
package web
// uruquim:file application

import "core:strings"

// TRUSTED_PROXY_MAX is how many trusted proxy prefixes an application may
// register.
//
// A fixed inline array rather than a dynamic one, for the reason the rest of
// this framework uses fixed arrays: it is request-path state read on every
// request, and a bound that is enforced at registration cannot be exhausted at
// 3 a.m. Eight is well past any real deployment — a topology with more than
// eight distinct proxy networks is one where the boundary is drawn wrong.
//
// WHAT HAPPENS WHEN IT IS FULL, because the capacity ledger does not accept a
// bound without one: registration REJECTS the application fail-closed. It does
// not silently drop the ninth, because a dropped trust entry is a proxy whose
// forwarded address is ignored — which fails in the safe direction but leaves
// the operator's configuration quietly untrue.
@(private)
TRUSTED_PROXY_MAX :: 8

// Trusted_Proxies is the registered set, stored on the App.
@(private)
Trusted_Proxies :: struct {
	// PREFIXES, matched textually, not CIDR arithmetic. See `trust_proxies`.
	prefix: [TRUSTED_PROXY_MAX]string,
	count:  int,
}

// trust_proxies declares which peers are allowed to speak for their clients.
//
// Each entry is an address PREFIX matched textually against the connected
// peer's rendered address: `"10."`, `"192.168."`, `"127.0.0.1"`, `"::1"`.
//
// **WHY PREFIXES RATHER THAN CIDR, stated plainly because CIDR is what a
// reviewer expects.** A correct CIDR implementation needs IPv4 and IPv6 parsing,
// mask arithmetic, and the IPv4-mapped-IPv6 edge — and each of those is a place
// to be subtly wrong in a security boundary. Textual prefixes are less
// expressive and their failure mode is the safe one: a prefix that does not
// match means the header is ignored and the peer is used, which is exactly the
// default. **A wrong CIDR mask can trust a network you did not mean to trust; a
// wrong prefix can only fail to trust one you did.**
//
// The asymmetry is the argument. If a deployment genuinely needs CIDR, that is
// evidence for a later work package, and adding it then is a strengthening —
// while shipping arithmetic now and finding it wrong would be a breach.
//
// **Ordering does not matter and duplicates are harmless**: this is a set
// membership test, not a chain walk.
//
// Registering MORE than `TRUSTED_PROXY_MAX` rejects the application
// fail-closed. Passing an empty slice is legal and means "trust nothing", which
// is also the default.
trust_proxies :: proc(a: ^App, prefixes: []string) {
	if a.private.poisoned {
		return
	}
	if len(prefixes) > TRUSTED_PROXY_MAX {
		trust_poison(a)
		return
	}

	// The strings are the CALLER's. They are read on the request path, so they
	// must outlive the App — string literals, which is what every real call site
	// passes. Cloning them would put an allocation and a teardown on a path that
	// has neither today, for a case that does not arise.
	a.private.trusted.count = 0
	for prefix in prefixes {
		if len(prefix) == 0 {
			// An empty prefix matches EVERY peer, which would trust the whole
			// internet through a typo. Refused rather than stored.
			trust_poison(a)
			return
		}
		a.private.trusted.prefix[a.private.trusted.count] = prefix
		a.private.trusted.count += 1
	}
}

@(private)
trust_poison :: proc(a: ^App, loc := #caller_location) {
	a.private.poisoned = true

	logger := context.logger
	if logger.procedure == nil {
		return
	}
	logger.procedure(logger.data, .Error, FRAMEWORK_MESSAGE_TRUST_INVALID, logger.options, loc)
}

// client_ip returns the address this request should be attributed to.
//
// **The connected peer**, unless that peer matches a prefix registered with
// `trust_proxies` — in which case the leftmost address of `X-Forwarded-For` is
// returned instead, and `""` if that header is absent or empty.
//
// LEFTMOST, and this is the part that is easy to get wrong in the unsafe
// direction. `X-Forwarded-For` grows left to right, so the leftmost entry is the
// original client — and it is also the entry a client can forge freely, since a
// client controls what it sends before any proxy appends to it. That is precisely
// why it is only read at all when the PEER is trusted: the trust decision is
// made on administered network identity, and the header is believed only
// downstream of it.
//
// **Returns a VIEW.** Over the peer string or over the request header, both
// request-scoped: copy it to keep it (G-05).
//
// It allocates nothing.
client_ip :: proc(ctx: ^Context) -> string {
	peer := ctx.private.peer

	if !trusted_peer(ctx, peer) {
		return peer
	}

	forwarded, ok := header(ctx, "X-Forwarded-For")
	if !ok || len(forwarded) == 0 {
		// A trusted proxy that forwarded nothing. The peer is the honest
		// answer, and inventing one would be worse than saying what we have.
		return peer
	}

	// The leftmost entry, trimmed. A single-hop chain has no comma at all.
	comma := strings.index_byte(forwarded, ',')
	first := forwarded if comma < 0 else forwarded[:comma]
	return strings.trim_space(first)
}

// trusted_peer is the membership test. Textual, bounded, and allocation-free.
@(private)
trusted_peer :: proc(ctx: ^Context, peer: string) -> bool {
	if ctx.private.trusted.count == 0 || len(peer) == 0 {
		return false
	}
	for i in 0 ..< ctx.private.trusted.count {
		if strings.has_prefix(peer, ctx.private.trusted.prefix[i]) {
			return true
		}
	}
	return false
}
