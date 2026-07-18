# Uruquim — Throwaway Prototypes

These experiments exist to **ratify or refute** proposed Phase-1 public
signatures with real Odin, per the freeze discipline: *specification text
proposes; compiling prototypes ratify.*

**They are throwaway.** No product package imports them. They are not the
framework; they are evidence.

## Status: EXECUTED — EXTENDED SUITE 10/10

The pinned toolchain `dev-2026-07a` (commit `819fdc7`) was **unreachable** in
the authoring environment — GitHub release egress is blocked by the session's
network policy (HTTP 403), and GitHub is not on the proxy allowlist. See
`planning/01-toolchain-baseline.md`.

The first run completed with `PASS=5 FAIL=4 SKIP=0`; after those failures were
recorded, four transparent throwaway-source corrections produced `PASS=9
FAIL=0 SKIP=0`. Both runs and separate intended probes are in
`planning/10-c1-execution-evidence.md`. The accepted Phase-1 JSON baseline
uses concrete payload values; pointer payloads remain unsupported. WP6 owns a
non-blocking one-level pointer-dereference prototype before that restriction
can be reconsidered. Production was banned while these probes ran; the
subsequent READY decision is recorded only in
`planning/07-spec-gate-phase-1.md`.

## How to produce real evidence

```bash
# 1. install dev-2026-07a into an isolated prefix and put it on PATH
export PATH="/tmp/uruquim-odin-toolchain:$PATH"
odin version    # current binary prints dev-2026-07-nightly:819fdc7

# 2. run the verification-only runner (never modifies sources)
bash experiments/run_checks.sh
```

The runner exits `3` if `odin` is absent (records the baseline), `1` if any
experiment fails, `0` if all pass.

## Experiment → decision map

| Experiment | Ratifies signature / contract | ADR |
|---|---|---|
| 01-api-shape | `app()` by value, `destroy(&app)`, `^App` ops | ADR-001 |
| 02-generic-json-response | `json(ctx,status,$T)`, `ok`/`created` exact shorthand | ADR-003 |
| 03-body-binding | `body(ctx, ^$T) -> bool`, request-allocator ownership | ADR-006 |
| 04-optional-ok | `#optional_ok` for value extractors, silent-drop risk | ADR-002 |
| 05-typed-state | `state(ctx,T)` rawptr+typeid vs parametric | ADR-004 |
| 06-request-views | request views + explicit persist copy | ADR-007 |
| 07-middleware-chain | cursor `next`, onion vs pre-order, commit timing | ADR-005 / ADR-008 |
| 08-transport-boundary | minimal private `Transport`, single commit | ADR-008 / ADR-009 |
| 09-test-transport | contract-suite prototype (behavior, not sockets) | — |
| 10-handler-errors | void handler vs typed error vs explicit outcome | ADR-011 |

Intended-failure probes remain commented and were not counted in the first
run. exp-05's wrong-type probe is an expected runtime assertion, despite older
text loosely grouping it with compile failures.
