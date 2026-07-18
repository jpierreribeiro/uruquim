# 04 — Phase 1 Scope Review

Status: **APPROVED BASELINE.** Human decision on 2026-07-18 includes the fixed
4 MiB body cap and minimal 405 with `Allow` in Phase 1'.

## Classification of the existing Phase-1 scope

Source: `knowledge-base/03-development-phases.md` §Phase 1.

### 1. Keep — provable now by prototype, core to the slice
- application: `app()`, `bare()`, `destroy` (exp-01)
- routes `get/post/put/patch/delete` via simple dispatcher (exp-09)
- `Context` (plain struct)
- extractors `path`, `path_int`, `query`, `query_int`, `query_int_or` (exp-04/09)
- `body(ctx,&dst)` (exp-03)
- responses `ok/created/no_content/json/text` (exp-02)
- error envelope + `bad_request/not_found/unauthorized/forbidden/internal_error` (exp-09)
- fixed 4 MiB body cap + `body_too_large` (exp-03)
- consistent 404 and minimal 405 with required `Allow` (exp-09 mechanism;
  behavior test belongs to WP4)
- `serve(&app, port)` with clean stop (exp-08)
- conceptual transport boundary + test transport + `test_request` (exp-08/09)
- `transport_contract_test` skeleton (exp-08)

### 2. Defer — belongs to a later phase
- `web.use`, groups, `router/group/mount` → Phase 2
- recovery, logger, request_id middleware → Phase 2
- radix tree, arenas-final, benchmarks → Phase 3
- public typed state (`app_with_state`, `web.state`) → Phase 3
- CORS, secure headers, cookies, uploads, static, observability → Phase 4
- OpenAPI, WebSocket, streaming, official adapter → Phase 5

### 3. Resolved defaults split
- **body size limit / `body_too_large`** — fixed 4 MiB cap is Phase 1;
  configurability remains Phase 3.
- **405 method_not_allowed** — minimal detection plus RFC-required `Allow` is
  Phase 1; the radix implementation only optimizes discovery/header building.
- **read/write timeouts** — app() default, P3. Depends on the transport; not
  Phase-1-provable. → keep deferred.

### 4. Premature — must not be frozen in Phase 1
- onion post-`next` semantics (ADR-005) — Phase-2 gate
- guaranteed threading model — after official adapter
- final request arena design — Phase 3
- definitive `Transport` shape — after second adapter
- `#optional_ok` policy — resolved: omitted from HTTP extractors so the
  compiler forces `ok` capture

### 5. Missing — implied but not yet specified
- `error.field` optionality (AMEND-2)
- `web.state` nil policy (AMEND-1)
- path *string* extractor empty-vs-missing semantics (exp-09 covers int only)
- collection wiring `-collection:uruquim` (WP0)
- verification-gate definition that compiles examples (WP10)

## Recommended reduced vertical slice (Phase 1')

Ship the smallest thing that lets a user write a JSON API and proves the
architecture, and **nothing that needs an unresolved decision**:

```text
INCLUDE (Phase 1')
  compiling public API skeleton (ratified signatures only)
  Request/Response model + views + single-commit
  in-memory test transport + test_request
  simple static + :param dispatcher (no radix)
  extractors: path, path_int, query, query_int, query_int_or, body
  responses: ok, created, no_content, json, text
  error envelope + helpers; consistent 404; minimal 405 with Allow
  fixed 4 MiB body cap
  minimal odin-http bootstrap adapter (buffered)
  transport conformance baseline (transport_contract_test)
  examples 01-03 compiling in the verification gate; ai-context parity

EXCLUDE (Phase 1')
  middleware / groups / recovery / logger      (P2)
  radix tree / arenas-final / benchmarks       (P3)
  public typed state                            (P3)
  configurable body limits / timeouts            (P3)
  everything in category 4 (premature)
```

### Decision on the formerly contested items (accepted)

- **body-limit:** include a **cap-and-reject in the bootstrap adapter** (a
  constant max, returning `body_too_large`) so the documented behavior is true
  in Phase 1, but do **not** promise configurable limits (that is P3/Advanced).
  This removes the A12 contradiction. Configurable limits remain P3.
- **405:** the interim dispatcher already knows all routes; returning 405 when
  a path exists under another method is cheap and matches the app() promise.
  **Accepted: include minimal 405 with the required `Allow` header** in Phase
  1'. Radix in P3 only optimizes it.
- **timeouts:** keep deferred (transport-dependent, not Phase-1-provable).

These inclusions turn A12/A13 from CONTRADICTORY to CONSISTENT without waiting
for Phase 3. AMEND-3 now records the precise progressive delivery schedule.

## Exit definition for Phase 1'

A user can write a small JSON CRUD-style API (GET+POST+path+query+body+JSON+
404) from `docs/ai-context.md`'s Phase-1 surface alone, it compiles and runs on
the bootstrap adapter, and the identical behavior passes on the test transport
via `transport_contract_test`. No middleware, no radix, no typed-state,
no unresolved decision in the shipped surface.
