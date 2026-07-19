# Phase 1 Implementation Plan

Status: **HUMAN-APPROVED SEQUENCE; PHASE-1 SPEC GATE READY.** Execute one work
package at a time. Every work package (WP) follows:
**SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE.**

Each WP lists: objective · spec clauses · planned files · affected API · tests
first · minimal implementation (future) · done · risks · dependencies ·
rollback. Signatures referenced here are ratified only after their experiment
runs on the pinned toolchain.

---

## WP0 — Toolchain and repository baseline
- **Execution status.** **COMPLETE.** Test-first run
  failed on the missing pin, then passed against `819fdc7` after the minimal
  baseline was added. GitHub Actions is unavailable by owner decision; the
  same gate is mandatory pre-push and repeats on the VPS. The real VPS recorded
  commit `4ae2d1c` green with 10/10 prototypes; its timer is enabled and active.
- **Objective.** Reproducible build: pinned Odin, collection wiring, local
  pre-push gate, and clean VPS repetition.
- **Spec.** freeze discipline; pinned `odin-version.txt`; repository baseline.
- **Files.** `odin-version.txt`, `build/check.sh`, `.githooks/pre-push`,
  `ops/ci/`, and collection documentation.
- **API.** none.
- **Tests first.** `build/check_test.sh` verifies the release/commit/digest
  pin, accepts the real compiler, observes 10/10 prototypes through the
  `uruquim` collection mapping, and rejects a divergent compiler. It does not
  check `web/`, which belongs to WP1.
- **Min impl.** pin + verification-only checker + tracked pre-push hook; VPS
  timer fetches a public branch, archives a clean commit, and runs the checker
  with the SHA-verified compiler.
- **Done.** local hook green and the VPS records the same pushed commit green.
- **Risks.** VPS toolchain download or GitHub fetch blocked → R-01.
- **Deps.** none. **Rollback.** delete build/ci files.

## WP1 — Compiling public API skeleton
- **Objective.** All ratified Phase-1' signatures exist as stubs; no HTTP
  behavior.
- **Spec.** §Public API Surface; §Canonical vocabulary; freeze discipline;
  planning/public-api-guardrails.md G-01/G-02/G-03/G-06/G-09.
- **Files.** `web/app.odin`, `web/routing.odin`, `web/context.odin`,
  `web/extract.odin`, `web/respond.odin`, `web/serve.odin`, `web/errors.odin`.
- **API.** `app/bare/destroy`, `get/post/put/patch/delete`, `Context`,
  `path/path_int/query/query_int/query_int_or/body`, `ok/created/no_content/
  json/text`, error helpers, `serve`.
- **Tests first.** `odin check` passes; a compile-only `_test.odin` references
  every public symbol (proves the surface exists and names match ai-context).
  A static contract rejects extra exports, Phase-2+ names, untyped Context
  bags, and backend-specific types in the public package.
- **Min impl.** stubs returning zero values / `not_implemented` markers.
- **Done.** surface compiles; parity test lists exactly the Phase-1 vocabulary;
  no synonym, transport type, or framework state bag was introduced.
- **Risks.** a signature fails to compile → NOT_READY trigger (gate).
- **Deps.** WP0; exp-01/02/03/04. **Rollback.** stubs are inert.

## WP2 — Framework request/response model
- **Objective.** `Request`/`Response` with views + ownership + commit state.
- **Spec.** §Request/Response ownership; ADR-007/008; planning/public-api-guardrails.md
  G-03/G-04/G-05.
- **Files.** `web/request.odin`, `web/response.odin`, `web/headers.odin`.
- **API.** Public: `Request{method,path,query,headers,body}`, `Method`
  (`UNKNOWN/GET/POST/PUT/PATCH/DELETE`), `Header_View`. Internal, NOT exported:
  `Response{status,headers,body,committed}` and `Header_Pair`. Surface
  checkpoint after WP2: exactly 32 symbols (29 + 3), behavior recorded by the
  permanent WP2 tests and API checker.
- **Tests first.** view-aliasing + invalidation test (port of exp-06);
  explicit persistent-copy test; single-commit test on the INTERNAL commit
  primitive (port of exp-08 — integration through `web.json`/`web.ok` belongs
  to WP6); Context shape test rejects dynamic/untyped storage.
- **Min impl.** views over a supplied buffer; `commit` guard.
- **Done.** exp-06/08 behaviors pass as real tests.
- **Risks.** allocator ownership wrong → R-04.
- **Deps.** WP1; exp-06/08. **Rollback.** internal types only.

## WP3 — In-memory test transport
- **Execution status.** **COMPLETE.** The in-memory facade, neutral machinery,
  dual API ledger and lazy teardown are merged. An application that never
  calls `test_request` links zero teardown symbols from `web/testing`, enforced
  by the permanent `nm` gate.
- **Objective.** drive dispatch and capture responses without sockets.
- **Spec.** §Test transport; §Three test suites.
- **Files.** Public facade in `web/` (package `web`):
  `web/test_support.odin` — `test_request` + `Recorded_Response`. Machinery in
  `web/testing/` (package `testing`): `test_transport.odin`, `recorder.odin`,
  `request_builder.odin`. The public symbols live in package `web` to preserve
  the canonical `web.test_request` call; machinery lives in `web/testing`.
- **API.** Public, package `web`: `web.test_request(&app, method, path) ->
  Recorded_Response`. `test_request` and `Recorded_Response` are the only two
  public symbols; both belong to the **test-support ledger**, tracked apart
  from the frozen 32-symbol application surface
  (planning/public-api-guardrails.md G-11). Total exported after WP3: 34 = 32
  application + 2 test-support.
- **Dependency direction (ratified in WP3).** One-way only:
  `web` (facade) → `web/testing` (machinery) → neutral internal/boundary
  types. `web/testing` MUST NOT import `uruquim:web` — the back-edge is a
  compile-time import cycle (`Cyclic importation of 'testing'`, ratified by the
  pinned-toolchain C1/C2/C5 probes). The facade converts `App`, `Method` and the
  captured response across the boundary; the machinery names no `web` type.
  Neither the facade nor the machinery may import `core:testing`.
  If this cannot be represented without a cycle or duplicated types, the WP3
  agent STOPS and produces a throwaway packages prototype — it does not move
  types or introduce `rawptr` silently.
- **`Recorded_Response` lifetime (ratified in WP3).** `status` is copied
  by value; `body` and `headers` are copied by the recorder into storage owned
  by the App's lazy test-support state, created on the first `test_request` and
  valid until `web.destroy(&app)`. No additional public cleanup is introduced,
  and applications that never call `test_request` never allocate the recorder.
- **Tests first.** `test_request` round-trips a canned request (port exp-09
  harness). The TESTS-FIRST commit also raises `build/check_public_api.sh` to
  the dual-ledger contract (permit the `web/testing/` subdirectory only; scan
  `web/test_support.odin` as the 2-symbol test-support ledger; keep the other
  `web/*.odin` at exactly 32; assert the 34-symbol union; drop `test_request`
  from the forbidden later-phase list) and records the RED evidence before the
  machinery exists. It ports the disposable package prototype into committed
  compile probes (one-way import succeeds; back-edge cycle fails with the
  expected diagnostic; neither side imports `core:testing`). It also records a
  minimal application binary before/after the facade exists, verifies that an
  application which never calls `test_request` performs no test-support
  allocation or package initialization, and reports any binary-size delta for
  human review rather than declaring hidden cost absent by assumption.
- **Min impl.** inbox/outbox loop over neutral request/response values; the
  facade owns the dispatch call, the recorder is a passive sink that copies
  status/headers/body/commit into owned storage.
- **Done.** `test_request` usable by all later WP tests; two recorded responses
  remain readable across consecutive calls until `destroy(&app)`; tracked
  recorder allocations are released by destroy; unused applications link no
  test-support teardown symbols.
- **Risks.** test transport diverging from real behavior → mitigated by WP9.
- **Deps.** WP2. **Rollback.** test-only package.

## WP4 — Minimal route registration and dispatch
- **Execution status.** **COMPLETE.** Registration, `:param` matching,
  order-independent static precedence, per-method isolation, the automatic 404,
  and the 405 with its exact `Allow` header are merged and test-pinned (35
  internal + 12 public-surface tests). The public surface did not move: 32
  application + 2 test-support = 34. Measured cost of routing on a minimal
  two-route application: 47,880 -> 58,072 bytes (+10,192); an application that
  registers no route pays +240 bytes (`routes_destroy` plus its
  `delete_dynamic_array` instantiation, reached by the static edge from
  `destroy`). Dispatch itself allocates nothing — matching walks the strings in
  place and the `Allow` value is built into fixed request-local storage.
- **Objective.** static + `:param` dispatch, no radix; consistent 404;
  minimal 405 (per scope decision).
- **Spec.** §Routing (observable behavior only); scope-review 405 decision;
  decisions D1–D5 below.
- **Files (amended in WP4).** `web/dispatch_table.odin`,
  `web/dispatch_match.odin` — top-level files in the EXISTING package `web`,
  every declaration package-private.
  The original plan said `web/internal/dispatch/*.odin`. **Refuted by the
  language, not by preference:** in Odin a subdirectory is a separate package,
  and the dispatcher must name `App`, `Handler`, `Context`, `Method` and the
  internal `Response`. A subpackage would need to import `uruquim:web`, which
  WP3 already ratified as a compile cycle (probe C5,
  `Cyclic importation of 'web_testing'`); the alternatives are duplicating the
  types, a `rawptr` bridge, or a frozen internal ABI — all forbidden. The files
  therefore live in `web/`, and `build/check_public_api.sh` permits exactly
  these two additional names. The checker is NOT relaxed to accept
  subdirectories or arbitrary files.
- **API.** internal; public `get/post/put/patch/delete` register into the
  table. **No public symbol is added: the ledgers stay 32 + 2 = 34.**
- **Decisions ratified in WP4.**
  - **D1 — parameters and route identity stay private.** WP4 adds only private
    parameter storage and matching in `Context_Internal`. It exports no
    `Params`, `Param`, `Route_Info`, `Route`, `Router` or accessor. WP5 makes
    `web.path`/`web.path_int` consume that private storage; the stable
    route identity for observability remains internal and future (OQ-18).
    `knowledge-base/01-architecture-spec.md` §Context Model is amended
    accordingly.
  - **D2 — internals stay in package `web`.** See Files above.
  - **D3 — dispatch takes the App explicitly:**
    `dispatch :: proc(a: ^App, ctx: ^Context)`. The WP3 stub `dispatch(ctx)`
    has no access to the App-owned table. No pointer to `App` is stored on
    `Context`, and no public signature changes. This signature is internal and
    replaceable.
  - **D4 — minimal 404/405 policy.** In `web.app()` a path miss is
    `.Not_Found`; a path known under another method is `.Method_Not_Allowed`
    with an `Allow` header. In `web.bare()` registered routes dispatch, but the
    automatic 404/405 defaults are NOT installed and a miss stays uncommitted —
    this makes the documented `app()`/`bare()` distinction real without
    inventing middleware. Bodies are EMPTY in WP4; the standardized JSON
    envelope is WP6 and is not implemented early. The header is exactly
    `Allow`, its value uses the deterministic canonical order
    `GET, POST, PUT, PATCH, DELETE`, includes only methods registered for that
    path, and separates them with comma + space. `.UNKNOWN` never becomes 501:
    it follows the same 405/404 rules as any other method. `Recorded_Response`
    gains no headers and no header accessor exists; `Allow` is verified by an
    internal `package web` test.
  - **D5 — path semantics limited to what WP4 proves.** Patterns begin with
    `/`; `/` is valid; a `:param` occupies one whole segment; at most one
    `:param` per pattern in this interim dispatcher; no wildcard. WP4
    normalizes NOTHING — not slashes, percent-encoding, dot segments, or
    trailing slashes — so `/users` and `/users/` are different patterns. A
    normalization policy and definitive registration-conflict diagnostics
    belong to Phase 3; WP4 freezes no public registration-error API. Precedence
    (static over parametric) is decided by pattern shape, never by registration
    order.
- **Tests first.** static match, `:param` capture, precedence (static>param) in
  both registration orders, per-method isolation, 404, 405-when-other-method
  with exact `Allow` header and no duplicates, `.UNKNOWN` following 404/405,
  `bare()` injecting neither, handler invoked exactly once, no fabricated 200
  for a handler that did not respond, App-owned pattern surviving mutation of
  the caller's buffer, `destroy` freeing the table exactly once.
- **Min impl.** App-owned linear table; public registration wrappers delegating
  to one private proc; linear static-then-parametric match by segment
  iteration; at most one captured param; handler invocation; internal 404/405
  commits; deterministic `Allow` construction; table teardown.
- **Done.** dispatch behavior matches the router spec's *observable* contract,
  so Phase 3 radix changes nothing public.
- **Risks.** observable behavior drifting from the future radix → pin with tests.
- **Deps.** WP2/WP3; exp-09. **Rollback.** replace table wholesale in P3.

## WP5 — Canonical extractors
- **Objective.** `path/path_int/query/query_int/query_int_or` with the
  respond-on-failure contract.
- **Spec.** §Extractor Control Flow; ADR-002; planning/public-api-guardrails.md G-01/G-04.
- **Files.** `web/extract.odin` (impl), `web/errors.odin` (envelope for
  invalid_path/query).
- **API.** the five extractors + failure-stop.
- **Tests first.** valid/invalid path int; query absent→default,
  malformed→400; each failure writes envelope once and a continued handler
  cannot replace it (ports of exp-09). Canonical example branches return
  immediately; the compile probe forces capture of `ok`.
- **Min impl.** parse + write envelope + return false.
- **Done.** extractor contract test-pinned; signatures omit `#optional_ok` and
  a negative compile probe proves that dropping `ok` is rejected.
- **Risks.** a future contributor re-adds `#optional_ok` → compile probe guards.
- **Deps.** WP2/WP4; exp-04/09. **Rollback.** signatures stable, bodies swap.

## WP6 — JSON responses and error envelope
- **Objective.** `json/text/ok/created/no_content` + envelope; failures before
  commit.
- **Spec.** §Response; §Std Errors; AMEND-2 (`field` optional); planning/public-api-guardrails.md
  G-01/G-04/G-09.
- **Files.** `web/respond.odin`, `web/errors.odin`.
- **API.** all response helpers; envelope encoder.
- **Tests first.** `ok`==`json(.OK)` byte-identical; concrete value payloads
  work; `&value`, pointer-typed variables, and other unsupported types follow
  the documented rejection path; marshal error is logged server-side before
  one pre-commit `internal_error`; envelope omits absent `field` (ports of
  exp-02).
- **Min impl.** `json.marshal` into request-owned response storage; commit
  guard; explicit server-side marshal diagnostic. Before finalizing, run a
  disposable one-level pointer-dereference prototype. If clean, propose a spec
  amendment before adding support; otherwise keep the accepted value-only
  baseline.
- **Done.** exp-02 behaviors pass; envelope contract fixed; marshal failures
  are observable in server logs; pointer-prototype result is recorded; error
  formatting/commit protection uses the private typed report path.
- **Risks.** marshal-after-commit ordering → R-05.
- **Deps.** WP2; exp-02. **Rollback.** helpers isolated.

## WP7 — JSON body binding
- **Objective.** `body(ctx,&dst)->bool`, request allocator, fixed 4 MiB body cap.
- **Spec.** §body; ADR-006; proposed ADR-012; scope-review body-limit decision.
- **Files.** `web/extract.odin` (`body`), `web/internal/memory/request_arena.odin`.
- **API.** `body`.
- **Tests first.** before production code, run a disposable repeated-binding
  prototype covering successful first bind, invalid first bind, empty body,
  and a second call. After ADR-012 is decided: valid nested bind into arena;
  empty/invalid→false+envelope; over-limit→`body_too_large` before parse;
  repeated-call behavior pinned without double-commit (ports of exp-03).
- **Min impl.** `json.unmarshal(^$T, arena_allocator)`; size check; the smallest
  request-body state required by accepted ADR-012. No replay cache unless that
  ADR explicitly accepts one.
- **Done.** exp-03 behaviors pass; ADR-012 is accepted with compiling evidence;
  ownership and consumption semantics are documented.
- **Risks.** unmarshal ignoring substituted allocator → R-06 (from exp-03);
  ambiguous repeated binding → R-15.
- **Deps.** WP2/WP6; exp-03. **Rollback.** body isolated.

## WP8 — Bootstrap real transport adapter
- **Objective.** minimal `odin-http` adapter behind the boundary; buffered.
- **Spec.** §Canonical Transport Direction; ADR-009; planning/public-api-guardrails.md G-06/G-07.
- **Files.** `web/internal/transport/odin_http_adapter.odin`,
  `web/internal/transport/boundary.odin`.
- **API.** none public; implements `Transport`.
- **Tests first.** adapter starts/stops; one real GET /ping over a socket
  (end-to-end suite, small); exported-signature scan rejects backend types;
  dependency inventory records what the adapter adds outside core.
- **Min impl.** map odin-http req/res ↔ framework Request/Response; enforce body
  cap while reading.
- **Done.** `serve` works on a real port; no odin-http type in any public
  signature (grep gate).
- **Risks.** odin-http beta API drift → R-02; egress to vendor it → R-01.
- **Deps.** WP2-WP7; laytan/odin-http vendored. **Rollback.** delete adapter;
  test transport still proves the core.

## WP9 — Transport conformance baseline
- **Objective.** semantic conformance for every transport plus wire/framing
  conformance for every real HTTP adapter.
- **Spec.** §Three test suites; cross-phase invariant.
- **Files.** `web/testing/conformance.odin`
  (`transport_contract_test(t, factory)`); adapter-owned raw HTTP corpus.
- **API.** internal test API.
- **Tests first.** semantic matrix: request conversion, body lifetime, header
  normalization, response commit, connection close/stop (ports of exp-08 +
  adapter). Real-adapter wire matrix: conflicting `Content-Length` and
  `Transfer-Encoding`, duplicate/non-identical lengths, malformed chunking,
  truncated bodies, invalid whitespace, unread-body disposal versus close,
  and `Expect: 100-continue`.
- **Min impl.** factory-parameterized semantic suite run against test transport
  + odin-http; raw-byte wire harness run only against real adapters. The core
  does not acquire a parser ABI merely to make the test transport imitate TCP.
- **Done.** both transports pass semantic conformance; the bootstrap adapter
  passes the Phase-1 wire corpus; unsupported cases are explicitly documented,
  never silently accepted.
- **Risks.** a semantic item satisfiable by only one backend surfaces a real
  boundary defect; wire behavior divergence → R-17.
- **Deps.** WP3/WP8. **Rollback.** suite is additive.

## WP10 — Phase 1 documentation and examples
- **Objective.** examples 01-03 compile in the verification gate; ai-context
  parity; AMEND-3/-4
  applied to docs.
- **Spec.** §AI-Friendly API Rules; audit AMEND-3/-4; planning/public-api-guardrails.md G-08/G-09.
- **Files.** `examples/01-hello-world`, `02-json-api`, `03-route-params`;
  doc edits (proposed, not part of code freeze).
- **API.** none.
- **Tests first.** the verification gate compiles every example; a parity
  check diffs ai-context
  symbols against the public package and rejects future-phase vocabulary in
  Phase-1 examples.
- **Min impl.** three example programs using only Phase-1' surface.
- **Done.** examples green; docs carry phase markers (AMEND-4) and the
  progressive-defaults note (AMEND-3); every response example uses concrete
  value payloads unless pointer support was separately amended after WP6.
- **Risks.** doc/code drift → the parity check is the guard.
- **Deps.** WP1-WP9. **Rollback.** examples are leaf packages.

## WP11 — Phase 1 Spec Gate and freeze
- **Objective.** freeze only proven signatures/contracts.
- **Spec.** freeze discipline; planning/public-api-guardrails.md full guardrail audit.
- **Files.** normative docs plus a temporary final gate record, archived after
  the release decision is incorporated.
- **API.** freeze the Phase-1' vocabulary.
- **Tests first.** the gate checklist is itself the acceptance test; include
  exact public-export and direct-dependency inventories with an owner/evidence
  row for every public symbol.
- **Min impl.** mark ratified signatures frozen; open items routed to their
  phase/ADR.
- **Done.** gate result computed from executed evidence (not predictions);
  anti-accretion review finds no alias, god context, backend leak, hidden
  escaping view, or unowned public dependency.
- **Risks.** freezing something un-ratified → forbidden by discipline.
- **Deps.** WP0-WP10 + executed experiments. **Rollback.** un-freeze pre-1.0.

---

## Dependency order

```
WP0 → WP1 → WP2 → {WP3, WP4} → WP5 → WP6 → WP7 → WP8 → WP9 → WP10 → WP11
                     └── WP3 also feeds WP4/WP5/WP6/WP7 tests
```

## Global rollback

Every WP is additive under `web/`, `web/testing/`, `web/internal/`,
`examples/`. Nothing here touches `knowledge-base/**`. The bootstrap adapter
(WP8) is the only socket-bound piece; deleting it leaves a fully test-covered,
transport-agnostic core proven on the test transport.
