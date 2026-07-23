# Phase 6 thread-safety boundary (WP70)

**Status:** ACCEPTED FOUNDATION, 2026-07-22. WP71 exposed a transport-neutral
capacity and WP72 passed the combined fault gate; ADR-030 Amendment 1 now
permits concurrent synchronous Handlers. Ledger effect: none.

## The ownership model

Configuration is single-threaded. `web.serve` finishes every lazy App-lifetime
structure, then atomically publishes one immutable serving snapshot before the
transport starts another lane. Routes, dispatch indexes, middleware chains,
limits, static mounts, CORS policy, proxy policy and the observer pointer are
read-only after publication.

A configuration call made after publication is refused and diagnosed. It does
not mutate the running snapshot and does not poison it: writing the poison flag
while request lanes read it would replace one race with another. `destroy` and
`test_request` are likewise not concurrent lifecycle operations; the owner calls
them only before serving or after `serve` has returned.

The hot request path takes no App mutex. Shared framework state is limited to:

- atomic request-ID seed publication and counter allocation;
- atomic publication/dispatch flags;
- a short adapter mutex that owns the lifetime of the backend server pointer;
- the backend's atomic shutdown election and aggregate refusal counter.

Backend state that need not be shared is lane-owned. In particular, each lane
owns its cached HTTP Date buffer and connection map. Exactly one successful
false-to-true shutdown transition may wake and later tear down the lanes.

## What the claim includes

The framework owns and tests concurrent route hits, misses, request-local
Contexts, request IDs, observer-pointer publication, stop requests and backend
lifecycle. The deterministic WP70 corpus starts eight threads together and
checks 4,096 unique generated IDs plus 1,024 mixed route/miss dispatches. A
real-socket case starts sixteen simultaneous `web.stop` callers. The WP69 drain
case that previously crashed is now GREEN without weakening its assertions.

The toolchain has no supported Odin thread-sanitizer mode in this pinned
configuration, so the mandatory evidence is deterministic contention plus
three semantic mutations: constant request IDs, incomplete miss publication
and late route mutation must each make the control fail.

Two adjacent worktrees built `examples/01-hello-world` with the pinned compiler
and identical commands: WP69 parent `1cd8175` produced 967,248 bytes and WP70
produced 971,616 bytes, a **4,368-byte** compatibility cost before concurrent
serving is exposed. The measurement is evidence, not a permanent size promise.

## What the claim excludes

`App_State` and everything reachable through it are application-owned. A
mutable value shared by handlers must use its own lock, atomics or a thread-safe
service; immutable configuration needs none. The framework cannot make an
arbitrary database client, cache, C library or application global safe merely
by storing its pointer.

An observer procedure is application code and can run concurrently on multiple
request lanes. The event is passed by value and framework-owned inputs remain
safe, but any mutable sink captured or reached by the observer must synchronize
itself. The same rule applies to the configured logger.

Blocking foreign code is not preemptible. Exact-once shutdown prevents a
framework use-after-free; it cannot unwind a handler permanently stuck in a C
call. WP72 owns the final public drain statement under concurrent serving.

## Adapter-transition rule

The changes to `vendor/odin-http` are Patch 12, marked **BRIDGE**. They fix real
multi-lane defects today but expose no vendor type or lane object through
`web`. The official future adapter must satisfy the same immutable-publication,
contention and exact-once-stop corpus; Patch 12 is then deleted with the old
adapter rather than ported by default.

## Rollback

Removing `web/concurrency.odin`, restoring the one-lane assumptions and
dropping Patch 12 returns the pre-WP70 implementation. No public symbol or
signature changes. The two new `core:sync` direct dependencies disappear with
that rollback.
