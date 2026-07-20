# Changelog

All notable changes to Uruquim are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is **not** semantic yet, because **there has been no release**. No
tag exists, and cutting one is an owner decision.

## [Unreleased]

Phase 1 is complete and its public contracts are frozen. What "frozen" means,
symbol by symbol with the evidence behind each, is in
`planning/phase-1-freeze.md`. Phase 2 has begun; its growth is recorded as
freeze amendments.

### Documented

- **Fault behaviour** (Phase 2, WP21): **zero new symbols** (ADR-020). Two
  different failures are now documented as the two different things they are.
  A handler that returns **without committing a response** is finalized by the
  response driver to the standardized `internal_error` 500 — identically under
  `web.serve` and `web.test_request`, identically under `web.app()` and
  `web.bare()`, in default *and* `-o:speed` builds, repeatably, and carrying no
  detail about the request. A handler that **faults** — panic, failed
  assertion, out-of-bounds index, nil dereference, divide-by-zero — **aborts
  the process**; run Uruquim under a supervisor.
- **`recovery` will never exist** (ADR-020). Odin has no recoverable panic:
  `context` is an implicit by-value parameter, so `web.app()` cannot install a
  fault hook on its caller's behalf, and `bounds_check_error` is
  `proc "contextless"` and cannot consult a hook even in principle. The earlier
  promise of "recovery middleware, default-on in `web.app()`" was not hard but
  impossible, and it has been withdrawn from `README.md`,
  `docs/quick-start.md` and `docs/canonical-patterns.md` rather than left
  standing as a default that would never be delivered (G-08). The Phase-4
  "last-gasp responder" is a different thing and must never be called recovery.

### Added

- **The `logger` middleware** (Phase 2, WP22): `web.logger`, a `Handler` value,
  **opt-in** — `web.use(&app, web.logger)`; there is no default-on logging
  (G-08). One `.Info` line per request, written through `context.logger` after
  the chain unwinds, carrying exactly three fields: method, **registered route
  pattern**, and **committed** status. It never logs the raw path, the query
  string, a header name or value, a body byte, or a captured path-parameter
  value — asserted on the exact bytes of the line, not described. A miss logs
  `-` for the route rather than falling back to the path, and a request whose
  chain committed nothing logs `-` for the status rather than reporting a
  response the logger never watched being sent (the driver's 500 finalization
  happens after dispatch returns; that failure reaches `web.observe`, which
  does see it). Misses are logged, so 404s and 405s are visible. The line is
  composed in a fixed stack buffer that no response can alias: a route field
  too long is cut on an escape boundary and **marked** `...[truncated]` — never
  grown silently, never dropped silently — and the status still follows the
  mark. CR, LF, backslash and control bytes are escaped, so a route pattern
  cannot forge a second log record. It imports **nothing**: not `core:log`
  (measured at ~37 KiB added to every application, referenced or not) and not
  `core:fmt`; an application that never names `web.logger` links **zero** logger
  symbols, proven with `nm` against a positive control (an application that does
  use it links six). Byte-identity of the binary is deliberately **not** claimed:
  the pinned toolchain does not build reproducibly, so that property fails for a
  tree compared against itself (plan amendment, 2026-07-20). No levels, sinks, sampling, structured
  fields or latency measurement — those are Phase-4 observability, and a log
  ring or drop policy would put an unbounded queue behind a bounded-buffer
  claim. Application ledger 42 → 43 (freeze Amendment 8).
- **Typed framework-error observer** (Phase 2, WP20): `web.observe`,
  `web.Framework_Event` and the now-public `web.Framework_Error`. One observer
  per application receives a typed event — kind, method, registered route
  pattern, committed status, offending typeid — for every framework-detected
  failure, on both transports, exactly once. The event carries **no message
  and no request path**: route identity is low-cardinality by construction,
  and an observer receives the event by value and nothing else, so it can
  neither respond nor read request bytes. Installing one changes no response.
  Application ledger 39 → 42 (freeze Amendment 7).
- **Request header lookup** (Phase 2, WP19): `web.header` and
  `web.bearer_token`. Pure lookups — `(value, ok)`, no automatic response,
  nothing ever logged, values are request-lifetime views. Names are
  case-insensitive (ASCII folding); duplicates: first occurrence wins; an
  empty value is present. `bearer_token` parses RFC 6750 strictly and returns
  the token verbatim — a sloppy `Authorization` is rejected, never repaired.
  `web.test_request` gains an optional `headers` parameter (`"Name: value"`
  lines), so header-driven code is testable without a socket. Application
  ledger 37 → 39 (freeze Amendments 5–6).
- **Route organisation** (Phase 2, WP18): `web.Router`, `web.router` and
  `web.mount`. A Router accepts the same `use` and the same five registration
  verbs an App does (it embeds an App — no new forms, no mutated signatures),
  and `mount(&app, "/prefix", &r)` attaches every route at prefix + pattern
  verbatim. Chains compose outermost-first: app globals, each enclosing
  router, the handler. Route-level middleware is a one-route Router
  (ADR-025 B). Fail-closed: an invalid prefix, a mis-ordered router, a
  mounted-router write, or a second mount rejects the application with a
  diagnostic. There is no `web.group`, ever (ADR-024). Application ledger
  34 → 37 (freeze Amendment 4).
- **Middleware** (Phase 2, WP17): `web.use` and `web.next` — onion execution
  with exact reverse unwind, total short-circuit, and a monotonic per-request
  cursor (a second `next()` is a no-op; the handler runs exactly once).
  App-level middleware observe automatic `404`/`405` responses, under
  `web.bare()` too. **Ordering is enforced fail-closed**: `use` after any
  registered route — or after the first dispatched request — rejects the
  application (every request answers `500`, `web.serve` refuses to start, and
  the diagnostic names the unprotectable pattern). Chains are flattened at
  registration; dispatch through a five-middleware chain allocates zero bytes.
  Application ledger 32 → 34 (freeze Amendment 3).

- A working bootstrap HTTP server: `web.serve(&app, port)` binds a real port
  behind a private transport boundary.
- Routing with static and `:param` segments, at most one parameter per pattern,
  static routes taking precedence over parametric ones, and per-method
  isolation.
- Automatic `404`, and `405` with an exact `Allow` header.
- Path and query extractors — `path`, `path_int`, `query`, `query_int`,
  `query_int_or` — that commit a standardized `400` on bad input, so handlers
  check a bool and return.
- JSON request body binding via `web.body`, with a fixed 4 MiB cap and a
  request-lifetime arena for decoded data.
- JSON, text and no-content responses, and five error responders.
- A standardized error envelope covering ten Phase-1 codes.
- In-memory testing with `web.test_request`, reaching real routing with no
  socket and no port.
- HTTP/1 conformance work: ambiguous and malformed framing is rejected and the
  connection closed, proven by a raw-wire corpus.
- `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md` and this changelog.

### Fixed

- Two remotely triggerable crashes and one request-smuggling vector, found by
  the Phase-1 transport conformance work and fixed in the vendored backend
  before any release. The patches are recorded in `vendor/odin-http/VENDOR.md`
  and the corpus that proves them is in `tests/wp9-wire/`.

### Public surface

**32 application symbols + 2 test-support symbols = 34, frozen.** The build
compares the compiler's own exported inventory — every signature, struct field,
enum member and enum backing type — against `build/phase1-public-signatures.txt`,
and the direct import set against `build/phase1-direct-dependencies.txt`.
Changing any of it requires a spec amendment.

Internals stay replaceable: the linear route table, the request arena and the
vendored backend are implementation and may be rewritten as long as the
observable contracts hold.

### Known limitations

Deliberate, documented, and each assigned to a later phase in
`planning/roadmap.md`:

- no middleware, route groups or typed application state;
- no request header lookup;
- no shutdown or stop — `web.serve` blocks until the process is signalled;
- no configurable limits or timeouts;
- only one server per process;
- no TLS, and no trusted-proxy handling;
- no path normalisation, no percent-decoding, no multi-value query access;
- `web.test_request` cannot carry a request body, so body-binding handlers
  cannot be exercised in memory;
- `HEAD` and `OPTIONS` are not supported;
- panics abort the process — Odin has no recoverable panic.

Uruquim is usable for building and testing a JSON API. It is **not** hardened
for unattended production exposure, and this changelog does not claim otherwise.
