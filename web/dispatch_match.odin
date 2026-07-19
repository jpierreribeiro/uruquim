// WP4 — MATCHING AND DISPATCH: turning a method and a path into a handler
// call, a 404, or a 405.
//
// Nothing in this file is public. `dispatch` is the core-private entry point
// the WP3 test-support facade drives today and a real transport adapter (WP8)
// will drive later.
//
// WHAT THIS FILE DELIBERATELY DOES NOT DO. It normalizes NOTHING — not
// slashes, not percent-encoding, not dot segments, not trailing slashes — so
// `/users` and `/users/` are different paths and stay that way. A normalization
// policy is Phase 3 (D5), and quietly adopting one here would freeze it by
// accident. It also allocates nothing: matching walks the two strings in place,
// the captured parameter is a view, and the `Allow` value is built into a fixed
// request-local buffer.
package web

// segment_next yields the next `/`-separated segment of a path, in place.
//
// `cursor` starts at 1 — just past the leading `/` — and is advanced past the
// segment that is returned. The split is STRICT: no empty segment is skipped
// and no trailing slash is folded away, because either would be a
// normalization decision this work package does not own.
//
//	"/"          -> [""]
//	"/users"     -> ["users"]
//	"/users/"    -> ["users", ""]
//	"/users/42"  -> ["users", "42"]
//
// It allocates nothing: the returned segment is a view into `path`.
@(private)
segment_next :: proc(path: string, cursor: ^int) -> (segment: string, ok: bool) {
	if cursor^ > len(path) {
		return "", false
	}

	start := cursor^
	end := start
	for end < len(path) && path[end] != '/' {
		end += 1
	}

	cursor^ = end + 1
	return path[start:end], true
}

// pattern_has_param reports whether a pattern contains a `:param` segment.
//
// Computed ONCE at registration and stored on the entry, so lookup can scan
// static routes before parametric ones without re-examining any pattern. That
// is what makes precedence depend on the pattern's shape rather than on
// registration order.
@(private)
pattern_has_param :: proc(pattern: string) -> bool {
	if len(pattern) == 0 || pattern[0] != '/' {
		return false
	}

	cursor := 1
	for {
		segment, ok := segment_next(pattern, &cursor)
		if !ok {
			return false
		}
		if len(segment) > 0 && segment[0] == ':' {
			return true
		}
	}
}

// route_match matches one pattern against one request path.
//
// Both must begin with `/`, and both must run out of segments TOGETHER: a
// pattern is not a prefix matcher, so `/a/b` does not match `/a` or `/a/b/c`.
// A `:param` segment matches exactly one whole segment and never spans a `/`,
// which is why `/users/:id` does not match `/users/42/posts`.
//
// The interim dispatcher supports at most one `:param` per pattern (D5). If a
// pattern nonetheless contains several, the FIRST is captured — a deterministic
// choice rather than an accident of iteration order.
//
// A pattern that does not begin with `/` matches nothing. That is how an
// invalid registration stays harmless without WP4 inventing a registration-
// error API that Phase 3 owns.
//
// It allocates nothing. `name` is a view over the App-owned pattern; `value` is
// a view over the request path and is valid only for this request.
@(private)
route_match :: proc(
	pattern: string,
	path: string,
) -> (
	name: string,
	value: string,
	matched: bool,
) {
	if len(pattern) == 0 || pattern[0] != '/' {
		return "", "", false
	}
	if len(path) == 0 || path[0] != '/' {
		return "", "", false
	}

	pattern_cursor := 1
	path_cursor := 1

	captured_name: string
	captured_value: string
	captured: bool

	for {
		pattern_segment, pattern_ok := segment_next(pattern, &pattern_cursor)
		path_segment, path_ok := segment_next(path, &path_cursor)

		// Both must end at the same time. If only one still has segments, the
		// paths have different depths and do not match.
		if !pattern_ok || !path_ok {
			if pattern_ok != path_ok {
				return "", "", false
			}
			return captured_name, captured_value, true
		}

		if len(pattern_segment) > 0 && pattern_segment[0] == ':' {
			if !captured {
				captured_name = pattern_segment[1:]
				captured_value = path_segment
				captured = true
			}
			continue
		}

		if pattern_segment != path_segment {
			return "", "", false
		}
	}
}

// route_lookup finds the handler for one method and path.
//
// TWO PASSES, and that is the whole precedence rule: every static route is
// considered before any parametric one, so `/users/me` wins over `/users/:id`
// regardless of which was registered first. A single-pass "first match wins"
// scan would make behavior depend on registration order — the precise property
// Phase 3's radix tree must be free to change the implementation of without
// changing the result.
//
// It allocates nothing. The returned pointer aliases the table, which is stable
// for the duration of a request because nothing registers during dispatch.
@(private)
route_lookup :: proc(
	a: ^App,
	method: Method,
	path: string,
) -> (
	entry: ^Route_Entry,
	param: Route_Param,
	found: bool,
) {
	// Pass 1 — static routes.
	for &candidate in a.private.routes {
		if candidate.method != method || candidate.has_param {
			continue
		}
		if _, _, ok := route_match(candidate.pattern, path); ok {
			return &candidate, Route_Param{}, true
		}
	}

	// Pass 2 — parametric routes.
	for &candidate in a.private.routes {
		if candidate.method != method || !candidate.has_param {
			continue
		}
		if name, value, ok := route_match(candidate.pattern, path); ok {
			return &candidate, Route_Param{name = name, value = value, found = true}, true
		}
	}

	return nil, Route_Param{}, false
}

// allow_value builds the `Allow` header value for a path, into `buffer`.
//
// It reports `allowed = false` when the path matches no route under any method
// — which is what separates a 404 from a 405.
//
// The set of methods is collected in a `bit_set`, which gives deduplication for
// free: a path registered twice under GET, or matched by both a static and a
// parametric GET route, still yields "GET" exactly once. The value is then
// emitted in `ALLOW_METHOD_ORDER`, so the output is deterministic and
// independent of both registration order and table order.
//
// It allocates nothing: `buffer` is the caller's fixed request-local storage,
// sized `ALLOW_VALUE_MAX`, and the returned string is a view into it — valid
// exactly as long as that buffer is.
@(private)
allow_value :: proc(a: ^App, path: string, buffer: []u8) -> (value: string, allowed: bool) {
	methods: bit_set[Method]

	for entry in a.private.routes {
		if _, _, ok := route_match(entry.pattern, path); ok {
			methods += {entry.method}
		}
	}

	if methods == {} {
		return "", false
	}

	n := 0
	for method in ALLOW_METHOD_ORDER {
		if method not_in methods {
			continue
		}
		if n > 0 {
			n += copy(buffer[n:], ", ")
		}
		n += copy(buffer[n:], method_token(method))
	}

	return string(buffer[:n]), true
}

// dispatch resolves one request and runs it. It is the core-private entry
// point, and it replaces the inert WP3 stub.
//
// It takes the App EXPLICITLY (D3). The WP3 stub took only the Context and so
// had no access to the App-owned table. The alternative — storing a `^App` on
// the Context — is rejected: it would make the request context outlive-
// sensitive for no benefit, since every caller of `dispatch` already holds the
// App. This signature is internal and replaceable; no public signature changed.
//
// The order of decisions is exactly:
//
//  1. a matching route runs its handler, once, and dispatch returns;
//  2. otherwise, `bare()` returns without committing anything;
//  3. otherwise, a path known under another method is a 405 with `Allow`;
//  4. otherwise, it is a 404.
//
// TWO THINGS IT DOES NOT DO. It never fabricates a 200: a handler that returns
// without responding leaves the response uncommitted, and the framework does
// not invent success on its behalf. And it never overwrites a response that was
// already committed — every automatic response goes through `response_commit`,
// so the ADR-008 guard applies to the framework's own writes exactly as it
// applies to a handler's.
//
// `.UNKNOWN` gets no special case. It is a valid HTTP method the framework
// gives no public meaning to, so it simply matches no route and falls through
// to the ordinary 405/404 rules. It never becomes a 501: that would be a
// response policy WP4 has no mandate to freeze.
//
// The 404 and 405 bodies are EMPTY. The standardized JSON error envelope is
// WP6, and rendering one here would implement WP6 early against a contract
// that WP6 owns.
@(private)
dispatch :: proc(a: ^App, ctx: ^Context) {
	entry, param, found := route_lookup(a, ctx.request.method, ctx.request.path)
	if found {
		ctx.private.param = param
		entry.handler(ctx)
		return
	}

	// `bare()` installs no default policy, so an unmatched request stays
	// uncommitted. This is the first work package in which `app()` and `bare()`
	// are observably different — the distinction the documentation already
	// described — and it is expressed without inventing middleware (D4).
	if !a.private.default_responses {
		return
	}

	// The `Allow` value and its header pair live in request-local storage on the
	// Context, NOT in a local: the committed response holds views over them, and
	// views into a dead stack frame would be exactly the dangling-view bug the
	// ownership rules exist to prevent.
	allow, other_methods_exist := allow_value(a, ctx.request.path, ctx.private.allow_buffer[:])
	if other_methods_exist {
		ctx.private.allow_header[0] = Header_Pair {
			name  = ALLOW_HEADER_NAME,
			value = allow,
		}
		response_commit(
			&ctx.private.response,
			.Method_Not_Allowed,
			ctx.private.allow_header[:],
			nil,
		)
		return
	}

	response_commit(&ctx.private.response, .Not_Found, nil, nil)
}
