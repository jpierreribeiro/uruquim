# Canonical API Patterns

This document is **normative**. For every common task there is exactly one
recommended form. Documentation, examples, tests, and generated code use only
these forms. If a pattern here conflicts with any other document except
`knowledge-base/01-architecture-spec.md`, this document wins.

> Status: Phase-1 canonical forms ratified at the 2026-07-18 Spec Gate.
> Later-phase sections are design targets and become available only at their
> marked phase gates.
>
> WP1 has compiled the Phase-1 surface: every form below is valid Odin against
> the real `web` package on the pinned toolchain. WP1 delivered a **compiling
> public API skeleton, not a functional server** — the procedures are inert
> stubs until WP2–WP9. The canonical *forms* are what this document fixes, and
> they are unchanged.
>
> WP2 added the request/response model: `Request`, `Method` and `Header_View`
> exist and behave as described below.
>
> WP4 has added routing: registration, `:param` matching,
> static-over-parametric precedence, per-method isolation, and the automatic
> 404/405 of `web.app()` all work, driven in memory by `web.test_request`.
>
> It is **still not a functional server**, and two of the forms below do not
> execute yet: no extractor returns a value (WP5/WP7) and no response helper
> produces output (WP6), so no JSON is ever rendered. `web.serve` binds no port
> (WP8). The canonical *forms* are what this document fixes, and they are
> unchanged.

## The one rule

**One important concept has one canonical name and one canonical form of use.**

There is no `decode_json` / `parse_body` / `extract_json` / `bind` — only
`web.body`. There is no `respond(ctx, 200, value)` — only the explicit
helpers below.

## Request data lifetime (copy to persist)

Request-derived strings, slices, headers, query values, params and body are
**temporary views** over storage owned by the transport for the duration of
one request. They are valid only during that request.

**To keep any of it, copy it explicitly with an appropriate allocator.**
Background work must receive owned application data — never a captured `ctx`
and never a request view.

The reused buffer does not fail loudly; the view silently starts reading
different bytes — same length, still live memory, different contents. This is
test-pinned (WP2): a path view that read `"/users"` reads `"######"` after the
transport reused its buffer, while a copy taken beforehand still reads
`"/users"`.

The canonical form is an explicit clone with an explicit allocator, taken
BEFORE the request ends:

```odin
import "core:slice"
import "core:strings"

handler :: proc(ctx: ^web.Context) {
	// Views — valid only for this request.
	path := ctx.request.path
	body := ctx.request.body

	// Copies — owned by the caller, valid afterwards. Free them.
	saved_path := strings.clone(path, context.allocator)
	saved_body := slice.clone(body, context.allocator)
	defer delete(saved_path)
	defer delete(saved_body)

	web.no_content(ctx)
}
```

Never hand `ctx`, a `Request`, or any view to background work: give it the
owned copies instead.

Applications do not reach a response object. There is no `ctx.response` — you
respond through `web.json`, `web.ok`, `web.created`, `web.text`,
`web.no_content` and the error helpers, and the framework guarantees those
supported paths do not overwrite a response that was already produced.

That guarantee covers the supported paths. It is not a security boundary: the
application and the framework share one program, and code that deliberately
reaches into framework internals bypasses it (ADR-008, "Scope of the
guarantee").

## Reading the request

```odin
handler :: proc(ctx: ^web.Context) {
	if ctx.request.method == .GET {   // UPPERCASE: .GET, never .Get
		web.ok(ctx, ctx.request.path)
		return
	}

	web.no_content(ctx)
}
```

`ctx.request` is the only public request surface in Phase 1:

| Field | Type | Notes |
|---|---|---|
| `method` | `web.Method` | `.UNKNOWN`, `.GET`, `.POST`, `.PUT`, `.PATCH`, `.DELETE` |
| `path` | `string` | view |
| `query` | `string` | view, raw and unparsed — use the query extractors |
| `headers` | `web.Header_View` | no lookup in Phase 1 |
| `body` | `[]u8` | view |

`Method` members are UPPERCASE. `.GET` is the canonical spelling; `.Get` does
not compile.

Any method token outside that set — `"HEAD"`, `"OPTIONS"`, `"PROPFIND"`, or a
lowercase `"get"`, since methods are case-sensitive — arrives as `.UNKNOWN`.
`.UNKNOWN` is not an error and produces no response by itself.

`Header_View` is **encapsulated by contract**, not opaque: Odin offers no
opacity, and it promises nothing about its representation. **There is no
header lookup in Phase 1** — `web.header(ctx, name)` is Phase 2. Do not invent
a substitute by reaching into the view.

## Application skeleton

```odin
package main

import web "uruquim:web"

main :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/health", health)
	web.get(&app, "/users/:id", get_user)
	web.post(&app, "/users", create_user)

	web.serve(&app, 8080)
}
```

- `web.app()` — progressive production defaults. Delivered so far: a
  standardized 404 and a minimal 405 with the `Allow` header (WP4). Still to
  come: the fixed 4 MiB request-body cap (WP7); recovery (Phase 2);
  configurable limits, read/write timeouts, and optimized 405/header handling
  (Phase 3); graceful shutdown hardening (Phase 4).
- `web.bare()` — no defaults (advanced; not for quick starts). It routes
  exactly like `web.app()` but installs neither the 404 nor the 405, so an
  unmatched request produces no response at all.
- `web.serve(&app, port)` — canonical. Use `web.serve_with(&app,
  web.Serve_Config{...})` only when you need host or other options.

`App` owns resources and is non-copyable by contract. Keep the value returned
by `web.app()`, pass its address, and destroy that same value exactly once.
Do not copy an `App` or destroy a copy.

## Routing

One canonical registration form per method — `web.get`, `web.post`, `web.put`,
`web.patch`, `web.delete` — taking the app, a pattern, and a handler:

```odin
web.get(&app, "/users", list_users)       // static
web.get(&app, "/users/:id", get_user)     // one :param segment
```

A pattern begins with `/`. A `:param` occupies exactly one whole segment, must
be named, and Phase 1 allows **at most one per pattern**. There is no wildcard.

A pattern outside that grammar — `/a/:x/:y`, a bare `/users/:`, or one without a
leading `/` — **never matches any request**, and never contributes to an `Allow`
header either. Registration accepts it silently and reports nothing, so check
your patterns: a route that is never reached looks exactly like a 404.

When a static and a parametric route both match, **the static one always
wins**, independently of registration order:

```odin
web.get(&app, "/users/:id", get_user)
web.get(&app, "/users/me", get_current_user)   // /users/me reaches THIS one
```

Methods are isolated: registering GET on a path does not register any other
method on it.

**Paths are not normalized.** `/users` and `/users/` are different, and
percent-encoding and dot segments are not decoded. Do not write code that
depends on either behavior; the normalization policy is decided in Phase 3.

Registration conflicts are not diagnosed in Phase 1. A duplicate pattern is
stored as given, and an unsupported one never wins a match — there is no
registration error to handle, and no such API is frozen yet.

The pattern string is copied: the App owns its copy, so the caller may reuse or
free its own buffer immediately after registering.

`web.app()` answers an unmatched request automatically:

```text
unknown path                     → 404
path registered on another method → 405 + Allow
```

`Allow` names only the methods registered for that path, always in the order
`GET, POST, PUT, PATCH, DELETE`, comma-and-space separated, never duplicated.
Phase 1 exposes no way to read response headers, so it is verified internally.
Both bodies are empty until WP6 renders the error envelope.

A method token outside the `Method` set arrives as `.UNKNOWN` and follows the
same 404/405 rules; it never becomes a 501.

## Handler

```odin
Health :: struct {
	status: string `json:"status"`,
}

health :: proc(ctx: ^web.Context) {
	web.ok(ctx, Health{status = "ok"})
}
```

Handlers take `^web.Context` and return nothing. They respond via helpers.
Payloads are typed structs — there is no untyped object literal.

The missing return value is deliberate: Uruquim does not use Echo-style
generic error propagation. Odin allows returned results to be ignored, and a
result would make the canonical extractor `return` more ceremonial. Internal
framework failures still pass through one private typed path for consistent
logging, public error formatting, and single-commit protection. Keep domain
errors in the application and map them explicitly at the HTTP boundary.

## Extractor pattern (the load-bearing pattern)

Extractors respond on failure themselves. The handler checks the boolean and
returns — nothing else. There are exactly two shapes:

```odin
// 1. Value-producing extractor: (value, ok)
id, ok := web.path_int(ctx, "id")
if !ok {
	return
}

// 2. Destination-filling extractor: bool
input: Create_User
if !web.body(ctx, &input) {
	return
}
```

Full handler:

```odin
get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	user, found := users.find(id) // returns a User value
	if !found {
		web.not_found(ctx, "user not found")
		return
	}

	web.ok(ctx, user)
}
```

Failure of `path_int` automatically produces:

```json
{
  "error": {
    "code": "invalid_path_parameter",
    "message": "Path parameter 'id' must be an integer",
    "field": "id"
  }
}
```

Do NOT write `or_else { ... }` blocks — that is not valid Odin. Do NOT write
manual status/JSON assembly for extractor failures — the extractor already
responded.

## JSON body binding

`web.body` fills a caller-owned destination and returns `bool`:

```odin
Create_User :: struct {
	name:  string `json:"name"`,
	email: string `json:"email"`,
}

create_user :: proc(ctx: ^web.Context) {
	input: Create_User
	if !web.body(ctx, &input) {
		return
	}

	user, err := insert_user(input)
	if err != nil {
		web.internal_error(ctx)
		return
	}

	web.created(ctx, user)
}
```

Invalid JSON automatically produces the `invalid_json` envelope; an oversized
body produces `body_too_large`.

## Query parameters

Three canonical procedures, explicit per-type names:

```odin
// Plain text lookup — no automatic error response.
search, found := web.query(ctx, "search")

// Required int — missing or malformed responds 400 and returns ok = false.
page, ok := web.query_int(ctx, "page")
if !ok {
	return
}

// Optional int with default — default applies ONLY when absent;
// a malformed value is still a 400.
limit, ok := web.query_int_or(ctx, "limit", 20)
if !ok {
	return
}
```

```text
GET /users              → limit = 20
GET /users?limit=50     → limit = 50
GET /users?limit=banana → 400 invalid_query_parameter
```

Future typed variants follow the same pattern: `query_<type>` /
`query_<type>_or`.

## Responses

| Intent | Canonical call |
|---|---|
| 200 + JSON | `web.ok(ctx, payload)` |
| 201 + JSON | `web.created(ctx, payload)` |
| 204 | `web.no_content(ctx)` |
| other status + JSON | `web.json(ctx, status, payload)` |
| plain text | `web.text(ctx, status, s)` |
| raw bytes (later phase) | `web.bytes(ctx, status, content_type, data)` |
| redirect (later phase) | `web.redirect(ctx, .Found, url)` |
| 400 | `web.bad_request(ctx, msg)` |
| 401 | `web.unauthorized(ctx, msg)` |
| 403 | `web.forbidden(ctx, msg)` |
| 404 | `web.not_found(ctx, resource)` |
| 409 (later phase) | `web.conflict(ctx, msg)` |
| 500 | `web.internal_error(ctx)` |

`web.ok` is exactly `web.json(ctx, .OK, value)` and `web.created` is exactly
`web.json(ctx, .Created, value)` — tiny shorthands, no extra behavior.

Phase-1 JSON payloads are concrete values:

```odin
user: User = load_user()
web.ok(ctx, user)       // accepted: User value
```

Do not pass `&user`, and do not pass a variable whose type is `^User`.
Pointers are unsupported by the Phase-1 baseline because the pinned official
JSON marshaller rejects them. WP6 will separately prototype a one-level
dereference; pointer support may be added only if that compiles cleanly and
the specification is amended first.

If marshalling rejects a payload type, the renderer logs the marshal error on
the server before returning one complete standardized `internal_error`, while
the response is still uncommitted. It never returns a silent 500 or partial
JSON.

## Application state

> Available from Phase 3 as an Advanced API. It does not exist in Phase 1.

```odin
App_State :: struct {
	db:     ^postgres.Pool,
	config: Config,
}

state := App_State{db = db, config = config}
app := web.app_with_state(&state)
```

`app_with_state` rejects nil. `web.state` asserts that state was registered
and that the requested type matches before returning the typed pointer.

```odin
list_users :: proc(ctx: ^web.Context) {
	state := web.state(ctx, App_State)

	users, err := user_repository.list(state.db)
	if err != nil {
		web.internal_error(ctx)
		return
	}

	web.ok(ctx, users)
}
```

## Middleware

> Available from Phase 2. It does not exist in Phase 1. CORS is a Phase-4
> built-in.

Attach:

```odin
web.use(&app,
	web.logger(),
	web.recovery(),
	web.cors(web.Cors_Config{
		allowed_origins = {"https://example.com"},
	}),
)
```

Write (a gate: allow or reject, then `web.next`):

```odin
require_auth :: proc(ctx: ^web.Context) {
	token, found := web.bearer_token(ctx)
	if !found {
		web.unauthorized(ctx, "missing bearer token")
		return
	}

	if !auth.token_is_valid(token) {
		web.unauthorized(ctx, "invalid bearer token")
		return
	}

	web.next(ctx)
}
```

Returning without calling `web.next` short-circuits the chain.

Middleware gates requests, logs, and sets response metadata. It does NOT hand
values to handlers — there is no `ctx.user_data`, no `locals`, no
`map[string]any`, by design.

## Auth / dependencies

> This example uses `web.bearer_token`, which becomes available in Phase 2.
> It is architectural guidance only and cannot be copied into a Phase-1 app.

When the handler needs the user, call a typed extraction procedure directly
(same contract as extractors) — no middleware involved:

```odin
current_user :: proc(ctx: ^web.Context) -> (^User, bool) {
	token, found := web.bearer_token(ctx)
	if !found {
		web.unauthorized(ctx, "missing bearer token")
		return nil, false
	}

	user, ok := auth.find_user_by_token(token)
	if !ok {
		web.unauthorized(ctx, "invalid bearer token")
		return nil, false
	}

	return user, true
}

get_profile :: proc(ctx: ^web.Context) {
	user, ok := current_user(ctx)
	if !ok {
		return
	}

	web.ok(ctx, user^) // explicit value; `user` itself is ^User
}
```

Use `require_auth` middleware only for routes that must be authenticated but
do not need the user value (typically whole groups):

```odin
admin := web.group(&app, "/admin")
web.use(&admin, require_auth)
```

Do not stack both on the same route — that duplicates validation. Pick the
extractor when you need the user, the gate when you don't.

## Route groups

> Available from Phase 2. They do not exist in Phase 1.

Explicit router values; no configuration callbacks:

```odin
api := web.router("/api")

web.get(&api, "/users", list_users)
web.post(&api, "/users", create_user)

admin := web.group(&api, "/admin", require_admin)
web.get(&admin, "/stats", stats)

web.mount(&app, &api)
```

## Testing

```odin
res := web.test_request(&app, .GET, "/users/42")
testing.expect(t, res.status == .OK)
testing.expect_value(t, res.body, `{"id":42}`)
```

`web.test_request(a: ^App, method: Method, path: string) -> Recorded_Response`
drives one request through the framework IN-MEMORY: no socket, no port, no
network syscall. `Recorded_Response` has exactly two fields:

```odin
res.status  // web.Status — copied by value
res.body    // string — a view over a copy the App owns
```

Lifetime: every response `test_request` returns stays readable — alongside all
the others from the same App — until `web.destroy(&app)`, which frees them. There
is no per-response cleanup, and there is no public `headers` field.

Routing is wired (WP4), so `test_request` returns real routed results: a
registered handler runs, an unknown path gives 404, and a path registered under
another method gives 405 with an `Allow` header. Because no response helper
works until WP6, a handler cannot produce a body — a matched route therefore
reports a zero status and an empty body, which is the honest report of an
uncommitted response, not a fabricated 200. The 404 and 405 bodies are also
empty until WP6 defines the error envelope. The machinery lives in
`web/testing/` and is not meant to be imported directly.
