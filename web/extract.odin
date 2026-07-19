// WP1 — COMPILING PUBLIC API SKELETON. NO HTTP BEHAVIOR.
//
// This file declares the canonical Phase-1 extractors. Nothing is parsed and
// no error response is written: WP5 implements the path/query extractors and
// WP7 implements body binding.
//
// There are exactly two extractor shapes and no third:
//
//	value, ok := web.path_int(ctx, "id")   // value-producing
//	if !ok { return }
//
//	input: Create_User                     // destination-filling
//	if !web.body(ctx, &input) { return }
//
// Value-producing HTTP extractors deliberately omit `#optional_ok` (ADR-002),
// so the pinned compiler rejects a call that drops `ok` with
// "Assignment count mismatch". Do not add the directive.
package web

// path returns the value of a path parameter.
//
// The parameter is present whenever the route matched, so this extractor
// cannot fail and writes no error response.
//
// The returned string is a view valid only for the current request; copy it
// explicitly with an appropriate allocator to keep it longer.
//
// WP1 STUB: always returns "". WP4 captures parameters; WP5 exposes them.
path :: proc(ctx: ^Context, name: string) -> string {
	return ""
}

// path_int returns a path parameter parsed as an integer.
//
// On failure it writes the standardized `invalid_path_parameter` response
// itself and returns ok = false; the handler only returns.
//
// WP1 STUB: always returns (0, false) and writes nothing. Returning false
// keeps the canonical call site correct — a handler simply returns — without
// pretending a response was produced. WP5 implements parsing and the envelope.
path_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool) {
	return 0, false
}

// query returns a query-string parameter as text.
//
// This is a plain lookup: it writes no automatic error response. `found`
// reports presence.
//
// The returned string is a view valid only for the current request.
//
// WP1 STUB: always returns ("", false). WP5 implements the lookup.
query :: proc(ctx: ^Context, name: string) -> (value: string, found: bool) {
	return "", false
}

// query_int returns a required query parameter parsed as an integer.
//
// A missing or malformed parameter writes the standardized
// `invalid_query_parameter` response and returns ok = false.
//
// WP1 STUB: always returns (0, false) and writes nothing. See `path_int`.
query_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool) {
	return 0, false
}

// query_int_or returns an optional query parameter parsed as an integer.
//
// `default_value` applies ONLY when the parameter is absent. A present but
// malformed value is a 400, never silently replaced by the default.
//
// WP1 STUB: always returns (0, false) and writes nothing. Note that the stub
// does not return `default_value`: WP1 cannot distinguish "absent" from
// "malformed", and returning the default would falsely claim the absence
// semantics that WP5 owns.
query_int_or :: proc(ctx: ^Context, name: string, default_value: int) -> (value: int, ok: bool) {
	return 0, false
}

// body decodes the JSON request body into a caller-owned destination.
//
// The destination form keeps ownership and storage explicit. On failure the
// extractor writes the standardized `invalid_json` or `body_too_large`
// response itself and returns false.
//
// WP1 STUB: always returns false, leaves `dst` untouched, and writes nothing.
// WP7 implements decoding, the request-lifetime allocator (ADR-006), and the
// fixed 4 MiB cap.
body :: proc(ctx: ^Context, dst: ^$T) -> bool {
	return false
}
