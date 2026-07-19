# Uruquim API Reference for Coding Agents

Paste this file into your agent's context (Cursor rules, CLAUDE.md, etc.).

**Use only the APIs documented in the Phase-1 sections below. Do not invent
procedures, aliases, or alternative forms. If something is not listed here, it
does not exist.** Anything under *Appendix — future phases* is NOT available and
must never be emitted.

## What works today

Uruquim is a working HTTP framework: `web.serve` binds a port and answers real
requests, routing and extractors work, JSON goes in and out, and every error is
a standardized JSON envelope.

- **Server:** `web.serve(&app, port)` binds IPv4 and blocks while serving.
- **Routing:** static and `:param` segments; a static route always wins over a
  parametric one, regardless of registration order.
- **Extractors:** path and query values; a fallible one answers `400` itself.
- **Bodies:** JSON decoded into a value you own, capped at a fixed **4 MiB**.
- **Responses:** JSON, text, `204`, and five error responders.
- **Automatic errors:** `404` for an unknown path, `405` with an exact `Allow`
  header for a known path under another method — both with a JSON envelope.
- **Testing:** `web.test_request` runs a request through real routing without a
  socket.
- **HTTP/1 safety:** ambiguous or malformed framing (`CL`+`TE`, duplicate
  `Content-Length`, bad chunking, truncated bodies) is rejected and the
  connection closed.

**Not available in Phase 1** — do not emit any of it: middleware, route groups,
typed application state, panic recovery (Phase 2); configurable limits and
read/write timeouts (Phase 3); graceful shutdown with a deadline (Phase 4);
request header lookup (Phase 2). See the appendix.

**Two ledgers.** The application API is exactly **32** symbols. The test-support
API is a separate ledger of exactly **2**. Union: **34**. Do not fold them
together and do not invent a third form.

## Application

```text
App        the application value
app()      create with the Phase-1 defaults (404 + 405)
bare()     create with NO automatic 404/405
destroy()  release; call exactly once, on the value app()/bare() returned
```

<!-- fragment: phase1/app-lifecycle -->
```odin
main :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/ping", ping)

	web.serve(&app, 8080)
}
```

`App` is non-copyable by contract: keep the value `app()` returned, pass
`&app` everywhere, and destroy that same value once.

`serve(a: ^App, port: int)` validates the port (1..65535), binds IPv4 Any and
blocks. An invalid port or a bind failure is logged and returns without
serving.

## Routing

```text
get(&app, pattern, handler)
post(&app, pattern, handler)
put(&app, pattern, handler)
patch(&app, pattern, handler)
delete(&app, pattern, handler)
```

<!-- fragment: phase1/routing -->
```odin
web.get(&app, "/users/me", current_user)
web.get(&app, "/users/:id", get_user)
web.post(&app, "/users", create_user)
```

Pattern rules:

- patterns begin with `/`; `/` itself is valid;
- `:name` matches exactly one whole segment and never spans a `/`;
- at most one `:param` per pattern in Phase 1; no wildcards;
- a static route beats a parametric one by SHAPE, not by registration order;
- methods are isolated: registering GET does not register POST;
- **nothing is normalized.** `/users` and `/users/` are different paths.
  Percent-encoding and `.`/`..` segments are not decoded.

Registration conflicts are not diagnosed in Phase 1. A pattern this dispatcher
cannot interpret simply never matches.

`web.app()` adds two automatic responses; `web.bare()` adds neither:

```text
unknown path                     -> 404 {"error":{"code":"not_found",...}}
path exists under another method -> 405 + Allow, {"error":{"code":"method_not_allowed",...}}
```

`Allow` lists only the methods registered for that path, always in the order
`GET, POST, PUT, PATCH, DELETE`, comma-and-space separated, with no duplicates.

A method outside the `Method` set arrives as `.UNKNOWN` and follows the same
404/405 rules. It never produces a 501.

## Handler

`Handler` is the one and only handler shape. It takes the context and returns
nothing; it answers through a response helper.

<!-- fragment: phase1/readme-taste -->
```odin
get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	web.ok(ctx, User{id = id, name = "Ada"})
}
```

A handler that returns without responding is a programming error: the driver
logs it and sends `500`. HTTP has no zero status.

## Request

`ctx.request` is the only public request surface — a `web.Request` value. There
is no `ctx.response`, no `ctx.params` and no `ctx.route`.

<!-- pseudocode: the Request field list -->
```odin
ctx.request.method   // web.Method
ctx.request.path     // string  — view
ctx.request.query    // string  — view, raw and undecoded
ctx.request.headers  // web.Header_View — no lookup in Phase 1
ctx.request.body     // []u8    — view
```

`Method` members are UPPERCASE. The complete set:

```text
.UNKNOWN  .GET  .POST  .PUT  .PATCH  .DELETE
```

Any other token — `"HEAD"`, `"OPTIONS"`, `"PROPFIND"`, or a lowercase `"get"`,
since HTTP methods are case-sensitive — arrives as `.UNKNOWN`.

**Lifetime.** Every request-derived string and slice is a VIEW over storage the
transport owns for the duration of one request. To keep any of it, copy it
explicitly:

<!-- fragment: phase1/copy-to-persist -->
```odin
keep_a_path :: proc(ctx: ^web.Context) -> string {
	name := web.path(ctx, "name")
	return clone_for_later(name)
}
```

Never hand a `^Context` or a request view to background work.

## Extractors

Every extractor that can fail RESPONDS TO THE CLIENT ITSELF and returns
`false`. On failure, just `return` — never write your own error response for an
extractor failure.

There are exactly two shapes:

<!-- fragment: phase1/path-int -->
```odin
// Shape 1 — value-producing: (value, ok)
get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	web.ok(ctx, User{id = id, name = "Ada"})
}
```

<!-- fragment: phase1/body -->
```odin
// Shape 2 — destination-filling: bool
create_user :: proc(ctx: ^web.Context) {
	input: Create_User
	if !web.body(ctx, &input) {
		return
	}

	web.created(ctx, User{id = 1, name = input.name})
}
```

The full set:

```text
path(ctx, name)            -> string          route matched => present; never responds
path_int(ctx, name)        -> (int, ok)       responds 400 on failure
query(ctx, name)           -> (string, found) never responds
query_int(ctx, name)       -> (int, ok)       responds 400 when absent or malformed
query_int_or(ctx, n, def)  -> (int, ok)       default ONLY when absent
body(ctx, &dst)            -> bool            responds 400/413 on failure
```

<!-- fragment: phase1/query -->
```odin
search :: proc(ctx: ^web.Context) {
	q, found := web.query(ctx, "q")
	if !found {
		web.bad_request(ctx, "the 'q' parameter is required")
		return
	}

	limit, ok := web.query_int_or(ctx, "limit", 20)
	if !ok {
		return
	}

	web.ok(ctx, User{id = limit, name = q})
}
```

Semantics you must not guess at:

- **Views, not copies.** `path` and `query` return views over the request.
- **The default applies only to ABSENCE.** `?limit=banana` and `?limit=` are
  both `400`, never `20`. Presence is decided by the key.
- **A key with no `=` is present with an empty value.** `?flag` gives
  `("", true)`; an absent key gives `("", false)`.
- **Integers are strict decimal:** an optional `-` then ASCII digits. `+5`,
  `0x10`, `1_000`, `1.5` and surrounding whitespace are rejected.
- **Comparison is exact and case-sensitive**, for path and query names.
- **Nothing is decoded.** `?q=a%20b` yields the literal `a%20b`.
- **`body` is single-use.** Call it at most once per request; a second call
  decodes nothing. After it returns false, `dst` is undefined — discard it.
- **The body cap is a fixed 4 MiB.** An oversized request is `413` before your
  handler runs, even if the handler never calls `body`.

JSON structs use tags:

<!-- pseudocode: a DTO with json tags -->
```odin
User :: struct {
	id:   int    `json:"id"`,
	name: string `json:"name"`,
}
```

## Responses

<!-- fragment: phase1/responses -->
```odin
respond_examples :: proc(ctx: ^web.Context) {
	web.ok(ctx, User{id = 1, name = "Ada"})
	web.created(ctx, User{id = 2, name = "Grace"})
	web.json(ctx, .Accepted, User{id = 3, name = "Queued"})
	web.text(ctx, .OK, "pong")
	web.no_content(ctx)
}
```

```text
ok(ctx, value)               200 JSON   — exactly json(ctx, .OK, value)
created(ctx, value)          201 JSON   — exactly json(ctx, .Created, value)
json(ctx, status, value)     any status, JSON
text(ctx, status, s)         plain text
no_content(ctx)              204, no body, no Content-Type
```

The status argument has type `Status`, so write an inferred enum member, never
a bare integer. The complete set:

```text
.OK .Created .Accepted .No_Content
.Bad_Request .Unauthorized .Forbidden .Not_Found .Method_Not_Allowed
.Internal_Server_Error
```

`Content-Type` is set for you: `application/json` for JSON and every envelope,
`text/plain; charset=utf-8` for text, none for `no_content`. There is no way to
set a response header yourself in Phase 1.

**Payloads are VALUES.** `web.ok(ctx, user)` — never a pointer, and never a
variable whose type is `^User`. A rejected payload is logged on the server and
answered with one complete `500`; no partial body is ever sent.

**The first response wins.** Once a response is committed, later responders are
no-ops. That is what makes "the extractor already answered, just return" safe.

## Errors

<!-- fragment: phase1/errors -->
```odin
deny :: proc(ctx: ^web.Context) {
	web.bad_request(ctx, "email is required")
}
```

```text
bad_request(ctx, message)     400
unauthorized(ctx, message)    401
forbidden(ctx, message)       403
not_found(ctx, resource)      404  message: Resource '<resource>' not found
internal_error(ctx)           500  takes no message on purpose
```

All errors share one envelope:

```json
{"error": {"code": "...", "message": "...", "field": "..."}}
```

`field` is present only for the two extractor errors
(`invalid_path_parameter`, `invalid_query_parameter`). For every other code it
is **omitted entirely** — never `null`, never `""`. `docs/errors.md` documents
each code.

## Testing

The test-support ledger is exactly **2** symbols, tracked separately from the
32 application symbols.

```text
test_request(&app, method, path) -> Recorded_Response
Recorded_Response{status, body}
```

<!-- fragment: phase1/test-request -->
```odin
check_ping :: proc() -> bool {
	app := web.app()
	defer web.destroy(&app)
	web.get(&app, "/ping", ping)

	res := web.test_request(&app, .GET, "/ping")
	return res.status == .OK && res.body == "pong"
}
```

It drives the REAL routing and the real response pipeline with no socket, so a
result here matches what a real client gets. It takes a method and a path and
nothing else: there is no query, header or body argument. `Recorded_Response`
exposes `status` and `body` only — there is no public way to read response
headers.

`body` stays valid until `web.destroy(&app)`.

## Full example (copy this shape)

The complete programs live in `examples/`. The smallest one:

<!-- compile: examples/01-hello-world/main.odin -->
```odin
package main

import web "uruquim:web"

main :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/ping", ping)

	web.serve(&app, 8080)
}

ping :: proc(ctx: ^web.Context) {
	web.text(ctx, .OK, "pong")
}
```

See `examples/02-json-api` for a CRUD-shaped API and
`examples/03-route-params` for path and query handling.

## Rules

- Never use `or_else` with a statement block — that is not valid Odin. Use
  `(value, ok)` plus `if !ok { return }`, or `if !web.body(ctx, &input) { return }`.
- Every fallible extractor's `ok` MUST be captured and checked; the compiler
  enforces it.
- `web.body` takes a POINTER to your struct and returns `bool`. Call it once.
- JSON payloads are passed BY VALUE. Do not pass `&value` or a pointer-typed
  variable.
- Method members are UPPERCASE: `.GET`, never `.Get`.
- Never configure allocators or transports — `web.app()` and `web.serve`
  handle them.
- Never store request data in maps or `any`; there is no `ctx.user_data`.
- Copy request-derived data explicitly if it must outlive the request.

---

## Appendix — future phases

**Everything below is UNAVAILABLE in Phase 1. Do not emit it.** It is listed
only so an agent recognizes the names and refuses them.

<!-- phase: 2; unavailable -->
```odin
// Phase 2 — unavailable in Phase 1.
web.use(&app, web.logger())
web.use(&app, web.recovery())
value, found := web.header(ctx, "x-api-key")
token, found := web.bearer_token(ctx)
```

<!-- phase: 3; unavailable -->
```odin
// Phase 3 — unavailable in Phase 1.
api := web.group(&app, "/api/v1")
state := web.state(ctx, App_State)
app := web.app_with_state(&my_state)
```

<!-- phase: 4; unavailable -->
```odin
// Phase 4 — unavailable in Phase 1.
web.serve_with(&app, web.Serve_Config{host = "0.0.0.0", port = 8080})
```

Other names reserved for later phases, none of which exist today:
`web.next`, `web.router`, `web.mount`, `web.serve_transport`,
`web.body_limit`, `web.bytes`, `web.redirect`, `web.conflict`.

Phase boundaries in one line each:

- **Phase 2** — middleware, panic recovery, header lookup, auth helpers.
- **Phase 3** — route groups, typed application state, configurable limits and
  read/write timeouts.
- **Phase 4** — graceful shutdown with a deadline, security hardening.
