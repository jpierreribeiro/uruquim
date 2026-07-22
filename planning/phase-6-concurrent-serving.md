# Phase 6 — bounded synchronous Handler concurrency (WP71)

**Status:** IMPLEMENTATION EVIDENCE, 2026-07-22. This document records the
owner decision requested by `phase-6-plan.md` WP71. ADR-030 is not amended
until WP72 passes the combined fault and shutdown gate.

## Decision

`Limits.max_handlers` names the maximum number of synchronous application
Handlers that may execute concurrently:

- `0` selects the recommended automatic policy: processor count clamped to
  **4..32**;
- `1` is explicit compatibility for deliberately single-Handler application
  state and deterministic tests;
- `2..256` is an exact requested capacity;
- negative values and values above 256 reject the application before bind.

The default is automatic because the project has no established user base
whose unsynchronized state must be preserved, while ordinary web applications
perform blocking database, filesystem, password-hashing and outbound HTTP
work. Making the safe conventional path opt-in would preserve compatibility
with applications that do not yet exist at the cost of surprising every new
one. The explicit `1` escape hatch keeps the old execution contract visible.

The field says **Handler capacity**, never backend thread count. A future
official Odin HTTP adapter may implement it differently, but it must preserve
the WP71/WP72 liveness, saturation and shutdown semantics.

## Mechanism and the discovered cancellation race

The bootstrap adapter maps one Handler unit to one odin-http serving lane.
Network reads and writes remain asynchronous and do not occupy a Handler unit.
Immediately before invoking application code, Patch 13 suspends that lane's
posted accept; it rearms accept when the Handler returns.

Merely calling `nbio.remove(accept)` was incorrect. Removal is asynchronous:
a client can complete the accept before the cancel CQE is processed, while the
Handler has already blocked. Suppressing that callback silently loses a live
connection — the explicit one-lane recovery test found this. The final bridge
detaches the operation record, waits for cancellation completion, preserves a
client that won the race, and only then enters application code.

This is deliberately a bridge patch. The future adapter inherits the semantic
corpus, not this io_uring mechanism.

The first complete gate exposed a second multi-lane boundary: Patch 8 compared
the admission budget with `len(td.conns)`, which is lane-local. Four lanes
therefore turned `max_connections = 6` into as many as 24 connections. The
final implementation claims and releases one server-wide atomic active slot;
the existing WP41 reservation corpus is the positive evidence. This finding is
why the full historical gate runs once on the final revision rather than being
replaced by WP71-only tests.

## Ownership and limits

- Framework routes, middleware and serving configuration are immutable after
  publication (WP70).
- `Context`, request views, response scratch and arenas remain lane-local.
- `App_State`, observer sinks and custom logger sinks are application-owned.
  Mutable shared values require locks, atomics or a thread-safe service.
- A synchronous Handler cannot be preempted. Full `max_handlers` saturation
  can delay every other Handler until one returns; this is capacity, not an
  execution deadline.
- `max_drain_time` cannot make permanently stuck application/foreign code safe
  to free. The process supervisor remains the outer bound.

## Evidence and controls

`build/check_wp71_controls.sh` proves:

1. automatic capacity and explicit four-unit capacity keep health live with
   three latch-blocked Handlers;
2. explicit one-unit mode exposes saturation, then recovers after release;
3. automatic policy is bounded to 4..32 and explicit values are exact;
4. `-1` and `257` poison the application before a request can succeed;
5. a blocked backend lane has no accept posted and rearms after return;
6. the server-wide admission reservation is unchanged by lane count;
7. independent mutations — auto collapsed to one, ceiling relaxed, accept
   suspension removed and global admission made lane-local — are rejected.

The loopback baseline must remain below 25 ms and the independent-health
observation window is 250 ms, as pre-registered in `phase-6-spec.md` §5.2.

## Cost and rollback

Adjacent worktrees at WP70 main `19b9cb9` and WP71, the same pinned compiler
and equal-length output paths measured `01-hello-world` at **970,312** and
**975,784** bytes: **+5,472 bytes** for the default concurrent-serving path.
Equal-length paths matter because the Odin output name changes binary padding;
the first measurement exposed and removed that instrument bias.

The application symbol ledger does not grow: this is one field on the existing
`Limits` record. The direct-dependency inventory grows from 21 to 23 because
the private adapter uses `core:os` to resolve automatic capacity and
`core:nbio` to schedule retained exchanges and complete accept cancellation.
No new dependency type crosses the boundary.

Rollback restores the WP70 single-lane adapter, removes `max_handlers`, Patch
13 and the two private imports. It does not affect routes, Handler signatures,
the in-memory transport or any Phase-5 public feature.
