# C-04 — Response size and memory retention: the measurement and the decision

**Status: LIVE (Closure, WP C-04).** Answers perimeters 2 and 3 of
`planning/production-readiness-closure.md` §4, both of which were open because
**nobody had a number**. Now there is one.

---

## 1. The measurement

`tests/c04-response-size`, gated by `build/check_c04_controls.sh`. Eight
keep-alive connections, one 4 MiB response each (phase 1), then 200 small
responses per connection on the *same* connections (phase 2). RSS is read from
`/proc/self/statm` — resident memory, which is what an operator sizes a cgroup
against, and the reading an accounting bug cannot fake (the WP2 two-instance
trap, applied to memory). The client's own scratch buffer is **touched before
the baseline is taken**, so its pages are counted as the client's rather than
as the framework's.

Three runs on the development box:

| Run | baseline | after 8 × 4 MiB | after 1600 small | retention | growth in phase 2 |
|---|---|---|---|---|---|
| 1 | 8.5 MiB | 40.7 MiB | 32.7 MiB | **32.2 MiB = 1.01×** | **−8.0 MiB** |
| 2 | — | — | — | **32.2 MiB = 1.01×** | **−12.0 MiB** |
| 3 | — | — | — | **24.1 MiB = 0.75×** | **−11.9 MiB** |

### What it says, in three findings

**F-C04-1 — a connection retains about one full copy of the largest response it
ever served.** 32 MiB served across 8 connections produced 32.2 MiB of resident
growth: **1.01×**, one byte held per byte sent. This is the growing
`virtual.Arena` behaving exactly as an arena should — `clean_request_loop` ends
each request with `free_all`, which resets the offset and keeps the blocks. The
consequence is the part that was never written down: **the footprint is
per-connection and it outlives the request that caused it.** With
`max_connections` at its default of 1024, the worst case is
`1024 × (largest response any one connection ever served)`, and **no setting
bounds it** — `max_body` caps what a client may *send*, not what a handler may
*build*, and ADR-014 buffers responses whole.

**F-C04-2 — there is no per-request leak, and the arena does give memory back.**
Phase 2 growth was **negative in all three runs** (−8.0, −12.0, −11.9 MiB):
1,600 small responses on arenas that had already grown cost nothing and released
some of the peak. A per-request reclaim defect would show as monotone growth
here; it does not exist. This is the half of perimeter 3 that can be called
CLOSED.

**F-C04-3 — the retention decays but does not return to baseline.** After 1,600
small responses RSS settles ~24 MiB above baseline — roughly three quarters of
the peak still held, and unchanged after the connections close (`after_close`
equals `after_small`, because the process, not the connection, is the last
owner of freed pages). Run 3's lower peak (0.75×) with the same steady state
shows the peak itself is allocator-timing-dependent; **the steady state is
not.**

---

## 2. The decision on response size

> **Uruquim does not add a response-size limit in this WP. The core's position
> is that total memory is DELEGATED — to a cgroup — and that delegation is now
> backed by a measured number rather than by an assumption. A
> `max_response_bytes` limit is RECOMMENDED as its own work package, specified
> below, and is not smuggled in at the end of an audit phase.**

**Why delegation is defensible.** The bound an operator actually needs is on the
*process*, not on one response: `1024 × largest response` is the quantity that
matters, and no per-response number expresses it. A cgroup does, exactly, and
`docs/operations.md` already makes it mandatory topology. The measurement is
what turns that from hand-waving into a sizing rule an operator can apply:

> **Size the memory cgroup for `max_connections × (largest response your
> handlers can build) + baseline`.** At the defaults that is 1024 × your largest
> response. Lower `max_connections` if that product is uncomfortable — it is the
> only setting that moves the product today.

**Why a limit is nonetheless the better long-term answer, and I recommend it.**
The measured 1.01× says the retention *is* the framework's own copy. A limit
checked where the framework copies the body would therefore prevent essentially
all of it, and would convert an OOM — which kills every in-flight request on the
process — into one typed 500 that an observer can see. That is a strictly better
failure mode, and it is the same argument ADR-039 made for the write deadline.

**Why it is not in this WP.** It mints public surface: a `Limits` field *and* a
`Framework_Error` member for the refusal to be observable, which is the full
gate-amendment checklist (up to twelve files) plus a ledger amendment. That is
a work package with its own gate run, not a tail-end addition to an audit. The
plan anticipated exactly this fork — C-04 is specified as "IMPLEMENTATION **or**
DECISION + SOAK" — and the decision is recorded here with its cost so the next
agent inherits a specification rather than a question.

### The specification, handed forward

- `Limits.max_response_bytes: int`, **default 0 = off**, matching
  `max_write_time` and `max_idle_time`: a framework-chosen number would break
  applications that legitimately serve large responses today (ADR-039's
  precedent, and the reason those two ship disabled).
- Enforced where the framework copies the completed body into the response
  buffer — the one point at which the framework, not the application, is about
  to allocate.
- A breach produces the standardized **500** through a new
  `Framework_Error.Response_Too_Large`, so it reaches the typed observer with a
  route and a status and no request-derived bytes.
- Trigger to promote this from recommendation to requirement: **any deployment
  that cannot set a memory cgroup**, or any application whose response sizes are
  not bounded by its own construction.

---

## 3. The soak, and what is honestly still owed

The suite above runs in ~2 seconds and answers the *shape* question — retention
versus leak — decisively, because the two phases separate them. It is **not** an
hours-long soak, and the difference matters:

- What a 2-second two-phase run can prove: there is no per-request reclaim
  defect, and the per-connection retention is ~1× of the largest response.
- What only an hours-long run can prove: that nothing accumulates on a timescale
  1,600 requests does not reach — fragmentation across many distinct sizes,
  slow growth in the connection map, spool-directory residue.

**The hours-long soak is therefore RECORDED AS OWED**, alongside the one other
scale claim this project has not demonstrated on hardware (the 3,000
real-socket SSE round, `docs/operations.md` and `planning/phase-7-freeze.md`).
Both want the same thing — a quiet machine for a long time — and both should be
run once, together, rather than approximated twice. Naming it here is the point:
an obligation in a document with a gate is trackable; an obligation in a
reader's memory is what this whole phase exists to stop relying on.
