# 05 — Phase 1 Implementation Plan

Status: **HUMAN-APPROVED SEQUENCE.** Implementation remains prohibited until
`planning/07-spec-gate-phase-1.md` records READY. After that, execute one work
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
- **Spec.** freeze discipline; baseline 01.
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
  planning/15 G-01/G-02/G-03/G-06/G-09.
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
- **Spec.** §Request/Response ownership; ADR-007/008; planning/15
  G-03/G-04/G-05.
- **Files.** `web/request.odin`, `web/response.odin`, `web/headers.odin`.
- **API.** `Request{method,path,query,headers,body}`, `Response{status,headers,
  body,committed}`.
- **Tests first.** view-aliasing + invalidation test (port of exp-06);
  explicit persistent-copy test; single-commit test (port of exp-08); Context
  shape test rejects dynamic/untyped storage.
- **Min impl.** views over a supplied buffer; `commit` guard.
- **Done.** exp-06/08 behaviors pass as real tests.
- **Risks.** allocator ownership wrong → R-04.
- **Deps.** WP1; exp-06/08. **Rollback.** internal types only.

## WP3 — In-memory test transport
- **Objective.** drive dispatch and capture responses without sockets.
- **Spec.** §Test transport; §Three test suites.
- **Files.** `web/testing/test_transport.odin`, `web/testing/recorder.odin`,
  `web/testing/request_builder.odin`.
- **API.** `web.test_request(&app, method, path) -> Recorded_Response`.
- **Tests first.** `test_request` round-trips a canned request (port exp-09
  harness).
- **Min impl.** inbox/outbox loop calling dispatch; recorder captures status/
  headers/body/commit.
- **Done.** `test_request` usable by all later WduP tests.
- **Risks.** test transport diverging from real behavior → mitigated by WP9.
- **Deps.** WP2. **Rollback.** test-only package.

## WP4 — Minimal route registration and dispatch
- **Objective.** static + `:param` dispatch, no radix; consistent 404;
  minimal 405 (per scope decision).
- **Spec.** §Routing (observable behavior only); scope-review 405 decision.
- **Files.** `web/internal/dispatch/table.odin`, `web/internal/dispatch/match.odin`.
- **API.** internal; public `get/post/...` register into the table.
- **Tests first.** static match, `:param` capture, precedence (static>param),
  404, 405-when-other-method with exact `Allow` header (ports of exp-09 + one
  405 case).
- **Min impl.** method+exact map, plus single-`:param` segment matcher.
- **Done.** dispatch behavior matches the router spec's *observable* contract,
  so Phase 3 radix changes nothing public.
- **Risks.** observable behavior drifting from the future radix → pin with tests.
- **Deps.** WP2/WP3; exp-09. **Rollback.** replace table wholesale in P3.

## WP5 — Canonical extractors
- **Objective.** `path/path_int/query/query_int/query_int_or` with the
  respond-on-failure contract.
- **Spec.** §Extractor Control Flow; ADR-002; planning/15 G-01/G-04.
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
- **Spec.** §Response; §Std Errors; AMEND-2 (`field` optional); planning/15
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
- **Spec.** §body; ADR-006; scope-review body-limit decision.
- **Files.** `web/extract.odin` (`body`), `web/internal/memory/request_arena.odin`.
- **API.** `body`.
- **Tests first.** valid nested bind into arena; empty/invalid→false+envelope;
  over-limit→`body_too_large` before parse (ports of exp-03).
- **Min impl.** `json.unmarshal(^$T, arena_allocator)`; size check.
- **Done.** exp-03 behaviors pass; ownership documented.
- **Risks.** unmarshal ignoring substituted allocator → R-06 (from exp-03).
- **Deps.** WP2/WP6; exp-03. **Rollback.** body isolated.

## WP8 — Bootstrap real transport adapter
- **Objective.** minimal `odin-http` adapter behind the boundary; buffered.
- **Spec.** §Canonical Transport Direction; ADR-009; planning/15 G-06/G-07.
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
- **Objective.** one suite both transports must pass.
- **Spec.** §Three test suites; cross-phase invariant.
- **Files.** `web/testing/conformance.odin`
  (`transport_contract_test(t, factory)`).
- **API.** internal test API.
- **Tests first.** request conversion, body lifetime, header normalization,
  response commit, connection close/stop (ports of exp-08 + adapter).
- **Min impl.** factory-parameterized suite run against test transport + odin-http.
- **Done.** both transports green; the bootstrap cannot shape the design.
- **Risks.** a conformance item only satisfiable by one backend → surfaces a
  real boundary defect (good).
- **Deps.** WP3/WP8. **Rollback.** suite is additive.

## WP10 — Phase 1 documentation and examples
- **Objective.** examples 01-03 compile in the verification gate; ai-context
  parity; AMEND-3/-4
  applied to docs.
- **Spec.** §AI-Friendly API Rules; audit AMEND-3/-4; planning/15 G-08/G-09.
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
- **Spec.** freeze discipline; gate 07; planning/15 full guardrail audit.
- **Files.** `planning/07-spec-gate-phase-1.md` (updated to EXECUTED results).
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
