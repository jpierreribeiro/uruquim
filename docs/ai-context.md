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
- **Bodies:** JSON decoded into a value you own, capped at **4 MiB** by
  default and configurable with `web.limits`.
- **Responses:** JSON, text, `204`, and five error responders.
- **Automatic errors:** `404` for an unknown path, `405` with an exact `Allow`
  header for a known path under another method — both with a JSON envelope.
- **Middleware:** `web.use` before any route, `web.next` inside; onion order,
  short-circuit, misses observed. Ordering is enforced fail-closed.
- **Route organisation:** `web.router()` builds a detached `Router` with the
  same verbs and `use`; `web.mount(&app, "/prefix", &r)` attaches it. A
  one-route Router is the route-level guard.
- **Request headers:** `web.header` (case-insensitive, first occurrence wins)
  and `web.bearer_token` (strict RFC 6750). Pure lookups — no automatic
  response, nothing logged, values are request-lifetime views.
- **Observability:** `web.observe` registers one observer that receives a
  typed `web.Framework_Event` for every framework-detected failure — kind,
  method, route pattern, status, payload type. Never a message, never a path.
- **Testing:** `web.test_request` runs a request through real routing without a
  socket.
- **HTTP/1 safety:** ambiguous or malformed framing (`CL`+`TE`, duplicate
  `Content-Length`, bad chunking, truncated bodies) is rejected and the
  connection closed.

**Not available yet** — do not emit any of it: a **write deadline** (the read
deadline exists as `Limits.max_request_time`; the write side does not, and no
field for it may be invented); graceful shutdown with a deadline (Phase 4). There is **no request-scoped state** and there will not be one
(ADR-028): `ctx` is not an extension bag, and a value a middleware computes for
a handler is passed down or recomputed. Panic recovery does not exist and never will: Odin has
no recoverable panic (ADR-020). See the appendix.

**Fault behaviour — state it accurately, both halves (ADR-020).**

- A handler that returns **without committing a response** is finalized by the
  response driver to the standardized `internal_error` 500 — logged on the
  server, and carrying no detail about the request. This holds identically
  under `web.serve` and `web.test_request`, identically under `web.app()` and
  `web.bare()`, and identically for the second fault and the hundredth.
- A handler that **faults** — panic, failed assertion, out-of-bounds index, nil
  dereference, divide-by-zero — **aborts the process**. The client gets an
  empty reply. Run under a supervisor.
- Never emit `web.recovery`, a `recovery` middleware, or advice to "wrap the
  handler to catch the panic". None of it exists, and none of it can.

**Two ledgers.** The application API is exactly **51** symbols (32 frozen in
Phase 1, plus `use`/`next`, `Router`/`router`/`mount`,
`header`/`bearer_token`, `observe`/`Framework_Event`/`Framework_Error`,
`logger` and `request_id` from Phase 2, and `route`, `app_with_state`,
`state`, `Limits`, `DEFAULT_LIMITS`, `limits` and `stop` from Phases 3-4). The
test-support API is a separate ledger of exactly **2**. Union: **53**. Do not
fold them together and do not invent a third form.

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

`web.stop(&app)` asks the running server to stop. It **returns immediately** —
it is a request, not a join — so it is safe to call from a signal handler. The
`web.serve` call returns when the drain finishes. Calling it twice, or with no
server running, is a no-op.

**It has no deadline.** A connection a client holds open can delay the drain
indefinitely; `Limits.max_request_time` bounds how long a request may take to
arrive, but it does not bound the drain itself. Run under a supervisor that can
kill, and do not build a control plane that assumes `stop` always completes.

**A blocking handler blocks the drain**, because the event loop is
single-threaded (ADR-030). A handler that sleeps or makes a synchronous call
holds the loop, and nothing — no deadline, no stop — runs until it returns.

### Limits

```text
Limits{max_body, max_request_line, max_headers, max_request_time}
DEFAULT_LIMITS                     4 MiB, 8000, 8000, 30 s (in nanoseconds)
limits(&app, l)                    set it; before the first request
```

<!-- fragment: phase3/limits -->
```odin
budget := web.DEFAULT_LIMITS
budget.max_body = 64 * 1024
web.limits(&app, budget)
```

**Start from `web.DEFAULT_LIMITS` and change what you mean to change.** A
`Limits` with a zero field is rejected: there is no unset state, so a forgotten
field cannot be told from a deliberate one, and the application is refused
fail-closed rather than run on a guess.

- the budget belongs to the **App**, not to `web.serve`, so `web.test_request`
  enforces the same numbers as a socket — a 413 in a test is a 413 in
  production;
- exactly the limit is accepted; one byte more is `413`;
- `web.limits` **after the first request** rejects the application: the budget
  is read on the request path, and changing it while serving would give two
  clients two different answers to the same body. Order relative to routes does
  not matter;
- `DEFAULT_LIMITS` is a **constant**, so no library can change another's
  defaults;
- **`max_request_time` bounds how long one request may take to ARRIVE**, first
  byte to last, in **nanoseconds** (30 s by default; `0` disables it). It is a
  REQUEST deadline, not an idle timeout — a client trickling one byte per second
  would reset an idle timer forever. It does **not** bound a slow handler: that
  is your program's own time.
- **There is still no WRITE deadline**, and no field for one. Do not emit
  `web.Limits{write_timeout = ...}` — it does not exist.

`Limits` bounds Uruquim's own per-request working memory. It does **not** bound
connections, accept backlog or process memory; those belong to the transport and
the operating system.

### Application state

```text
app_with_state(&state) -> App     app() plus ONE typed value; rejects nil
state(ctx, T) -> ^T               that value, typed; asserts before it casts
```

<!-- fragment: phase3/app-state -->
```odin
App_State :: struct {
	greeting: string,
}

main :: proc() {
	state := App_State{greeting = "hi"}
	app := web.app_with_state(&state)
	defer web.destroy(&app)

	web.get(&app, "/config", show_config)
	web.serve(&app, 8080)
}

show_config :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	web.ok(ctx, s^)
}
```

**One value, APP-scoped, created before serving** — a database pool, a config
struct, a cache. `web.app_with_state` gives the same defaults as `web.app()`
plus that value; a nil pointer rejects the application fail-closed.

- the App stores the **pointer**, so a handler writing through it mutates your
  value. The value must **outlive the App** — put it in `main`, beside it;
- `web.state(ctx, T)` asserts that state was registered and that `T` is
  **exactly** the registered type, then returns `^T`. A wrong type aborts: it
  is a programming error, not a runtime condition (ADR-020);
- handlers and middleware read it the same way. There is no second name;
- it is **not** per-request storage, and there is none.

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
- up to eight `:param` segments per pattern (WP33); no wildcards. A pattern
  declaring more is invalid and never matches;
- a static route beats a parametric one by SHAPE, not by registration order;
- methods are isolated: registering GET does not register POST;
- **nothing is normalized.** `/users` and `/users/` are different paths, and
  percent-encoding is neither decoded nor rewritten. WP31b adds REJECTION, not
  transformation: a dot segment, an interior empty segment, a percent-encoded
  slash or a percent-encoded NUL is answered `400` before matching.

Registration conflicts ARE diagnosed (WP30). Two routes registered for the same
method and the same path shape reject the application fail-closed — every
request answers 500 and `web.serve` refuses to start — because the second route
could never have served. Parameter NAMES do not distinguish routes: `/users/:id`
and `/users/:uid` are the same pattern. A pattern this dispatcher cannot
interpret is a separate case and simply never matches.

`web.app()` adds two automatic responses; `web.bare()` adds neither:

```text
unknown path                     -> 404 {"error":{"code":"not_found",...}}
path exists under another method -> 405 + Allow, {"error":{"code":"method_not_allowed",...}}
```

`Allow` lists only the methods registered for that path, always in the order
`GET, POST, PUT, PATCH, DELETE`, comma-and-space separated, with no duplicates.

### Route identity

```text
route(ctx) -> string    the REGISTERED PATTERN, or "" when nothing matched
```

<!-- fragment: phase3/route-identity -->
```odin
by_route :: proc(ctx: ^web.Context) {
	// "/users/:id" — never "/users/42". `record_hit` is YOUR code.
	record_hit(web.route(ctx))
	web.next(ctx)
}
```

`web.route(ctx)` returns the pattern the request matched, so `/users/:id` and
never `/users/42`. Use it — not `ctx.request.path` — to label metrics, logs or
spans: route identity must be **low-cardinality**, and a path-valued label
creates one time series per id and puts user data in a dashboard.

A mounted route reports the composed pattern (`/api/users/:id`). A `404` or a
`405` reports `""`, because no route ran; treat that as the "unmatched" bucket.
The result is a view over App-owned storage and stays valid until `destroy` —
the one value reachable from a `^Context` that outlives its request. It is the
same string `web.Framework_Event.route` carries, by design and by test.

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
is no `ctx.response`, no `ctx.params` and no `ctx.route` **field** — route
identity is read with `web.route(ctx)`, below.

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

## Middleware

```text
use(&app, middleware)   register; MUST come before the first route
next(ctx)               run the rest of the chain from inside a middleware
```

A middleware is an ordinary `Handler`. `use` after any route — or after the
first dispatched request — REJECTS the application fail-closed: every request
answers `500` and `web.serve` refuses to start. Register every `use` first.

<!-- fragment: phase2/bearer-auth -->
```odin
require_auth :: proc(ctx: ^web.Context) {
	token, ok := web.bearer_token(ctx)
	if !ok || !token_is_valid(token) {
		web.unauthorized(ctx, "authentication required")
		return
	}
	web.next(ctx)
}
```

Chains run in `use` order and unwind in reverse (`A>B>C>H<C<B<A`). Returning
without calling `next` short-circuits: nothing downstream runs and your
response wins. Code after `next` runs at unwind, when the response is already
committed — read there, never write (a late response attempt is rejected; the
first response survives). A second `next()` is a no-op; the handler runs
exactly once. Middleware also observe automatic `404`/`405` responses.
`docs/middleware.md` has the full contract.

**The one built-in middleware is `web.logger`.** It is opt-in — there is no
default-on logging — and writes one `.Info` line per request through
`context.logger`:

<!-- fragment: phase2/logger-use -->
```odin
web.use(&app, web.logger)      // before the first route, like every use
```

```text
uruquim: GET /orders/:id 200   method, REGISTERED PATTERN, committed status
uruquim: GET - 404             a miss has no pattern: `-`, never the raw path
uruquim: GET /silent -         nothing was committed while the logger watched
```

It never logs the raw path, the query string, a header, a body byte, or a
captured parameter value. A too-long route field is cut and marked
`...[truncated]`, never grown and never silently dropped. Do not tell a user to
configure its level, sink or format: it has none, by design.

**`web.request_id` is the other built-in.** Opt-in, registered FIRST so later
middleware see the ID:

<!-- fragment: phase2/request-id-use -->
```odin
web.use(&app, web.request_id)
web.use(&app, web.logger)
```

A handler reads it through the ordinary accessor — there is no second name:
`web.header(ctx, "X-Request-Id")`. An inbound ID is honoured ONLY if it matches
`[A-Za-z0-9._-]` and length 1..64; anything else (a space, a control byte, and
above all CR/LF) is DISCARDED and replaced — never echoed, never logged. The ID
appears on every committed response including a 404, a 405 and the standardized
500. **It is unique but NOT unguessable: never present it as authentication.**

## Routers

```text
Router                        a detached collection of routes + middleware
router() -> Router            create; allocates nothing
mount(&app, "/prefix", &r)    attach every route at prefix + pattern
```

A `Router` accepts the SAME procedures an `App` does — `use`, the five verbs,
`destroy` — with no new forms. Build it fully (every `use` before its first
route), then mount it; `mount` COPIES, closes the router (later registrations
on it fail closed), and counts as a registration for the app. Destroy the app
AND every router, each exactly once. `web.group` stays unavailable in every
future phase (ADR-024) — a mounted Router is the one canonical grouping.

<!-- fragment: phase2/router-mount -->
```odin
api := web.router()
defer web.destroy(&api)
web.use(&api, require_auth)
web.get(&api, "/users", list_users)

web.mount(&app, "/api", &api)
```

The prefix must begin with `/` and must not end with `/`; the mounted pattern
is prefix + pattern VERBATIM (nothing is normalised, so a router's `"/"`
mounted at `"/api"` serves `"/api/"`, not `"/api"`). Chain order: app globals,
then each enclosing router outermost-first, then the handler. A route needing
its own guard is a ONE-ROUTE Router mounted at the path.

## Request headers

```text
header(ctx, name)  -> (value, ok)   the effective request header
bearer_token(ctx)  -> (value, ok)   strict RFC 6750 Authorization parse
```

Both are PURE lookups: they never commit a response (unlike the extractors —
an absent header is routinely not an error) and never log. `ok` means
presence; an empty value is present. Names are case-insensitive; duplicates:
first occurrence wins. Values are VIEWS valid only for the request — copy to
persist. The token comes back verbatim: never trimmed, never normalised; a
sloppy `Authorization` (two spaces, trailing blank, wrong scheme) is rejected,
not repaired.

<!-- fragment: phase2/bearer-auth -->
```odin
require_auth :: proc(ctx: ^web.Context) {
	token, ok := web.bearer_token(ctx)
	if !ok || !token_is_valid(token) {
		web.unauthorized(ctx, "authentication required")
		return
	}
	web.next(ctx)
}
```

## Observability

```text
observe(&app, observer)   register ONE observer; a later call replaces it
Framework_Event{kind, method, route, status, payload_type}
Framework_Error           closed enum: the framework failure kinds
```

An observer is a plain procedure taking the event **by value**:

<!-- fragment: phase2/observe -->
```odin
report_failure :: proc(event: web.Framework_Event) {
	metrics_increment(event.kind, event.route, event.status)
}
```

It receives the event and **nothing else** — no `ctx`, no body, no headers —
so it cannot respond and cannot read request bytes. `route` is the REGISTERED
PATTERN (`/users/:id`), never the request path, and is `""` when no route
matched; no field carries a message. `status` is what the framework actually
committed; a failure outside a request (`serve` could not bind) carries no
method, route or status.

It fires for framework-detected FAILURES only — a marshal failure, an
undecodable body, a double `web.body`, a handler that committed nothing, an
invalid or unavailable `serve` port, a fail-closed application. A `404` or a
`400` from an extractor is a normal outcome, not a failure, and emits nothing.
Installing an observer changes no response.

## Testing

The test-support ledger is exactly **2** symbols, tracked separately from the
51 application symbols.

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
result here matches what a real client gets. `body`, `query` and `headers` are
optional parameters; each `headers` element is one `"Name: value"` line
(`headers = {"Authorization: Bearer tok"}`). `Recorded_Response` exposes
`status` and `body` only — there is no public way to read response headers.

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

<!-- phase: 4; unavailable -->
```odin
// Phase 4 — unavailable in Phase 1.
web.serve_with(&app, web.Serve_Config{host = "0.0.0.0", port = 8080})
```

Other names reserved for later phases, none of which exist today:
`web.serve_transport`, `web.body_limit`, `web.bytes`, `web.redirect`,
`web.conflict`. Two names will NEVER exist: `web.recovery` (ADR-020) and
`web.group` (ADR-024).

Phase boundaries in one line each:

- **Phase 2** — middleware, route organisation, header lookup, the typed
  error observer, the built-in `logger` and `request_id` (all delivered). No
  panic recovery — Odin has no recoverable panic (ADR-020).
- **Phase 3** — route groups, typed application state, configurable limits and
  read/write timeouts.
- **Phase 4** — graceful shutdown with a deadline, security hardening.
