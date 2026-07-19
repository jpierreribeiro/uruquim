// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares application construction and teardown. It installs no
// default policy, allocates nothing, and builds no router.
package web

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
	// WP1 skeleton marker. No route table, allocator, default policy, or
	// production transport is wired yet; those belong to WP4, WP7 and WP8.
	skeleton_only: bool,

	// WP3 test-support state (the in-memory `web.test_request` transport). It is
	// LAZY: this zero value holds no allocation, so `app()`/`bare()` allocate
	// nothing and an application that never calls `test_request` never creates a
	// recorder. `destroy` frees it if it was used. The type belongs to the
	// machinery package `web/testing`; `web` names it but the machinery never
	// names a `web` type, keeping the dependency one-way.
	test_transport: testing.Test_Transport,
}

// app creates an application with the progressive Phase-1 defaults.
//
// WP1 STUB: returns a zero App and configures nothing. The Phase-1 default
// policy contract — fixed 4 MiB request-body cap, standardized 404, and
// minimal 405 with an `Allow` header — is delivered by WP4 and WP7. Recovery is
// Phase 2; configurable limits and timeouts are Phase 3; graceful shutdown
// hardening is Phase 4. This stub claims none of them.
app :: proc() -> App {
	return App{}
}

// bare creates an application with none of the default middleware or policies,
// for callers that want full control.
//
// WP1 STUB: returns a zero App. Because `app` installs no defaults yet either,
// the two are not yet observably different; WP4 onward makes the distinction
// real.
bare :: proc() -> App {
	return App{}
}

// destroy releases everything the application owns.
//
// Call it exactly once, on the original value returned by `app` or `bare`.
//
// WP3: releases the test-support state if `test_request` was ever used, exactly
// once. It remains a no-op for an application that never called `test_request`
// — the recorder is inactive and frees nothing. There is still no production
// transport, route table, or allocator to release; those arrive in WP4/WP7/WP8.
destroy :: proc(a: ^App) {
	testing.destroy(&a.private.test_transport)
}
