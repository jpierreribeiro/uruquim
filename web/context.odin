// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the canonical request context and the canonical handler
// type. It contains no request parsing, no response state, and no dispatch.
package web

import "core:mem"

// Handler is the one and only handler shape (ADR-011). It takes the request
// context and returns nothing: handlers respond through the response helpers.
// Do not add a second handler signature, and do not return `error`,
// `Handler_Error`, `Handler_Outcome`, or any other result from a handler.
Handler :: proc(ctx: ^Context)

// Context is the canonical, non-parametric request context.
//
// It is deliberately NOT an extension bag: it will never expose `user_data`,
// `locals`, `values`, `map[string]any`, `map[any]any`, or a public `rawptr`
// (planning/public-api-guardrails.md G-03). Middleware-produced values reach handlers through typed
// extraction procedures.
//
// WP2 adds `request`. There is NO public `response` field and there never will
// be one: the response object and its commit state are framework-internal, and
// applications respond through the helpers (ADR-008). Keeping
// the API responder-only is what stops a hand-written status or `committed`
// flag from becoming an ordinary thing for an application to do.
//
// There is NO public `params` and NO public `route` field, and there will not
// be one (amended in WP4). WP4 matches routes and captures the path parameter
// into the private slot below; WP5 makes the existing `web.path` and
// `web.path_int` extractors read it, which keeps one canonical access path
// instead of announcing a second public field. A stable route identity for
// observability stays internal and future (OQ-18).
//
// LIFETIME: `request` is a bundle of views over transport-owned storage, valid
// only for the duration of this request. Copy explicitly to persist, and never
// hand `ctx` or a request view to background work (planning/public-api-guardrails.md G-05).
Context :: struct {
	request: Request,

	private: Context_Internal,
}

// Context_Internal is package-private: application code cannot NAME this type.
// It is encapsulated BY CONTRACT, not by the compiler — Odin has no per-field
// privacy, and fields stay reachable through a public field. Do not rely on
// this for safety guarantees (ADR-008, "Scope of the guarantee").
// WP2 gave it the response state, WP4 the routing state, and WP7 the
// request-lifetime arena and body-consumption state. A middleware chain cursor
// belongs to Phase 2.
//
// It deliberately holds NO pointer back to the App. `dispatch` receives the App
// explicitly instead, which keeps the request context free of a reference whose
// lifetime it would otherwise have to justify.
@(private)
Context_Internal :: struct {
	// The single-commit guard's storage. It lives here, and not on Context,
	// so that no application can address it as public API — reachability
	// through `private` is accepted and is not a security boundary
	// (ADR-008, "Scope of the guarantee"). WP6 wires the public responders
	// onto `response_commit`; WP2 leaves it untouched by any public path.
	response: Response,

	// WP4 — the captured path parameter, or the zero value when the matched
	// route was static. `value` is a view over the request path and `name` a
	// view over the App-owned pattern; neither is copied, and neither survives
	// the request. WP5 exposes it through `web.path`/`web.path_int`.
	param: Route_Param,

	// WP4 — request-local storage for the 405 `Allow` header.
	//
	// The value and its header pair must outlive `dispatch`, because the
	// committed response holds VIEWS over them and the caller reads that
	// response after dispatch returns. Building them in a local would hand back
	// views into a dead stack frame. A fixed buffer sized to the longest
	// possible value is what makes producing a 405 allocation-free; the
	// alternative, allocating a string per 405, would put an allocation on a
	// path that an unauthenticated client can trigger at will.
	allow_buffer: [ALLOW_VALUE_MAX]u8,

	// WP6 — request-local storage for the committed response's header pairs.
	//
	// It replaces WP4's single-slot `allow_header`: a 405 now carries `Allow`
	// AND `Content-Type`, so two slots are the Phase-1 worst case
	// (`RESPONSE_HEADER_MAX`). Every name and value stored here is a STATIC
	// string, or — for `Allow` — a view over `allow_buffer` above, so the array
	// holds no allocation and needs no teardown.
	//
	// It lives on the Context, not in a local, for the same reason
	// `allow_buffer` does: the committed response holds a VIEW over it and is
	// read after `dispatch` returns.
	response_headers: [RESPONSE_HEADER_MAX]Header_Pair,

	// WP5 — request-local storage for the extractor error envelope, on exactly
	// the same terms as `allow_buffer` above and for exactly the same reason:
	// the committed response holds a VIEW over it, and it is read after the
	// extractor returns.
	//
	// A fixed buffer, not an allocation. There is no request-lifetime arena
	// until WP7 (ADR-006), so an allocated envelope would have no owner and no
	// point of release — and a malformed `?page=x` is something an
	// unauthenticated client can send at will, so allocating there would be a
	// remote memory-pressure lever. `ERROR_BODY_MAX` is the exact worst case,
	// derived from the ratified codes and messages in `web/errors.odin` and
	// re-checked there by `#assert`.
	//
	// Only the FIRST commit ever writes here: `error_commit_parameter` consults
	// the commit guard before touching the buffer, so a second failure cannot
	// rewrite the bytes the first response is still pointing at.
	error_buffer: [ERROR_BODY_MAX]u8,

	// WP7 — the single-consumer body capability (ADR-012 A). `.Fresh` is the
	// zero value, so a new Context begins with the body available. `web.body`
	// moves it to `.Consumed` on its first call, before the limit and parse.
	body_state: Body_State,

	// WP7 — the request-lifetime arena that owns decoded nested body data
	// (ADR-006). It is LAZY: this zero value holds no allocation, so a request
	// that never binds a body — or whose body is empty or over-limit — creates
	// no arena. `arena_active` says whether it has been initialized, and the
	// driver frees it exactly once via `request_arena_destroy` after the
	// response is captured. It belongs to the REQUEST, never the App or the
	// Response, and the WP6 Response-owned buffers are never migrated into it.
	request_arena: mem.Dynamic_Arena,
	arena_active:  bool,
}
