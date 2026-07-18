# Uruquim — Development Phases

## Process Contract

Every phase follows this strict rule:

- finalize spec statements for the phase
- write tests for the phase
- implement only after tests exist
- do not expand scope mid-phase unless the specification is amended first

Each phase has three mandatory gates: **Spec Gate**, **Test Gate**,
**Implementation Gate**. A phase is not complete until all three pass.

Cross-phase invariants, enforced from Phase 1 onward:

- no transport-native types in any public signature
- every documented example compiles in CI
- `docs/ai-context.md` matches the public API at every merge

## Phase One — Productive Vertical Slice

### Goal

Not "Hello World". The phase is complete only when a user can build a small
JSON CRUD-style API without accessing transport internals.

### Scope (required)

- application creation with safe defaults: `web.app()`, `web.bare()`,
  `web.destroy`
- GET and POST routing (static and `:param` routes; full method set may land
  in Phase 2 with the real router)
- query access: `web.query_or`
- path extractors: `web.path_int`, `web.path_string`
- JSON rendering: `web.ok`, `web.created`, `web.no_content`, `web.json`,
  `web.text`
- JSON binding: `web.body`
- standardized error envelope + helpers (`bad_request`, `not_found`,
  `unauthorized`, `forbidden`, `internal_error`)
- body size limit (default-on)
- panic recovery (default-on)
- consistent 404 behavior
- in-memory testing harness: `web.test_request` over the test transport
- internal transport boundary (`Transport` struct) prepared for
  `core:net/http`
- functional bootstrap adapter over `odin-http`
- transport-neutral public handler API: `proc(ctx: ^web.Context)`
- `web.serve(&app, port)` and graceful shutdown

Routing MAY use a simple interim dispatcher; the radix router is Phase 2. The
interim dispatcher's *observable behavior* (precedence, 404) must already
match the router spec so Phase 2 changes nothing publicly.

### Forbidden in this phase

- route groups, middleware registration API (`web.use`) beyond the built-in
  defaults
- streaming bodies
- validation system
- observability beyond startup/access logging needed for debugging
- Systems API surface (`Typed_App`, custom allocators, `serve_transport`)

### Spec Gate checklist

- [ ] freeze canonical names for everything in scope (extract/respond/app/serve)
- [ ] define the standardized error envelope and initial code list
- [ ] define extractor contract (respond-on-failure, `(value, ok)`)
- [ ] define `Request`/`Response` minimum fields and commit semantics
- [ ] define the `Transport` boundary and test-transport contract
- [ ] define default policies of `web.app()` (limits, timeouts, recovery)
- [ ] define shutdown behavior

### Test Gate checklist

- [ ] static route returns expected status and body
- [ ] `:param` route extracts value; `path_int` failure returns the
      standardized `invalid_path_parameter` response
- [ ] `web.body` success and `invalid_json` failure paths
- [ ] oversized body returns `body_too_large`
- [ ] unknown route returns standardized 404
- [ ] panic in handler returns 500 via recovery
- [ ] `test_request` round-trips without sockets
- [ ] adapter starts and stops cleanly; response cannot be committed twice
- [ ] `web.bare()` installs none of the default policies

### Implementation Gate checklist

- [ ] odin-http bootstrap adapter implemented behind the boundary
- [ ] test transport implemented
- [ ] examples `01-hello-world`, `02-json-api`, `03-route-params` compile and
      run in CI
- [ ] a small CRUD example is writable using only public API (proof of goal)
- [ ] no transport-native types leak into public signatures
- [ ] `docs/quick-start.md`, `docs/errors.md`, `docs/canonical-patterns.md`,
      `docs/ai-context.md` cover the shipped surface

## Phase Two — Custom Router

### Goal

Replace the interim dispatcher with a real method-sharded radix router,
with no public API change.

### Scope (required)

- router init/destroy; one radix tree per HTTP method
- full method set: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- static segments, `:param`, terminal `*wildcard`
- zero-allocation lookup on the hot path
- route conflict detection with diagnostics
- 404 and 405 behavior
- route pattern metadata preserved for observability
- benchmarks (registration excluded, lookup measured)

### Forbidden

- middleware composition API
- binding/validation changes
- streaming

### Spec Gate checklist

- [ ] radix node shape; precedence rules; duplicate/conflict rules
- [ ] path normalization policy
- [ ] param extraction representation (no maps)
- [ ] 405 and OPTIONS policy

### Test Gate checklist

- [ ] static/param/wildcard match; static beats param; param beats wildcard
- [ ] duplicate registration rejected; invalid wildcard placement rejected
- [ ] per-method routing isolated; 405 when route exists on another method
- [ ] matched pattern preserved for instrumentation
- [ ] fuzz/property tests for insert+lookup invariants

### Implementation Gate checklist

- [ ] radix insert/lookup implemented; conflict diagnostics implemented
- [ ] params populated without map allocation
- [ ] lookup hot path reviewed for avoidable allocations; benchmarks recorded
- [ ] all Phase 1 public-behavior tests still pass unchanged

## Phase Three — Middleware and Typed State

### Goal

Deterministic middleware composition and the opt-in typed state story.

### Scope (required)

- `web.use` at app, group, and route level; `web.router` / `web.group` /
  `web.mount`
- onion semantics: `web.next`, short-circuit, `abort`
- chain flattening at registration time
- application state: `web.app_with_state` + `web.state(ctx, T)` with
  typeid-validated access
- per-request state pattern (documented canonical pattern; Systems API
  `Typed_App` prototype)
- auth pattern via extraction procedures (`current_user`-style)
- logger middleware (route-pattern aware)
- request ID middleware

### Spec Gate checklist

- [ ] exact ordering rules (global → outer groups → inner → route → handler)
- [ ] abort semantics; post-`next` unwind order
- [ ] `app_with_state` registration and validation semantics
- [ ] Systems API prototype decision: parametric `Typed_App` vs composed
      context — decided with real compiled prototypes

### Test Gate checklist

- [ ] middleware order exactness, including nested groups
- [ ] short-circuit stops downstream; unwind order correct
- [ ] `web.state` returns registered state; wrong type asserts
- [ ] request ID present in context and response header
- [ ] typed request state writable in middleware, readable in handler

### Implementation Gate checklist

- [ ] flattened chains built at registration; no dispatch-time assembly
- [ ] logger, request ID implemented
- [ ] examples `04-middleware`, `05-route-groups`, `06-authentication`
- [ ] all phase tests pass

## Phase Four — Production

### Goal

Harden for serious use.

### Scope (required)

- read/write timeouts wired through config; timeout middleware
- CORS middleware; secure headers middleware
- graceful shutdown robustness (in-flight requests covered)
- cookies helpers
- file upload (fully specified multipart contract) and static file serving
- structured logging
- metrics and tracing hooks (route-pattern keyed)
- allocator/lifetime audit; benchmark regression harness
- request/response edge-case coverage

### Gates (summary)

- Spec: timeout semantics; telemetry hook points; upload/static contracts;
  shutdown guarantees
- Test: timeout behavior; shutdown with in-flight requests; recovery +
  telemetry interaction; upload limits; benchmark harness exists
- Implementation: hardening middleware done; audit completed; examples
  `07-crud`, `08-postgres`, `09-file-upload`, `10-observability`; docs
  `memory-model.md`, `middleware.md`, `cookbook.md` complete

## Phase Five — Ecosystem and AI

### Goal

Make Uruquim maximally usable by humans and coding agents, and land the
canonical transport.

### Scope

- canonical documentation pass (quick-start, cookbook, errors complete and
  example-verified)
- `docs/ai-context.md` finalized as a maintained compatibility artifact
- project templates
- optional CLI (`uruquim new`, `uruquim generate` exploration)
- OpenAPI generation (likely codegen-based)
- integrations (Postgres pool pattern, config loading pattern)
- **official `core:net/http` adapter** when the package ships; parity tests
  against the bootstrap adapter; bootstrap adapter then demoted or removed
- validation story decision (tag-based vs codegen), prototype-gated

### Gates (summary)

- Spec: adapter parity contract; codegen scope; validation decision recorded
- Test: adapter parity suite green on both transports; docs examples compile;
  template projects build
- Implementation: `core:net/http` adapter shipped as canonical; migration
  verified to require zero application changes

## Exit Criteria for the Project Core

The framework core is architecturally established only when:

- a small JSON CRUD API can be written from `docs/ai-context.md` alone
- the router is custom, benchmarked, and fully test-covered
- middleware semantics are stable and test-pinned
- transport is decoupled, with `core:net/http` as canonical backend
- the hot path has been allocation-reviewed
- every documented example compiles in CI
