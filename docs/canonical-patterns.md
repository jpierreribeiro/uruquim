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
health :: proc(ctx: ^web.Context) {
	web.ok(ctx, web.object{
		"status" = "ok",
	})
}
```

Handlers take `^web.Context` and return nothing. They respond via helpers.

## Extractor pattern (the load-bearing pattern)

Extractors respond on failure themselves. The handler checks `ok` and
returns — nothing else:

```odin
get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	user, found := find_user(id)
	if !found {
		web.not_found(ctx, "user")
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

```odin
Create_User :: struct {
	name:  string `json:"name"`,
	email: string `json:"email"`,
}

create_user :: proc(ctx: ^web.Context) {
	input, ok := web.body(ctx, Create_User)
	if !ok {
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

```odin
page := web.query_or(ctx, "page", int, 1)
```

Missing or unparsable values fall back to the default. Use required-query
extraction only when semantically required.

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

Write:

```odin
require_auth :: proc(ctx: ^web.Context) {
	token, ok := web.bearer_token(ctx)
	if !ok {
		web.unauthorized(ctx, "missing bearer token")
		return
	}

	web.next(ctx)
}
```

Returning without calling `web.next` short-circuits the chain.

## Auth / dependencies

Composable extraction procedures, same contract as extractors:

```odin
current_user :: proc(ctx: ^web.Context) -> (^User, bool) {
	token, ok := web.bearer_token(ctx)
	if !ok {
		web.unauthorized(ctx, "missing bearer token")
		return nil, false
	}

	user, verified := auth.verify(token)
	if !verified {
		web.unauthorized(ctx, "invalid token")
		return nil, false
	}

	return user, true
}

profile :: proc(ctx: ^web.Context) {
	user, ok := current_user(ctx)
	if !ok {
		return
	}

	web.ok(ctx, user)
}
```

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
