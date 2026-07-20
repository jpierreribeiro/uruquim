# Route representation shootout — WP28

**Status: MEASURED. A representation is chosen, and every loser's numbers are
recorded.** RG-2's required output, in its own words: *"a representation chosen
from data, with the losing candidates and their numbers recorded."*

Produced by `tests/wp28-runner`; correctness proven by `tests/wp28-shootout`,
which runs in the gate. WP28 chooses; **WP29 implements**.

---

## 0. The stopping rule, applied before the numbers

FINDING-E derived it from the machine rather than from taste: the p95 spread of
*unchanged* code is **±57.6% at 5 routes** and falls to ~13% at 5,000. So:

> **A candidate that "wins" at 5 or 50 routes has won nothing measurable. The
> cardinalities where this instrument discriminates are 500 and 5,000.**

Every conclusion below is drawn from those two columns. The 5- and 50-route
rows are printed because hiding them would be dishonest, not because they
decide anything.

---

## 1. The result, at the cardinalities that discriminate

Median p95 nanoseconds per lookup, ten alternating repetitions.

### 5,000 routes

| Candidate | All_Static | All_Param | Mixed |
|---|---:|---:|---:|
| linear *(today)* | 207,694 | 244,714 | 191,094 |
| linear_improved | 131,199 | **290,098** | 159,587 |
| bucketed | 213,267 | 252,470 | 175,472 |
| hybrid | **838** | 209,131 | 108,504 |
| **radix_ptr** | **1,133** | **1,351** | 1,681 |
| **radix_idx** | **1,141** | **1,358** | **1,402** |

### 500 routes

| Candidate | All_Static | All_Param | Mixed |
|---|---:|---:|---:|
| linear *(today)* | 58,416 | 62,739 | 40,430 |
| linear_improved | 47,596 | 74,869 | 32,300 |
| bucketed | 63,817 | 63,662 | 33,619 |
| hybrid | 858 | 55,441 | 24,047 |
| **radix_ptr** | 1,354 | 1,484 | 1,410 |
| **radix_idx** | 1,324 | 1,625 | 1,405 |

### The one-sentence version

**The radix trees are flat.** ~1.1–1.7 µs whether the table holds 5 routes or
5,000, while every linear variant grows with the table. At 5,000 mixed routes
that is **191 µs versus 1.4 µs — about 136×**, which is more than two orders of
magnitude clear of the ±57.6% noise floor. This is not a close call and does not
need one.

---

## 2. The decision

**`radix_idx` — the segment-keyed tree with nodes in a flat array.**

And the honest half: **the timing did not choose between `radix_idx` and
`radix_ptr`.** They are the same algorithm in two memory layouts, and their
medians differ by less than either cell's own spread — 1,141 vs 1,133 at
5,000 static, 1,402 vs 1,681 mixed, against spreads of 7,900–13,700 bp. **Any
document claiming one is faster than the other on this evidence would be
reading noise.**

So the choice is made on grounds the shootout *can* settle:

* **Teardown is one free instead of N.** `radix_idx` frees a single array;
  `radix_ptr` walks a node list and frees each one. Fewer owners, fewer ways to
  leak, and the project's lifetime ledger has to describe less.
* **No pointer can dangle across growth.** Building the index tree already
  forced this into the open: a parent must be re-indexed *after* a child is
  appended, because the append may reallocate. With pointers that hazard is
  invisible until it corrupts something. The comment recording it is in
  `candidates.odin`, and it is the strongest argument here — it is the same
  class of bug as P8, the dangling-slice corruption the middleware pool's index
  pairs were designed to make impossible (Phase-2 spec §2.2). **The project has
  already chosen indices over pointers once, for this exact reason.**
* **It matches the internals that exist.** Route chains are addressed by
  `chain_start`/`chain_len` index pairs into an App-owned pool. A node array
  indexed the same way is the shape this codebase already reasons in.

`radix_ptr` is recorded as **co-fastest and rejected on ownership**, not on
speed. That distinction matters if anyone revisits this.

---

## 3. The losers, with their numbers and why each lost

**`linear` — the baseline.** O(n), as measured: 1.7 µs at 5 routes, 191 µs at
5,000 mixed. It is not wrong, it does not scale, and Phase 2's own comment
already called the flat array interim.

**`linear_improved` — rejected, and it is the instructive one.** The prefilter
(segment count, first byte, total length) helped static tables — 131 µs vs
208 µs at 5,000 — and **hurt parametric ones: 290 µs vs 245 µs, the worst
number in the entire shootout.** When the discriminating byte falls inside the
parameter segment the prefilter cannot reject anything, so every route pays for
the check and none is skipped. A cheap test that cannot fail is not cheap. This
is exactly the kind of plausible optimisation that folklore keeps and
measurement removes.

**`bucketed` — rejected, and RG-2 predicted it.** 213 µs vs linear's 208 µs at
5,000 static: no measurable difference, because *the bucketed design still scans
linearly inside each bucket*. RG-2's own disclaimer, confirmed rather than
assumed.

Its non-speed argument survives and should be carried into WP29: bucketing makes
static-beats-parametric **structural** instead of re-derived by comparison
order. **The radix tree gets that property for free** — a static child is tried
before the parametric child at every level — so the idea is adopted while the
representation is not.

**`hybrid` — rejected, and it is the near miss.** A map over whole static paths
is superb: **838 ns at 5,000 routes, flat**, the fastest single cell measured.
But it degenerates to a linear scan the moment a parameter appears — 209 µs on
all-parametric, 108 µs on mixed. Real tables are mixed. A representation that is
excellent on half of a table and unchanged on the other half is a representation
that is unchanged.

Worth recording rather than discarding: **if a future measurement shows static
lookup dominating a real workload, a whole-path map in front of the radix tree
is a known, measured 838 ns.** That is a fact WP29 may use, not a plan.

---

## 4. THE CAVEAT WP29 MUST NOT IGNORE — **WITHDRAWN BY WP29, see the note at the end of this section**

**This shootout measures matchers in isolation. It does not measure the
framework.**

Put beside WP26's end-to-end baseline, the arithmetic is sobering:

| At 5,000 routes, Mixed | median p95 |
|---|---:|
| Full `web.test_request` dispatch (WP26) | ~1,916,000 ns |
| The matcher alone, linear (WP28) | ~191,000 ns |
| The matcher alone, radix_idx (WP28) | ~1,400 ns |

**Route matching is roughly 10% of end-to-end p95 at 5,000 routes.** Replacing
it removes almost all of that 10% — a real and large win at high cardinality —
but Amdahl's law sets the ceiling, and **the other ~90% is somewhere else**:
the test transport, the recorder, response construction, arena handling.

Two consequences, stated so nobody has to be disappointed later:

1. **WP29 must not promise an end-to-end speedup proportional to 136×.** The
   claim it can defend is about the matcher, and it must name that perimeter —
   the same discipline the capacity ledger enforces for the word "bounded".
2. **At low cardinality there is nothing to win at all.** At 5 routes every
   candidate sits inside the noise floor. The radix tree is chosen because it
   does not *degrade* there, not because it improves anything.

And one gap named rather than implied: **where the other 90% goes has not been
measured.** WP27 accounted for the allocation *count* on the socket path, not
the *time*. That is a real open question, and on this evidence it is worth more
than any further router work.

### WITHDRAWN, 2026-07-20, by WP29's measurement

**Everything above in §4 is wrong, and `planning/router-implementation.md` §3
explains why.** Matching was approximately **99%** of end-to-end cost at 5,000
routes, not 10%: replacing it took dispatch from 883 us to 1.5 us.

The error was a methodology failure. The `linear` entrant in this shootout is
one I wrote for the shootout, and it pre-split every pattern at build time —
this file says so, approvingly. **The shipped framework was not a candidate and
had not precomputed:** `route_lookup` re-parsed the pattern string on every
comparison, for every route, on every request, making the real baseline roughly
10x slower than the "linear" measured here. The 10% figure divided the real
scan's end-to-end cost by an isolated faster reimplementation's.

**A baseline must be the shipped code, or it is a different program.** The
fair-head-start rule was right for comparing candidates to each other and wrong
the moment one of those numbers was compared to production.

What survives: at low cardinality there is still nothing to win, and the radix
tree is justified there because it does not degrade.

---

## 5. What WP29 inherits

* **Representation: `radix_idx`.** Segment-keyed, nodes in a flat array,
  children by index, static child tried before parametric at every level.
* **A correctness harness that already exists.** `tests/wp28-shootout` proves
  six representations return byte-identical answers across every shape,
  cardinality and miss in its matrix — including the precedence case where a
  static and a parametric route describe the same path. WP29's implementation
  can be added as a seventh entrant and held to the same bar.
* **Matching must allocate nothing.** All six candidates do, proven in the gate
  with a positive control. This is a disqualifier, not a score: on a machine
  with a ±57.6% timing spread, the allocation count is the measurement that can
  actually detect a regression.
* **WP31a and WP32a are already decided**, so the router is being built against
  known semantics rather than constraining them afterwards.

## 6. Addendum — the node interior, measured

§6 originally listed the node's interior as owed to WP29, on the grounds that
the shootout had chosen the shape of the *table* and not the shape of a *node*.
That gap is now closed, because WP29 cannot inherit an unmeasured choice.

**Two things were added: a seventh candidate and a fourth shape.**

`radix_arr` is `radix_idx` with one difference — children keyed by a **sorted
array plus binary search** instead of a `map[string]int`. Everything else is
identical, so the measured difference *is* the node interior.

`Deep` is the shape the first three did not cover, and its absence was a real
flaw. `All_Static`, `All_Param` and `Mixed` put every route under one prefix, so
the node above them has **fan-out equal to the whole table** — 5,000 children.
Real applications register narrow, deep trees. `Deep` spreads routes over digit
segments: depth 5, fan-out at most 10. Measuring only the wide shape would have
chosen the node interior by an accident of my own generator, and it is precisely
the shape where a sorted array should win.

### The numbers, median p95 ns

| Routes | Shape | `radix_idx` (map) | `radix_arr` (sorted array) | array is slower by |
|---:|---|---:|---:|---:|
| 500 | All_Static | **1,344** | 2,174 | 62% |
| 500 | All_Param | **1,478** | 2,361 | 60% |
| 500 | Mixed | **1,493** | 2,257 | 51% |
| 500 | Deep | **1,746** | 2,179 | 25% |
| 5,000 | All_Static | **1,338** | 2,331 | 74% |
| 5,000 | All_Param | **1,335** | 2,463 | 84% |
| 5,000 | Mixed | **1,922** | 3,021 | 57% |
| 5,000 | Deep | **1,609** | 1,918 | 19% |

### The reading, and it needs care

**No single cell is decisive.** Each cell's own p95 spread runs 2,400–9,800
basis points, so a 25% gap sits inside the noise of the cell that produced it.
Quoting any one row as proof would be exactly the mistake FINDING-E exists to
prevent.

**What is evidence is the unanimity.** The map is faster in **eight cells out of
eight**, across two cardinalities and four shapes, by 19–84%. A direction that
holds in every independent cell is informative even when no individual cell is
significant on its own — and the magnitudes line up with the mechanism: one hash
against roughly twelve string comparisons at fan-out 5,000, and the gap shrinks
to its smallest, 19%, exactly where fan-out is smallest.

**The array lost on its own home ground.** `Deep` was added because it is the
shape where binary search over ≤10 children should beat a hash. It is the
closest result — and it is still a loss.

**DECISION: the node keeps `map[string]int`.** Measured, not assumed, and
measured against the alternative the idiom guide's warning would have favoured.
That warning ("avoid maps in hot dispatch paths") is not overturned; it is
scoped. What it is right about is *per-request* maps, which allocate — and no
candidate here allocates at lookup, proven in the gate. A map built once at
registration and only read afterwards is a different thing from a map built per
request, and this is the number that separates them.

### `Deep` changed nothing else

Worth stating, because it was the shape most likely to overturn the main result:
at 5,000 routes `linear` costs 240,957 ns on `Deep` against 219,537 ns on
`Mixed`. **A realistically-shaped table does not rescue the linear scan** — it
is marginally worse on it. The main decision stands on four shapes rather than
three.

## 7. What this shootout still did not measure

* **Build time and table memory.** Registration cost was not compared. A radix
  tree with a `map` per node allocates more at registration than a flat array,
  and for a 5,000-route table that is worth knowing before WP29 ships. **Owed.**
* **Multi-parameter patterns.** Every candidate supports exactly one `:param`,
  which is what WP4's dispatcher supports today. **WP33** changes that, and it
  should re-run this harness rather than assume the ordering survives.
* **`-o:speed`.** Debug builds throughout, matching the gate.
