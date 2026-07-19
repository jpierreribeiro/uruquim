// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the Phase-1 error responders. Nothing is rendered: WP6
// owns the standardized error envelope, the error code list, and the private
// typed error-report path that framework-detected failures pass through.
//
// The envelope every one of these will eventually produce is:
//
//	{"error": {"code": "...", "message": "...", "field": "..."}}
//
// with `field` omitted entirely when the error is not bound to an input field.
// WP1 declares no envelope type and no code enum, so it makes no part of that
// contract available yet.
package web

// bad_request writes a standardized 400 response.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
bad_request :: proc(ctx: ^Context, message: string) {
}

// unauthorized writes a standardized 401 response.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
unauthorized :: proc(ctx: ^Context, message: string) {
}

// forbidden writes a standardized 403 response.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
forbidden :: proc(ctx: ^Context, message: string) {
}

// not_found writes a standardized 404 response for the named resource.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
not_found :: proc(ctx: ^Context, resource: string) {
}

// internal_error writes a standardized 500 response.
//
// It takes no message on purpose: internal failure detail is logged on the
// server, never returned to the client.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
internal_error :: proc(ctx: ^Context) {
}
