# 02 — Prototype Findings

Status: **AUTHORED, NOT EXECUTED.** All nine experiments exist as compilable
Odin under `experiments/`, each with a local README (question, hypothesis,
command, expected result, limitations, conclusion). None was executed here
because the pinned toolchain was unreachable (baseline 01).

Consequently every finding below is a **predicted** outcome with an explicit
ratification command. The runner `experiments/run_checks.sh` produces the real
evidence wherever `odin` (dev-2026-07a) is on PATH. Predicted outcomes must not
be cited as ratification.

## Confidence key

- **HIGH** — behavior follows directly from documented Odin/stdlib semantics.
- **MEDIUM** — plausible from documentation but with a real failure mode.
- **OPEN** — genuinely undecided; the experiment gathers evidence, not a verdict.

## Findings

### F1 · api-shape (exp-01) — MEDIUM
Predict: `app()` by value compiles; `&app` is the stable operating address;
`[dynamic]` header copies alias one backing store, so `destroy` must run once.
Watch: by-value return + `defer destroy` double-free if a copy is destroyed
twice. Ratify: `odin run experiments/01-api-shape`. Decides ADR-001 (else fall
back to `app_init(&app)`).

### F2 · generic-json-response (exp-02) — HIGH
Predict: `json(ctx,status,$T)` marshals struct/pointer/slice/large values;
`ok`/`created` show `commit==1`; a proc/rawptr value trips a marshal error
(intended-failure probe). `any` stays an internal stdlib detail. Ratify:
`odin run experiments/02-generic-json-response`. Decides ADR-003.

### F3 · body-binding (exp-03) — MEDIUM
Predict: `body(ctx,&dst)->bool` binds nested strings/slices into the
substituted request arena; empty/invalid → false+responded; over-limit
short-circuits before parsing; `arena.offset>0` proves ownership. Watch:
`json.unmarshal` allocating nested data on `context.allocator` regardless of the
passed allocator. Ratify: `odin run experiments/03-body-binding`. Decides
ADR-006.

### F4 · optional-ok (exp-04) — HIGH (mechanism) / OPEN (policy)
Predict: `#optional_ok` legal; bool droppable; the plain form's discard is a
compile error (intended-failure probe records the diagnostic). Mechanism is
HIGH; the *policy* (keep the directive vs force bool-handling to prevent silent
drop) is OPEN and decided in ADR-002 from the diagnostic text.

### F5 · typed-state (exp-05) — MEDIUM
Predict: A (rawptr+typeid) compiles, mutation visible on original (shared
lifetime), wrong-type asserts; B (parametric) is compile-checked but adds type
args at every call site. nil is the edge → AMEND-1. Ratify:
`odin run experiments/05-typed-state`. Decides ADR-004 (expected: A canonical,
B advanced).

### F6 · request-views (exp-06) — HIGH
Predict: views alias the buffer; overwriting the buffer corrupts `req.path`
while a pre-clone `saved` survives — the request-lifetime rule made physical.
Ratify: `odin run experiments/06-request-views`. Decides ADR-007.

### F7 · middleware-chain (exp-07) — OPEN (by design)
Predict: one cursor drives pre-order and onion; onion "after" runs **after**
`handler:commit` (post-commit) — the exact reason post-`next` semantics are
transport-conditional; per-request state is a slice + 3 scalars, no per-hop
heap. **No Phase-2 verdict.** Feeds ADR-005 and ADR-008.

### F8 · transport-boundary (exp-08) — MEDIUM
Predict: minimal `Transport{data,serve,stop}` + single-commit guard works; test
transport captures responses with no sockets; no backend type on the
handler surface (runner greps to confirm). Watch: whether single-commit can be
enforced purely framework-side (HIGH that it can for buffered responses).
Decides ADR-008/ADR-009.

### F9 · test-transport (exp-09) — HIGH
Predict: six `@(test)` procedures pass, pinning static-200, path-int
valid/invalid (400 envelope), query default-absent (20) vs malformed (400), and
404 — the contract-suite prototype, sockets-free. Ratify:
`odin test experiments/09-test-transport`. This is the executable proof behind
"conformance suite from Phase 1".

## What ratification would change

| If an experiment FAILS | Consequence |
|---|---|
| exp-01 double-free | ADR-001 flips to `app_init(&app)` canonical; README/spec example changes |
| exp-03 allocator ignored | body ownership reopens; WP7 needs a copy pass |
| exp-04 `#optional_ok` illegal here | drop directive; call sites unchanged |
| exp-05 assert/cast unreliable | canonical state accessor redesigned before Phase 3 |
| exp-09 malformed≠400 | `query_int_or` semantics reopened (unlikely) |

## Aggregate

Predicted: 9/9 compile; exp-04 and one probe each in exp-02/exp-05 are
**intended** compile failures recorded separately from real failures. Until the
runner is executed on dev-2026-07a, the honest status of the whole set is
`NOT_EXECUTED`, and the gate treats compile-ratification as a blocker.
