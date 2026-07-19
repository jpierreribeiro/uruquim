// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the five Phase-1 route registration procedures. It stores
// no route, validates no pattern, and dispatches nothing. Route groups
// (`router`, `group`, `mount`) and middleware (`use`, `next`) are Phase 2 and
// are deliberately absent.
package web

// get registers a handler for GET requests matching `pattern`.
//
// `pattern` is a route pattern such as "/users" or "/users/:id", not a
// concrete request path.
//
// WP1 STUB: the registration is discarded. WP4 introduces the dispatch table,
// pattern validation, static-over-parameter precedence, and conflict detection.
get :: proc(a: ^App, pattern: string, handler: Handler) {
}

// post registers a handler for POST requests matching `pattern`.
//
// WP1 STUB: the registration is discarded. See `get`.
post :: proc(a: ^App, pattern: string, handler: Handler) {
}

// put registers a handler for PUT requests matching `pattern`.
//
// WP1 STUB: the registration is discarded. See `get`.
put :: proc(a: ^App, pattern: string, handler: Handler) {
}

// patch registers a handler for PATCH requests matching `pattern`.
//
// WP1 STUB: the registration is discarded. See `get`.
patch :: proc(a: ^App, pattern: string, handler: Handler) {
}

// delete registers a handler for DELETE requests matching `pattern`.
//
// WP1 STUB: the registration is discarded. See `get`.
delete :: proc(a: ^App, pattern: string, handler: Handler) {
}

// dispatch is the core-private request dispatcher.
//
// WP3 STUB: it performs NO routing and produces NO automatic response — it
// leaves `ctx` exactly as it received it, with the response uncommitted. It
// exists so `web.test_request` has a real core dispatch call to drive; WP4
// replaces this body with the route table, `:param` matching, the standardized
// 404, and the minimal 405 with its `Allow` header. Deliberately NOT a fake
// 200/echo: an uncommitted response is the honest WP3 result.
@(private)
dispatch :: proc(ctx: ^Context) {
}
