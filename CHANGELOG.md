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

### Added

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
