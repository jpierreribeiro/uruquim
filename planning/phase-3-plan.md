# Phase 3 — Performance core: work package plan

**Status: DRAFT FOR HUMAN REVIEW.** Nothing here is frozen. Every signature is
marked **PROPOSED**. Phase 2 froze 44 application + 2 test-support = 46
(`planning/phase-2-freeze.md`); this plan proposes how that grows and demands
evidence for each increment.

Work packages continue the numbering: **WP26 – WP38**, mapping onto the
`P3-1 … P3-13` slots reserved in `planning/later-phases-plan.md`.

The theme is stated in one line, because it constrains every decision below:
**make it stay fast as route count and traffic grow, and let operators bound
it — with representation decisions conditioned on measurement, never on
folklore.**

---

## 0. Four findings that reshape this plan before any work package starts

All four are measured facts from Phase 2, not recollections. Three of them
invalidate something the skeleton plan in `later-phases-plan.md` assumed.

### FINDING-A — the toolchain does not build reproducibly, and RG-1 must survive that

Five builds of an **identical, unmodified** source tree produced five different
binaries: 876,304 / 876,352 / 876,352 / 876,368 / 876,360 bytes, five distinct
md5 sums. The vendored `nbio` emits polymorphic instantiations whose mangled
parameter names vary between runs.

**Consequences for Phase 3, which is the phase that lives on measurement:**

* **Binary size has a ~100-byte noise floor.** Any regression check on binary
  size must state that floor and treat smaller deltas as "no measurable
  change". A gate that fails on a 40-byte "regression" would fail randomly.
* **Byte-identity is never a valid assertion** (WP22 Amendment 1). Where a
  work package wants to say "unchanged", it asserts a symbol count, an
  allocation count, or a behavioural equivalence — never a hash.
* **Timing needs far more than this.** If the *linker* is nondeterministic,
  code layout is too, and layout moves branch prediction and cache behaviour.
  RG-1's methodology must therefore include repeated alternating runs and
  report a distribution, not a number. A single "X is 8% faster" measurement
  taken once is not evidence and must not be accepted by the gate.

### FINDING-B — the framework cannot import a clock, and Phase 3 needs one twice

WP6 measured `core:log` at **~37 KiB added to every application**, referenced
or not, because Odin links an imported package regardless of use. That measured
rule is why `web/logger.odin` imports nothing, why `web.logger` has **no latency
field**, and why WP23's request-ID generator seeds from ASLR addresses instead
of `base:intrinsics` or `core:time`. `build/phase1-direct-dependencies.txt`
pins `web`'s direct imports at five and the freeze gate enforces it.

Phase 3 needs a clock in two places, and they are **not** the same problem:

* **The benchmark harness (WP26)** needs timing. It must live **outside**
  `package web` — in `tests/` or a separate benchmark package — so no
  application ever links it. This is not a preference; importing `core:time`
  into `web` to benchmark it would change the thing being benchmarked.
* **Timeouts (WP36)** need a clock **on the serving path**. But that path is
  `web/internal/transport`, which already imports `core:net` — so the cost
  question there is entirely different from the cost question in `web`, and it
  must be measured rather than assumed either way. **A work package that adds
  a `core:time` import to `web` itself needs owner approval and a measured
  justification.**

The skeleton plan did not distinguish these two. It must.

### FINDING-C — Phase 2 froze CLAIMS, so Phase 3's gate obligations are larger

`planning/phase-2-freeze.md` added three ledgers that Phase 1 did not have, and
`build/check_phase2_freeze.sh` enforces them. Every Phase-3 work package
inherits obligations no Phase-2 work package had:

* **The capacity ledger becomes wrong the moment limits are configurable.**
  Today it says the body limit is "**4 MiB**, fixed, not configurable until
  Phase 3". WP36 changes that row, and it must change it **in the same commit**
  or the freeze gate is telling a lie about the shipped code.
* **Any new strong claim needs a negative control**, in the claim ledger,
  before it can be made in prose. "The new router is faster" is a claim. So is
  "reuse does not retain a giant buffer".
* **"Bounded" stays a gated word.** WP36 makes limits configurable; it does
  **not** make the server bounded. Connections, backlog and header counts
  remain the transport's, and the gate rejects any document that says
  otherwise.

**The six-file ledger ritual still applies**, unchanged, to every work package
that adds a symbol: `check_public_api.sh`, `check_phase1_freeze.sh`,
`phase1-public-signatures.txt`, `planning/phase-1-freeze.md`, `check_docs.sh`
plus `docs/ai-context.md`, and `CHANGELOG.md` — in ONE change, or the gate
fails with a misleading cause.

### FINDING-E — the timing noise floor is ±57.6%, and WP28 must plan around it

**Added by WP26, 2026-07-20.** FINDING-A predicted the shape of this; it did not
supply the magnitude, and the magnitude is worse than this plan assumed.

Ten alternating repetitions of the **unchanged** Phase-2 dispatch path gave a
derived p95 spread of **5,763 basis points — ±57.6%** at 5 routes. The full
table is in [`planning/phase-2-baseline.md`](phase-2-baseline.md).

Consequences, none of them optional:

* **No timing-based regression gate is available at small cardinalities.** A
  change would have to make dispatch more than half again as slow before this
  machine could distinguish it from running the same binary twice. `WP26`'s gate
  step therefore asserts **allocations and instrument soundness, and no timing
  at all** — a consequence of the measurement, not a shortcut around it.
* **Noise falls as cardinality rises**: 5,763 bp at 5 routes, 1,302 bp at
  5,000, because the work grows while the jitter does not.
* **WP28 may not be decided on 5- or 50-route timings.** A candidate that wins
  at 5 routes by 20% has won nothing measurable. The cardinalities where this
  instrument discriminates are **500 and 5,000**, and the shootout's conclusions
  must come from there or be recorded as undecided. That is a stopping rule, and
  it is now derived from data rather than asserted.
* **The Phase-2 scan is linear and now has a number**: ~165 ns per registered
  route, 1.8 µs at 5 routes rising to 826 µs at 5,000. WP28's candidates have
  something concrete to beat.

### FINDING-D — the concept budget is now a measured number, and Phase 3 spends it

WP25 re-ran the usage laboratory:

| Program | Concepts |
|---|---|
| five-route CRUD, unguarded | **14** (unchanged since Phase 1) |
| the same, with middleware, router, auth, logging, request IDs | **23** |

The skeleton plan's own words: *"if a five-route CRUD service now needs 25
concepts instead of 14, that is a finding, not a footnote."* At 23, Phase 3
starts with **two concepts of headroom** before that sentence becomes true of
this project.

Three Phase-3 work packages propose public surface (WP34 route identity, WP36
limits, WP37 typed state).

**The budget is stated in CONCEPTS, not symbols, because they are not the same
unit** — an earlier draft of this plan conflated them. The usage lab counts
`web.*` names that appear *in a program*. A metrics accessor (WP34) costs a
symbol and very likely **zero** concepts, because a CRUD service never calls it;
a limits struct taken at its defaults (WP36) does the same. A symbol budget
would block a change that costs a reader nothing and wave through one that costs
three.

**So: the guarded lab program may reach at most 25 concepts, and WP38 measures
it with the instrument that produced 23.** Symbol growth stays governed by what
already governs it — G-01 (one name per operation) and G-09 (growth carries
evidence), per symbol, as in every phase so far. If the guarded number passes
25, the freeze says so in those words rather than quietly printing a longer
table.

---

## 1. Entry conditions (not work packages)

| ID | Item | Status |
|---|---|---|
| E-1 | Phase 2 frozen — ledger 46, `check_phase2_freeze.sh` green | ✅ met (`planning/phase-2-freeze.md`) |
| E-2 | The full gate exits 0 on `main` | ✅ verified after the Phase-2 merges |
| E-3 | A benchmark harness exists | ✅ **met by WP26** — `tests/support/bench`, gate step, `planning/benchmark-methodology.md`, `planning/phase-2-baseline.md` |

E-3 is the real gate. The skeleton lists "a benchmark harness exists" as an
entry condition *and* as P3-1; it is a work package, and treating it as a
prerequisite that someone else supplies is how a phase starts choosing
representations before it can measure them.

---

## 2. Work package sequence

| WP | P3 | Name | Type | Owner approval |
|---|---|---|---|---|
| 26 | P3-1 | Benchmark harness and Phase-2 baseline | TESTS | no |
| 27 | P3-3a | Allocation audit (A-8, A-12, A-13) | PROTOTYPE | no |
| 28 | P3-2 | Route representation shootout | PROTOTYPE | no — **but must not choose before measuring** |
| 29 | P3-3 | Router implementation | IMPLEMENTATION | no (internal only) |
| 30 | P3-4 | Registration conflict diagnostics | SPEC + IMPLEMENTATION | **yes** if it changes registration behaviour |
| **31a** | P3-5 | Path normalisation — **the policy** | SPEC | **yes** — observable HTTP semantics |
| **32a** | P3-6 | HEAD, OPTIONS, 501 — **the decision** | SPEC | **yes** — observable HTTP semantics |
| 31b | P3-5 | Path normalisation — implementation | IMPLEMENTATION | covered by 31a |
| 32b | P3-6 | HEAD, OPTIONS, 501 — implementation | IMPLEMENTATION | covered by 32a |
| 33 | P3-7 | Multi-param routes without a map | IMPLEMENTATION | no |
| 34 | P3-9 | Route identity accessor | SPEC + IMPLEMENTATION | **yes** — public surface |
| 35 | P3-10 | Arena, buffer reuse and oversize policy | IMPLEMENTATION | no |
| 36 | P3-11 | Configurable limits and timeouts | SPEC + IMPLEMENTATION | **yes** — public surface + capacity ledger |
| 37 | P3-12 | Typed application state, and the request-scope question | PROTOTYPE + IMPLEMENTATION | **yes** — public surface |
| 38 | P3-13 | Phase-3 freeze | FREEZE | **yes** |

**Dependencies:** 26 → {27, **31a**, **32a**}; {27, 31a, 32a} → 28 → 29;
29 → {30, 31b, 32b, 33}; 26 → 35; {26, 35} → 36; 34 and 37 are independent of
the router work and may run in parallel; all → 38.

**Note the shape:** the first three work packages produce **no user-visible
feature at all**. That is deliberate and is the single most important structural
decision in this plan — a performance phase that starts by implementing is a
performance phase that has chosen its representation by taste.

**WHY 31a AND 32a COME BEFORE THE SHOOTOUT, and this is a correction to the
first draft of this plan.** Path normalisation decides which paths are *equal*,
and OPTIONS decides which methods the table must *answer*. Both change what the
router has to match. Running the shootout first and those decisions afterwards
gives two bad outcomes and no good one: either WP29 is rewritten once the
semantics arrive, or — quieter and worse — the semantics get silently
constrained by a representation chosen without knowing about them. That would be
a design decision made by scheduling accident. So the two **specs** run before
the shootout and the two **implementations** after the router exists; the
approval each needs attaches to the spec half, where the decision actually is.

Note also that P3-8 (precomputed chains) is **absent as its own work package**;
see §4.

---

## 3. The work packages

### WP26 — Benchmark harness and Phase-2 baseline

**Type: TESTS.** Nothing else in Phase 3 may start first.

* **Public surface. None.** The harness lives outside `package web`
  (FINDING-B): an application must never link a clock because the framework
  benchmarks itself.
* **Objective.** A methodology, in the gate, plus a recorded Phase-2 baseline
  to regress against.
* **What the methodology must record**, per RG-1 and its 2026-07-20 amendment:
  hardware, warm-up, route distribution, concurrency levels, p50/p95/p99,
  allocation counts, binary size, build time, peak **and retained** memory,
  protocol version, keep-alive setting, alternating run order, core affinity
  and build mode.
* **Semantic equivalence is a GATE CONDITION, not advice.** Every candidate
  must answer the same protocol version and produce equivalent status, headers
  and body. This is a measured failure, not a hypothetical: a benchmark run was
  once thrown away entirely because the load generator spoke HTTP/1.0, the
  strict server rejected every request, and the tool cheerfully reported 100%
  non-2xx **as throughput**. A load generator that gets rejected still reports a
  number, and the number looks like a number.
* **FINDING-A applies directly.** Report distributions from repeated
  alternating runs, never a single figure. State the ~100-byte binary-size
  noise floor. A benchmark that cannot distinguish its own noise from a change
  is not a benchmark.
* **The tolerance is DERIVED, and here is the procedure** — an earlier draft
  said "measured, not chosen" without saying how, which is an instruction to
  pick a number and call it measured. Run the unchanged baseline **at least ten
  times, in alternating order**, and take the observed **p95 spread** as the
  tolerance floor. A later change counts as a regression only when it exceeds
  that floor. The number then comes from the machine rather than from taste, and
  it is re-derived — not inherited — whenever the hardware changes.
* **Completion criteria.** The harness runs from the gate; the Phase-2 baseline
  is committed as data; re-running on unchanged code reproduces the baseline
  within the derived tolerance above.
* **Out of scope.** Choosing anything. This work package produces numbers.

### WP27 — Allocation audit

**Type: PROTOTYPE.** RG-3.

* **Public surface. None.**
* **Objective.** Where does per-request allocation actually go? A measured list
  and a decision per item.
* **Known candidates, already named by the audit:** **A-8** (inbound headers
  materialised per request — WP19 made them *read*, but nothing measured
  whether the materialisation is worth it), **A-12** (static header pairs
  cloned needlessly), **A-13** (`Header_Pair` ↔ `transport.Header` conversions).
* **The claim it must protect.** Claim C-5 in the Phase-2 freeze says *dispatch
  through a middleware chain allocates zero bytes*, measured around
  `driver_run`/`driver_cleanup` and explicitly **not** around `test_request`.
  Any change here must keep that measurement valid and must not quietly widen
  the perimeter the claim names.
* **Out of scope.** Fixing them. This work package measures and decides; the
  fixes land in WP29 and WP35 where they can be regression-tested.

**DONE, 2026-07-20 — `planning/allocation-audit.md`, measured by
`tests/wp27-internal` in the gate.** A typical JSON 200 costs five allocations
on the socket path; a 405 with a request ID costs nine. Three outcomes, and one
of them is a correction rather than a schedule:

* **A-12 as filed is WITHDRAWN.** "They are static strings, so the clone is
  waste" is false for two of the three headers this framework emits. `Allow` and
  `X-Request-Id` carry values living in `Context_Internal` buffers that die at
  `driver_cleanup`, and aliasing them would hand the transport a view into freed
  memory. What survives is narrower and certain: every response header *name* is
  a package constant, so cloning names is unambiguous waste — **1 allocation per
  header per request, owner WP29**. The values must keep being cloned.
* **A-8 is half wrong in the direction that matters.** One `temp_allocator`
  slice per request, and the strings are **views, not copies**. Also stale: "no
  Phase-1 path can read them" stopped being true when WP19 shipped
  `web.header`. Handed to **WP35**, because the fix is a fixed-capacity buffer
  question the arena policy owns.
* **A-13 is confirmed exactly as filed and is being kept.** Two allocations per
  request, no string copying — the price of ADR-009's one-way boundary, now a
  number instead of an adjective. Reclassified from "cost to remove" to "cost
  accepted, with a number".

**Consequence for the sequence: WP28 inherits nothing from this.** None of the
three sits on the route-matching path; all three are request/response edges. The
shootout is not blocked by any decision here.

### WP28 — Route representation shootout

**Type: PROTOTYPE.** RG-2. **It must not choose before measuring.**

* **Public surface. None.**
* **Five candidates, all measured on Uruquim's own workloads:** pointer-based
  radix, index-based radix, hybrid, improved linear, and **class-bucketed
  linear** (static / `:param` / wildcard buckets, linear scan inside the
  matching bucket).
* **Cardinality sweep: 5, 50, 500 and 5,000 routes.** The only property a tree
  uniquely owns is *scaling*, so the sweep must reach far enough for scaling to
  become visible, or the shootout cannot answer the question it exists to ask.
* **The WORKLOAD SHAPE is part of the measurement, and omitting it flatters the
  incumbent.** A linear scan's cost depends entirely on *where* the answer is,
  so a benchmark that only ever hits the first route measures nothing. Every
  candidate is measured against the same matrix: a hit at the **start**, the
  **middle** and the **end** of the table; a **miss** (which scans everything);
  and a **405** (which scans everything and then builds `Allow`). Route
  composition — the static / `:param` / wildcard proportions — is stated with
  the numbers, because a bucketed candidate's advantage is a function of exactly
  that ratio. See §6 — it is the difference
  between a shootout and a demo.
* **C-5 governs this work package** (`later-phases-plan.md`): the radix-router
  justification is not what folklore says. "A real, validated system does it
  this way" is not evidence about Uruquim's route cardinalities. Class-bucketed
  linear arrives with its own disclaimer — **it also scans linearly inside each
  bucket** — and is a hypothesis to measure, not a result to adopt.
* **The losing candidates and their numbers are RECORDED.** A shootout that
  publishes only the winner is a decision dressed as a measurement.
* **THE STOPPING RULE, stated before any number is collected so it cannot be
  chosen to fit the result:** *if no candidate beats the incumbent by more than
  the measured noise floor, at the cardinalities this project actually targets,
  **the incumbent wins**.* Given FINDING-A, that is a likely outcome at 5 and 50
  routes — which is what almost every real application has.
* **A no-op WP29 is a SUCCESS, not a wasted phase.** Without this said out loud,
  a work package named "router implementation" will produce a router
  implementation whether or not the data asked for one — which is C-5's warning
  arriving through a different door. The phase's job is to find out whether a
  change is warranted, and "it is not" is a finding worth the same as any other.
* **Deliverable.** A representation chosen from data, with the data — or a
  recorded decision to keep the current one, with the same data.

### WP29 — Router implementation

**Type: IMPLEMENTATION. Change classification: internal only.**

* **Public surface. None.**
* **The hard constraint:** every existing test produces a **byte-identical
  RESPONSE** — same status, same headers, same body — and those tests pass
  *unchanged and unmodified*. A test edited to accommodate a "performance"
  change is a behaviour change wearing a costume.
* **Read that word carefully:** byte-identical *responses* are testable and are
  required here. Byte-identical *binaries* are not a valid assertion anywhere in
  this project (FINDING-A). The two words look alike and mean different things;
  an implementation agent reads both in one sitting.
* **The pool invariant survives.** WP12 P8 measured a stored `[]Handler`
  dangling into `0xAAAAAAAAAAAAAAAA` the moment the pool reallocated, and P8b
  measured the same defect reading back *correctly* on the plain heap — a
  latent corruption. Index pairs are immune by construction. Any new
  representation must state, in its file comment, why it is immune or how it is
  protected.
* **Registration must stay fail-closed.** `append` in Odin does **not** panic
  when it cannot allocate: it returns `num_appended = 0`. WP18 Amendment 1
  fixed exactly this bug in `mount`. Every allocation on a registration path in
  the new representation checks its result and poisons the App on failure.
* **Mutation probes.** The existing WP17/WP18 probes must still pass — and if
  the representation changes the lines they anchor on, the probes are updated
  in the same change with their reasoning, never deleted.
* **Rollback.** HIGH while the change is internal-only: revert the commit and
  the old table returns, because no public signature and no observable
  behaviour moved. That is exactly why the "internal only" classification is
  worth defending — the moment a representation change drags an observable
  difference with it, this stops being revertible and becomes a behaviour
  change that applications may already depend on.

### WP30 — Registration conflict diagnostics

**Type: SPEC + IMPLEMENTATION.** Owner approval if registration behaviour
changes observably.

* Phase 1 deliberately does **not** diagnose a duplicate or conflicting
  registration (WP4 D5): a malformed pattern is stored, marked invalid, and
  never matches. Go panics at registration.
* **The decision to produce:** diagnose-and-poison (the ADR-019 mechanism
  already exists and is proven), diagnose-and-continue, or ratify the silence
  permanently. Fail-closed is this project's default and the burden is on any
  other answer.
* **Note the interaction with WP29:** a bucketed or tree representation makes
  some conflicts *structurally* detectable that a linear scan never noticed.
  Do not let a representation change silently become a behaviour change.

### WP31 — Path normalisation policy

**Type: SPEC + IMPLEMENTATION. Requires owner approval — observable HTTP
semantics.**

* Phase 1 normalises **nothing** on purpose: `/users` and `/users/` are
  different patterns, and percent-encoding and dot segments are not decoded.
* **This is a security decision, not an ergonomic one.** Path normalisation is
  where directory-traversal and route-confusion bugs live; every normalisation
  rule is an opportunity for two components to disagree about what a path
  means.
* **The output is a policy or a permanent ratification of its absence** — and
  either way it is written down, tested, and given a negative control.

### WP32 — HEAD, OPTIONS, and the 501 decision

**Type: SPEC + IMPLEMENTATION. Requires owner approval — observable HTTP
semantics.**

* **C-1: HEAD is effectively mandatory**, and 501 is a SHOULD that Uruquim
  currently declines. The vendored backend's HEAD handling is currently held
  under core control by a patch the wire corpus pins (`check_public_api.sh`).
* **The decision to produce:** automatic HEAD (respond as GET, suppress the
  body), automatic OPTIONS (built from the same `Allow` machinery a 405
  already uses), and whether an unknown method becomes 501 or stays outside the
  framework's vocabulary.
* **Interaction to respect:** the `Allow` value and its byte-exact order are
  ratified (WP4 D4) and pinned by the gate. OPTIONS reuses that machinery; it
  does not grow a second one.

### WP33 — Multi-param routes without a map

**Type: IMPLEMENTATION.**

* Phase 1 supports **at most one** `:param` per pattern; more marks the pattern
  invalid.
* **The convergent design, per C-6:** a small fixed inline array of views in
  request-local storage. Not a map, not an allocation, not a bag.
* **G-03 is the boundary.** This adds capacity to an existing private slot; it
  does not add a general-purpose keyed store, and `web.path` stays the one
  canonical accessor (G-01).
* **Capacity ledger row required:** the new fixed bound joins the "fixed at
  compile time" table, with its behaviour when full stated — like every other
  bound in that table.
* **Rollback.** MEDIUM. No symbol is added, but a pattern that was *invalid*
  becomes *valid*: applications will register two-param routes, and withdrawing
  the capacity silently turns those routes into 404s. Reversible only before
  anyone ships a two-param route.

### WP34 — Route identity accessor

**Type: SPEC + IMPLEMENTATION. Requires owner approval — public surface.**

* **C-2: observability is blocked on one missing accessor, and the constraint
  is a MUST.** OpenTelemetry requires `http.route` to be low-cardinality and
  MUST NOT be populated when the framework cannot supply it.
* The framework **already has** the value: `ctx.private.route` is the
  registered pattern, and `Framework_Event.route` already exposes it to
  observers. This work package is the smallest change that lets an
  *application* read it for its own metrics.
* **Public surface (PROPOSED): +1.** The name must not become a second way to
  ask a question `web.header` or the event already answers (G-01).
* **The redaction rule travels with it:** the pattern, never the path. The
  gate assertion that keeps `Framework_Event` free of request-derived strings
  has an obvious analogue here.

### WP35 — Arena, buffer reuse and oversize policy

**Type: IMPLEMENTATION.** RG-4, risk **R-16**.

* **The risk, stated as measured:** one adversarial request permanently raises
  process RSS across otherwise small traffic. Signals: retained capacity
  follows peak body size; memory does not return near baseline after a giant
  request.
* **The decision:** retain, trim, or release — **with numbers behind it**, and
  the fallback already named in the register (release oversize allocations at
  request end even if common-path buffers stay reusable).
* **This work package activates a Phase-2 test that has been waiting for it.**
  `wp23_public_an_id_never_leaks_into_the_next_request` currently passes
  *structurally* — `Context` is a fresh stack value per request, so the overlay
  starts zeroed and there is nothing to leak. WP35 is the work package that
  makes something be pooled. **That test is the tripwire**, and if it goes red
  here it has done its job; it must not be "fixed" by weakening it.
* **Peak and retained memory are reported, not only allocation counts** — the
  register asks for exactly this.
* **Rollback.** MEDIUM, and it decays. Reverting the reuse policy is a revert
  while the change is purely internal; but once something is pooled, any code
  written against the pooled lifetime — including a generational token, if one
  is introduced — has to come out with it. Keep the reuse and the token in one
  commit so they revert as one.
* **The stale-reference test comes with the reuse, and not before** (§6).
  The moment a slot is reused, a reference held from the previous request stops
  being merely stale and starts being *wrong*. The shape of the test is already
  written down: request A arms a timeout; the slot is released; request B
  reuses it; A's timeout fires; **B must survive**. A generational token is the
  known answer. The discipline attached to it matters as much as the mechanism:
  **while nothing is pooled, do not build the abstraction** — an empty
  generational wrapper around storage that is never reused is complexity with no
  defect to catch.

### WP36 — Configurable limits and timeouts

**Type: SPEC + IMPLEMENTATION. Requires owner approval — public surface and a
capacity-ledger amendment.**

* **The shape is already decided** by the P3-8/P3-11 amendment: an options
  struct with a package default constant, on `core:net`'s `DEFAULT_TCP_OPTIONS`
  precedent — **not** a builder.
* **But the derivation must still be MEASURED, not assumed** (§6). Compare
  the two shapes on real numbers — configuration consulted per request versus an
  immutable runtime derived once at boot — and report branch count, allocations,
  binary size and ergonomics. The amendment chose the second on reasoning; this
  work package is where that reasoning acquires evidence. And do not expose a
  large tuning struct before there is data to justify each field.
* **Validate once at boot, read on the hot path.** `serve` derives a private,
  immutable `Server_Runtime` holding resolved budgets — request line, header
  block, body, response bytes, timeouts, arena policy — with every cross-limit
  relationship checked once and **diagnosed at boot rather than at 3 a.m. under
  load**. Nothing on the request path re-interprets a limit or discovers a
  contradiction.
* **Keep it the smallest struct HTTP actually needs.** Do not import a general
  system-specification concept from a runtime that sizes shards, pools and
  rings; Uruquim sizes none of those.
* **FINDING-B applies:** timeouts need a clock on the serving path. That path
  is `web/internal/transport`, which already imports `core:net` — a different
  cost question from importing into `web`, and it must be **measured**.
* **FINDING-C applies:** the capacity ledger's "4 MiB, fixed, not configurable
  until Phase 3" row changes **in this commit**, and the claim ledger gains a
  row for whatever new promise the options make.
* **The word "bounded" is still gated.** Configurable limits bound the
  framework's own per-request working memory. They do not bound connections,
  backlog or header counts, and no document may say they do.
* **THIS WORK PACKAGE OWNS THE CONCURRENCY DECISION** (P3-8's other half, which
  an earlier draft of this plan left unassigned). The boot-time snapshot is
  taken here, so this is where it must be recorded whether registration *during
  serving* is **rejected** or **made impossible** — and the choice is written
  down rather than left to whichever happens to be true of the implementation.
  **Name the interaction with what already ships:** ADR-019 and ADR-023 already
  poison an App on `use()` after the first dispatch. A snapshot model either
  subsumes that guard or sits beside it, and the plan must say which; silently
  replacing a shipped fail-closed guarantee is the one outcome not available.
* **`test_request` must honour the same limits, and this work package owns
  that too.** R-10 parity is the property both transports exist to keep: if the
  body limit becomes configurable and the in-memory transport keeps a hard-coded
  4 MiB, then `test_request` answers 200 where a socket answers 413 — on exactly
  the kind of boundary a test suite is supposed to prove. The test-support
  ledger stays at 2; this is behaviour, not a new symbol.
* **Rollback. LOW — this is the least reversible package in the phase.** An
  options struct is a public type: once an application writes a limit, removing
  or renaming a field breaks its build, and *tightening a default* breaks its
  traffic. Ship the smallest struct that HTTP actually needs, because every
  field is a promise kept for as long as the type exists. Adding a field later
  is easy; that asymmetry is the whole argument for starting small.

### WP37 — Typed application state, and the request-scope question

**Type: PROTOTYPE + IMPLEMENTATION. Requires owner approval — public surface.**

**This work package must answer TWO questions that the skeleton plan conflated,
and one of them is currently being answered wrongly in shipped documentation.**

**Question 1 — application state (ADR-004, already accepted).** `web.state(ctx,
T)`: a `rawptr` + `typeid` on the `App`, with an asserted accessor. AMEND-1
applies — registration rejects nil, and access asserts registration plus exact
type before casting. This is for a database handle or configuration: **one
value, app-scoped, set before serving**.

**Question 2 — request-scoped typed state. UNDECIDED, and this plan does not
assume it.** It is a different feature with a different lifetime, and the
project's own research argues *against* it:

* **C-6** finds that Go's `context.WithValue` and Rust's `http::Extensions`
  exist for type-erased, dynamically-keyed state crossing library boundaries —
  which Uruquim does not have — and concludes that this **supports G-03 rather
  than challenging it**.
* **G-03** forbids the context extension bag outright.
* The honest consequence is that the canonical auth pattern's revalidation cost
  (WP24) may be **permanent**.

A G-08 correction has already been merged for this: the auth example, the
CHANGELOG and the Phase-2 freeze previously said Phase 3 *would* remove that
cost, which no ADR had decided. They now say the cost stands until an ADR says
otherwise, and `check_examples.sh` rejects a comment that schedules a future
capability.

**ADR-028 is now open for exactly this** (PROPOSED, 2026-07-20), with three
live options:

1. **No request-scoped state, permanently.** Ratify the revalidation cost and
   the pass-it-down workaround as the answer. Costs nothing, closes the
   question, and is what C-6 points at.
2. **A small fixed `[N]{typeid, rawptr}` array in request storage.** C-6's own
   fallback if extensibility is *genuinely* required — bounded, typed at
   access, no map, no allocation. Needs a capacity-ledger row and a very
   clear reason why the existing pattern is insufficient.
3. **A typed slot for exactly one application value**, mirroring the WP19/WP23
   overlay design (one slot, known capacity, one writer ratified per phase).

**Rollback.** Option 1 is HIGH — it ships nothing, so there is nothing to
withdraw, and adding a mechanism later is a pure strengthening. Options 2 and 3
are **LOW**: once an application stores a value per request, removing the slot
breaks it at compile time and no deprecation window helps. That asymmetry is
itself an argument, and it is the reason the recommendation falls where it does.

**ADR-028 recommends option 1** and places the burden of proof on the others.
The evidence for 2 or 3 must be a real program that cannot be written cleanly
today — never a hypothetical — and option 1 is the only reversible one:
adding a mechanism later is a pure strengthening, while shipping one and
withdrawing it breaks applications.

### WP38 — Phase-3 freeze

**Type: FREEZE. Requires owner approval.**

Everything WP25 required, plus what Phase 3 adds:

* Full ledger diff; signature snapshot refresh; **every** mutation suite re-run
  (Phase 2 ended with ten suites, all passing, each with a positive control).
* **The three ledgers amended, not appended:** the capacity ledger's fixed rows
  become configurable rows (WP36); the lifetime ledger gains any new borrowed
  value (WP33, WP34, WP37); the claim ledger gains a row per new promise **with
  a negative control**, because a claim without one does not freeze.
* **A performance regression benchmark in the gate**, with its tolerance stated
  and justified against FINDING-A's noise floor.
* **The usage laboratory re-run**, and FINDING-D's budget checked: if the
  guarded CRUD number passes 25 concepts, the freeze says so in those words.
* **`nm` measurements with positive controls** for every new "costs nothing
  when unused" claim.

---

## 4. What this plan deliberately does NOT include

* **P3-8 as its own work package.** "Precomputed middleware chains" is already
  what Phase 2 built: `chain_flatten` runs at registration, dispatch re-slices
  an App-owned pool through an index pair, and WP17 measured zero allocations,
  zero bytes, temp allocator untouched. The remaining half of the amendment —
  compiling the final table before serving and rejecting or preventing
  registration during serving — belongs to **WP29** (representation) and
  **WP36** (boot-time derivation), where it can be regression-tested. Listing
  it separately would create a work package whose deliverable already exists.
  **C-7 governs whatever is left:** post-`next` currently costs stack frames,
  not allocations, which is a genuine advantage over koa-compose and Axum's
  `from_fn` — and Phase 3 must not surrender it for a marginal gain.
* **A package-manager story.** C-8: Odin will never officially support one.
  `odin-version.txt` already pins a release, a commit and an asset SHA-256,
  which is stronger than anything surveyed in the ecosystem. Budget one to two
  core-library migrations per year instead.
* **Anything from Phase 4.** Graceful shutdown, trusted proxies and
  `X-Forwarded-*`, TLS, uploads, structured logging, sampling, and a stop
  procedure all stay where they are. If a Phase-3 work package finds it needs
  one of them, that is a finding to write down, not scope to absorb.

---

## 4b. A note on this plan's own review

Eight defects were found reviewing the first draft, and all eight are applied
above rather than left as commentary. Three changed the structure — the spec
halves of WP31/WP32 moved ahead of the shootout, the shootout gained a stopping
rule, and the concurrency decision gained an owner — and one, the shootout's
workload matrix, came from the external reference dossier (§6).

The rest were precision: the budget now counts concepts rather than symbols,
the benchmark tolerance has a procedure instead of an adjective, and every
implementation package carries **Rollback** again, which the Phase-2 template
had and the first draft of this one silently dropped.

Recorded because the reasoning is the reviewable part, and because a plan that
hides its own corrections teaches the next reader to hide theirs.

---

## 5. Risks this plan does not resolve

| Risk | Why it stays open |
|---|---|
| **R-16 retained giant buffer** | WP35 decides a policy, but the adversarial shape is only as good as the benchmark that models it. A hostile traffic pattern nobody thought to write is not covered by a passing test. |
| **Choosing a representation on a benchmark that flatters it** | WP28 records losing candidates and numbers, which makes a bad choice *visible*. It does not make it impossible. |
| **Timing nondeterminism (FINDING-A)** | Repeated alternating runs reduce it; they do not eliminate it. A 3% difference may never be trustworthy on this toolchain, and the freeze should say so rather than report it. |
| **Concept budget (FINDING-D)** | A budget is a constraint, not a mechanism. Only the freeze's re-run of the usage lab actually measures it, and by then the symbols are shipped. |
| **The request-scope question (WP37)** | Whichever way it goes, it is hard to reverse: adding the mechanism later is a pure strengthening, but shipping it and withdrawing it would break applications. Option 1 is the reversible one. |

---

## 6. The external reference dossier

Some environments supply a **reference dossier**: a close study of another
production runtime, written up out of band. Phase 2 already took four things
from it, and they were among the better decisions in that phase — the claim /
lifetime / capacity ledgers, the ownership table, the load-generator trap in
RG-1, and the rule that "bounded" must name a perimeter.

**Consult it for Phase 3 when it is available.** It is the densest source on
exactly the problems this phase has: measurement methodology, bounded pools,
backpressure, slot reuse and compiled configuration. A second implementation
that has already hit these walls is worth more than a fresh guess.

### The rule

* **It is REFERENCE, never architecture to copy.** "That system does it this
  way" is **never** a justification, in a commit message, an ADR or a code
  comment.
* **It is not a dependency and must never become one.**
* Take **discipline** — how a claim is evidenced, how a bound states what it
  does when full, how a benchmark avoids measuring its own error. Do **not**
  take structure: a concurrency runtime sizes shards, pools and rings, and
  Uruquim sizes none of those. Importing a general system-specification concept
  would be cargo-culting a solution to a problem this framework does not have.
* Its ideas enter the shootout as **hypotheses, with no head start**. The
  bucketed representation it favours also scans linearly inside each bucket;
  authority is not evidence about Uruquim's route cardinalities.

### It stays OUT of the repository — owner decision, 2026-07-20

The dossier is **deliberately never committed**. It is supplied in the working
environment of whoever is doing the work.

Three consequences, and they are requirements rather than observations:

* **No gate may check for it, ever.** A gate that did would fail on every clean
  clone and in CI.
* **No work package may block on it.** If it is not there, proceed —
  everything load-bearing has already been absorbed into this plan, the ADRs
  and the gate, which is why the list below records what was absorbed instead
  of sending you to find it again.
* **Nothing may cite it as evidence.** A freeze citation must resolve inside
  the repository; the Phase-1 and Phase-2 evidence matrices are checked that
  way and Phase 3's will be too. Read it for ideas, then prove the idea *here*,
  with a test and a negative control that live in this tree.

### What has already been absorbed

Recorded so nobody re-derives it, and so no work package needs the dossier to
proceed:

* **Into WP28** — the routing benchmark is specified by cardinality *and by
  workload shape*: hit at the start, middle and end; a miss; a 405; with the
  static / `:param` / wildcard proportions stated alongside the numbers. This is
  what exposed the eighth defect in this plan's own review.
* **Into WP36** — compiled limits are *measured*, not assumed: per-request
  lookup versus a boot-derived immutable runtime, compared on branch count,
  allocations, size and ergonomics. And no large tuning struct ships before
  there is data for each field.
* **Into WP35** — the stale-slot test arrives *with* the reuse and never before
  it: request A arms a timeout, the slot is freed, request B reuses it, A's
  timeout fires, **B must survive**. A generational token is the known answer,
  and while nothing is pooled, the abstraction is not built.
* **Deferred to Phase 4** — a deterministic transport fault lab (seeded
  fragment sizes, failure at byte N, delayed completion, concurrent close,
  artificially small pool, final checker). Named here so the Phase-4 planner
  finds it rather than inventing it.

### Already rejected, and staying rejected

Settled, and not reopened by consulting the dossier again: recovering a panic
inside a handler (ADR-020 proved it impossible), making the studied system a
dependency, rewriting the HTTP server, and "zero allocation" as a slogan
without a perimeter and a test — which the claim ledger now enforces.

---

## 7. What an implementation agent should read first

1. This document, for the work package it is doing — **including §0**, because
   three of the four findings there contradict the older skeleton.
2. `planning/later-phases-plan.md` §Phase 3 — the research gates and the C-1…C-8
   findings, which remain authoritative for the questions they cover.
3. `planning/phase-2-freeze.md` — the three ledgers it will have to amend, and
   the nine claims it must not break.
4. `planning/public-api-guardrails.md` — G-01 through G-11 are not advice.
5. `planning/adrs.md` — an ACCEPTED ADR supersedes plan text when they
   disagree. That is what happened in WP21, and this plan is not exempt.
6. **The external reference dossier** (§6), when the environment supplies it.
   Reference, never architecture; it is never committed, never cited as
   evidence, and its absence is never a blocker.
7. **The code and tests of the work package before it.** Never conclude from
   documents alone: this project has now had two cases where the documentation
   described behaviour the code did not have, and one of them was introduced by
   the same agent that wrote the gate against it.
