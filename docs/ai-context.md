# Uruquim API Reference for Coding Agents

Paste this file into your agent's context (Cursor rules, CLAUDE.md, etc.).

**Use only the APIs documented here. Do not invent procedures, aliases, or
alternative forms. If something is not listed, it does not exist.**

> Status: tracks the public API; updated in the same commit as any public API
> change. Pre-Phase-1: describes the frozen target surface.

## Application

```odin
package main

import web "uruquim:web"

main :: proc() {
	app := web.app()          // production defaults: recovery, body limit,
	defer web.destroy(&app)   // timeouts, 404/405, graceful shutdown

	web.get(&app, "/path", handler)
	web.post(&app, "/path", handler)
	web.put(&app, "/path/:id", handler)
	web.patch(&app, "/path/:id", handler)
	web.delete(&app, "/path/:id", handler)

	web.use(&app, middleware)     // optional

	web.serve(&app, 8080)
}
```

With typed application state:

```odin
app := web.app_with_state(&state)         // state: ^App_State (your struct)
state := web.state(ctx, App_State)        // inside handlers: ^App_State
```

## Handler

Handlers take `^web.Context`, return nothing, and respond via helpers:

```odin
handler :: proc(ctx: ^web.Context) {
	web.ok(ctx, payload)
}
```

## Extractors

Every extractor that can fail RESPONDS TO THE CLIENT ITSELF on failure and
returns `false`. On failure, just `return` — never write your own error
response for an extractor failure.

There are exactly two shapes:

```odin
// Shape 1 — value-producing: (value, ok)
id, ok := web.path_int(ctx, "id")
if !ok {
	return
}

// Shape 2 — destination-filling: bool (JSON body into your struct)
input: Create_User
if !web.body(ctx, &input) {
	return
}
```

All extractors:

```odin
name := web.path(ctx, "name")                 // string (route matched ⇒ present)

id, ok := web.path_int(ctx, "id")             // (int, ok), responds 400 on failure

search, found := web.query(ctx, "search")     // (string, found), no auto-response

page, ok := web.query_int(ctx, "page")        // required, responds 400 on failure

limit, ok := web.query_int_or(ctx, "limit", 20) // default only when ABSENT;
                                                // malformed value → 400

value, found := web.header(ctx, "x-api-key")  // (string, found), no auto-response
token, found := web.bearer_token(ctx)         // (string, found), no auto-response

state := web.state(ctx, App_State)            // ^App_State (app_with_state apps)
```

JSON structs use tags:

```odin
User :: struct {
	id:   int    `json:"id"`,
	name: string `json:"name"`,
}
```

## Responses

```odin
web.ok(ctx, payload)              // 200 JSON
web.created(ctx, payload)         // 201 JSON
web.no_content(ctx)               // 204
web.json(ctx, .Accepted, payload) // any status, JSON
web.text(ctx, .OK, "pong")
web.redirect(ctx, .Found, "/login")

web.bad_request(ctx, "invalid input")            // 400
web.unauthorized(ctx, "authentication required") // 401
web.forbidden(ctx, "insufficient permission")    // 403
web.not_found(ctx, "user")                       // 404
web.conflict(ctx, "already exists")              // 409
web.internal_error(ctx)                          // 500
```

All error responses share the envelope:

```json
{"error": {"code": "...", "message": "...", "field": "..."}}
```

## Middleware

A middleware is a handler that calls `web.next(ctx)` to continue, or returns
without calling it to stop the chain:

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

Middleware never hands values to handlers. When a handler needs the
authenticated user, it calls a typed extraction procedure
(`current_user(ctx) -> (^User, bool)`) instead of relying on middleware.

Built-ins: `web.logger()`, `web.recovery()`, `web.request_id()`,
`web.cors(web.Cors_Config{...})`, `web.secure_headers()`,
`web.body_limit(bytes)`.

## Route groups

```odin
api := web.router("/api")
web.get(&api, "/users", list_users)

admin := web.group(&api, "/admin", require_admin)
web.get(&admin, "/stats", stats)

web.mount(&app, &api)
```

## Full example (copy this shape)

```odin
package main

import web "uruquim:web"

Create_User :: struct {
	name: string `json:"name"`,
}

User :: struct {
	id:   int    `json:"id"`,
	name: string `json:"name"`,
}

main :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/users/:id", get_user)
	web.post(&app, "/users", create_user)

	web.serve(&app, 8080)
}

get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	web.ok(ctx, User{id = id, name = "Jean"})
}

create_user :: proc(ctx: ^web.Context) {
	input: Create_User
	if !web.body(ctx, &input) {
		return
	}

	web.created(ctx, User{id = 1, name = input.name})
}
```

## Rules

- Never use `or_else { ... }` blocks — invalid Odin. Use `(value, ok)` +
  `if !ok { return }`, or `if !web.body(ctx, &input) { return }`.
- `web.body` takes a POINTER to your struct and returns `bool` — it never
  returns the value.
- Never configure allocators, transports, or response writers — `web.app()`
  and `web.serve` handle them.
- Never store request data in maps or `any`; there is no `ctx.user_data` —
  use typed structs, `web.state`, and extraction procedures like
  `current_user(ctx) -> (^User, bool)`.
- Never name a variable `context` (reserved by Odin); the framework context
  is always `ctx`.
- One canonical call per task; do not mix or invent alternatives. Typed query
  extractors are named `query_<type>` / `query_<type>_or` — there is no
  generic `query_or(ctx, name, type, default)`.
- `web.ok(ctx, v)` == `web.json(ctx, .OK, v)`; `web.created(ctx, v)` ==
  `web.json(ctx, .Created, v)`.
