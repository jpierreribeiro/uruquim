// WP4 — ROUTE TABLE: the App-owned storage the five registration procedures
// write into, and its teardown.
//
// Nothing in this file is public. There is no exported `Route`, `Router`,
// `Params`, `Param` or `Route_Info`, and no accessor for any of them: WP4 adds
// behavior, not surface, and the ledgers stay at 32 application + 2
// test-support = 34 (planning/phase-1-plan.md §WP4 D1).
//
// WHY THIS LIVES IN `web/` AND NOT `web/internal/dispatch/`. The plan proposed a
// subpackage. In Odin a subdirectory is a SEPARATE PACKAGE, and this code must
// name `App`, `Handler`, `Context`, `Method` and the internal `Response` — so a
// subpackage would have to import `uruquim:web`, which is the back-edge WP3
// already ratified as a compile cycle (probe C5). The alternatives are
// duplicating the types, bridging through an untyped pointer, or freezing an
// internal ABI, and all three are forbidden. The dispatcher is therefore
// package-private files in the existing package, and
// `build/check_public_api.sh` permits exactly these two file names rather than
// being relaxed to accept subdirectories (D2).
//
// THIS IS THE INTERIM DISPATCHER, not the router. It is a linear table, and it
// is deliberately not the Phase-3 data structure: the compact per-method tree
// with its precomputed chains, conflict diagnostics and normalization policy
// belongs to Phase 3. WP4's only job is to make the OBSERVABLE contract —
// precedence, per-method isolation, 404, 405 with `Allow` — true and
// test-pinned, so that replacing this table later changes nothing publicly.
package web

import "core:strings"

// Route_Entry is one registered route.
//
// The table is a flat array of these: contiguous, cache-friendly to scan, and
// trivially replaceable. There is no node, no child pointer and no tree.
//
// OWNERSHIP. `pattern` is OWNED by the App — a clone made at registration with
// the table's allocator, and released exactly once by `routes_destroy`. It is
// deliberately not the caller's string: retaining a caller-supplied view would
// leave every route dangling as soon as the caller reused its buffer, and a
// registration-time clone is the one allocation the spec explicitly permits
// (`knowledge-base/02-odin-idioms-guidelines.md`, "Registration MAY allocate").
//
// `has_param` is computed once at registration rather than re-derived on every
// request. It is what makes static-over-parametric precedence a property of the
// PATTERN instead of the registration order: lookup scans static entries first
// and parametric entries second, so both registration orders resolve
// identically.
@(private)
Route_Entry :: struct {
	method:    Method,
	pattern:   string,
	handler:   Handler,
	has_param: bool,
}

// Route_Param is the captured path parameter for one request.
//
// It lives in `Context_Internal`, NOT on `Context`. There is no public
// `ctx.params` and no public accessor in Phase 1 (D1): WP5 makes the existing
// `web.path` and `web.path_int` extractors read this storage, which keeps one
// canonical access path instead of announcing a second public field.
//
// LIFETIME. `value` is a VIEW over the request path and is valid only for the
// duration of the request, exactly like every other request-derived view
// (planning/public-api-guardrails.md G-05). `name` is a view over the
// App-owned pattern and is valid until `destroy`. Neither is copied: copying
// would be a per-request allocation that a direct view makes unnecessary.
@(private)
Route_Param :: struct {
	name:  string,
	value: string,
	found: bool,
}

// ALLOW_HEADER_NAME is the exact 405 header name. Not `allow`, not `ALLOW`.
@(private)
ALLOW_HEADER_NAME :: "Allow"

// ALLOW_METHOD_ORDER is the deterministic order an `Allow` value lists methods
// in. It is a property of the FRAMEWORK, never of the application's
// registration sequence, so two applications that register the same methods in
// different orders produce byte-identical `Allow` headers.
//
// `.UNKNOWN` is absent and unreachable: no public procedure registers it, so it
// can never own a route and can never appear here.
@(private)
ALLOW_METHOD_ORDER :: [5]Method{.GET, .POST, .PUT, .PATCH, .DELETE}

// ALLOW_VALUE_MAX is the byte length of the longest possible `Allow` value,
// "GET, POST, PUT, PATCH, DELETE" — every method, comma-and-space separated.
// The value is built into a fixed request-local buffer of exactly this size, so
// producing a 405 allocates nothing.
@(private)
ALLOW_VALUE_MAX :: 29

// route_register is the SINGLE registration path. `get`, `post`, `put`, `patch`
// and `delete` are one-line delegations to it, so there is exactly one place
// where a route is validated, cloned and stored.
//
// ALLOCATION. The table is LAZY, like the WP3 test-support state: an App that
// registers no route allocates nothing. The first registration creates the
// dynamic array with `context.allocator`, and every pattern clone afterwards
// uses that same allocator — read back from the array — so registration and
// teardown can never disagree about which allocator owns the storage.
//
// WP4 REJECTS NOTHING. A malformed pattern, a duplicate method+path, or a
// pattern with more than one `:param` is stored as given: definitive
// registration-conflict detection and its diagnostics are Phase 3 (D5), and
// inventing an error contract here would freeze a public registration-error API
// that no work package has ratified. What WP4 does guarantee is that such a
// registration cannot corrupt matching — `route_match` simply never matches a
// pattern it cannot interpret.
@(private)
route_register :: proc(a: ^App, method: Method, pattern: string, handler: Handler) {
	if a.private.routes == nil {
		a.private.routes = make([dynamic]Route_Entry, context.allocator)
	}

	owned := strings.clone(pattern, a.private.routes.allocator)

	append(
		&a.private.routes,
		Route_Entry {
			method = method,
			pattern = owned,
			handler = handler,
			has_param = pattern_has_param(owned),
		},
	)
}

// routes_destroy releases the table exactly once and returns it to its zero
// state.
//
// It frees every owned pattern with the allocator that created it, then the
// array itself. It is a no-op for an App that registered no route, and a second
// call is a safe no-op — `web.destroy` is specified as call-once, but a
// teardown that double-frees when called twice is a worse failure than one that
// simply does nothing.
@(private)
routes_destroy :: proc(a: ^App) {
	if a.private.routes == nil {
		return
	}

	// Captured before the array is freed: after `delete_dynamic_array` the
	// array's own allocator field is no longer a safe thing to read.
	allocator := a.private.routes.allocator

	for entry in a.private.routes {
		delete_string(entry.pattern, allocator)
	}

	delete_dynamic_array(a.private.routes)
	a.private.routes = nil
}

// method_token converts a `Method` to its on-the-wire token.
//
// Package-internal and total: every input maps to a token, it never allocates,
// and it returns a static string. `.UNKNOWN` maps to the empty token, which
// `method_from_token` converts back to `.UNKNOWN`.
//
// It lives here, beside the route table, because it is method VOCABULARY shared
// by two callers: the `Allow` builder below and the WP3 test-support facade.
// Keeping one mapping is what stops the framework and its test transport from
// ever disagreeing about what a method is called.
@(private)
method_token :: proc(method: Method) -> string {
	switch method {
	case .GET:
		return "GET"
	case .POST:
		return "POST"
	case .PUT:
		return "PUT"
	case .PATCH:
		return "PATCH"
	case .DELETE:
		return "DELETE"
	case .UNKNOWN:
		return ""
	}
	return ""
}
