# 07 — Phase 1 Spec Gate

Status: **EVALUATED.** This gate is computed objectively from the current
evidence. Because the pinned toolchain was unreachable (baseline 01), the
compile-ratification criteria are **not satisfied yet**, and the result is
computed accordingly.

## Criteria, in three buckets

### Bucket A — provable now by prototype
*(each maps to an experiment; provable ⇒ the experiment RAN and PASSED)*

| ID | Criterion | Experiment | State |
|---|---|---|---|
| A-1 | `app()`/`destroy` compile, address stable, no double-free | exp-01 | **NOT_EXECUTED** |
| A-2 | `json(ctx,status,$T)` + `ok`/`created` commit==1 | exp-02 | NOT_EXECUTED |
| A-3 | `body(ctx,&dst)->bool`, arena ownership, empty/invalid/limit | exp-03 | NOT_EXECUTED |
| A-4 | `#optional_ok` legal; discard diagnostic captured | exp-04 | NOT_EXECUTED |
| A-5 | `state(ctx,T)` correct/wrong/nil/lifetime | exp-05 | NOT_EXECUTED |
| A-6 | request views + invalidation + persist copy | exp-06 | NOT_EXECUTED |
| A-7 | cursor chain, onion==post-commit, state cost | exp-07 | NOT_EXECUTED |
| A-8 | minimal transport, single-commit, no leaked types | exp-08 | NOT_EXECUTED |
| A-9 | contract-suite behaviors (404, path/query/body) pass | exp-09 | NOT_EXECUTED |

Bucket A satisfied: **0 / 9** (all authored, none executed).

### Bucket B — designed, but dependent on future implementation
*(cannot be closed at a Spec Gate; carried into WPs)*

- B-1 onion post-`next` semantics → Phase-2 gate (ADR-005).
- B-2 guaranteed threading model → after official adapter.
- B-3 final request arena / benchmarks → Phase 3.
- B-4 definitive `Transport` ABI → after 2nd adapter.
- B-5 read/write timeouts → Phase 3 (transport-dependent).
- B-6 radix optimization → Phase 3 (behavior pinned now by exp-09 tests).

These are **not** blockers; they are correctly deferred and test-pinned where
observable.

### Bucket C — blockers requiring an ADR or human decision

| ID | Blocker | Owner | Evidence needed | Deadline |
|---|---|---|---|---|
| C-1 | **Run the prototype suite on dev-2026-07a** (Bucket A) | toolchain owner | `run_checks.sh` output, all PASS + intended-failures recorded | before WP1 |
| C-2 | ADR-002: keep or drop `#optional_ok` for extractors | API owner | exp-04 diagnostic | before WP5 |
| C-3 | ADR-004: confirm rawptr+typeid canonical + AMEND-1 nil policy | API owner | exp-05 | before WP-typed-state (P3) |
| C-4 | ADR-001: confirm `app()` by value | API owner | exp-01 | before WP1 freeze |
| C-5 | Scope decision: body-cap + minimal 405 in Phase 1' (vs AMEND-3 defer) | product owner | scope-review §contested | before WP4/WP7 |
| C-6 | AMEND-2: `error.field` optional/omitted | API owner | audit A10 | before WP6 |

## Objective result

Decision rule (from the plan):
- **READY** — all pre-implementation criteria satisfied AND zero critical
  blockers.
- **READY_WITH_BLOCKERS** — architecture viable, but explicit human/ADR
  decisions are assigned before the first affected WP.
- **NOT_READY** — a central signature does not compile, ownership/commit is
  undefined, or transport/JSON makes the slice unviable.

Evaluation:
- No central signature has been shown *not* to compile (they simply have not
  been compiled). Ownership and commit models are fully designed
  (exp-06/07/08) and internally consistent. JSON and the transport boundary are
  viable on paper and prototyped. → **not NOT_READY.**
- Bucket A is 0/9 executed, so criteria are **not all satisfied** → **not
  READY.**
- The architecture is viable and every open item has a named owner, evidence,
  and a deadline tied to a WP. → **READY_WITH_BLOCKERS.**

### RESULT: **READY_WITH_BLOCKERS**

The single critical blocker is **C-1** (execute the ratification suite on the
pinned toolchain; blocked today by egress, risk R-01). C-2, C-4, C-5, C-6 are
decision blockers due before their first affected WP; C-3 is due before the
Phase-3 typed-state work.

## What this means concretely

- The **planning** deliverable is complete and independent of the compiler.
- **No production implementation may start** (WP1+) until C-1 turns Bucket A to
  9/9 PASS and C-2/C-4/C-5/C-6 are decided.
- When C-1 is executed, this document is updated in place (WP11) with real
  runner output, and the result is recomputed — expected to move to **READY**
  if Bucket A passes and the decision blockers are closed.

## Non-critical items explicitly deferred

Bucket B in full; AMEND-3 timeout clause; path-string empty-vs-missing
semantics; examples 04-10; observability. None gate Phase 1'.
