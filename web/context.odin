// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the canonical request context and the canonical handler
// type. It contains no request parsing, no response state, and no dispatch.
package web

// Handler is the one and only handler shape (ADR-011). It takes the request
// context and returns nothing: handlers respond through the response helpers.
// Do not add a second handler signature, and do not return `error`,
// `Handler_Error`, `Handler_Outcome`, or any other result from a handler.
Handler :: proc(ctx: ^Context)

// Context is the canonical, non-parametric request context.
//
// It is deliberately NOT an extension bag: it will never expose `user_data`,
// `locals`, `values`, `map[string]any`, `map[any]any`, or a public `rawptr`
// (planning/15 G-03). Middleware-produced values reach handlers through typed
// extraction procedures.
//
// WP1 declares only the private internal slot. `request`, `response`, `params`
// and `route` are introduced by WP2 (request/response model) and WP4 (routing);
// declaring them here would promise a lifetime and commit contract that does
// not exist yet.
Context :: struct {
	private: Context_Internal,
}

// Context_Internal is package-private and unreachable from application code.
// WP2 and WP4 give it real contents; in WP1 it exists only so that Context has
// a stable shape with no public field.
@(private)
Context_Internal :: struct {
	// WP1 skeleton marker. No allocator, chain cursor, or transport hook is
	// wired yet; those belong to WP2, WP4 and WP8.
	skeleton_only: bool,
}
