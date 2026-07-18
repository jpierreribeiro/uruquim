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
- no code generator, no mandatory CLI, no heavy metaprogramming

**Note on `web.app()` defaults:** the architecture spec defines the full
default-policy contract (recovery, limits, timeouts, 404/405, graceful
shutdown). It is delivered progressively — recovery in Phase 2, limits and
timeouts in Phase 3, shutdown robustness in Phase 4 — but the *end-state
contract* is fixed now and each phase moves `web.app()` closer to it.

## Phase 1 — Minimal Productive API

### Goal

A user can build a small JSON API with routes, extractors, and JSON/text
responses, without touching transport internals. Not just Hello World: the
phase is complete only when a small CRUD-style API is writable from the
public API alone.

### Scope (required)

- application: `web.app()`, `web.bare()`, `web.destroy`
- routes: `web.get`, `web.post`, `web.put`, `web.patch`, `web.delete`
  (static and `:param`), via a simple interim dispatcher
- `web.Context` (plain struct, non-parametric)
- path extractors: `web.path`, `web.path_int`
- query extractors: `web.query`, `web.query_int`, `web.query_int_or`
- JSON body: `web.body(ctx, &dst)`
- responses: `web.ok`, `web.created`, `web.no_content`, `web.json`,
  `web.text`
- error helpers + standardized envelope: `bad_request`, `unauthorized`,
  `forbidden`, `not_found`, `internal_error`
- consistent 404 behavior
- server: `web.serve(&app, port)` with clean stop
- internal transport boundary (`Transport` struct) prepared for
  `core:net/http`; functional bootstrap adapter over `odin-http`
- in-memory test transport + `web.test_request` (required by the tests-first
  process itself)

### Forbidden in this phase

- middleware registration (`web.use`), groups
- radix tree (interim dispatcher must already match the routing spec's
  observable behavior — precedence, 404 — so Phase 3 changes nothing
  publicly)
- streaming, uploads, validation system
- Advanced API surface (`app_init`, `Advanced_Config`, `serve_transport`,
  typed state)
- OpenAPI

### Spec Gate checklist

- [ ] freeze the canonical vocabulary (app/routes/extractors/responses/serve)
- [ ] freeze the extractor control flow: `(value, ok)` + `#optional_ok` for
      value-producing; `^$T` destination + `bool` for `web.body`
- [ ] freeze `query_int_or` semantics (default only on absence; malformed
      value is a 400)
- [ ] freeze the error envelope and initial code list
- [ ] define `Request`/`Response` minimum fields and commit semantics
- [ ] define the `Transport` boundary and test-transport contract
- [ ] define clean-stop behavior

### Test Gate checklist

- [ ] static route returns expected status and body
- [ ] `:param` route extracts value; `path_int` failure produces
      `invalid_path_parameter`
- [ ] `web.query_int` missing/malformed produces `invalid_query_parameter`
- [ ] `web.query_int_or`: absent → default; malformed → 400
- [ ] `web.body` success and `invalid_json` failure paths
- [ ] unknown route returns standardized 404
- [ ] `web.ok`/`web.created` byte-identical to equivalent `web.json` calls
- [ ] `test_request` round-trips without sockets
- [ ] adapter starts and stops cleanly; response cannot be committed twice

### Implementation Gate checklist

- [ ] odin-http bootstrap adapter implemented behind the boundary
- [ ] test transport implemented
- [ ] examples `01-hello-world`, `02-json-api`, `03-route-params` compile and
      run in CI
- [ ] small CRUD example writable using only public API (proof of goal)
- [ ] no transport-native types leak into public signatures
- [ ] `docs/quick-start.md`, `docs/errors.md`, `docs/canonical-patterns.md`,
      `docs/ai-context.md` cover the shipped surface

## Phase 2 — Middleware and Groups

### Goal

Deterministic middleware and route organization, still on the interim
dispatcher.

### Scope (required)

- `web.use` at app, group, and route level
- route groups: `web.router`, `web.group`, `web.mount`
- `web.next`; short-circuit by returning without `next`
- recovery middleware — becomes default-on in `web.app()`
- logger middleware
- request ID middleware
- `web.header`, `web.bearer_token` lookups
- documented auth pattern: gate-only `require_auth` middleware + typed
  `current_user` extraction procedure (no `user_data` field, ever)

### Spec Gate checklist

- [ ] exact ordering rules (global → outer groups → inner → route → handler)
- [ ] **onion decision:** post-`next` semantics supported only if the
      transport boundary guarantees them without confusing behavior
      (prototype on the bootstrap transport); otherwise simplify to
      pre-handler + short-circuit
- [ ] chain flattening at registration time specified
- [ ] recovery semantics; request ID source/generation

### Test Gate checklist

- [ ] middleware order exactness, including nested groups
- [ ] short-circuit stops downstream
- [ ] post-`next` unwind order correct (if onion adopted)
- [ ] recovery converts panic to standardized 500
- [ ] request ID present in context and response header
- [ ] `web.bare()` installs none of the defaults

### Implementation Gate checklist

- [ ] flattened chains built at registration; no dispatch-time assembly
- [ ] recovery, logger, request ID implemented
- [ ] examples `04-middleware`, `05-route-groups`, `06-authentication`
- [ ] all Phase 1 public-behavior tests still pass unchanged

## Phase 3 — Performance Core

### Goal

Replace the interim internals with the real data-oriented core, with no
public API change.

### Scope (required)

- method-sharded radix tree router (static, `:param`, terminal `*wildcard`)
- zero-allocation lookup on the common path
- params in small fixed buffers (no maps)
- route conflict detection with diagnostics; 405 behavior
- precomputed middleware chains (from Phase 2) verified allocation-free at
  dispatch
- per-request arena; reusable buffers
- allocation reduction pass across the hot path
- body size limit and read/write timeouts — become default-on in `web.app()`
- benchmark suite (lookup, dispatch, JSON round-trip) with regression harness

### Spec Gate checklist

- [ ] radix node shape; precedence rules; duplicate/conflict rules
- [ ] path normalization policy; 405 and OPTIONS policy
- [ ] param representation; arena lifetime contract
- [ ] default limit/timeout values for `web.app()`

### Test Gate checklist

- [ ] static beats param; param beats wildcard
- [ ] duplicate registration rejected; invalid wildcard placement rejected
- [ ] per-method routing isolated; 405 when route exists on another method
- [ ] matched pattern preserved for instrumentation
- [ ] fuzz/property tests for insert+lookup invariants
- [ ] oversized body produces `body_too_large`; timeout behavior covered

### Implementation Gate checklist

- [ ] radix insert/lookup implemented; params without map allocation
- [ ] arena + buffer reuse implemented; hot path allocation-reviewed
- [ ] benchmarks recorded; regression harness in CI
- [ ] all Phase 1–2 public-behavior tests pass unchanged

## Phase 4 — Production

### Goal

Harden for serious use.

### Scope (required)

- graceful shutdown robustness (in-flight requests covered)
- CORS middleware; secure headers middleware
- cookies helpers
- file uploads (fully specified multipart contract)
- static file serving
- structured logging; observability hooks (route-pattern keyed metrics and
  tracing points)
- load tests
- allocator/lifetime audit

### Gates (summary)

- Spec: shutdown guarantees; upload/static contracts; telemetry hook points
- Test: shutdown with in-flight requests; upload limits; recovery+telemetry
  interaction; load-test baseline recorded
- Implementation: hardening middleware done; audit completed; examples
  `07-crud`, `08-postgres`, `09-file-upload`, `10-observability`; docs
  `memory-model.md`, `middleware.md`, `cookbook.md` complete

## Phase 5 — Future

### Goal

Optional layers and the canonical transport, without disturbing the frozen
API.

### Scope (candidates, each spec-gated individually)

- **official `core:net/http` adapter** when the package ships — parity tests
  against the bootstrap adapter; migration verified to require zero
  application changes; bootstrap adapter then demoted or removed. (If
  `core:net/http` ships earlier, this item may be pulled forward between
  phases.)
- OpenAPI as an optional layer over the existing API (`web.Route_Info`
  direction); no handler rewrites required
- automatic documentation from the OpenAPI layer
- WebSocket (separate package)
- streaming request/response APIs
- HTTP/2, as the official transport permits
- Advanced API completion: `app_init` + `Advanced_Config`, typed
  `Request_State`, `serve_transport`
- validation story decision (explicit vs tag-based), prototype-gated, never
  requiring a generator
- project templates

## Exit Criteria for the Project Core

The framework core is architecturally established only when:

- a small JSON CRUD API can be written from `docs/ai-context.md` alone
- the router is custom, benchmarked, and fully test-covered
- middleware semantics are stable and test-pinned
- transport is decoupled, with `core:net/http` as canonical backend
- the hot path has been allocation-reviewed
- every documented example compiles in CI
