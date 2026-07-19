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
// WP2 adds `request`. There is NO public `response` field and there never will
// be one: the response object and its commit state are framework-internal, and
// applications respond through the helpers (ADR-008, planning/18 P-1). Keeping
// the API responder-only is what stops a hand-written status or `committed`
// flag from becoming an ordinary thing for an application to do.
//
// `params: Params` and `route: Route_Info` are introduced by WP4 (routing);
// declaring them here would promise a matching contract that does not exist.
//
// LIFETIME: `request` is a bundle of views over transport-owned storage, valid
// only for the duration of this request. Copy explicitly to persist, and never
// hand `ctx` or a request view to background work (planning/15 G-05).
Context :: struct {
	request: Request,

	private: Context_Internal,
}

// Context_Internal is package-private: application code cannot NAME this type.
// It is encapsulated BY CONTRACT, not by the compiler — Odin has no per-field
// privacy, and fields stay reachable through a public field. Do not rely on
// this for safety guarantees (ADR-008, "Scope of the guarantee").
// WP2 gives it the response state, which is the only reason the slot exists
// today. No allocator, chain cursor or transport hook is wired yet: those
// belong to WP4, WP7 and WP8, and WP2 adds nothing it does not test.
@(private)
Context_Internal :: struct {
	// The single-commit guard's storage. It lives here, and not on Context,
	// so that no application can address it as public API — reachability
	// through `private` is accepted and is not a security boundary
	// (ADR-008, "Scope of the guarantee"). WP6 wires the public responders
	// onto `response_commit`; WP2 leaves it untouched by any public path.
	response: Response,
}
