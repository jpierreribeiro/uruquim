# 10 — C-1 Execution Evidence

Status: **EXECUTED — FIRST RUN FAILED (5/9 PASS).** This file preserves the
first real execution before any prototype source correction.

## Toolchain actually executed

```text
Install prefix: /tmp/uruquim-odin-toolchain
odin version:   dev-2026-07-nightly:819fdc7
OS:             Linux Mint 22.1, Linux 6.8.0-86-generic
CPU:            Intel(R) Core(TM) i7-8665U CPU @ 1.90GHz
RAM:            23845 MiB
Backend:        LLVM 20.1.8
Binary SHA-256: 6fea037515fee6c4e681a67fe86818998241f15abbadd8df67899d9f0ff32b12
```

The commit matches the pinned authority (`819fdc7`). The binary identifies
itself as `dev-2026-07-nightly`, not literally `dev-2026-07a`; this naming
difference is recorded, not normalized away.

The isolated prefix contains `core:net`, `core:nbio`, and
`core:encoding/json`.

## Command

```bash
env PATH=/tmp/uruquim-odin-toolchain:/usr/bin:/bin \
  bash experiments/run_checks.sh
```

Exit code: `1`.

## Real runner output

```text
odin version: odin version dev-2026-07-nightly:819fdc7
--- api-shape (run) ---
caller app addr = 0x7FFC10F71EC0 ; app.self_addr(recorded in app()) = 7ffc10f71de0
[serve] port=8080 routes=2 app_addr=0x7FFC10F71EC0
[serve] port=8081 routes=1 app_addr=0x7FFC10F71E60
PASS: api-shape
--- generic-json-response (run) ---
experiments/02-generic-json-response/main.odin(41:45) Error: Use of import name 'json' not in the form of 'x.y'
experiments/02-generic-json-response/main.odin(41:56) Error: Cannot determine type for implicit selector expression '.OK'
experiments/02-generic-json-response/main.odin(42:45) Error: Use of import name 'json' not in the form of 'x.y'
experiments/02-generic-json-response/main.odin(42:56) Error: Cannot determine type for implicit selector expression '.Created'
experiments/02-generic-json-response/main.odin(75:2) Error: Use of import name 'json' not in the form of 'x.y'
experiments/02-generic-json-response/main.odin(75:14) Error: Cannot determine type for implicit selector expression '.OK'
FAIL(1): generic-json-response
--- body-binding (run) ---
valid+nested       ok=true err=None responded=false name="Jean" tags=["a", "b"]
empty-body         ok=false err=Invalid_Json responded=true name="" tags=[]
invalid-json       ok=false err=Invalid_Json responded=true name="" tags=[]
over-limit         ok=false err=Body_Too_Large responded=true name="" tags=[]
arena used bytes: 68
PASS: body-binding
--- optional-ok (run) ---
experiments/04-optional-ok/main.odin(41:27) Error: Compound literals of dynamic types are disabled by default
Suggestion: add '#+feature dynamic-literals' for this file; the literal implicitly allocates with context.allocator
FAIL(1): optional-ok
--- typed-state (run) ---
[A] correct -> db="primary" hits=1 (lifetime: shared &st)
[A] st.hits after handler = 1 (mutation visible => same object)
[B] correct -> db="primary" (wrong type is a COMPILE error, not runtime)
PASS: typed-state
--- request-views (run) ---
experiments/06-request-views/main.odin(16:31) Syntax Error: Expected a comma, got a newline
experiments/06-request-views/main.odin(17:31) Syntax Error: Expected a comma, got a newline
experiments/06-request-views/main.odin(18:31) Syntax Error: Expected a comma, got a newline
experiments/06-request-views/main.odin(19:32) Syntax Error: Expected a comma, got a newline
FAIL(1): request-views
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
experiments/09-test-transport/main_test.odin(48:37) Error: Cannot take the pointer address of 'query' which is a procedure parameter
experiments/09-test-transport/main_test.odin(65:19) Warning: itoa is deprecated: Use strconv.write_int() instead
experiments/09-test-transport/main_test.odin(69:19) Warning: itoa is deprecated: Use strconv.write_int() instead
FAIL(1): test-transport
============================================
PASS=5 FAIL=4 SKIP=0
```

## Classification

| Experiment | First-run result | Consequence |
|---|---|---|
| exp-01 API shape | PASS | ADR-001 receives real evidence; pre-return self-address differs as expected, so `App` must never retain it. |
| exp-02 generic JSON | **FAIL** | ADR-003 reopened. Candidate source collides between imported package name `json` and local renderer `json`; `$T` itself was not reached. |
| exp-03 body binding | PASS | ADR-006 supported; nested allocation used the supplied arena (`68` bytes). |
| exp-04 optional-ok | **FAIL** | ADR-002 remains open. Compilation stopped at an unrelated dynamic map literal before the directive behavior was exercised. |
| exp-05 typed state | PASS | ADR-004 receives real evidence for correct-type access and shared lifetime; nil/wrong-type policy remains human/spec work. |
| exp-06 request views | **FAIL** | ADR-007 reopened. The candidate `Request` struct is syntactically invalid because commas are missing before trailing comments. |
| exp-07 middleware chain | PASS | ADR-005/008 evidence confirms onion unwind occurs after handler commit. No Phase-2 decision is made. |
| exp-08 transport boundary | PASS | ADR-008/009 supported for the throwaway buffered model; second commit rejected. |
| exp-09 test transport | **FAIL** | Contract prototype unratified. Odin forbids taking the address of a procedure parameter for `split_iterator`; deprecated `itoa` calls also need review. |

## Intentional probes — separate from real failures

The commented probes were **not executed by the runner** and are not counted
as either PASS or FAIL:

- exp-02: proc/raw payload probe remains commented; expected JSON marshal
  rejection path was not reached because baseline compilation failed first.
- exp-04: plain two-result discard remains commented; its expected compile
  diagnostic was not captured because baseline compilation failed first.
- exp-05: wrong-type accessor remains commented; this is actually an expected
  **runtime assertion**, not a compile failure. The normal correct-type run
  passed.

## Gate consequence

The first run left Bucket A incomplete. C-1 was then continued with explicit,
source-visible prototype corrections; the evidence above remains the immutable
record of the original failure.

## Second runner pass after recorded corrections

Corrections applied only to throwaway sources:

- exp-02: import `core:encoding/json` as `encoding_json`, preserving the local
  candidate procedure name `json`.
- exp-04: replace the disabled dynamic map literal with `make` + assignments.
- exp-06: add required struct-field commas.
- exp-09: iterate over a local copy of `query`; replace deprecated `itoa` with
  the pinned `write_int(buf, i64, base)` signature.

Command and exit code:

```text
env PATH=/tmp/uruquim-odin-toolchain:/usr/bin:/bin bash experiments/run_checks.sh
exit: 0
PASS=9 FAIL=0 SKIP=0
```

Behavioral output that affects decisions:

```text
api-shape:
  caller app addr = 0x7FFC86488400
  app.self_addr(recorded in app()) = 7ffc86488320

generic-json-response:
  ok/User       -> status=OK commit=1 body={"id":1,"name":"Jean"}
  created/^User -> status=Bad_Request commit=1 body={"id":1,"name":"Jean"}
  json/Big      -> status=OK commit=1 body={"tags":["a","b","c"],"scores":[10,20,30,40],"nested":[{"id":3,"name":"x"},{"id":4,"name":"y"}]}
  stderr: [json] marshal error: Unsupported_Type

optional-ok:
  checked   -> id=42 ok=true
  discarded -> just_id=42 (ok discarded; allowed but discouraged)
  missing   -> v=0 ok=false responded=true

request-views:
  views -> method="GET" path="/users" query="page=2"
  after reuse -> req.path="######" ; saved="/users"

test-transport:
  Finished 6 tests. All tests were successful.
```

The runner is mechanically green, but exp-02 **refutes pointer payload support**
in the pinned official JSON package: `User` and `Big` values serialize, while
`^User` returns `Unsupported_Type`. The stale previous body remains in the toy
capture because the error path changes status/commit but does not clear it;
production behavior must render a fresh `internal_error` before commit.

## Intended probes executed separately from the runner

The probes ran from copies under `/tmp/uruquim-intended-probes`; workspace
sources remained in their normal runnable state.

### exp-02 unsupported proc payload — intended runtime marshal rejection

```text
exit: 0
[json] marshal error: Unsupported_Type   # ^User normal-run rejection
[json] marshal error: Unsupported_Type   # proc probe rejection
```

### exp-04 plain two-result discard — intended compile failure

```text
exit: 1
/tmp/uruquim-intended-probes/exp04/main.odin(61:2) Error:
Assignment count mismatch '1' = '2'
    p := query_int_plain(&ctx, "id")
```

This directly supports removing `#optional_ok` from HTTP extractors: with the
directive the boolean was silently discarded; without it the compiler forces
two-result handling.

### exp-05 wrong state type — intended runtime assertion

```text
exit: 132
runtime assertion: web.state called with a type different from the registered App_State
```

This is a runtime assertion probe, not a compile failure. It supports the
typeid check; the nil-registration policy still requires AMEND-1.

## C-1 conclusion at execution time

The mechanical runner requirement and separate intended-probe capture were
complete. At that time A-2 was semantically refuted for pointer payloads and
A-5's nil policy still needed a spec decision. Those human decisions were
subsequently made; `planning/07-spec-gate-phase-1.md` is the authoritative
recomputed READY result. This file remains the immutable execution history.
