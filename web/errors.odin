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

// ---------------------------------------------------------------------------
// WP5 — the narrow, package-private envelope machinery for the two extractor
// errors, and NOTHING else.
//
// WP5 must produce `invalid_path_parameter` and `invalid_query_parameter`
// envelopes, because an extractor that fails without responding would leave the
// client with no answer at all. It must NOT implement WP6: the public
// responders above stay inert stubs, there is no generic renderer, no error-code
// enum, no envelope type, and no `Content-Type` or header policy. Everything
// below is `@(private)`, so the application ledger stays at exactly 32.
//
// WHY THE JSON IS HAND-WRITTEN. `core:encoding/json` would escape correctly,
// but `json.marshal` ALLOCATES, and Phase 1 has no request-lifetime arena to
// free that allocation from — the arena is WP7 (ADR-006). The alternatives were
// to leak one allocation per failed extraction, or to introduce WP7's arena
// early. Both are worse than emitting the envelope directly. Hand-writing it
// also keeps the encoder out of applications that merely reach an extractor
// error: `build/check_public_api.sh` forbids the import, and the cost
// measurement in the WP5 PR records the difference.
//
// The escaper is not trusted on the strength of that reasoning. Every envelope
// this file produces is parsed back by the OFFICIAL `core:encoding/json` parser
// in strict `.JSON` mode in `tests/wp5-internal/`, including names carrying
// quotes, backslashes, control characters, multi-byte UTF-8, and lengths far
// past the buffer.
//
// LIFETIME AND OWNERSHIP. The envelope is written into
// `ctx.private.error_buffer` — request-local storage owned by the Context,
// exactly like WP4's `allow_buffer` — and the committed `body` is a VIEW over
// it. It stays valid as long as the Context does, which is precisely as long as
// the transport or the WP3 recorder needs in order to copy it out. Nothing is
// allocated and nothing needs freeing, so an unauthenticated client cannot
// drive memory growth by sending malformed parameters.
// ---------------------------------------------------------------------------

// The ratified wire codes (docs/errors.md). Clients match on these strings, so
// they are spelled once and asserted by the checker.
@(private)
ERROR_CODE_INVALID_PATH_PARAMETER :: "invalid_path_parameter"

@(private)
ERROR_CODE_INVALID_QUERY_PARAMETER :: "invalid_query_parameter"

// The three ratified message shapes. Each is a prefix and a suffix wrapped
// around the escaped parameter name.
@(private)
ERROR_MESSAGE_PATH_PREFIX :: "Path parameter '"

@(private)
ERROR_MESSAGE_QUERY_PREFIX :: "Query parameter '"

@(private)
ERROR_MESSAGE_INTEGER_SUFFIX :: "' must be an integer"

@(private)
ERROR_MESSAGE_REQUIRED_SUFFIX :: "' is required"

// ERROR_NAME_ESCAPED_MAX bounds how many ESCAPED bytes of a parameter name the
// envelope carries.
//
// A bound is unavoidable: the envelope goes into fixed storage, and a parameter
// name is application-supplied with no length limit. 64 bytes is far beyond any
// real name — the ratified examples are `id`, `page` and `limit` — while
// keeping the Context small.
//
// Truncation happens on an ESCAPE-UNIT boundary, never inside one: half a
// `\u00XX` sequence or half a multi-byte UTF-8 rune is not valid JSON, and
// "the envelope is always valid JSON" is the property this whole file exists to
// guarantee.
@(private)
ERROR_NAME_ESCAPED_MAX :: 64

// ERROR_BODY_MAX is the exact worst-case envelope length.
//
//	{"error":{"code":"                     18
//	invalid_query_parameter                23  (the longer of the two codes)
//	","message":"                           13
//	Query parameter '' must be an integer   37  (the longest message shell)
//	","field":"                             11
//	"}}                                      3
//	                                       ---
//	                                       105  + the name, escaped, twice
//
// The name appears in both `message` and `field`, so the budget is counted
// twice. `#assert` below re-derives the 105 from the actual constants, so a
// future edit to a message cannot silently outgrow the buffer.
@(private)
ERROR_BODY_MAX :: 105 + 2 * ERROR_NAME_ESCAPED_MAX

#assert(
	len("{\"error\":{\"code\":\"") +
	max(len(ERROR_CODE_INVALID_PATH_PARAMETER), len(ERROR_CODE_INVALID_QUERY_PARAMETER)) +
	len("\",\"message\":\"") +
	max(len(ERROR_MESSAGE_PATH_PREFIX), len(ERROR_MESSAGE_QUERY_PREFIX)) +
	max(len(ERROR_MESSAGE_INTEGER_SUFFIX), len(ERROR_MESSAGE_REQUIRED_SUFFIX)) +
	len("\",\"field\":\"") +
	len("\"}}") <=
	ERROR_BODY_MAX - 2 * ERROR_NAME_ESCAPED_MAX,
)

// error_json_unit_length reports how many bytes of `name`, starting at `i`, form
// ONE indivisible escape unit, and how many bytes that unit occupies once
// escaped.
//
// A unit is never split by truncation. There are four kinds:
//
//   - `"` and `\`      -> 1 source byte, 2 escaped bytes;
//   - a control byte   -> 1 source byte, 6 escaped bytes (`\u00XX`);
//   - a UTF-8 sequence -> 1..4 source bytes, copied verbatim;
//   - anything else    -> 1 source byte, 1 escaped byte.
//
// A multi-byte lead byte claims its continuation bytes so the sequence moves as
// one unit. A malformed lead, or a stray continuation byte, is treated as a
// single byte: this file does not repair invalid UTF-8, and a name that was not
// valid UTF-8 to begin with cannot be made valid by escaping it.
@(private)
error_json_unit_length :: proc(name: string, i: int) -> (source: int, escaped: int) {
	c := name[i]

	switch {
	case c == '"', c == '\\':
		return 1, 2
	case c < 0x20:
		return 1, 6
	case c < 0x80:
		return 1, 1
	}

	// A UTF-8 lead byte: 110xxxxx = 2, 1110xxxx = 3, 11110xxx = 4.
	width := 1
	switch {
	case c >= 0xF0:
		width = 4
	case c >= 0xE0:
		width = 3
	case c >= 0xC0:
		width = 2
	}

	// Never run past the end of the string, and never claim a byte that is not
	// a continuation byte (10xxxxxx) — a truncated or malformed sequence stays
	// as short as it actually is.
	n := 1
	for n < width && i + n < len(name) && name[i + n] & 0xC0 == 0x80 {
		n += 1
	}
	return n, n
}

// error_write_escaped_name appends `name` to `buffer` at `n`, JSON-escaped and
// bounded by ERROR_NAME_ESCAPED_MAX.
//
// It is DETERMINISTIC for a given name, which is what lets the caller emit the
// name twice — once in `message`, once in `field` — and get identical bytes both
// times without a scratch buffer.
@(private)
error_write_escaped_name :: proc(buffer: []u8, n: int, name: string) -> int {
	// A local, not a constant: the pinned compiler rejects indexing a constant
	// string ("Cannot index a constant").
	HEX := "0123456789abcdef"

	n := n
	used := 0
	i := 0

	for i < len(name) {
		source, escaped := error_json_unit_length(name, i)

		// Stop on a unit boundary rather than emitting a partial escape.
		if used + escaped > ERROR_NAME_ESCAPED_MAX {
			break
		}

		c := name[i]
		switch {
		case c == '"':
			n += copy(buffer[n:], "\\\"")
		case c == '\\':
			n += copy(buffer[n:], "\\\\")
		case c < 0x20:
			n += copy(buffer[n:], "\\u00")
			buffer[n] = HEX[c >> 4]
			buffer[n + 1] = HEX[c & 0x0F]
			n += 2
		case:
			n += copy(buffer[n:], name[i:i + source])
		}

		used += escaped
		i += source
	}

	return n
}

// error_commit_parameter builds one WP5 envelope and commits it, exactly once.
//
// THE GUARD COMES FIRST, and that ordering is load-bearing. The envelope buffer
// is shared request-local storage, and an already-committed response holds a
// VIEW over it. Writing the new envelope before consulting `response_commit`
// would overwrite the bytes of the FIRST response — which would still report
// its original status while silently serving a different body. Checking
// `committed` up front means a second failure touches nothing at all.
//
// It allocates nothing, never panics, sets no header, and produces no partial
// response: the body is complete before `response_commit` sees it.
@(private)
error_commit_parameter :: proc(
	ctx: ^Context,
	code: string,
	message_prefix: string,
	name: string,
	message_suffix: string,
) {
	if ctx.private.response.committed {
		return
	}

	buffer := ctx.private.error_buffer[:]
	n := 0

	n += copy(buffer[n:], "{\"error\":{\"code\":\"")
	n += copy(buffer[n:], code)
	n += copy(buffer[n:], "\",\"message\":\"")
	n += copy(buffer[n:], message_prefix)
	n = error_write_escaped_name(buffer, n, name)
	n += copy(buffer[n:], message_suffix)
	n += copy(buffer[n:], "\",\"field\":\"")
	n = error_write_escaped_name(buffer, n, name)
	n += copy(buffer[n:], "\"}}")

	response_commit(&ctx.private.response, .Bad_Request, nil, buffer[:n])
}

// error_invalid_path_parameter commits the 400 for a path parameter that is
// absent, empty, malformed, or outside the range of `int`.
//
// All four collapse into ONE message on purpose. Distinguishing "absent" from
// "malformed" here would describe the SERVER's routing to the client: a name
// the handler asked for but the route never captured is a programming error in
// the application, not something the caller can act on.
@(private)
error_invalid_path_parameter :: proc(ctx: ^Context, name: string) {
	error_commit_parameter(
		ctx,
		ERROR_CODE_INVALID_PATH_PARAMETER,
		ERROR_MESSAGE_PATH_PREFIX,
		name,
		ERROR_MESSAGE_INTEGER_SUFFIX,
	)
}

// error_query_parameter_required commits the 400 for a required query parameter
// that is ABSENT.
//
// It is a different message from the one below because the two are different
// problems for the caller: one says "you left it out", the other says "what you
// sent is not a number".
@(private)
error_query_parameter_required :: proc(ctx: ^Context, name: string) {
	error_commit_parameter(
		ctx,
		ERROR_CODE_INVALID_QUERY_PARAMETER,
		ERROR_MESSAGE_QUERY_PREFIX,
		name,
		ERROR_MESSAGE_REQUIRED_SUFFIX,
	)
}

// error_invalid_query_parameter commits the 400 for a query parameter that is
// PRESENT but not a valid integer.
@(private)
error_invalid_query_parameter :: proc(ctx: ^Context, name: string) {
	error_commit_parameter(
		ctx,
		ERROR_CODE_INVALID_QUERY_PARAMETER,
		ERROR_MESSAGE_QUERY_PREFIX,
		name,
		ERROR_MESSAGE_INTEGER_SUFFIX,
	)
}
