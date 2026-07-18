# 04 — Phase 1 Scope Review

Status: **RECOMMENDATION.** Classifies the current Phase-1 scope into five
categories and proposes a reduced vertical slice.

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
- consistent 404 (exp-09)
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

### 3. Contested — promised as `web.app()` default but scheduled later
- **body size limit / `body_too_large`** — docs promise it (canonical L139-140),
  phases place it in P3. → OQ-3 / AMEND-3.
- **405 method_not_allowed** — listed as an app() default, placed in P3 (radix).
  But an interim dispatcher *can* detect "path exists on another method". → OQ-3.
- **read/write timeouts** — app() default, P3. Depends on the transport; not
  Phase-1-provable. → keep deferred.

### 4. Premature — must not be frozen in Phase 1
- onion post-`next` semantics (ADR-005) — Phase-2 gate
- guaranteed threading model — after official adapter
- final request arena design — Phase 3
- definitive `Transport` shape — after second adapter
- `#optional_ok` policy — pending exp-04 (mechanism ok, policy open)

### 5. Missing — implied but not yet specified
- `error.field` optionality (AMEND-2)
- `web.state` nil policy (AMEND-1)
- path *string* extractor empty-vs-missing semantics (exp-09 covers int only)
- collection wiring `-collection:uruquim` (WP0)
- CI definition that compiles examples (claimed contract, no file — audit A24)

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
  error envelope + helpers; consistent 404
  minimal odin-http bootstrap adapter (buffered)
  transport conformance baseline (transport_contract_test)
  examples 01-03 compiling in CI; ai-context parity

EXCLUDE (Phase 1')
  middleware / groups / recovery / logger      (P2)
  radix tree / arenas-final / benchmarks       (P3)
  public typed state                            (P3)
  body-limit enforcement / 405 / timeouts       (contested → see decision)
  everything in category 4 (premature)
```

### Decision on the contested items (recommended)

- **body-limit:** include a **cap-and-reject in the bootstrap adapter** (a
  constant max, returning `body_too_large`) so the documented behavior is true
  in Phase 1, but do **not** promise configurable limits (that is P3/Advanced).
  Cheap, removes the A12 contradiction. Alternative: adopt AMEND-3 wording and
  leave enforcement to P3. **Recommend: include the cap** — it is a few lines
  and makes the docs honest now.
- **405:** the interim dispatcher already knows all routes; returning 405 when
  a path exists under another method is cheap and matches the app() promise.
  **Recommend: include minimal 405** in Phase 1'. Radix in P3 only optimizes it.
- **timeouts:** keep deferred (transport-dependent, not Phase-1-provable).

Adopting these two inclusions turns A12/A13 from CONTRADICTORY to CONSISTENT
without waiting for Phase 3, and only AMEND-3's timeout clause remains as a
documentation note.

## Exit definition for Phase 1'

A user can write a small JSON CRUD-style API (GET+POST+path+query+body+JSON+
404) from `docs/ai-context.md`'s Phase-1 surface alone, it compiles and runs on
the bootstrap adapter, and the identical behavior passes on the test transport
via `transport_contract_test`. No middleware, no radix, no typed-state,
no unresolved decision in the shipped surface.
