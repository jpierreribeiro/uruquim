// CANONICAL EXTRACTORS. Path and query extraction (WP5) and JSON body binding
// (WP7) are all implemented here.
//
// This file declares the canonical Phase-1 extractors. WP5 implements the five
// path/query extractors and the two 400 envelopes they commit on failure; WP7
// implements body binding.
//
// WHAT THIS FILE DELIBERATELY DOES NOT DO. It normalizes NOTHING and decodes
// NOTHING: no percent-decoding, no `+`-as-space, no case folding, no key or
// value trimming. `?q=a%20b` yields the literal bytes `a%20b`. A decoding
// policy interacts with transport conformance (WP9) and with the Phase-3
// normalization decision, and adopting one here would freeze it by accident.
//
// It also allocates NOTHING. Both lookups scan in place and return views over
// request-owned storage, and even the error path writes into fixed
// request-local storage on the Context (see `web/errors.odin`).
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
// uruquim:file application

import encoding_json "core:encoding/json"

// parse_int_strict parses a WHOLE decimal integer, and nothing else.
//
// Package-internal. It is deliberately NOT `strconv.parse_int`: on the pinned
// toolchain that procedure defaults to base 0, which accepts `0x1f`, `0b101`
// and digit separators like `1_000`, and it reports success without consuming
// the whole string unless the caller checks the byte count. Both behaviors
// would silently widen the ratified contract — `?page=0x10` is not a number a
// caller should be able to send — so this parser accepts exactly:
//
//	an optional '-', then one or more ASCII digits, and nothing more.
//
// A leading `+`, surrounding whitespace, a decimal point, an exponent and an
// empty string are all rejected. The magnitude is accumulated in `u64` and
// bounds-checked BEFORE each multiply, so a value outside `int` is rejected
// rather than wrapped: `min(int)` has a magnitude one larger than `max(int)`,
// and accumulating into a signed `int` would overflow at exactly that value.
//
// It allocates nothing and never panics.
@(private)
parse_int_strict :: proc(s: string) -> (value: int, ok: bool) {
	if len(s) == 0 {
		return 0, false
	}

	negative := s[0] == '-'
	digits := s[1:] if negative else s
	if len(digits) == 0 {
		return 0, false
	}

	// The largest magnitude each sign can represent.
	limit := u64(max(int)) + 1 if negative else u64(max(int))

	magnitude: u64
	for i in 0 ..< len(digits) {
		c := digits[i]
		if c < '0' || c > '9' {
			return 0, false
		}

		d := u64(c - '0')
		// Checked BEFORE the multiply: `magnitude * 10 + d` would already have
		// wrapped by the time it could be compared against the limit.
		if magnitude > (limit - d) / 10 {
			return 0, false
		}
		magnitude = magnitude * 10 + d
	}

	if negative {
		if magnitude == u64(max(int)) + 1 {
			return min(int), true
		}
		return -int(magnitude), true
	}
	return int(magnitude), true
}

// path returns the value of a path parameter.
//
// The parameter is present whenever the route matched, so this extractor
// cannot fail and writes no error response.
//
// The returned string is a view valid only for the current request; copy it
// explicitly with an appropriate allocator to keep it longer.
//
// WP5: reads the single parameter WP4 captured into private Context storage.
// There is no public `ctx.params` and there will not be one (WP4 D1) — this
// procedure is the one canonical way to read a captured parameter.
//
// The name must match EXACTLY. A near-miss returns "" rather than the value of
// whichever parameter happens to be captured: silently answering a different
// question than the one asked is a worse failure than an empty result, and the
// interim dispatcher captures at most one parameter per route (D5), so there is
// no set to search.
//
// It allocates nothing and copies nothing: the result is the same view over the
// request path that `route_match` produced.
path :: proc(ctx: ^Context, name: string) -> string {
	param := ctx.private.param
	if !param.found || param.name != name {
		return ""
	}
	return param.value
}

// path_int returns a path parameter parsed as an integer.
//
// On failure it writes the standardized `invalid_path_parameter` response
// itself and returns ok = false; the handler only returns.
//
// WP5: absent, empty, malformed and out-of-range all produce the SAME 400. See
// `error_invalid_path_parameter` for why they are not distinguished.
//
// It has no `#optional_ok` (ADR-002), so the pinned compiler rejects a call
// that drops `ok` with "Assignment count mismatch". Do not add the directive:
// three negative probes in `tests/wp5-public-surface/probes/` and a static
// checker ban exist to keep it absent.
path_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool) {
	raw := path(ctx, name)

	parsed, parsed_ok := parse_int_strict(raw)
	if !parsed_ok {
		error_invalid_path_parameter(ctx, name)
		return 0, false
	}
	return parsed, true
}

// query returns a query-string parameter as text.
//
// This is a plain lookup: it writes no automatic error response. `found`
// reports presence.
//
// The returned string is a view valid only for the current request.
//
// WP5: a direct scan of `ctx.request.query`, which does NOT include the leading
// `?`. Pairs are separated by `&`; a pair splits at its FIRST `=`, so
// `a=b=c` yields the value `b=c`. A key with no `=` is PRESENT with an empty
// value, which is what makes `?flag` distinguishable from an absent `flag`.
// Comparison is exact and case-sensitive. When a key repeats, the first
// occurrence wins — a minimal internal rule, not an announced duplicate-key
// contract.
//
// NO MAP, and no `strings.split`. Both would allocate on the hot path of every
// request that reads a parameter, and a map would additionally have to be built
// and torn down per request to serve lookups that are almost always one or two
// keys deep. A linear scan over a short string is faster in the shapes that
// actually occur and costs nothing when no parameter is read at all.
query :: proc(ctx: ^Context, name: string) -> (value: string, found: bool) {
	q := ctx.request.query

	start := 0
	for start <= len(q) {
		end := start
		for end < len(q) && q[end] != '&' {
			end += 1
		}

		pair := q[start:end]

		separator := -1
		for i in 0 ..< len(pair) {
			if pair[i] == '=' {
				separator = i
				break
			}
		}

		if separator < 0 {
			// A bare key: present, with an empty value. The empty result is
			// taken from the end of `pair` rather than written as `""` so that
			// every value this procedure returns is a view into the request
			// query, with no special case.
			if pair == name {
				return pair[len(pair):], true
			}
		} else if pair[:separator] == name {
			return pair[separator + 1:], true
		}

		start = end + 1
	}

	return "", false
}

// query_int returns a required query parameter parsed as an integer.
//
// A missing or malformed parameter writes the standardized
// `invalid_query_parameter` response and returns ok = false.
//
// WP5: absence and malformation produce DIFFERENT messages under the same code.
// Unlike the path case, both are things the caller can actually fix, and
// "is required" versus "must be an integer" is the difference between adding a
// parameter and correcting one.
//
// It has no `#optional_ok` (ADR-002).
query_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool) {
	raw, found := query(ctx, name)
	if !found {
		error_query_parameter_required(ctx, name)
		return 0, false
	}

	parsed, parsed_ok := parse_int_strict(raw)
	if !parsed_ok {
		error_invalid_query_parameter(ctx, name)
		return 0, false
	}
	return parsed, true
}

// query_int_or returns an optional query parameter parsed as an integer.
//
// `default_value` applies ONLY when the parameter is absent. A present but
// malformed value is a 400, never silently replaced by the default.
//
// WP5: this is the load-bearing distinction of the extractor, and the reason it
// still returns `ok`. `?limit=banana` is a mistake the caller should hear about;
// quietly serving page size 20 instead would turn a broken request into a
// successful one. Presence is decided by the KEY, so `?limit=` is present with
// an empty value and is therefore a 400 — not an absence.
//
// It has no `#optional_ok` (ADR-002). The directive is most tempting exactly
// here, because the procedure reads like a total "value or default" function;
// it is not, and the probe `discard_query_int_or_ok.odin` keeps it that way.
query_int_or :: proc(ctx: ^Context, name: string, default_value: int) -> (value: int, ok: bool) {
	raw, found := query(ctx, name)
	if !found {
		return default_value, true
	}

	parsed, parsed_ok := parse_int_strict(raw)
	if !parsed_ok {
		error_invalid_query_parameter(ctx, name)
		return 0, false
	}
	return parsed, true
}

// body decodes the JSON request body into a caller-owned destination.
//
// The destination form keeps ownership and storage explicit. On failure the
// extractor writes the standardized error response itself and returns false, so
// the canonical handler simply returns:
//
//	input: Create_User
//	if !web.body(ctx, &input) { return }
//
// WP7 implements it. The order of operations is normative:
//
//  1. SINGLE CONSUMER (ADR-012 A). The body is a one-use capability. The moment
//     this call begins it is marked consumed — before the limit check and
//     before the parser — so a first attempt that fails still spends it. A
//     second call decodes nothing: it logs a private diagnostic and produces a
//     500 only if no response is committed yet; a response the first call
//     already committed is left untouched. Never a double commit, no replay.
//  2. EMPTY body is invalid JSON: 400 `invalid_json`, and NO arena is created.
//  3. The 4 MiB cap is checked BEFORE the arena and BEFORE the parser. Exactly
//     `BODY_LIMIT` bytes is allowed; a strictly larger body is 413
//     `body_too_large`, again with no arena.
//  4. Decoding runs in strict `.JSON` mode against the request-lifetime arena
//     (ADR-006), so nested strings and slices are arena-owned and freed in one
//     shot at request end. On failure:
//       - a parse-level error (`Invalid_Data`) is the client's malformed JSON:
//         400 `invalid_json`;
//       - anything else — an incompatible destination, a nil/non-pointer dst —
//         is a decoder fault, NOT shown to the client: it is logged through the
//         typed report and answered with a 500.
//
// After `body` returns false, the partial content of `dst` is UNDEFINED and
// must be discarded. On success `dst` is fully populated and its nested data is
// valid until the request ends.
body :: proc(ctx: ^Context, dst: ^$T) -> bool {
	// 1. Single consumer. A second call never reaches the parser.
	if ctx.private.body_state == .Consumed {
		framework_report(T, .Body_Consumed_Twice)
		// The first response wins: only fill in a 500 if nothing is committed.
		if !ctx.private.response.committed {
			error_commit_static(ctx, .Internal_Server_Error, ERROR_BODY_INTERNAL)
		}
		framework_observe_request(T, ctx, .Body_Consumed_Twice)
		return false
	}
	ctx.private.body_state = .Consumed

	raw := ctx.request.body

	// 2. Empty body: invalid JSON, no arena.
	if len(raw) == 0 {
		error_commit_static(ctx, .Bad_Request, ERROR_BODY_INVALID_JSON)
		return false
	}

	// 3. The fixed cap, before the arena and the parser.
	if len(raw) > BODY_LIMIT {
		error_commit_static(ctx, STATUS_BODY_TOO_LARGE, ERROR_BODY_TOO_LARGE)
		return false
	}

	// 4. Decode into the request-lifetime arena, strict JSON.
	request_arena_init(ctx)
	err := encoding_json.unmarshal(raw, dst, .JSON, request_arena_allocator(ctx))
	if err != nil {
		if body_error_is_client_json(err) {
			error_commit_static(ctx, .Bad_Request, ERROR_BODY_INVALID_JSON)
		} else {
			// A decoder/destination fault. Log through the typed path while the
			// response is still uncommitted (R-05), then answer 500.
			framework_report(T, .Body_Decode_Failed)
			error_commit_static(ctx, .Internal_Server_Error, ERROR_BODY_INTERNAL)
			framework_observe_request(T, ctx, .Body_Decode_Failed)
		}
		return false
	}

	return true
}

// body_error_is_client_json reports whether an unmarshal error is the CLIENT's
// malformed JSON (→ 400) rather than a decoder/destination fault (→ 500).
//
// `unmarshal_any` validates the whole input with `is_valid` before parsing, so
// every parse-level failure — empty, truncated, and the rejected JSON5 forms —
// surfaces as `Unmarshal_Data_Error.Invalid_Data`. A bare `json.Error` would be
// a parse error too. Everything else — `Unsupported_Type_Error`, a
// nil/non-pointer destination — means the JSON was well-formed but the
// destination could not receive it, which is not something the caller can fix
// by sending different JSON and is therefore not reported as `invalid_json`.
@(private)
body_error_is_client_json :: proc(err: encoding_json.Unmarshal_Error) -> bool {
	switch e in err {
	case encoding_json.Error:
		return true
	case encoding_json.Unmarshal_Data_Error:
		return e == .Invalid_Data
	case encoding_json.Unsupported_Type_Error:
		return false
	}
	return false
}
