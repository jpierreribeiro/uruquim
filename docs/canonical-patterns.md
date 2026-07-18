# Canonical API Patterns

This document is **normative**. For every common task there is exactly one
recommended form. Documentation, examples, tests, and generated code use only
these forms. If a pattern here conflicts with any other document except
`knowledge-base/01-architecture-spec.md`, this document wins.

> Status: normative draft. Frozen at the Phase 1 Spec Gate; until then,
> amendments are allowed but must be made here first, spec-first.

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

- `web.app()` — production-oriented defaults (recovery, body limit, timeouts,
  404/405, graceful shutdown).
- `web.bare()` — no defaults (advanced; not for quick starts).
- `web.serve(&app, port)` — canonical. Use `web.serve_with(&app,
  web.Serve_Config{...})` only when you need host or other options.

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

	user, found := users.find(id)
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
| raw bytes | `web.bytes(ctx, status, content_type, data)` |
| redirect | `web.redirect(ctx, .Found, url)` |
| 400 | `web.bad_request(ctx, msg)` |
| 401 | `web.unauthorized(ctx, msg)` |
| 403 | `web.forbidden(ctx, msg)` |
| 404 | `web.not_found(ctx, resource)` |
| 409 | `web.conflict(ctx, msg)` |
| 500 | `web.internal_error(ctx)` |

`web.ok` is exactly `web.json(ctx, .OK, value)` and `web.created` is exactly
`web.json(ctx, .Created, value)` — tiny shorthands, no extra behavior.

## Application state

```odin
App_State :: struct {
	db:     ^postgres.Pool,
	config: Config,
}

state := App_State{db = db, config = config}
app := web.app_with_state(&state)
```

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

	web.ok(ctx, user)
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
