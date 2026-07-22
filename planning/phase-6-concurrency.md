# Phase 6 concurrency verdict (WP72)

**Status. ACCEPTED — bounded multi-lane synchronous serving, 2026-07-22.**
This is ADR-030 Amendment 1. The Phase-4 single-lane decision remains correct
for the throughput experiment that made it; the Phase-6 liveness workload and
the repaired safety boundary change the product decision.

## The question that was actually measured

This was not another requests-per-second shootout. The pre-registered question
was whether an independent health request can finish while ordinary synchronous
application code is waiting on an external dependency.

| Arm | Occupied Handler units | Health before release | Result |
|---|---:|---:|---|
| explicit one unit | 1 of 1 | no | negative control |
| explicit four units | 1, then 2, then 3 | yes after every addition | accepted liveness arm |
| explicit four units | 4 of 4 | no; yes after release | declared saturation boundary |

The loopback baseline stayed below the pre-registered 25 ms validity ceiling;
independent health completed inside the 250 ms observation window whenever at
least one Handler unit remained. No percentage throughput claim is derived
from this result.

## Safety gate

The candidate passed the conditions ADR-030 originally lacked:

- WP70 publishes immutable routes/middleware/configuration, allocates request
  IDs atomically, owns lane-local Date and connection maps, and elects exactly
  one shutdown owner;
- 4,096 request IDs and 1,024 mixed route/miss dispatches survive deterministic
  contention; sixteen simultaneous `web.stop` callers converge on one server
  lifetime;
- registration after serving is refused without mutating live state;
- pending-read cancellation and the WP59 use-after-free regression remain
  green through WP58 and WP41;
- slow readers, idle sockets and slow writers remain asynchronous and do not
  consume Handler units;
- CORS/preflight, static files, buffered multipart, request IDs, middleware,
  route hits, 404 and 405 all succeed over the real wire while three of four
  Handler units are latch-blocked;
- 3,000 completed idle keep-alive connections drained in **557.887815 ms**
  under a 3 s `max_drain_time`, without leak or use-after-free;
- seeded repeated startup/shutdown and full saturation recovery are green.

The 3,000-connection client and server share one test process, so the harness
requires soft `RLIMIT_NOFILE >= 8192`. The default 1,024 limit fails around 506
clients because every connection consumes a descriptor at both ends. The gate
sets and verifies 8192 explicitly; descriptor exhaustion is not interpreted as
a server result.

The first historical gate also caught a real multi-lane regression before this
verdict: admission used a lane-local connection count, multiplying
`max_connections` by lane count. Patch 8 now claims one server-wide atomic
slot. WP41 and the WP71 mutation control prove the public budget remains global.

## Decision and public contract

Adopt bounded synchronous Handler concurrency:

- `Limits.max_handlers = 0` derives processor count clamped to 4..32;
- `1` preserves explicit single-Handler compatibility;
- `2..256` requests an exact capacity;
- handlers remain ordinary synchronous Odin procedures;
- socket reads/writes do not consume a Handler unit;
- mutable application-owned state must synchronize itself.

This design chooses the ordinary CRUD programming model — call a database,
inspect the result, respond — without futures, callbacks or request
continuations. It bounds the blast radius of blocking work; it does not pretend
to preempt it.

## Non-guarantee and operational rule

When all Handler units are occupied, new Handler progress may wait until one
returns. Arbitrary application or foreign code that never returns may outlive
`max_drain_time`; freeing its state would be a use-after-free, not graceful
shutdown. The supervisor remains the outer process deadline.

Database pool capacity in the canonical Phase-6 deployment must stay below
Handler capacity, leaving room for health and control work. WP74–WP78 own the
database-specific cancellation promise; WP72 makes none on their behalf.

## Adapter transition, ledger and rollback

The semantic contract is Handler capacity and the combined corpus, not
odin-http threads, io_uring operations or Patch 13. A future official Odin HTTP
adapter must pass the same liveness, saturation, 3,000-connection and shutdown
gate before replacing the bootstrap adapter.

No public symbol was added: WP71 used a field on `Limits`, and the application
ledger remains 62 + 2 test-support. Rollback is now **MEDIUM/LOW** rather than
HIGH: explicit `max_handlers = 1` is the compatibility path, while removing the
field/default would break a documented execution contract.
