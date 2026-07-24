# C-07 — The Closure record and the production-readiness verdict

**Status: FREEZE (Closure, WP C-07).** The reconciled record of the Production
Readiness Closure, and the verdict its exit condition demands.

---

## 1. What the phase was for, and whether it worked

The Closure was called after a fourth finding arrived by accident. The write
deadline was in the Phase-3 contract, was deliberately declined at the Phase-3
freeze for a correct reason, was recorded as pending — **and then stopped being
trackable until it resurfaced in conversation.** The diagnosis was not that the
framework was bad but that it had excellent per-feature discipline and no layer
above it reconciling every promise into one place.

The test of that diagnosis is simple: *did review-by-resource find things
review-by-feature had missed?*

**It found four production-blocking defects, all pre-existing on `main`, none of
which any existing suite detected.** Three of the four make `web.stop` never
return — the framework's most load-bearing operational promise. That is the
answer.

| # | Defect | How it was reached | Fix |
|---|---|---|---|
| **F-C03-1** | The drain loop's `#partial switch` omitted `.Will_Close`, so a single client sending `Connection: close` and not reading its response made `web.stop` **never return, past every deadline**. `max_drain_time` bounded nothing for the most ordinary client there is. | C-03 cell D8 — enumerating *states*, not scenarios | patch 26 |
| **F-C05-1** | `handler_lane_enter`'s accept-cancel spin is unbounded. A lane parked in it never reaches `_server_thread_shutdown`, and `serve` waits for every lane: **4 runs in 6 wedged**, `web.stop` not returning in 60 s against a 3 s deadline. | C-05's saturation ramp — and it refuted an argument C-01 had accepted | patch 27 |
| **F-C01-1** | The `.Insufficient_Resources` accept retry re-armed unguarded, leaving an unreachable `accept` that survives `nbio.remove(td.accept)` and holds `num_waiting()` above zero — shutdown never ends, exactly at fd exhaustion. | C-01's ten questions, asked of every operation | patch 24 |
| **A10** | Every RST'd connection held an admission slot for the full 500 ms close delay, so a flood above `budget / 500 ms` made the server refuse everyone: **1 healthy probe served in 59**. | C-03, inheriting the F-002 report's out-of-scope note | patch 25 |

Two further results are worth as much as the fixes:

- **The parallel limitation lists had already drifted into falsehood.**
  `docs/operations.md` told operators large-body upload had "no public API yet"
  and that the framework "will not spool to disk" — both false since 7.5-C2 —
  and called streaming out-of-core four bullets after saying SSE covers server
  push. A list maintained in eleven places decays into telling you to build a
  workaround for a solved problem.
- **`proxy_buffering off` was proven mandatory rather than advisable**: with
  nginx's default, a stream reaches the client *never*.

---

## 2. The exit condition, judged

> No framework-owned operation exists without an explicitly declared owner,
> capacity, deadline, or cancellation; and where something is unbounded or
> external, the responsible topology is named, mandatory, documented and tested.

**MET.** The evidence, each part gate-enforced so it cannot quietly stop being
true:

| Half of the condition | Instrument | Gate |
|---|---|---|
| every operation has a declared owner / capacity / deadline / cancellation | `planning/closure-async-op-inventory.md` — **23 operation-creating call sites × 10 questions**, census derived from the source | `check_c01_controls.sh` |
| every framework-owned resource has limit / deadline / cancellation / saturation / metric / shutdown | `planning/closure-readiness-matrix.md` — **13 resources × 8 properties, no unanswered cell** | `check_readiness_matrix.sh` |
| the fault space is enumerated rather than discovered | `planning/closure-fault-campaign.md` — **34 cells, 0 unanswered** | `check_c03_controls.sh` |
| the combined saturation profile is known, and the write-observability gap is specified | `planning/closure-saturation-and-write-observability.md` — the **Handler lane binds first, at 4 concurrent clients** | `check_c05_controls.sh` |
| the router's deliberate differences are pinned as a negative corpus | `planning/closure-httprouter-study.md` — 10 cases, BSD-3 notice gated | `check_c08_controls.sh` |
| unbounded memory has a named, mandatory topology **with a measured sizing rule** | `planning/closure-response-size-and-memory.md` — `max_connections × largest response` | `check_c04_controls.sh` |
| the delegated topology is **tested**, not only documented | `planning/closure-proxy-contract.md` | `check_c06_controls.sh` |

**Unclassified cells: zero.** Every cell in the matrix and every cell in the
grid carries a disposition, and both gates fail if one loses it.

---

## 3. The residual, classified

Per §3 of the plan, a classified **acceptable operational limitation** does not
block the verdict; an **unclassified cell** or a **blocking absence** does.
There are none of the latter two. What remains:

### 3.1 One open DEFECT — and it is named, not buried

**F-C03-2 — the real-socket suites crash at a low rate under gate load.** Two
observations this session against fourteen green runs; ruled out as a regression
(green on pristine `origin/main` and on this tree alike); signature is a crash
inside server *startup*, before a suite's own work begins. It is **not closed**,
and the standing project advice — re-run — is a workaround with a ticket rather
than a verdict. **The instrument it needs is named:** an ASan/debug gate build
with kept core dumps, exactly as the F-002 investigation used.

This is the one item that would make a reader hesitate, and it should. It does
not violate the exit condition — no operation lacks an owner because of it — but
it is an unexplained crash in a project that has just proven the value of not
accepting explanations without tests.

### 3.2 Acceptable operational limitations, delegated with a mandatory topology

Each is in the matrix with its owner; none blocks the verdict.

- **TLS** → the reverse proxy. Topology now **tested** (C-06).
- **Total process memory** → a cgroup, with the C-04 sizing rule.
- **Accept backlog** → the kernel (`somaxconn`).
- **Restart, and the outer bound on a blocked handler** → a supervisor with a
  kill timeout. A faulting handler aborts the process by construction (Odin has
  no recoverable panic, ADR-020) and a blocked one is not preemptible.
- **Deadlines are request-scoped, not shutdown-scoped** (F-C01-2): between
  `web.stop` and the drain deadline the sweep no longer runs, so `max_drain_time`
  (default 10 s) is the only bound that survives. Setting it to 0 is valid and
  removes that bound too.
- **Periodic lane timers are uncancellable but self-terminating** — a clean stop
  costs 991 ms, and C-01 named the mechanism (the 1 s Date timer).
- **`web.static` reads synchronously**, blocking its lane, bounded by
  `max_file_size` (8 MiB default).

### 3.3 Specified and deferred — each with a trigger, none with a question mark

Deferred work here means *a specification handed forward*, not an open question.

| Item | Why deferred | Trigger |
|---|---|---|
| `Limits.max_response_bytes` (C-04) | mints a `Limits` field **and** a `Framework_Error` member — a twelve-file ledger amendment deserving its own WP and gate run | a deployment that cannot set a memory cgroup |
| `web.Server_Stats` / `web.stats()` (C-05) | same, +2 ledger | the first deployment running detached streams |
| A real-proxy interop round (C-06) | no proxy binary on the gate machine | before any production deployment behind nginx |
| Upstream keep-alive + duplicated limits through a **pooling** proxy (C-06) | needs a second fixture, not a switch on the first | with the real-proxy round |
| The **hours-long** soak (C-04) | a 2-second two-phase run answers the shape question; only a long run reaches slow accumulation | a quiet machine |
| The **3,000 real-socket** SSE round (Phase 7) | same | the same quiet machine — run once, together |
| `radix_compact` (C-08) | optimisation with no readiness consequence | only on material gain, and it must pass the backtracking test unchanged |

---

## 4. The verdict

> **PRODUCTION-READY FOR A CONTROLLED PILOT**, behind a reverse proxy with
> `proxy_buffering off`, under a supervisor with a kill timeout, inside a memory
> cgroup sized by the C-04 rule, with `max_write_time` and `max_idle_time`
> enabled. The Closure's exit condition is **met**: no framework-owned operation
> lacks a declared owner, capacity, deadline or cancellation, and every
> delegation names a topology that is mandatory, documented and now tested.
>
> **The one thing standing between this and an unqualified verdict is F-C03-2**,
> an unexplained low-rate crash under gate load. It is a defect with a
> reproduction rate and a named instrument, not an unknown.

**What changed the verdict from the 2026-07-23 audit's "controlled pilot" is not
the label but its basis.** That audit reached the same words from a review of
features. This one reaches them from an enumerated space: 23 operations, 13
resources, 34 fault cells, zero unclassified. The difference is that a future
finding is now a *new cell* rather than a *new category* — which is the only
form of "done" a systemic review can honestly claim.

### The rule this phase leaves behind

Written into `planning/closure-async-op-inventory.md` beside the entry that
earned it, because C-01 got a cell wrong and C-05's measurement caught it:

> **A cell whose safety rests on reasoning rather than on a test is not
> answered, it is deferred.**

C-01 classified the unbounded accept-cancel spin as acceptable on the argument
that `io_uring` always delivers a completion for a cancelled submission. The
argument was plausible, the kind a careful reader accepts — and four runs in six
wedged. The ten questions found the operation and asked the right question of
it; what failed was the step after.

---

## 5. What Phase 8 inherits

Phase 8 (proof-by-use, WP102–113, **not renumbered** — R1 stands) begins on a
foundation where:

- shutdown actually terminates in the three ways it previously did not;
- the limitations list is one gated document rather than eleven prose lists, two
  of which were lying;
- the saturation profile is known, and it is not the one the configuration
  suggests: **the Handler lane binds first, at four concurrent clients**, while
  the connection budget sits idle. An operator tuning `max_connections` is
  tuning the wrong knob, and Phase 8's board will meet this immediately.
