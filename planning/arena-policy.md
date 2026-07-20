# Arena and oversize policy — WP35

**Status: MEASURED. The decision is to change nothing, and that is the finding
rather than an absence of one.** RG-4 asked what happens to a request arena
after an unusually large body — retain, trim or release — and required "a policy
with numbers behind it". The numbers say the policy is already correct.

Measured by `tests/wp35-public-surface`, which runs in the gate.

---

## 1. R-16, as the register states it

> One adversarial request permanently raises process RSS across otherwise small
> traffic. Signals: **retained capacity follows peak body size**; memory does
> not return near baseline after a giant request.

## 2. What was measured

Small requests establish a baseline; one **3 MiB** body runs — inside the 4 MiB
cap, so it is accepted rather than answered 413; small traffic resumes.

| Point | Retained bytes |
|---|---:|
| baseline, after warm-up | 1,929 |
| after a 3 MiB request and four small ones | 2,254 |
| after a **second** 3 MiB request and four more | no further growth |

**Retained capacity does not follow peak body size.** A 3 MiB request moved
retained memory by roughly **325 bytes** — about 0.01% of the body — and peak
memory exceeded the body while retained memory never approached it.

**The residual does not accumulate**, which is the sharper question and the one
a single measurement cannot answer. A per-request residual would be R-16
arriving slowly. A second oversize request added none, so what was observed is a
one-off high-water mark and not a ratchet.

## 3. Why the design already behaves this way

* The request arena is `mem.Dynamic_Arena`, created **lazily** at the first body
  bind and destroyed by `request_arena_destroy` inside `driver_cleanup` — once
  per request, on both drivers.
* Every other request-local buffer (`allow_buffer`, `error_buffer`,
  `response_headers`, `request_id_buffer`) is a **fixed array on `Context`**,
  and `Context` is a fresh stack value per request.

**Nothing is pooled.** The register's own fallback — *"release oversize
allocations at request end even if common-path buffers stay reusable"* — is not
a change to make; it is the shipped behaviour, and now it is measured rather
than assumed.

## 4. The decision, and the thing deliberately NOT built

**No reuse policy, no trimming heuristic, and no generational token.**

WP35's own discipline decides this, and it is worth quoting because it is the
part that is easy to ignore when a work package feels obliged to produce code:

> **While nothing is pooled, do not build the abstraction** — an empty
> generational wrapper around storage that is never reused is complexity with no
> defect to catch.

The stale-reference hazard the token would defend against is real *once
something is pooled*: request A arms a timeout, the slot is released, request B
reuses it, A's timeout fires, and B must survive. That test comes **with** the
reuse and not before, and the reuse and the token must land in one commit so
they revert as one.

## 5. The tripwire

`tests/wp35-public-surface` is not documentation of a happy state. It is the
alarm for the moment a later work package pools something — **WP36**'s timeouts
are the likeliest candidate, since a timer needs somewhere to live across a
request boundary.

If these assertions go red, they have done their job. **They must not be
"fixed" by weakening them.** The same instruction the plan already attaches to
`wp23_public_an_id_never_leaks_into_the_next_request`, which passes structurally
today for the same reason: nothing is pooled yet.

## 6. What this did not measure

* **Process RSS.** Retained bytes are measured through a tracking allocator, not
  through `/proc/self/statm`. An allocator that returns memory to its free list
  without returning it to the OS would satisfy every assertion here and still
  raise RSS. That is a real gap, it belongs to the allocator and not to the
  framework, and naming it is cheaper than implying it was covered.
* **Concurrent oversize traffic.** Single-threaded throughout. N simultaneous
  3 MiB requests each hold their own arena, so peak scales with concurrency —
  which is the transport's bound to state, not this framework's, and the
  capacity ledger already says connections are not bounded here.
* **Bodies above the cap.** A body over 4 MiB is answered 413 and never reaches
  an arena. That path is WP7's and unchanged.
