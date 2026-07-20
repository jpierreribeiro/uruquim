# Phase-2 dispatch baseline — WP26

**Status: RECORDED DATA.** Produced by `build/check_wp26_bench.sh` on
2026-07-20. Nothing here is a decision; WP26's own scope line is *"This work
package produces numbers."* WP28 chooses a representation, and it must beat
these.

The methodology behind every number is
[`planning/benchmark-methodology.md`](benchmark-methodology.md). Read it before
quoting anything below, because three of these figures mean less than they look
like they mean.

---

## 1. Environment

Recorded beside the numbers because a distribution without its environment is
not reproducible, and therefore is not evidence.

```text
odin        dev-2026-07a, commit 819fdc7
cpu         Intel(R) Core(TM) i7-8665U CPU @ 1.90GHz
cores       8
memory      24418264 kB
kernel      Linux 6.8.0-86-generic x86_64
build mode  debug (no -o:speed) — the mode the gate builds
tier        in-process dispatch via web.test_request; no socket
affinity    none pinned; the sweep alternates instead
protocol    n/a at this tier — no wire is involved
iterations  20,000 per run, after 2,000 discarded warm-up
repetitions 10, alternating (repetition outer, configuration inner)
```

---

## 2. Dispatch latency, median of ten repetitions

Nanoseconds per `web.test_request`, against the **linear route table Phase 2
shipped**. Median across the ten repetitions of each configuration's own p50 and
p95.

| Routes | Shape | median p50 (ns) | median p95 (ns) |
|---:|---|---:|---:|
| 5 | All_Static | 1,820 | 3,387 |
| 5 | All_Param | 1,922 | 3,432 |
| 5 | Mixed | 1,801 | 3,295 |
| 50 | All_Static | 8,875 | 19,899 |
| 50 | All_Param | 9,530 | 20,871 |
| 50 | Mixed | 8,811 | 20,645 |
| 500 | All_Static | 79,573 | 180,557 |
| 500 | All_Param | 86,227 | 183,431 |
| 500 | Mixed | 79,489 | 181,097 |
| 5,000 | All_Static | 826,228 | 1,783,046 |
| 5,000 | All_Param | 899,445 | 1,867,831 |
| 5,000 | Mixed | 883,258 | 1,916,286 |

### What this shows, stated plainly

**The scan is linear, and the sweep is wide enough to see it.** Ten times the
routes costs about ten times the time, at every step: 1.8 µs → 8.9 µs → 79.5 µs
→ 826 µs. The marginal cost is roughly **165 ns per registered route**, and it
does not improve with cardinality.

That is not a defect. `web/dispatch_table.odin` says so in its own comment —
the flat array is an interim representation and "Phase 3 replaces this table
wholesale without any public change". WP26's job was to put a number on it
before anyone argues about representations, and the number is now on it.

**Shape barely matters at this representation**, which is itself informative:
`All_Param` costs 3–8% more than `All_Static` and the difference does not grow
with cardinality. A linear scan pays for the scan, not for what it finds. WP28's
candidates will not have that property, which is precisely why the shootout
measures all three shapes rather than one.

**This is the debug build.** The gate builds debug, so this is the mode that
gets regression-checked. A `-o:speed` baseline would be a different document,
and mixing the two in one table is how a benchmark starts lying.

---

## 3. The derived tolerance — and the finding inside it

The rule, from WP26: run the unchanged baseline at least ten times in
alternating order and take the observed **p95 spread** as the tolerance floor. A
later change is a regression only when it exceeds that floor. The number comes
from the machine, and is re-derived rather than inherited when the hardware
changes.

Spread in basis points (1 bp = 0.01%) of each configuration's smallest observed
p95:

| Routes | Shape | p95 min (ns) | p95 max (ns) | spread (bp) |
|---:|---|---:|---:|---:|
| 5 | All_Static | 3,101 | 4,464 | 4,395 |
| 5 | All_Param | 2,463 | 3,774 | **5,322** |
| 5 | Mixed | 2,429 | 3,829 | **5,763** |
| 50 | All_Static | 16,698 | 21,258 | 2,730 |
| 50 | All_Param | 19,225 | 23,157 | 2,045 |
| 50 | Mixed | 18,911 | 22,925 | 2,122 |
| 500 | All_Static | 162,582 | 191,579 | 1,783 |
| 500 | All_Param | 176,477 | 206,125 | 1,679 |
| 500 | Mixed | 167,971 | 190,215 | 1,324 |
| 5,000 | All_Static | 1,646,044 | 1,986,129 | 2,066 |
| 5,000 | All_Param | 1,741,075 | 1,986,635 | 1,410 |
| 5,000 | Mixed | 1,784,027 | 2,016,330 | 1,302 |

```text
TOLERANCE_FLOOR_BP 5763
```

### FINDING-E — timing on this machine cannot see a small win

**The derived floor is 5,763 basis points. That is ±57.6%.** Even the calmest
configuration, 500 routes Mixed, spreads 13.2% across ten repetitions of
*identical code*.

The consequence is not a footnote and should not be softened into one:

* **A timing-based regression gate is not available at Phase-2 cardinalities.**
  A change would have to make dispatch more than half again as slow before this
  machine could distinguish it from the noise of running the same binary twice.
* **Small route counts are the worst case, not the best.** At 5 routes the whole
  operation is ~2 µs, so scheduler jitter and cache state dominate. Noise falls
  as cardinality rises — 5,763 bp at 5 routes, 1,302 bp at 5,000 — because the
  work grows while the jitter does not.
* **WP28 must therefore not be decided on small-cardinality timings.** A
  candidate that "wins" at 5 routes by 20% has won nothing. The cardinalities
  where this instrument can actually discriminate are 500 and 5,000, and the
  shootout's conclusions have to come from there or be stated as undecided.
* **This is why the gate asserts allocations instead.** An allocation count
  distinguishes 68 from 69 with certainty on any machine; a timing here cannot
  distinguish 100% from 158%. `tests/wp26-bench` asserts no timing at all, and
  that is a consequence of this measurement rather than a shortcut around it.

FINDING-A predicted the shape of this — a nondeterministic linker means
nondeterministic code layout, and layout moves branch prediction and cache
behaviour. What FINDING-A did not supply was the magnitude. Now it is measured,
and it is larger than the plan assumed.

---

## 4. Allocation baseline

Measured by `tests/wp26-bench`, with the tracker installed **before** the App
exists so that the App's own captured allocator is the tracked one.

| Quantity | Value |
|---|---|
| Registration, 32 routes, Mixed | 168 allocations |
| Dispatch, 64 iterations | 68 allocations |
| Dispatch, 128 iterations | 133 allocations |
| Repeat of the 64-iteration run | 68 allocations, exactly |

**Perimeter, because the capacity ledger requires one.** This measures
`web.test_request`, which includes the test transport and the response recorder.
It is **not** the perimeter of Phase-2 claim **C-5**, which measured zero
allocations around `driver_run`/`driver_cleanup` and explicitly *not* around
`test_request`. Nothing here widens C-5, and no number in this section may be
quoted as if it did.

**`context.temp_allocator` is not tracked.** A probe measured zero temp
allocations on this path, so tracking it adds nothing — and wrapping the temp
allocator underneath the `odin test` runner's own memory tracking hangs the
runner, which is recorded here so the next person does not spend an afternoon
rediscovering it.

**What is asserted, and what is refused.** No threshold was invented. The gate
asserts three properties — registration cost is independent of the iteration
count, dispatch cost scales with dispatches, and identical input yields an
identical count — and records the counts here. A "must stay under N allocations"
assertion would be a number chosen by taste, and this document does not contain
one.

The third property is the load-bearing one. Every allocation assertion in this
repository rests on the allocator being deterministic; if that ever goes flaky,
they are all worth less than they appear, and that is a finding rather than a
retry.

---

## 5. What WP26 did NOT measure

Named, because a baseline that quietly omits a dimension invites someone to
assume it was covered.

* **Anything over a socket.** No protocol version, no keep-alive setting, no
  concurrency level, no connection handling. RG-1 lists all four, and this
  baseline covers none of them. The reasoning is in the methodology document
  §Tiers: the socket adds scheduler and kernel noise measured in microseconds,
  and the difference between two route representations is measured in
  nanoseconds — an end-to-end benchmark cannot see what WP28 must decide. **A
  socket tier is still owed**, and it belongs with WP36's timeouts, where there
  is something to configure and therefore something to measure.
* **Peak and retained memory.** RG-1 lists both. Neither is here: the
  allocation *count* is instrumented, the resident set is not.
* **Throughput.** No requests-per-second figure appears anywhere in this
  document, deliberately. At this tier there is no server, no connection and no
  concurrency, so a throughput number would be an invented reciprocal of a
  latency — the exact shape of a figure that looks like a measurement and is not.
* **`-o:speed`.** Debug only, as stated.

---

## 6. Reproducing this

```bash
bash build/check_wp26_bench.sh > /tmp/wp26-baseline.txt
```

Roughly fifteen minutes, dominated by the 5,000-route configurations — which is
itself a data point about the current representation.

The script re-verifies the toolchain pin before measuring, refuses to emit a
baseline if any run was unverified, and refuses to emit one if the tolerance
could not be derived. It measures and decides nothing.
