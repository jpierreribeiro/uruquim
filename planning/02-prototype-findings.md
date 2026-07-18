# 02 — Prototype Findings

Status: **EXECUTED — FIRST RUN 5/9, SECOND RUN 9/9.** Both runs and the
separate intended probes are preserved in
`planning/10-c1-execution-evidence.md`. Mechanical corrections were applied
only after the failed first run was recorded.

Predictions below are superseded by the real result where stated. Commented
intentional probes were not run and remain separate from the four baseline
failures.

## Confidence key

- **HIGH** — behavior follows directly from documented Odin/stdlib semantics.
- **MEDIUM** — plausible from documentation but with a real failure mode.
- **OPEN** — genuinely undecided; the experiment gathers evidence, not a verdict.

## Findings

### F1 · api-shape (exp-01) — MEDIUM
**Real result: PASS.** The caller address remained stable during operations;
the address captured before return differed, exactly establishing the
no-pre-return-self-pointer invariant.
Predict: `app()` by value compiles; `&app` is the stable operating address;
`[dynamic]` header copies alias one backing store, so `destroy` must run once.
Watch: by-value return + `defer destroy` double-free if a copy is destroyed
twice. Ratify: `odin run experiments/01-api-shape`. Decides ADR-001 (else fall
back to `app_init(&app)`).

### F2 · generic-json-response (exp-02) — HIGH / DECIDED BASELINE
**First result: FAIL. ADR-003 was reopened.** The import name `json` collides with
the local candidate renderer named `json`; compilation never reached `$T` or
marshal behavior.

**Second result: mechanically PASS; pointer support refuted.** Values
serialize and helpers commit once, but `^User` is rejected by the pinned JSON
marshaller as `Unsupported_Type`. The accepted ADR-003 baseline is value-only;
WP6 owns a non-blocking one-level dereference probe.
Predict: `json(ctx,status,$T)` marshals struct/pointer/slice/large values;
`ok`/`created` show `commit==1`; a proc/rawptr value trips a marshal error
(intended-failure probe). `any` stays an internal stdlib detail. Ratify:
`odin run experiments/02-generic-json-response`. Decides ADR-003.

### F3 · body-binding (exp-03) — MEDIUM
**Real result: PASS.** Valid nested data, empty/invalid/over-limit branches,
and `arena used bytes: 68` matched the hypothesis.
Predict: `body(ctx,&dst)->bool` binds nested strings/slices into the
substituted request arena; empty/invalid → false+responded; over-limit
short-circuits before parsing; `arena.offset>0` proves ownership. Watch:
`json.unmarshal` allocating nested data on `context.allocator` regardless of the
passed allocator. Ratify: `odin run experiments/03-body-binding`. Decides
ADR-006.

### F4 · optional-ok (exp-04) — HIGH / DECIDED
**First result: FAIL before mechanism. ADR-002 remained open.** A dynamic map
compound literal is disabled without `#+feature dynamic-literals`; no
`#optional_ok` diagnostic was obtained.

**Second result: PASS.** `#optional_ok` permits silent discard. The separate
plain-form probe fails with `Assignment count mismatch '1' = '2'`, supporting
the accepted decision to remove the directive from HTTP extractors.
Predict: `#optional_ok` legal; bool droppable; the plain form's discard is a
compile error (intended-failure probe records the diagnostic). Mechanism is
HIGH; the *policy* (keep the directive vs force bool-handling to prevent silent
drop) is OPEN and decided in ADR-002 from the diagnostic text.

### F5 · typed-state (exp-05) — MEDIUM
**Real result: PASS for the normal path.** Correct rawptr+typeid access,
mutation visibility, and the parametric alternative compiled. Wrong-type/nil
probes remain unexecuted.

**Separate probe:** wrong type exits `132` with the expected runtime assertion.
Accepted AMEND-1 makes nil a rejected registration precondition, not a UB
probe.
Predict: A (rawptr+typeid) compiles, mutation visible on original (shared
lifetime), wrong-type asserts; B (parametric) is compile-checked but adds type
args at every call site. nil is the edge → AMEND-1. Ratify:
`odin run experiments/05-typed-state`. Decides ADR-004 (expected: A canonical,
B advanced).

### F6 · request-views (exp-06) — HIGH
**Real result: FAIL. ADR-007 reopened.** `Request` fields lack commas before
trailing comments, so the ownership behavior was not reached.

**Second result: PASS.** Reused buffer changes `req.path` to `######`; the
allocator-backed copy remains `/users`. ADR-007 is supported again.
Predict: views alias the buffer; overwriting the buffer corrupts `req.path`
while a pre-clone `saved` survives — the request-lifetime rule made physical.
Ratify: `odin run experiments/06-request-views`. Decides ADR-007.

### F7 · middleware-chain (exp-07) — OPEN (by design)
**Real result: PASS.** Onion unwind occurred after handler commit; pre-order
and state-cost evidence matched the prediction.
Predict: one cursor drives pre-order and onion; onion "after" runs **after**
`handler:commit` (post-commit) — the exact reason post-`next` semantics are
transport-conditional; per-request state is a slice + 3 scalars, no per-hop
heap. **No Phase-2 verdict.** Feeds ADR-005 and ADR-008.

### F8 · transport-boundary (exp-08) — MEDIUM
**Real result: PASS.** Both responses committed exactly once with expected
status/body.
Predict: minimal `Transport{data,serve,stop}` + single-commit guard works; test
transport captures responses with no sockets; no backend type on the
handler surface (runner greps to confirm). Watch: whether single-commit can be
enforced purely framework-side (HIGH that it can for buffered responses).
Decides ADR-008/ADR-009.

### F9 · test-transport (exp-09) — HIGH
**Real result: FAIL. Contract remains unratified.** Odin rejects taking the
address of procedure parameter `query` for `strings.split_iterator`; two
`strconv.itoa` calls also emit deprecation warnings. The tests did not run.

**Second result: PASS.** A local string-header copy satisfies the iterator and
all six tests pass; `write_int` removes the pinned deprecation warning.
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

First run: **5 PASS / 4 FAIL / 0 SKIP**. Second and post-amendment runs:
**9 PASS / 0 FAIL / 0 SKIP**. Intended probes were executed separately.
Pointer response payloads are refuted by official JSON and the accepted
baseline is value-only. The recomputed pre-implementation gate is READY.
