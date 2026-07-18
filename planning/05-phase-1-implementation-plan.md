# 05 — Phase 1 Implementation Plan

Status: **PLAN ONLY. Implementation remains prohibited at this stage**, even if
the gate reads READY. Every work package (WP) follows:
**SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE.**

Each WP lists: objective · spec clauses · planned files · affected API · tests
first · minimal implementation (future) · done · risks · dependencies ·
rollback. Signatures referenced here are ratified only after their experiment
runs on the pinned toolchain.

---

## WP0 — Toolchain and repository baseline
- **Objective.** Reproducible build: pinned Odin, collection wiring, CI.
- **Spec.** freeze discipline; baseline 01.
- **Files.** `odin-version.txt` (pin), `build/check.sh`, `.github/workflows/ci.yml`
  (or equivalent), `ols.json`/collection note.
- **API.** none.
- **Tests first.** CI job that runs `odin version` and asserts `dev-2026-07a`;
  `odin check ./web`.
- **Min impl.** install script into `/tmp/uruquim-odin-toolchain`; `-collection:
  uruquim=<root>`.
- **Done.** CI green on an empty compiling `web` package.
- **Risks.** toolchain fetch blocked in CI too (same egress class) → R-01.
- **Deps.** none. **Rollback.** delete build/ci files.

## WP1 — Compiling public API skeleton
- **Objective.** All ratified Phase-1' signatures exist as stubs; no HTTP
  behavior.
- **Spec.** §Public API Surface; §Canonical vocabulary; freeze discipline.
- **Files.** `web/app.odin`, `web/routing.odin`, `web/context.odin`,
  `web/extract.odin`, `web/respond.odin`, `web/serve.odin`, `web/errors.odin`.
- **API.** `app/bare/destroy`, `get/post/put/patch/delete`, `Context`,
  `path/path_int/query/query_int/query_int_or/body`, `ok/created/no_content/
  json/text`, error helpers, `serve`.
- **Tests first.** `odin check` passes; a compile-only `_test.odin` references
  every public symbol (proves the surface exists and names match ai-context).
- **Min impl.** stubs returning zero values / `not_implemented` markers.
- **Done.** surface compiles; parity test lists exactly the Phase-1 vocabulary.
- **Risks.** a signature fails to compile → NOT_READY trigger (gate).
- **Deps.** WP0; exp-01/02/03/04. **Rollback.** stubs are inert.

## WP2 — Framework request/response model
- **Objective.** `Request`/`Response` with views + ownership + commit state.
- **Spec.** §Request/Response ownership; ADR-007/008.
- **Files.** `web/request.odin`, `web/response.odin`, `web/headers.odin`.
- **API.** `Request{method,path,query,headers,body}`, `Response{status,headers,
  body,committed}`.
- **Tests first.** view-aliasing + invalidation test (port of exp-06);
  single-commit test (port of exp-08).
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
  404, 405-when-other-method (ports of exp-09 + one 405 case).
- **Min impl.** method+exact map, plus single-`:param` segment matcher.
- **Done.** dispatch behavior matches the router spec's *observable* contract,
  so Phase 3 radix changes nothing public.
- **Risks.** observable behavior drifting from the future radix → pin with tests.
- **Deps.** WP2/WP3; exp-09. **Rollback.** replace table wholesale in P3.

## WP5 — Canonical extractors
- **Objective.** `path/path_int/query/query_int/query_int_or` with the
  respond-on-failure contract.
- **Spec.** §Extractor Control Flow; ADR-002.
- **Files.** `web/extract.odin` (impl), `web/errors.odin` (envelope for
  invalid_path/query).
- **API.** the five extractors + failure-stop.
- **Tests first.** valid/invalid path int; query absent→default,
  malformed→400; each failure writes envelope once (ports of exp-09).
- **Min impl.** parse + write envelope + return false.
- **Done.** extractor contract test-pinned; `#optional_ok` policy per ADR-002.
- **Risks.** ADR-002 human decision unresolved → gate blocker.
- **Deps.** WP2/WP4; exp-04/09. **Rollback.** signatures stable, bodies swap.

## WP6 — JSON responses and error envelope
- **Objective.** `json/text/ok/created/no_content` + envelope; failures before
  commit.
- **Spec.** §Response; §Std Errors; AMEND-2 (`field` optional).
- **Files.** `web/respond.odin`, `web/errors.odin`.
- **API.** all response helpers; envelope encoder.
- **Tests first.** `ok`==`json(.OK)` byte-identical; marshal error → pre-commit
  internal_error; envelope omits absent `field` (AMEND-2) (ports of exp-02).
- **Min impl.** `json.marshal` into request/temp buffer; commit guard.
- **Done.** exp-02 behaviors pass; envelope contract fixed.
- **Risks.** marshal-after-commit ordering → R-05.
- **Deps.** WP2; exp-02. **Rollback.** helpers isolated.

## WP7 — JSON body binding
- **Objective.** `body(ctx,&dst)->bool`, request allocator, body cap.
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
- **Spec.** §Canonical Transport Direction; ADR-009.
- **Files.** `web/internal/transport/odin_http_adapter.odin`,
  `web/internal/transport/boundary.odin`.
- **API.** none public; implements `Transport`.
- **Tests first.** adapter starts/stops; one real GET /ping over a socket
  (end-to-end suite, small).
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
- **Objective.** examples 01-03 compile in CI; ai-context parity; AMEND-3/-4
  applied to docs.
- **Spec.** §AI-Friendly API Rules; audit AMEND-3/-4.
- **Files.** `examples/01-hello-world`, `02-json-api`, `03-route-params`;
  doc edits (proposed, not part of code freeze).
- **API.** none.
- **Tests first.** CI compiles every example; a parity check diffs ai-context
  symbols against the public package.
- **Min impl.** three example programs using only Phase-1' surface.
- **Done.** examples green; docs carry phase markers (AMEND-4) and the
  progressive-defaults note (AMEND-3).
- **Risks.** doc/code drift → the parity check is the guard.
- **Deps.** WP1-WP9. **Rollback.** examples are leaf packages.

## WP11 — Phase 1 Spec Gate and freeze
- **Objective.** freeze only proven signatures/contracts.
- **Spec.** freeze discipline; gate 07.
- **Files.** `planning/07-spec-gate-phase-1.md` (updated to EXECUTED results).
- **API.** freeze the Phase-1' vocabulary.
- **Tests first.** the gate checklist is itself the acceptance test.
- **Min impl.** mark ratified signatures frozen; open items routed to their
  phase/ADR.
- **Done.** gate result computed from executed evidence (not predictions).
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
