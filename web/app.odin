// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares application construction and teardown. It installs no
// default policy, allocates nothing, and builds no router.
package web
// uruquim:file application

import testing "uruquim:web/testing"

// App owns the application's resources.
//
// Ownership contract (ADR-001, ratified by experiment 01): `app()` returns App
// by value and stores no pointer to the pre-return local. The caller keeps that
// value, passes `&app` to every mutating operation, and calls `destroy` on that
// same value exactly once. App is non-copyable by contract: a copy must never
// be destroyed independently.
App :: struct {
	private: App_Internal,
}

// App_Internal is package-private: application code cannot NAME this type.
// It is encapsulated BY CONTRACT, not by the compiler — Odin has no per-field
// privacy, and fields stay reachable through a public field. Do not rely on
// this for safety guarantees (ADR-008, "Scope of the guarantee").
@(private)
App_Internal :: struct {
	// WP4 route table: a flat array of registered routes, owned by the App.
	// It is LAZY — this zero value holds no allocation, so `app()`/`bare()`
	// still allocate nothing and an application that registers no route never
	// creates a table. `destroy` frees it, and every pattern it owns, exactly
	// once. The entry type and the whole matching strategy are internal: Phase 3
	// replaces this table wholesale without any public change.
	routes: [dynamic]Route_Entry,

	// WP4 default-policy flag: whether dispatch installs the automatic 404 and
	// 405. `app()` sets it; `bare()` leaves it false. It is the mechanism behind
	// the documented app()/bare() distinction, and it deliberately is NOT
	// middleware — Phase 2 owns that.
	//
	// The remaining Phase-1 defaults are not here yet: the fixed 4 MiB body cap
	// is WP7, and no allocator or production transport is wired before WP8.
	default_responses: bool,

	// WP3 test-support state (the in-memory `web.test_request` transport). It is
	// LAZY: this zero value holds no allocation, so `app()`/`bare()` allocate
	// nothing and an application that never calls `test_request` never creates a
	// recorder. The type belongs to the machinery package `web/testing`; `web`
	// names it but the machinery never names a `web` type, keeping the
	// dependency one-way.
	test_transport: testing.Test_Transport,

	// The test-support teardown, registered LAZILY by `test_request` on first
	// use (planning/public-api-guardrails.md G-11).
	//
	// This indirection exists to eliminate a shipped cost, not to be clever.
	// `web.destroy` runs in EVERY application, so calling `testing.destroy`
	// directly from it creates a STATIC call edge into the machinery — and that
	// edge links the recorder teardown, plus its `delete_dynamic_array` and
	// `delete_slice` instantiations, into binaries that never test anything.
	// Through a proc pointer the only reference lives inside `test_request`, so
	// when `test_request` is dead-code-eliminated the teardown goes with it.
	//
	// The permitted residual is exactly this pointer field — one word of struct
	// and its nil initialization — never the teardown routine itself. Asserted
	// by `build/check_g11_teardown.sh`, which fails if `nm` finds any
	// `web/testing` teardown symbol in an application that never tests.
	test_teardown: proc(t: ^testing.Test_Transport),
}

// app creates an application with the progressive Phase-1 defaults.
//
// WP4 delivers two of them: a consistent 404 for an unmatched path, and a
// minimal 405 — with an exact `Allow` header listing the methods registered for
// that path — when the path exists under a different method. WP6 gave both the
// standardized error envelope.
//
// Still NOT delivered, and not claimed: the fixed 4 MiB request-body cap (WP7),
// panic recovery (Phase 2), configurable limits and read/write timeouts
// (Phase 3), and graceful shutdown hardening (Phase 4).
//
// It allocates nothing. The route table is created on the first registration.
app :: proc() -> App {
	return App{private = App_Internal{default_responses = true}}
}

// bare creates an application with none of the default middleware or policies,
// for callers that want full control.
//
// WP4 makes the distinction real for the first time. A `bare` application still
// dispatches every route it registers, but it installs NO automatic 404 and no
// automatic 405: an unmatched request simply leaves the response uncommitted,
// and deciding what to do about it belongs to the caller.
bare :: proc() -> App {
	return App{}
}

// destroy releases everything the application owns.
//
// Call it exactly once, on the original value returned by `app` or `bare`.
//
// WP4: releases the route table and every pattern the App cloned at
// registration, exactly once. It is a no-op for an application that registered
// no route.
//
// WP3/G-11: releases the test-support state by calling the teardown that
// `test_request` registered on its first call. For an application that never
// called `test_request` the pointer is nil and this is a genuine no-op — and,
// because the pointer is the only reference to it, the teardown routine is not
// even linked into that binary (planning/public-api-guardrails.md G-11).
//
// Calling `testing.destroy` directly here instead would be a static edge from
// every application's `destroy` into the machinery, linking the recorder
// teardown into binaries that never test. That is the cost this indirection
// exists to remove.
//
// The request arena and the transport own no App-lifetime state, so there is
// nothing further for `destroy` to release.
destroy :: proc(a: ^App) {
	routes_destroy(a)

	if a.private.test_teardown != nil {
		a.private.test_teardown(&a.private.test_transport)
	}
}
