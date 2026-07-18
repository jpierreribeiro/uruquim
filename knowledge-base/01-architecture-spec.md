# Uruquim — Architecture Specification

## Purpose

This document defines the architecture of Uruquim, a high-performance HTTP
microframework for Odin.

Uruquim borrows the ergonomics *goals* of Gin/FastAPI-class frameworks while
rejecting the implementation assumptions that come from garbage-collected
runtimes, reflection-rich type systems, and object-oriented design. It is
designed to be idiomatic for Odin:

- procedural API style
- explicit data and state
- allocator-aware internals
- transport decoupling
- DOD-first design
- low-allocation hot paths
- no hidden OOP simulation

This document is normative.

## Central Architectural Statement

> Internally data-oriented and allocator-aware; externally simple, productive,
> and predictable.

The framework SHALL hide allocator, router, transport, and response machinery
from ordinary handlers. A user must be able to implement a typed JSON API using
only `app`, route registration, extractors, response helpers, and `serve`.

## Three Equal Commitments

The architecture is governed by three commitments of equal weight:

1. **Performance** — memory correctness and a predictable hot path.
2. **Productivity** — safe defaults, simple CRUD, few mandatory concepts.
3. **AI readability** — canonical API, compiling examples, no aliases, no magic.

Any design decision that maximizes one commitment by materially damaging
another is invalid.

## Productivity as a First-Class Architectural Requirement

The framework SHALL optimize not only for runtime performance, but also for
implementation correctness, discoverability, and low cognitive overhead.

The default application path SHALL:

- require no explicit allocator configuration
- require no explicit transport selection
- provide production-oriented defaults
- expose canonical helpers for common HTTP operations
- allow a functional JSON API to be written with minimal framework knowledge

Advanced memory and transport configuration SHALL remain available through a
separate explicit API.

The framework SHALL provide two usage levels:

1. **Productive API** — default and documented first.
2. **Systems API** — explicit control over allocators, transport, state, and
   lifecycle.

The acceptance metric for the public API is:

> A basic AI coding agent, after reading three examples, can produce a correct
> CRUD API without inventing abstractions.

The ordinary user SHALL NOT need to understand any of the following to ship a
working API: allocators, transport callbacks, buffer ownership, adapter
internals, manual `Context` assembly, response writer construction, or router
initialization. These concerns exist — internally.

## Canonical Transport Direction

The future Odin `core:net/http` package (announced as built on `core:nbio`)
SHALL be treated as the canonical transport backend.

Before it is available or stable, the framework MAY use `laytan/odin-http`
behind an internal adapter.

No public framework API SHALL expose `odin-http` types.

Migration to `core:net/http` SHALL NOT require application-level handler or
routing changes.

The internal boundary is:

```text
Framework Core
    └── Internal HTTP Boundary
            ├── core:net/http adapter — canonical (when available)
            ├── odin-http adapter — bootstrap/compatibility
            └── test transport — in-memory, no sockets
```

Consequences:

1. Development MAY begin on `odin-http`.
2. The public API MUST NEVER depend on its types.
3. When `core:net/http` ships, an official adapter is created.
4. Once the official adapter is stable, the `odin-http` adapter MAY be removed
   or moved to a separate package.
5. The framework SHALL NOT reimplement full HTTP parsing without necessity.

The transport boundary is an **internal** architecture concern. It SHALL NOT
appear in the Quick Start or in ordinary application code. Ordinary usage is:

```odin
web.serve(&app, 8080)
```

Internally, transport selection is resolved by the framework:

```odin
@(private)
default_transport :: proc() -> Transport {
	when ODIN_HAS_CORE_HTTP {
		return core_http_transport()
	} else {
		return odin_http_transport()
	}
}
```

Advanced users MAY inject a transport explicitly:

```odin
web.serve_transport(&app, &custom_transport, web.Serve_Config{port = 8080})
```

This appears only in advanced documentation, never in the Quick Start.

## Public API Surface

### The five concepts

The entire ordinary public API is built from five concepts:

```text
app        create/destroy the application
route      register handlers on methods and paths
extract    read typed values out of the request
respond    write typed responses
serve      run the server
```

### Application

```odin
app := web.app()            // production-oriented defaults
defer web.destroy(&app)

app := web.bare()           // no default middleware or policies (advanced)

app := web.app_with_state(&state)   // app() + registered typed app state
```

`web.app()` SHALL be appropriate for moderate production use, not only demos.
It SHALL configure by default:

- panic recovery
- request body size limit
- read timeout
- write timeout
- header count/size limits
- consistent 404 and 405 handling
- rejection of malformed requests
- startup logging
- graceful shutdown

`web.bare()` creates an application with none of the default middleware or
policies, for users who want full control.

### Routing

```odin
web.get(&app, "/users/:id", get_user)
web.post(&app, "/users", create_user)
web.put(&app, "/users/:id", update_user)
web.patch(&app, "/users/:id", patch_user)
web.delete(&app, "/users/:id", delete_user)
```

Route groups use explicit router values, not configuration callbacks
(callbacks complicate lifetimes and produce less predictable code for AI):

```odin
api := web.router("/api")

web.get(&api, "/users", list_users)
web.post(&api, "/users", create_user)

admin := web.group(&api, "/admin", require_admin)
web.get(&admin, "/stats", stats)

web.mount(&app, &api)
```

### Handlers

```odin
Handler :: proc(ctx: ^web.Context)
```

One signature for handlers and middleware. Handlers write to the context via
response helpers; they do not return values in v1. (Result-returning handlers
`proc(ctx) -> web.Result` are a possible future ergonomic layer; they require
boxing/codegen decisions and SHALL NOT block the first release.)

### Extractors

Extractors read typed values from the request. **On failure, the extractor
writes the standardized error response itself and returns `ok = false`; the
handler only returns.** This is the single most important productivity
mechanism in the framework.

```odin
id, ok := web.path_int(ctx, "id")
if !ok {
	return
}

input, ok := web.body(ctx, Create_User)
if !ok {
	return
}

page  := web.query_or(ctx, "page", int, 1)
name  := web.path_string(ctx, "name")
state := web.state(ctx, App_State)
```

> Note on syntax: `value := f() or_else { ... }` with a statement block is not
> valid Odin (`or_else` takes an expression). The canonical pattern is
> `(value, ok)` + `if !ok { return }`. If prototyping finds a strictly better
> compiling form (e.g. `or_return` against a `web.Result`), the canonical
> pattern may be amended **once**, before Phase 1 freezes.

### Response helpers

Explicit helpers, one per output kind. No `respond(ctx, status, any)` style
overload whose behavior depends on `any`.

```odin
web.ok(ctx, payload)          // 200 + JSON
web.created(ctx, payload)     // 201 + JSON
web.no_content(ctx)           // 204

web.json(ctx, status, payload)   // arbitrary status + JSON
web.text(ctx, status, "pong")
web.bytes(ctx, status, content_type, data)
web.redirect(ctx, .Found, "/login")

web.bad_request(ctx, "invalid input")
web.unauthorized(ctx, "authentication required")
web.forbidden(ctx, "insufficient permission")
web.not_found(ctx, "user")
web.conflict(ctx, "email already registered")
web.internal_error(ctx)
```

`ok`/`created` are defined as exact shorthands of `json` with fixed status;
they are the canonical form for those statuses.

### Serving

```odin
web.serve(&app, 8080)                              // canonical
web.serve_with(&app, web.Serve_Config{             // explicit configuration
	host = "0.0.0.0",
	port = 8080,
})
web.serve_transport(&app, &transport, config)      // advanced: inject transport
```

## Standardized Error Responses

All framework-generated error responses SHALL share one JSON envelope:

```json
{
  "error": {
    "code": "invalid_path_parameter",
    "message": "Path parameter 'id' must be an integer",
    "field": "id"
  }
}
```

Required error codes include at minimum:

- `invalid_path_parameter`
- `invalid_query_parameter`
- `invalid_json`
- `body_too_large`
- `not_found`
- `method_not_allowed`
- `unauthorized`
- `forbidden`
- `internal_error`

The envelope shape and code list are part of the compatibility contract and
SHALL be documented in `docs/errors.md`.

## Context Model

### Default Context (non-parametric)

The default `Context` is a plain struct. It is what nearly every application
and every documentation example uses:

```odin
Context :: struct {
	request:  Request,
	response: Response,

	params: Params,
	route:  Route_Info,

	private: Context_Internal,   // chain cursor, allocators, transport hooks
}
```

The parametric `Context(App_State, Request_State)` form SHALL NOT be the
default public surface: highly parametric signatures are noisy at call sites
and are reproduced incorrectly by AI agents with limited Odin exposure.

### Application state without visible generics

Typed application state is registered once and read with a validated typed
accessor:

```odin
App_State :: struct {
	db:     ^Database,
	config: Config,
}

state := App_State{db = db}
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

Internally this MAY use a `rawptr` + `typeid` pair validated at the boundary:

```odin
App :: struct {
	state_ptr:  rawptr,
	state_type: typeid,
	// ...
}

state :: proc(ctx: ^Context, $T: typeid) -> ^T {
	assert(ctx.private.app.state_type == typeid_of(T),
		"web.state called with a type different from the registered App_State")
	return cast(^T)ctx.private.app.state_ptr
}
```

A single `rawptr` isolated behind a typed, asserted accessor is acceptable; a
`map[string]any` bag spread through the request is not. This distinction is
normative.

### Typed request state — opt-in (Systems API)

Fully typed app + request state remains available for advanced users:

```odin
app: web.Typed_App(App_State, Request_State)

web.app_init(&app, &state, web.App_Config{
	allocator         = allocator,
	request_allocator = request_allocator,
	transport         = transport,
})
```

Or, if compiler ergonomics make full parametrization too costly, via
composition:

```odin
App_Context :: struct {
	using base: web.Context,

	app:     ^App_State,
	request: Request_State,
}
```

The rule: **typed state is an advanced capability, not a tax charged to every
application.** The exact mechanism (parametric specialization vs. composed
context) SHALL be validated with real Odin prototypes before the Systems API
freezes; the Productive API freezes first and independently.

### Dependencies / extraction procedures

There is no dependency-injection container. Composable procedures fill the
role of FastAPI's `Depends`:

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

Extraction procedures follow the extractor contract: respond on failure,
return `(value, ok)`.

## Router

### Responsibilities

- route registration
- route conflict detection
- path matching
- method dispatch
- parameter extraction
- lookup of the precomputed middleware+handler execution chain
- route metadata for observability

### Structure

The router SHALL use one compact radix tree per HTTP method.

Suggested node shape:

```odin
Node_Kind :: enum {
	Static,
	Param,
	Wildcard,
}

Route_Node :: struct {
	prefix: string,
	kind:   Node_Kind,

	static_keys:     [dynamic]u8,
	static_children: [dynamic]^Route_Node,

	param_child:    ^Route_Node,
	wildcard_child: ^Route_Node,

	param_name: string,
	priority:   u32,

	route: ^Resolved_Route,
}
```

### Registration rules

Registration SHALL validate and reject invalid patterns at registration time:

- path must begin with `/`
- wildcard segment must be terminal
- a param segment occupies exactly one path segment
- static and param/wildcard children must not produce ambiguous resolution
- duplicate method+path registrations are invalid
- all conflicts detected early, with clear diagnostics

Route precedence: static > parameter > wildcard.

### Middleware flattening

Registration produces a `Resolved_Route` containing the final flattened
handler chain (global → group nesting order → route middleware → terminal
handler). No chain concatenation occurs during dispatch.

### Parameter storage

Params are written into request-local storage (small fixed array or
pre-capacitied slice). The framework SHALL NOT allocate a map for params on
the hot path.

## Middleware

### User surface

The user surface is trivial; the precomputed chain is internal.

```odin
web.use(&app,
	web.logger(),
	web.recovery(),
	web.cors(web.Cors_Config{
		allowed_origins = {"https://example.com"},
	}),
)
```

Custom middleware is an ordinary handler that calls `web.next`:

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

The user SHALL NOT be required to: return a new handler, assemble wrappers,
manipulate a chain index, use `rawptr`, or provide continuation callbacks.

### Execution model (internal)

Deterministic cursor-based onion semantics:

- `next(ctx)` advances to the next handler
- middleware may run code before and after `next(ctx)`
- returning without calling `next(ctx)` short-circuits
- `abort(ctx)` prevents further downstream execution
- post-`next` code runs in reverse-unwind order

Ordering: app/global middleware → outer groups → inner groups → route
middleware → terminal handler. Stable and test-covered.

### Error and panic policy

- parsing/binding/validation errors are normal response paths
- registration conflicts fail loudly at setup time
- runtime panic recovery is provided by the official recovery middleware,
  installed by default in `web.app()`

## Transport Adapter (internal)

The adapter isolates the core from socket/event-loop, HTTP parser, body
streaming, and server runtime concerns.

```odin
Dispatch_Proc :: proc(req: ^Request, res: ^Response)

Transport :: struct {
	user_data: rawptr,

	init:             proc(t: ^Transport) -> Transport_Error,
	listen_and_serve: proc(t: ^Transport, endpoint: Endpoint, dispatch: Dispatch_Proc) -> Transport_Error,
	shutdown:         proc(t: ^Transport),
	destroy:          proc(t: ^Transport),
}
```

The framework defines its own transport-agnostic `Request` and `Response`
types. Phase 1 assumes buffered request bodies; streaming is a later,
specialized API.

A **test transport** (in-memory, no sockets) is required from Phase 1 so that
`web.test_request` works without binding ports.

## Lifecycle

Request lifecycle:

1. transport accepts and parses into framework-native request view
2. router resolves method/path into `Resolved_Route`
3. framework initializes `Context`
4. framework executes the flattened chain
5. response committed to transport
6. request-local resources cleaned up
7. temp allocator region cleared at transport-defined boundary

Application lifecycle: `app` → registration → (internal transport init) →
`serve` → graceful shutdown → destroy. In the Productive API, steps other than
`app`, registration, `serve`, and `destroy` are invisible.

## Observability

Core requirement, mostly middleware-shaped:

- request ID
- access logging by route pattern (not raw path)
- panic recovery logging
- route pattern introspection
- hook points for metrics/tracing

## Memory Model (internal)

Allocation classes: app-lifetime, router-lifetime, request-lifetime,
scratch/temp. Route trees and flattened chains are router-lifetime; context
and param buffers are request-lifetime or frame-backed; parsing scratch uses
the temp allocator where safe. Allocator ownership is documented for every
init/destroy pair.

None of this appears in the Productive API. `web.app()` selects correct
allocators internally; the Systems API exposes them.

## AI-Friendly API Rules (normative)

- One canonical name per common operation. No equivalent aliases
  (`body`, not also `decode_json`/`parse_body`/`extract_json`/`bind`).
- No overloads whose behavior depends on `any`.
- Prefer explicit helpers: `ok`, `json`, `text`, `body`, `path_int`.
- Every public procedure has a minimal compiling example.
- Public examples are part of the compatibility contract and compile in CI.
- Internal procedures are never documented beside public ones without being
  clearly marked private.
- `docs/canonical-patterns.md` defines the single recommended form for each
  common task; documentation and examples use only those forms.
- `docs/ai-context.md` maintains a compact public-API reference sized for an
  agent context window; it is updated in the same commit as any public API
  change.

## Validation (deferred, prototype-gated)

Tag-driven validation (`validate:"required,min=2"`) and a
`web.body_validated` extractor are attractive but SHALL NOT enter the core
until prototypes establish: real tag-introspection capability, reflection
cost, compile-time metadata options, diagnostic ergonomics, and binary-size
impact. Code generation is the leading candidate mechanism.

## Code Generation (future differentiator, not v1)

An optional CLI (`uruquim generate`) MAY later provide FastAPI-like ergonomics
— attribute-driven route registration, binding, validation, OpenAPI, docs —
by generating plain Odin code, keeping reflection and magic out of the
runtime. The manual canonical API freezes first; codegen targets it.

## Non-Goals for the Core

- ORM/database layer (but see below)
- dependency injection container
- template engine
- WebSocket abstraction in core
- HTTP/2-specific abstractions in core
- reflection-heavy auto-validation in v1
- macro-like hidden magic

**Integration story requirement:** while no ORM ships in core, the framework
SHALL make database/config/auth integration natural via `app_with_state` +
`web.state`, and the cookbook SHALL show a full Postgres-backed CRUD example.

## Reference Project Structure

```text
uruquim/
├── web/                        public package (import web "uruquim:web")
│   ├── app.odin                app / bare / app_with_state / destroy
│   ├── routing.odin            get/post/... , router/group/mount
│   ├── context.odin
│   ├── extract.odin            path_int, body, query_or, state, ...
│   ├── respond.odin            ok, created, json, text, errors, ...
│   ├── serve.odin              serve / serve_with / serve_transport
│   ├── errors.odin             error envelope + codes
│   │
│   ├── internal/
│   │   ├── router/             radix tree, register, lookup, params
│   │   ├── chain/              flattening + cursor execution
│   │   ├── transport/          boundary, odin_http adapter, core_http adapter, test transport
│   │   └── memory/             allocation classes, request arenas
│   │
│   ├── middleware/             logger, recovery, request_id, cors, timeout, secure_headers, body_limit
│   └── testing/                test_request, recorder
│
├── docs/
│   ├── quick-start.md
│   ├── canonical-patterns.md
│   ├── cookbook.md
│   ├── errors.md
│   ├── memory-model.md
│   ├── middleware.md
│   └── ai-context.md
│
└── examples/                   all compiled in CI
    ├── 01-hello-world/
    ├── 02-json-api/
    ├── 03-route-params/
    ├── 04-middleware/
    ├── 05-route-groups/
    ├── 06-authentication/
    ├── 07-crud/
    ├── 08-postgres/
    ├── 09-file-upload/
    └── 10-observability/
```

## Final Architectural Position

The framework is defined by five pillars:

- productive canonical public API (`app` / route / extract / respond / `serve`)
- custom radix router
- deterministic flattened middleware chain
- internal transport boundary with `core:net/http` as the canonical backend
- opt-in typed state (Systems API), never a tax on ordinary applications

Not "FastAPI in Odin", but: **FastAPI's productivity with a data-oriented,
predictable implementation for Odin.**
