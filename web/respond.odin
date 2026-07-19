// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the Phase-1 success responders and the public status
// type. Nothing is serialized and nothing is committed: WP6 implements JSON
// rendering, the error envelope, and the single-commit guard.
package web

// Status is the HTTP status enumeration used by the public response helpers.
//
// It exists because the ratified `json(ctx, status, value)` and
// `text(ctx, status, s)` signatures require a status type. Its members are
// limited to the statuses the Phase-1 public documentation and the Phase-1
// default-policy contract actually name; later phases add their own.
Status :: enum int {
	OK                    = 200,
	Created               = 201,
	Accepted              = 202,
	No_Content            = 204,
	Bad_Request           = 400,
	Unauthorized          = 401,
	Forbidden             = 403,
	Not_Found             = 404,
	Method_Not_Allowed    = 405,
	Internal_Server_Error = 500,
}

// json writes `value` as a JSON response with the given status.
//
// This is the single JSON renderer; `ok` and `created` are exact shorthands
// over it and never diverge from it. Phase-1 payloads are passed BY VALUE:
// `&value` and pointer-typed variables are not accepted payload forms
// (ADR-003), because the pinned marshaller rejects them with
// `Unsupported_Type`.
//
// WP1 STUB: serializes nothing and commits nothing. WP6 implements marshalling,
// the server-side marshal diagnostic, and the pre-commit `internal_error` path.
json :: proc(ctx: ^Context, status: Status, value: $T) {
}

// ok writes a 200 JSON response.
//
// It is exactly `json(ctx, .OK, value)` — a fixed-status shorthand with no
// extra serialization, headers, or error handling.
ok :: proc(ctx: ^Context, value: $T) {
	json(ctx, .OK, value)
}

// created writes a 201 JSON response.
//
// It is exactly `json(ctx, .Created, value)`.
created :: proc(ctx: ^Context, value: $T) {
	json(ctx, .Created, value)
}

// text writes a plain-text response with the given status.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
text :: proc(ctx: ^Context, status: Status, s: string) {
}

// no_content writes a 204 response with no body.
//
// WP1 STUB: writes nothing and commits nothing. WP6 implements it.
no_content :: proc(ctx: ^Context) {
}
