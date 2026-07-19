# Uruquim API Reference for Coding Agents

Paste this file into your agent's context (Cursor rules, CLAUDE.md, etc.).

**Use only the APIs documented here. Do not invent procedures, aliases, or
alternative forms. If something is not listed, it does not exist.**

> Status: phase-aware public API contract. Only the Phase-1 sections below are
> ratified; sections marked Phase 2/3/4 do not yet exist and must not be
> emitted by a coding agent.
>
> **Implementation status (WP4): routing works; there is still no server.**
> Every name and signature here exists in `web/` and compiles on the pinned
> toolchain, so code written against this reference compiles.
>
> What now really works: `Request`, `Method` and `Header_View`; route
> registration and dispatch, including `:param` matching and
> static-over-parametric precedence; the automatic 404 and the 405 with its
> `Allow` header in `web.app()`; and `web.test_request`, which drives one
> request in-memory (no sockets) and returns the real routed result.
>
> What still does NOT work: **no extractor returns a value** (`web.path`,
> `web.path_int`, `web.query*` and `web.body` are inert stubs until WP5/WP7);
> **no response helper produces output** (`web.ok`, `web.json`, `web.text` and
> the error helpers commit nothing until WP6), so no JSON is ever produced; and
> `web.serve` returns immediately without binding a port (WP8). The 404 and 405
> bodies are EMPTY — the standardized error envelope below is WP6.
>
> A handler that responds with nothing leaves the response uncommitted, and
> `web.test_request` reports that honestly as a zero status and an empty body.
> The framework never fabricates a 200. Write against these shapes; do not
> deploy against them.
>
> **Two ledgers.** The application API is exactly 32 symbols (below). The
> test-support API is a separate ledger of exactly 2 — `web.test_request` and
> `web.Recorded_Response` (see Testing). Union: 34. Do not fold them together and
> do not invent a third form.

## Application

```odin
package main

import web "uruquim:web"

main :: proc() {
	app := web.app()          // Phase 1: 404 and minimal 405 with the
	defer web.destroy(&app)   // required Allow header (the 4 MiB body cap
	                          // is WP7 and does not exist yet)

	web.get(&app, "/path", handler)
	web.post(&app, "/path", handler)
	web.put(&app, "/path/:id", handler)
	web.patch(&app, "/path/:id", handler)
	web.delete(&app, "/path/:id", handler)

	web.serve(&app, 8080)
}
```

`App` owns resources and is non-copyable by contract. Pass `&app` and destroy
that same value once; never copy it or destroy a copy. Recovery arrives in
Phase 2; configurable limits, read/write timeouts, and optimized 405/header
handling in Phase 3; robust graceful shutdown in Phase 4.

Typed application state is an Advanced API available from Phase 3, not Phase
1:

```odin
app := web.app_with_state(&state)         // state: ^App_State (your struct)
state := web.state(ctx, App_State)        // inside handlers: ^App_State
```

`app_with_state` rejects nil. `web.state` asserts registered state and exact
type before returning the pointer.

## Routing

```odin
web.get(&app, "/users", list_users)        // static
web.get(&app, "/users/:id", get_user)      // one :param segment
```

Rules (all test-pinned):

- a pattern begins with `/`; `/` itself is a valid pattern;
- `:param` occupies exactly ONE whole segment — `/users/:id` matches
  `/users/42` but never `/users/42/posts`;
- at most one `:param` per pattern in Phase 1, and it must be named; there is
  no wildcard;
- a pattern outside that grammar (`/a/:x/:y`, `/users/:`, or no leading `/`)
  **never matches anything** and never appears in an `Allow` header;
- a static route always beats a parametric one that also matches, no matter
  which was registered first — `/users/me` wins over `/users/:id`;
- methods are isolated: registering GET on a path does not register POST;
- **nothing is normalized.** `/users` and `/users/` are different paths.
  Percent-encoding and `.`/`..` segments are not decoded. Do not rely on any
  normalization; the policy is Phase 3.

Registration conflicts are not diagnosed in Phase 1. A duplicate registration is
stored as given, and an unsupported pattern simply never wins a match; there is
no registration-error type to catch. A route that is never reached is
indistinguishable from a 404, so check your patterns.

The captured `:param` value is NOT readable yet — `web.path(ctx, "id")` is a
WP5 stub that still returns `""`. Routing matches; extraction comes next.

`web.app()` adds two automatic responses:

```text
unknown path                     → 404, empty body
path exists under another method → 405 + Allow, empty body
```

`Allow` lists only the methods registered for that path, in the fixed order
`GET, POST, PUT, PATCH, DELETE`, comma-and-space separated, with no
duplicates. It is a response header and Phase 1 gives you no way to read
response headers.

A method outside the `Method` set arrives as `.UNKNOWN` and follows the same
404/405 rules. It never produces a 501.

`web.bare()` routes identically but installs NEITHER default: an unmatched
request simply produces no response at all.

## Handler

Handlers take `^web.Context`, return nothing, and respond via helpers:

```odin
handler :: proc(ctx: ^web.Context) {
	payload: User = load_user()
	web.ok(ctx, payload) // payload is a User value
}
```

## Request

`ctx.request` is the only public request surface. There is no `ctx.response`,
no `ctx.params` and no `ctx.route` in Phase 1.

```odin
ctx.request.method   // web.Method
ctx.request.path     // string  — view
ctx.request.query    // string  — view, raw; use the query extractors
ctx.request.headers  // web.Header_View — NO lookup in Phase 1
ctx.request.body     // []u8    — view
```

`web.Method` members are UPPERCASE. Write `.GET`, never `.Get`:

```odin
// The complete set: .UNKNOWN .GET .POST .PUT .PATCH .DELETE
m: web.Method = .GET

if ctx.request.method == .GET { }
```

Any other method token — `"HEAD"`, `"OPTIONS"`, `"PROPFIND"`, or a lowercase
`"get"`, since HTTP methods are case-sensitive — arrives as `.UNKNOWN`.
`.UNKNOWN` is not an error and produces no response on its own.

`web.Header_View` is encapsulated by contract: it promises nothing about its
representation, and Phase 1 gives it no accessor. **There is no header lookup
in Phase 1** — `web.header(ctx, name)` is Phase 2.

Request data is a temporary view. To keep it, copy it:

```odin
saved := strings.clone(ctx.request.path, context.allocator)
defer delete(saved)
```

Do not return `error`, `Handler_Error`, `Handler_Outcome`, or another result
from a canonical handler. Uruquim is intentionally not Echo: framework
failures use a private typed reporting path, while application-domain errors
are mapped explicitly at the HTTP boundary. There is only one handler shape.

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

// Phase 2, unavailable in Phase 1:
value, found := web.header(ctx, "x-api-key")
token, found := web.bearer_token(ctx)

// Phase 3 Advanced API, unavailable in Phase 1:
state := web.state(ctx, App_State)
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

web.bad_request(ctx, "invalid input")            // 400
web.unauthorized(ctx, "authentication required") // 401
web.forbidden(ctx, "insufficient permission")    // 403
web.not_found(ctx, "user")                       // 404
web.internal_error(ctx)                          // 500
```

`web.redirect` and `web.conflict` belong to later phases and do not exist in
the Phase-1 surface.

The status argument of `web.json` and `web.text` has type `web.Status`, so it
is always written as an inferred enum member (`.OK`, `.Created`, `.Accepted`,
`.No_Content`, `.Bad_Request`, `.Unauthorized`, `.Forbidden`, `.Not_Found`,
`.Method_Not_Allowed`, `.Internal_Server_Error`). Never pass a bare integer
such as `200`.

The Phase-1 JSON baseline accepts concrete values only:

```odin
user: User = load_user()
web.ok(ctx, user)       // accepted
// web.ok(ctx, &user)   // not accepted
```

If `user` has type `^User`, it is also not an accepted payload. Do not pass a
pointer variable. WP6 may prototype one-level pointer dereference, but pointer
support does not exist unless compiler evidence and a later spec amendment
say otherwise.

If marshalling rejects a value type, the renderer logs the marshal error on
the server, then—only while uncommitted—writes one complete standardized
`internal_error`. A silent 500 or partial JSON is forbidden.

All error responses share the envelope:

```json
{"error": {"code": "...", "message": "..."}}
```

`field` is optional and is omitted when the error is not associated with a
specific input field.

## Testing

The test-support API is a SEPARATE ledger of exactly two public symbols, both in
package `web`: `web.test_request` and `web.Recorded_Response`. They are public,
documented, and behavior-tested, but tracked apart from the 32-symbol
application surface.

```odin
app := web.app()
defer web.destroy(&app)

res := web.test_request(&app, .GET, "/users/42")   // in-memory, no sockets
testing.expect_value(t, res.status, web.Status.OK)
testing.expect_value(t, res.body, `{"id":42}`)
```

```odin
web.test_request(a: ^web.App, method: web.Method, path: string) -> web.Recorded_Response

Recorded_Response :: struct {
	status: web.Status,   // copied by value
	body:   string,       // a view over a copy the App owns
}
```

Lifetime: every `Recorded_Response` stays readable — alongside all the others
from the same App — until `web.destroy(&app)`, which frees them. There is no
per-response cleanup to call.

Prohibitions (these do NOT exist; do not emit them):

- no `testing.test_request` — the symbol is `web.test_request`; the `web/testing`
  machinery is internal and is not imported directly;
- no `res.headers`, no `res.committed`, no allocator or transport field on
  `Recorded_Response` — it has exactly `status` and `body`;
- no `web.test_request` overloads, builders, or optional query/body/header
  arguments — the signature is exactly `(&app, method, path)`;
- no cleanup procedure for `Recorded_Response`.

`web.test_request` returns REAL routed results (WP4): a registered route's
handler runs, an unknown path produces 404, and a path registered under another
method produces 405.

Because no response helper works yet (WP6), a handler cannot produce a body, so
a matched route reports a zero status and an empty body — the response is
genuinely uncommitted, not a fabricated 200. Only the framework's own 404 and
405 carry a status today, and both have empty bodies until WP6.

`web.bare()` routes but installs neither default, so an unmatched request on a
bare app stays uncommitted.

## Middleware

> Phase 2 and later. None of this section exists in Phase 1.

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

Phase-2 built-ins: `web.logger()`, `web.recovery()`, `web.request_id()`.
CORS and secure headers are Phase 4. A configurable body limit is Phase 3;
Phase 1 has the fixed 4 MiB cap and no `web.body_limit` middleware.

## Route groups

> Phase 2 and later. None of this section exists in Phase 1.

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
- JSON response helpers take payloads BY VALUE in the Phase-1 baseline. Do
  not pass `&value` or a variable with pointer type such as `^User`.
- Never configure allocators, transports, or response writers — `web.app()`
  and `web.serve` handle them.
- Never store request data in maps or `any`; there is no `ctx.user_data`.
  Use typed structs and extraction procedures. `web.state` is a Phase-3
  Advanced API, not a Phase-1 escape hatch.
- Never name a variable `context` (reserved by Odin); the framework context
  is always `ctx`.
- One canonical call per task; do not mix or invent alternatives. Typed query
  extractors are named `query_<type>` / `query_<type>_or` — there is no
  generic `query_or(ctx, name, type, default)`.
- `web.ok(ctx, v)` == `web.json(ctx, .OK, v)`; `web.created(ctx, v)` ==
  `web.json(ctx, .Created, v)`.
- There is no `ctx.response`. Respond only through the helpers above; the
  response object and its commit state are framework-internal.
- Request data is a temporary view valid only during the request. To keep a
  string, header, param or body slice, copy it explicitly with an appropriate
  allocator. Never hand a request view to background work.
- There is no header lookup in Phase 1. `web.header(ctx, name)` is Phase 2 —
  do not invent a Phase-1 substitute, and do not reach into
  `ctx.request.headers` to build one.
- `web.Method` members are UPPERCASE: `.GET`, never `.Get`. `HEAD` and
  `OPTIONS` are not members; those tokens arrive as `.UNKNOWN`.
- `web.Request`, `web.Method` and `web.Header_View` are the only types WP2
  adds. There is no public `Response`, no `Header_Pair`, no `[]Header`, and no
  `method_raw`.
- The only test-support symbols are `web.test_request` and
  `web.Recorded_Response` (see Testing). There is no `testing.test_request`, no
  `Recorded_Response.headers`, no builder, and no cleanup call.
