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

## The one rule

**One important concept has one canonical name and one canonical form of use.**

There is no `decode_json` / `parse_body` / `extract_json` / `bind` — only
`web.body`. There is no `respond(ctx, 200, value)` — only the explicit
helpers below.

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

- `web.app()` — progressive production defaults. Phase 1 provides a fixed
  4 MiB request-body cap, standardized 404, and minimal 405 with `Allow`.
  Phase 2 adds recovery; Phase 3 adds configurable limits, read/write
  timeouts, and optimized 405/header handling; Phase 4 hardens graceful
  shutdown.
- `web.bare()` — no defaults (advanced; not for quick starts).
- `web.serve(&app, port)` — canonical. Use `web.serve_with(&app,
  web.Serve_Config{...})` only when you need host or other options.

`App` owns resources and is non-copyable by contract. Keep the value returned
by `web.app()`, pass its address, and destroy that same value exactly once.
Do not copy an `App` or destroy a copy.

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
```

In-memory, no sockets, no ports.
