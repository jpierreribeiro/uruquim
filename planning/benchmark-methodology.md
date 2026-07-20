# Benchmark methodology — WP26

**Status: THE METHODOLOGY RG-1 ASKED FOR.** It governs every performance number
Phase 3 produces. The numbers themselves live in
[`planning/phase-2-baseline.md`](phase-2-baseline.md).

RG-1's question was "what is the methodology?" — recorded hardware, warm-up,
route distribution, concurrency levels, p50/p95/p99, allocations, binary size,
build time, peak and retained memory, plus semantic equivalence. This document
answers it, and is explicit about the two items it does not yet cover.

---

## 1. Where the harness lives, and why it can never move

`tests/support/bench/` — a test-support package, outside `package web`.

This is not a preference. WP6 measured `core:log` at **~37 KiB added to every
application, referenced or not**, because Odin links an imported package whether
it is used or not. `core:time` would cost the same. A framework that imported a
clock in order to benchmark itself would have changed the thing it was
measuring, and every application would carry the cost forever.

`build/phase1-direct-dependencies.txt` pins `package web`'s five direct imports
and `check_phase1_freeze.sh` diffs the live set against it, so this is enforced
rather than remembered.

---

## 2. Tiers — and why the socket is not the first one

**Tier 1, in-process dispatch.** One `web.test_request` per sample: real
routing, real middleware chain, real response commit, no socket. This is what
WP26 built and what WP28 will decide on.

**Tier 2, end-to-end over a socket.** Protocol version, keep-alive, concurrency
levels. **Not built.**

The ordering is a measurement argument, not a scheduling convenience. The
difference between two route representations is measured in **nanoseconds**; a
loopback socket adds scheduler and kernel noise measured in **microseconds**. An
end-to-end benchmark would bury the signal WP28 exists to find under three
orders of magnitude of transport. Measuring the wrong thing precisely is still
measuring the wrong thing.

Tier 2 answers a different and real question, and it is still owed. It belongs
with **WP36**, where configurable limits and timeouts give it something to vary
and therefore something to measure.

---

## 3. What every measurement must record

Beside the numbers, never in a commit message: toolchain release and commit,
CPU model, core count, memory, kernel, build mode, tier, core affinity,
iterations, warm-up count, repetitions, and — at tier 2 — protocol version and
keep-alive setting.

A distribution without its environment cannot be reproduced, and an
unreproducible number is an anecdote with decimal places.

---

## 4. Warm-up

A fixed count of iterations runs first and is discarded (2,000 before 20,000 in
the current baseline).

Not superstition: the first dispatch through a cold table pays for page faults
and branch-predictor training that no steady-state request pays again. Including
it puts a one-off cost into the p99 of every run.

**The warm-up is verified too.** A table that answered 404 would otherwise warm
up the miss path and then be measured on it.

---

## 5. Route distribution

Two axes, both required.

**Cardinality: 5, 50, 500, 5,000.** RG-2's sweep. The only property a tree
representation uniquely owns is *scaling*, so a sweep that stops early cannot
answer the question the shootout exists to ask.

**Shape: `All_Static`, `All_Param`, `Mixed`.** Representations differ mainly in
how they treat the static/parametric distinction, and a structure that wins on
all-static tables can lose badly on mixed ones. In `Mixed` the two kinds
alternate rather than being blocked, so a linear scan cannot short-circuit on a
static prefix and skip the rest.

**The sweep hits every route.** `planning/phase-3-plan.md` names the failure
directly: a routing benchmark must not "only ever hit the first route". A linear
scan flatters itself spectacularly when every request matches at index 0, and
the flattery survives into a representation decision. Paths are generated
alongside patterns, cover the whole table, and are walked round-robin.

---

## 6. Reporting — distributions, never a figure

Every timing is reported as **n, min, p50, p95, p99, max**.

There is no mean, deliberately: a mean hides the tail, and the tail is the whole
question for a request pipeline. p99 is what an operator feels.

Percentiles use **nearest-rank**, so every reported value is one the machine
actually observed. An interpolated p99 is a number that never happened, and this
project does not report those.

FINDING-A is why single figures are banned: five builds of an identical source
tree produced five different binaries, because the vendored `nbio` emits
polymorphic instantiations whose mangled parameter names vary between runs. A
nondeterministic linker means nondeterministic code layout, and layout moves
branch prediction and cache behaviour. **A single "X is 8% faster" reading on
this toolchain is not evidence.**

---

## 7. Alternating order

The outer loop is the repetition; the inner loop is the configuration.

Running all repetitions of one configuration back-to-back would let it keep a
warm cache and a trained branch predictor for its whole block, then hand the
next configuration a cold one. The measured difference would be the order.

---

## 8. The tolerance is derived, not chosen

Run the unchanged baseline **at least ten times in alternating order**, and take
the observed **p95 spread** as the tolerance floor. A later change counts as a
regression only when it exceeds that floor.

The number therefore comes from the machine, and is **re-derived rather than
inherited** whenever the hardware changes. An earlier draft of the phase plan
said the tolerance was "measured, not chosen" without saying how, which in
practice is an instruction to pick a number and call it measured.

Spread is expressed in **basis points** rather than nanoseconds so the floor
survives a move to a faster machine, where every absolute figure changes and the
relative noise largely does not.

**The measured floor is 5,763 bp — ±57.6%.** That is FINDING-E, and its
consequences are set out in the baseline document: a timing-based regression
gate is not available at small cardinalities on this machine, and WP28 may not
be decided on 5-route timings.

---

## 9. Semantic equivalence is a gate condition

**Every candidate must do the same work, and every response must be verified.**
Not sampled — every one.

This is a measured failure rather than pedantry. A reference study threw away an
entire ApacheBench comparison because `ab` speaks HTTP/1.0, the strict HTTP/1.1
server rejected every request, and the tool cheerfully reported **100% non-2xx
as throughput**. A load generator that gets rejected still reports a number, and
the number looks like a number.

`dispatch_run` therefore checks the status of every response and refuses to
return a usable timing if even one differs. The runner exits non-zero and emits
no baseline. A run that measured the miss path is not a slow run; it is not a
run at all.

**And the verification is proven able to fail.** `tests/wp26-bench` corrupts a
workload with a path nothing matches and asserts the run comes back unverified.
Without that control, `verified == true` would be true of everything — including
a benchmark of a server answering 404 to every request.

---

## 10. Binary size and build time

Both are **reported, never asserted**.

FINDING-A measured a **~100-byte binary-size noise floor** on this toolchain. A
gate that failed on a 40-byte "regression" would fail randomly. And byte-identity
is never a valid assertion anywhere in this repository — where a work package
wants to say "unchanged", it asserts a symbol count, an allocation count, or a
behavioural equivalence, never a hash.

---

## 11. Allocation — the one quantity with no noise

Allocation counts are exact, deterministic and machine-independent. They are
therefore where the *gate's* regression assertion lives, while timing lives in a
recorded baseline.

The tracker must be installed **before the App exists**. The App captures an
allocator at registration and keeps using it; a tracker installed afterwards
sees none of the App's own work, and the measurement would silently be of
something else.

Every allocation figure must state its **perimeter**. The WP26 numbers measure
`web.test_request`, including the test transport and recorder — which is *not*
the perimeter of Phase-2 claim C-5. A measurement that quietly widens a frozen
claim's perimeter is worse than no measurement, because the claim keeps its
wording and loses its meaning.

---

## 12. What this methodology does not yet cover

Named rather than implied:

* **Peak and retained memory.** RG-1 lists both. Allocation *count* is
  instrumented; resident set is not.
* **Concurrency, keep-alive and protocol version.** Tier 2, unbuilt.
* **Throughput.** No requests-per-second figure is produced at tier 1, because
  there is no server and no concurrency — a throughput number there would be an
  invented reciprocal of a latency.
* **`-o:speed`.** Debug only, matching what the gate builds.

Each is a gap with an owner, not an oversight.
