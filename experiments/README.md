# Uruquim — Throwaway Prototypes

These experiments exist to **ratify or refute** proposed Phase-1 public
signatures with real Odin, per the freeze discipline: *specification text
proposes; compiling prototypes ratify.*

**They are throwaway.** No product package imports them. They are not the
framework; they are evidence.

## Status: NOT_EXECUTED (baseline)

The pinned toolchain `dev-2026-07a` (commit `819fdc7`) was **unreachable** in
the authoring environment — GitHub release egress is blocked by the session's
network policy (HTTP 403), and GitHub is not on the proxy allowlist. See
`planning/01-toolchain-baseline.md`.

Therefore every experiment result is currently
`NOT_EXECUTED — pending compile on pinned toolchain`, with hypothesis and
expected outcome stated in each local `README.md`. The code is written to run;
it simply has not been run here. **No signature is marked ratified.**

## How to produce real evidence

```bash
# 1. install dev-2026-07a into an isolated prefix and put it on PATH
export PATH="/tmp/uruquim-odin-toolchain:$PATH"
odin version    # must print dev-2026-07a

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

Intended-failure probes (compile errors we *want*) are commented in the
sources and called out in each README so success and intentional failure are
recorded separately.
