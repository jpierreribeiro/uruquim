# Router implementation — WP29

**Status: SHIPPED, and it corrects a claim WP28 made.** The flat route scan is
replaced by the segment-keyed radix index WP28 chose. Observable behaviour is
unchanged, proven by the entire existing test suite passing untouched.

**No public symbol. The ledger stays 44 + 2 = 46.** `web/dispatch_index.odin` is
entirely `@(private)`; the README's promise that "the linear route table … may be
rewritten as long as the observable contracts hold" is being spent exactly as
written.

---

## 1. What changed

`a.private.routes` — the flat array — **remains the single owner** of every
pattern, handler and chain index pair. `mount` still copies into it, teardown
still frees it, and registration is unchanged. The radix tree is an **index over
that array**: it stores integers into it and owns nothing but its own nodes.

A bug in the index can lose a lookup. It cannot lose a pattern.

Two procedures changed their internals and neither changed its signature:
`route_lookup` walks the tree instead of scanning twice, and `allow_value`
collects methods from the tree instead of testing every entry.

**The index is built at registration, never at dispatch.** A lazily-built tree
would allocate inside the first request, and claim **C-5**'s perimeter — measured
around `driver_run`/`driver_cleanup` — would silently start including a one-off
cost that only the first caller pays.

**Precedence is now structural.** The old two-pass scan enforced
"static beats parametric" by running one loop before the other. The walk tries a
node's static child before its parametric child at every level, so `/users/me`
still wins over `/users/:id` regardless of registration order — and the rule is
now a property of the shape rather than of the order two loops appear in.

---

## 2. The result, end to end

Median p50 / p95 nanoseconds through `web.test_request`, ten alternating
repetitions, produced by the same WP26 harness that recorded the baseline.

| Routes | Shape | before (p50) | after (p50) | before (p95) | after (p95) |
|---:|---|---:|---:|---:|---:|
| 5 | Mixed | 1,801 | 1,341 | 3,295 | 2,358 |
| 50 | Mixed | 8,811 | 1,357 | 20,645 | 2,319 |
| 500 | Mixed | 79,489 | 1,410 | 181,097 | 2,450 |
| 5,000 | Mixed | 883,258 | **1,486** | 1,916,286 | **2,713** |
| 5,000 | All_Static | 826,228 | **1,280** | 1,783,046 | **2,218** |
| 5,000 | All_Param | 899,445 | **1,555** | 1,867,831 | **2,839** |

**At 5,000 mixed routes: 883 µs → 1.5 µs, about 594× on p50 and 706× on p95.**

**And dispatch is now flat.** From 5 routes to 5,000, p50 moves from 1,341 ns to
1,486 ns — **11%**, which is inside the noise floor. The framework no longer
cares how many routes an application registers. That, rather than any single
ratio, is the property worth having.

---

## 3. THE CORRECTION — WP28's "10%" was wrong, and here is why

`planning/router-shootout.md` §4 warned, in bold, that route matching was
**"roughly 10% of end-to-end p95 at 5,000 routes"**, and told WP29 it must not
promise an end-to-end speedup proportional to the matcher's 136×.

**That warning was wrong, and this measurement withdraws it.** Matching was
approximately **99%** of end-to-end cost at 5,000 routes, not 10%.

The error is worth more than the number, because it is a methodology failure and
not a slip:

The shootout compared six candidates against a `linear` entrant that **I wrote
for the shootout**, and that entrant pre-split every pattern into segments at
build time. `candidates.odin` even says so out loud — *"Every candidate gets the
same head start, so the shootout measures the representation and not who
remembered to precompute."*

**The shipped framework was not one of the candidates, and it had not
precomputed.** Its `route_lookup` called `route_match(pattern, path)`, which
re-parsed the *pattern string* with `segment_next` on every comparison, for every
route in the table, on every request. So the real baseline was roughly **10×
slower** than the shootout's "linear" — 1.9 ms against 191 µs — and the 10%
figure was computed by dividing the end-to-end cost of the real scan by the
isolated cost of a faster reimplementation.

**Two lessons, recorded rather than absorbed quietly:**

1. **A baseline must be the shipped code, or it is a different program.** The
   fair-head-start rule was right for comparing candidates to *each other* and
   wrong the moment a candidate's number was compared to production.
2. **The shootout understated its own winner.** The correction runs in the
   flattering direction, which is exactly when a project is least likely to go
   back and check. It was found only because WP29 re-ran the end-to-end harness
   instead of assuming the prediction.

**What survives from that warning:** at low cardinality there is still nothing to
win. At 5 routes the before/after difference sits inside the noise floor, and the
radix tree is justified there because it does not *degrade*, not because it
improves anything.

---

## 4. Allocation failure, and what WP18 caught

The first version of this index did not check its allocations, and two WP18
suites — `wp18_mount_that_cannot_allocate_rejects_the_application` and
`wp18_a_mount_that_cannot_allocate_never_serves` — crashed it immediately.

They were right to. **WP18 Amendment 1** exists because discarding an `append`
result is precisely how routes disappear in silence while the application still
reports healthy, and `mount` is fail-closed by contract: a partial mount rejects
the whole application.

So every allocation in `index_insert` is now checked, `mount` poisons the
application when the index cannot grow, and the map insert is **verified by
reading it back** — a map assignment reports no error, and under a failing
allocator it silently does nothing, which would leave a node unreachable and no
diagnostic anywhere.

That the existing suite caught this within one gate run is the argument for
having written it.

---

## 5. What WP29 did not do

* **The `Allow` byte-exact order is untouched.** `allow_value` collects the same
  set through a different route and emits it through the same
  `ALLOW_METHOD_ORDER` machinery. WP32b will reuse it for OPTIONS, and it must
  still find one machine and not two.
* **Registration cost was not measured.** The tree allocates a node per distinct
  segment and a map per node, which is more registration work than appending to
  an array. For a 5,000-route table that is worth knowing. **Still owed**, and it
  is now the largest unmeasured thing in the router.
* **Path normalisation (WP31b) and HEAD/OPTIONS (WP32b) are not implemented.**
  Their specs are decided (`planning/phase-3-spec.md`) and both sit before
  matching, so neither is constrained by this representation.
* **Multi-parameter patterns remain one-per-pattern**, as WP4 shipped them.
  **WP33** changes that, and the tree is the right shape for it: a second
  parameter is another level, not another scan.
