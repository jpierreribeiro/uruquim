// WP6 — SUCCESS RESPONDERS. JSON and text rendering, and the public status type.
//
// Rendering completes BEFORE anything is committed (R-05). That ordering is the
// whole reason a marshal failure can still produce a clean 500: nothing has been
// written when the failure is discovered, so the error path is free to commit a
// fresh envelope rather than patch a half-sent response.
//
// Bodies rendered here are OWNED by the internal `Response` (ADR-014) and are
// released by `response_destroy`, which the response driver calls after the
// response has been captured or written. See `web/response.odin`.
package web
// uruquim:file application

import encoding_json "core:encoding/json"
import "core:mem"

// The stdlib import is ALIASED because this package exports a procedure named
// `json`. Without the alias the two collide — the same failure experiment 02
// recorded and had to work around.

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
// WP6: the payload is marshalled with the official `core:encoding/json` encoder
// into an allocation the `Response` then OWNS.
//
// ORDER OF OPERATIONS, and every step of it is load-bearing:
//
//  1. If a response was already committed, return IMMEDIATELY — before
//     marshalling, before allocating, and before logging. A handler that
//     responds twice must not pay for the second render, and must not emit a
//     second diagnostic for a payload nobody will ever see.
//  2. Marshal completely. Nothing is committed while this can still fail.
//  3. On failure: release any partial buffer the encoder returned, report the
//     failure through the private typed path — which LOGS on the server, while
//     the response is still uncommitted (R-05) — and commit one complete
//     `internal_error`. Not a single byte of the rejected payload reaches the
//     client.
//  4. On success: transfer the buffer to the response with the JSON
//     `Content-Type`.
//
// PAYLOADS ARE VALUES (ADR-003, OQ-14, R-13). The pinned marshaller rejects
// pointer and procedure payloads with `Unsupported_Type`, so `&value` and
// pointer-typed variables take the step-3 path and produce a 500. This is the
// accepted Phase-1 baseline, not an oversight; adopting one-level dereference
// requires a ratified spec amendment.
json :: proc(ctx: ^Context, status: Status, value: $T) {
	if ctx.private.response.committed {
		return
	}

	data, err := encoding_json.marshal(value, {}, context.allocator)
	if err != nil {
		// The encoder may hand back a partially-filled buffer alongside the
		// error. It has no owner, so it is released here.
		if data != nil {
			delete_slice(data, context.allocator)
		}

		framework_report(T, .Response_Marshal_Failed)
		internal_error(ctx)
		return
	}

	response_commit_owned(
		&ctx.private.response,
		status,
		response_json_headers(ctx),
		data,
		context.allocator,
	)
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
// WP6: `s` is COPIED into an allocation the `Response` owns. Retaining the
// caller's string instead would dangle as soon as the caller reused its
// storage — the response is read after the handler returns, so a view into
// handler-local or request-local data is exactly the bug the ownership rules
// exist to prevent (G-05).
//
// An allocation failure leaves the response uncommitted rather than committing
// a truncated body: a partial response is worse than none, and the caller's
// handler simply returns without answering.
text :: proc(ctx: ^Context, status: Status, s: string) {
	if ctx.private.response.committed {
		return
	}

	body, err := mem.alloc_bytes(len(s), allocator = context.allocator)
	if err != nil {
		return
	}
	copy(body, s)

	response_commit_owned(
		&ctx.private.response,
		status,
		response_text_headers(ctx),
		body,
		context.allocator,
	)
}

// no_content writes a 204 response with no body.
//
// It sets NO `Content-Type`: there is no content to describe, and announcing a
// media type for an empty body would be a claim about nothing. It allocates
// nothing.
no_content :: proc(ctx: ^Context) {
	response_commit(&ctx.private.response, .No_Content, nil, nil)
}
