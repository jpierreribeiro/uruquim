# 07 — Phase 1 Spec Gate

Status: **READY.** The gate was temporarily reopened for the requested
Echo-style handler-error study. Experiment 10, ADR-011, and the corresponding
normative updates are now complete; C-8 is closed without changing the
canonical handler signature.

## Authority and execution

```text
Toolchain prefix: /tmp/uruquim-odin-toolchain
odin version:     dev-2026-07-nightly:819fdc7
Pinned commit:    819fdc7
Platform:         Linux Mint 22.1, Linux 6.8.0-86-generic, LLVM 20.1.8
Command:          env PATH=/tmp/uruquim-odin-toolchain:/usr/bin:/bin bash experiments/run_checks.sh
Exit:             0
Result:           PASS=10 FAIL=0 SKIP=0
```

The original `5 PASS / 4 FAIL` run, the corrected second run, and the intended
negative probes remain preserved in `planning/10-c1-execution-evidence.md`.
The following is the real verification run made after applying the accepted
normative amendments. The only display normalization is the exp-06 body view:
its long repeated `\\x00` tail is shown as `...`; status, diagnostics, test
counts, addresses, timestamp, seed, and all decision-bearing values are copied
from the runner output.

```text
odin version: odin version dev-2026-07-nightly:819fdc7
--- api-shape (run) ---
caller app addr = 0x7FFDD705B410 ; app.self_addr(recorded in app()) = 7ffdd705b330
[serve] port=8080 routes=2 app_addr=0x7FFDD705B410
[serve] port=8081 routes=1 app_addr=0x7FFDD705B3B0
PASS: api-shape
--- generic-json-response (run) ---
[json] marshal error: Unsupported_Type
ok/User      -> status=OK commit=1 body={"id":1,"name":"Jean"}
created/^User -> status=Bad_Request commit=1 body={"id":1,"name":"Jean"}
json/Big     -> status=OK commit=1 body={"tags":["a","b","c"],"scores":[10,20,30,40],"nested":[{"id":3,"name":"x"},{"id":4,"name":"y"}]}
PASS: generic-json-response
--- body-binding (run) ---
valid+nested       ok=true err=None responded=false name="Jean" tags=["a", "b"]
empty-body         ok=false err=Invalid_Json responded=true name="" tags=[]
invalid-json       ok=false err=Invalid_Json responded=true name="" tags=[]
over-limit         ok=false err=Body_Too_Large responded=true name="" tags=[]
arena used bytes: 68
PASS: body-binding
--- optional-ok (run) ---
checked   -> id=42 ok=true
discarded -> just_id=42 (ok discarded; allowed but discouraged)
missing   -> v=0 ok=false responded=true
PASS: optional-ok
--- typed-state (run) ---
[A] correct -> db="primary" hits=1 (lifetime: shared &st)
[A] st.hits after handler = 1 (mutation visible => same object)
[B] correct -> db="primary" (wrong type is a COMPILE error, not runtime)
PASS: typed-state
--- request-views (run) ---
views    -> method="GET" path="/users" query="page=2" body="body-bytes-here..."
after reuse -> req.path (view, now GARBAGE)="######" ; saved (copied)="/users"
PASS: request-views
--- middleware-chain (run) ---
onion order   : ["global:before", "group:before", "route:auth", "handler:commit", "route:after", "group:after", "global:after"]
onion commit  : true  (commit happens at handler; middleware 'after' runs post-commit)
preorder order: ["preorder:run", "preorder:run", "handler:commit"]
per-request chain state = slice + index + aborted + committed (no per-hop alloc)
PASS: middleware-chain
--- transport-boundary (run) ---
resp[0] status=200 commit=1 body=pong
resp[1] status=404 commit=1 body={"error":{"code":"not_found"}}
PASS: transport-boundary
--- test-transport (test) ---
[INFO ] --- [2026-07-18 22:33:41] Starting test runner with 6 threads. Set with -define:ODIN_TEST_THREADS=n.
[INFO ] --- [2026-07-18 22:33:41] The random seed sent to every test is: 236291843545088. Set with -define:ODIN_TEST_RANDOM_SEED=n.
[INFO ] --- [2026-07-18 22:33:41] Memory tracking is enabled. Tests will log their memory usage if there's an issue.

Finished 6 tests in 645.988µs. All tests were successful.

PASS: test-transport
============================================
PASS=9 FAIL=0 SKIP=0
```

The toy exp-02 deliberately records its rejected pointer as `Bad_Request` and
leaves the prior body visible; that output is negative evidence, not the
framework contract. The accepted production contract requires a server log
and a fresh complete `internal_error` before commit. WP6 tests that behavior.

## Bucket A — prototype-ratified language and contract shapes

| ID | Criterion | Experiment | State |
|---|---|---|---|
| A-1 | `app()`/`destroy` compile; caller storage is authoritative | exp-01 | **PASS / DECIDED** — by value, no pre-return self-pointer, no copied destroy |
| A-2 | `$T` JSON values; exact one-call `ok`/`created`; rejection known | exp-02 | **PASS / DECIDED** — value-only baseline; pointer/proc rejected; WP6 deref probe non-blocking |
| A-3 | `body(ctx,&dst)->bool`; request allocator; empty/invalid/limit | exp-03 | **PASS / DECIDED** — fixed Phase-1 cap is 4 MiB |
| A-4 | two-result safety diagnostic | exp-04 | **PASS / DECIDED** — omit `#optional_ok`; plain discard is a compiler error |
| A-5 | typed app state alternatives, correct access and wrong-type guard | exp-05 | **PASS / DECIDED** — future private rawptr+typeid; reject nil; assert presence/type |
| A-6 | request views, invalidation, explicit persistent copy | exp-06 | **PASS / DECIDED** |
| A-7 | middleware chain alternatives and post-commit unwind risk | exp-07 | **PASS / DEFERRED** — decision belongs to Phase-2 gate |
| A-8 | conceptual transport boundary and single commit | exp-08 | **PASS / DECIDED** — private shape remains unfrozen |
| A-9 | in-memory dispatch contract | exp-09 | **PASS** — six tests |
| A-10 | void vs returned-error/outcome handler models | exp-10 | **PASS / DECIDED** — keep void handler; private typed error path; four behavior tests plus two compiler probes |

Bucket A result: **10/10 PASS; zero undecided Phase-1 signature blockers.**

## Bucket B — intentionally deferred, with owner

- Middleware pre-order vs onion: Phase-2 Spec Gate, ADR-005.
- Guaranteed threading/event-loop model: no promise; revisit with real
  transport evidence.
- Typed application state implementation and configurable limits: Phase 3.
- Final request arena, radix, benchmarks, optimized 405/header construction:
  Phase 3.
- Definitive internal `Transport` ABI: not frozen before a second real adapter.
- Robust in-flight graceful shutdown: Phase 4.
- Typed per-request `Request_State` and remaining Advanced API: later gate.

These items cannot expand Phase 1 and are not blockers.

## Bucket C — blocker closure ledger

| ID | Closure | Evidence / human decision |
|---|---|---|
| C-1 | **CLOSED** | pinned compiler; original ratification `9/9`, extended final verification `10/10`; transcript above, evidence 10, and exp-10 |
| C-2 | **CLOSED** | ADR-002 B: remove `#optional_ok`; exp-04 mismatch diagnostic |
| C-3 | **CLOSED** | ADR-004 A + AMEND-1; future Phase-3 only |
| C-4 | **CLOSED** | ADR-001 C: canonical `app()` by value with ownership invariants |
| C-5 | **CLOSED** | fixed 4 MiB body cap + minimal 405 with required `Allow` in Phase 1 |
| C-6 | **CLOSED** | AMEND-2: `error.field` optional and omitted when absent |
| C-7 | **CLOSED** | ADR-003 value-only baseline; mandatory marshal logging; WP6 deref probe non-blocking |
| C-8 | **CLOSED** | ADR-011 A: exp-10 proved returned results may be ignored and break bare `return`; keep `proc(ctx)` plus private typed error reporting |

## Normative amendment check

- AMEND-1 applied: nil/type policy for future typed application state.
- AMEND-2 applied: optional omitted `error.field`.
- AMEND-3 applied: progressive defaults with Phase-1 cap/404/405+`Allow`.
- AMEND-4 applied: future surfaces are phase-marked in `ai-context.md`.
- JSON value-only guidance and marshal logging were added to the architecture,
  idioms, agent prompt, canonical patterns, AI context, errors, and WP6 plan.
- App-by-value and no-copy/no-self-pointer invariants are normative.

Static parity checks found no response call using `&payload` except the
explicitly commented **not accepted** example. One old `^User` responder in
the architecture was changed to explicit value dereference. There is no
`web/` or `examples/` directory yet, so no product example can truthfully be
compiled at this pre-implementation gate. Exact documentation/example
compilation becomes a hard WP1/WP10 test; the ten prototype packages cover
the proposed language shapes now.

## Objective result

Decision rule:

- **READY:** every pre-implementation criterion has executed evidence, all
  Phase-1 decisions are explicit, normative docs agree, and no critical
  blocker remains.
- **READY_WITH_BLOCKERS:** architecture is viable but a named Phase-1 human or
  compiler decision remains.
- **NOT_READY:** a central signature is refuted without an accepted fallback,
  or ownership/commit/transport feasibility is undefined.

### HISTORICAL RESULT BEFORE C-8: **READY**

All C-1 through C-7 blockers are closed. Production implementation was not
started before this READY result. Subsequent work is authorized only in the
approved sequence WP0 → WP1 → …, one work package at a time, using
SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE.

This READY result does not freeze middleware semantics, a transport ABI,
threading, radix internals, pointer response support, or any later-phase API.

## Recomputed result after C-8

### CURRENT RESULT: **READY**

All C-1 through C-8 blockers are closed. Experiment 10 passed four behavior
tests; its ignored-result probe compiled and its bare-return probe failed with
the expected diagnostic. ADR-011 is accepted, canonical documents agree, and
the Phase-1 handler remains `proc(ctx: ^Context)`.

This READY result authorizes the approved WP sequence but does not itself
start production implementation. WP0 must complete its real-VPS repetition
before WP1 begins.
