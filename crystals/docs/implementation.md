# Implementation plan — CE0 to CE2

**Status: DRAFT FOR HUMAN REVIEW. Nothing here is approved and no work package
is started.** Work packages are numbered `CE-n` (Crystal Ecosystem) so they
never collide with the core's `WP-n`, which continue at WP26.

The theme, in one line: **prove the idea with the smallest artifact that can
disprove it, and require zero commits to the core repository while doing it.**

---

## Entry conditions

These are not work packages. If they are not true, the plan does not start.

| # | Condition | Status today |
|---|---|---|
| CE-E1 | The core's Phase-2 surface is frozen and gate-enforced | **met** — 44 + 2 = 46, `check_phase2_freeze.sh` |
| CE-E2 | The owner has read [`crystal-contract.md`](crystal-contract.md) and [`first-crystal.md`](first-crystal.md) and accepted or amended ADR-C001…C005 | **not met** |
| CE-E3 | It is agreed that no work package here may add, widen or change a core symbol | **not met — needs an explicit yes** |
| CE-E4 | A decision on whether ecosystem work may proceed before Phase 3, given that `roadmap.md` places it in Phase 5 | **not met** — see [`roadmap.md`](roadmap.md) §Sequencing honesty |

**CE-E3 is the one that matters.** It is the difference between an ecosystem and
a back door into a frozen framework, and it should be said out loud before any
code exists rather than discovered in review.

---

## CE0 — The contract, and nothing else

**Type: DOCUMENTATION. No code.**

**Deliverable.** The documents in this directory, reviewed and amended until the
owner would be willing to hand them to someone else as instructions.

**Why it is a work package rather than a preamble.** Every ecosystem that grew
its rules after its packages ended up with rules that describe what the packages
already did. The contract is cheap now and expensive later.

**Exit criteria.**

1. ADR-C001 through C005 accepted, amended or rejected — each with a reason
   recorded, including the rejections.
2. ADR-C006 explicitly deferred to the core's WP37, not silently pending.
3. The five categories survive an attempt to classify all fifteen candidates in
   [`ideas.md`](ideas.md). A candidate that fits nowhere, or in two places, is a
   finding about the taxonomy.
4. `first-crystal.md`'s success and failure criteria accepted *before* any code,
   so the experiment cannot be graded on a curve afterwards.

**Rollback.** Total. It is documentation in a directory nothing imports.

---

## CE1 — `crystals:dev/watch`, and the machinery it forces into existence

**Type: PROTOTYPE. Requires owner approval — it creates a repository.**

**Deliverable.** A Tool Crystal: a separate executable that watches source
directories, debounces, runs the real `odin build` with the project's own
collection flags, keeps the previous process alive on a failed build, and
restarts the server on a successful one.

**What is actually under test.** Not the watcher. The *machinery*: a second
repository, a collection root, a `CRYSTAL.md`, a compatibility matrix, a gate,
and whether a person other than the author can build a sample project from a
clean checkout using two `-collection:` flags and a set of pinned SHAs.

**Why this one.** Its blast radius on the core is structurally none — it never
imports `uruquim:web` and is not in the server process. See
[`first-crystal.md`](first-crystal.md) for the full argument.

**Controls.**

1. The Crystals repository builds on the pinned toolchain, verified against
   `odin-version.txt` the same way the core verifies it.
2. A public-symbol inventory derived from the compiler, pinned to a file, diffed
   by the gate. Hand-maintained lists are rejected.
3. A direct-import inventory, pinned and diffed.
4. A sample project consumes the Crystal via `-collection:crystals=…` and
   compiles in the gate.
5. `CRYSTAL.md` exists and answers ownership, capacity, threading, failure and
   teardown — including the child process, its file descriptors and its signals.
6. **The termination limitation is stated, not glossed:** the core has no
   graceful shutdown before Phase 4, so a restart cuts in-flight requests with
   no deadline. A `CRYSTAL.md` that omits this fails the control.
7. The debounce window has a stated number and a stated behaviour when events
   arrive during a build — queue, coalesce or drop, named explicitly.
8. A failed build leaves the previous server **serving**, proven by a test that
   introduces a syntax error and asserts the old process still answers.

**Non-goals, recorded so they are not absorbed.** No `core:dynlib` reload. No
config file format. No project scaffolding. No test running. No log
prettification. Each is a separate Crystal or nothing.

**Rollback.** HIGH — delete a repository nothing in the core references.

**Findings expected, and to be written down rather than worked around.** How
much of a gate survives being written for a package with no HTTP surface; what
`CRYSTAL.md` sections turn out to be dead weight for a Tool; and how badly the
missing `web.stop` actually hurts in daily use, which is the evidence Phase 4
will want.

---

## CE2 — `crystals:web/health`, the first coupled Crystal

**Type: PROTOTYPE. Requires owner approval — it imports the frozen surface.**

**Deliverable.** A Route Crystal exporting `routes :: proc() -> web.Router`,
which registers a liveness route and optionally a readiness route, with its own
middleware scope, and never touches the application's `App`.

**What is under test.** The coupling half of the contract, which CE1 leaves
entirely unproven — specifically ADR-C003's claim that returning a detached
`Router` is safer than mutating the `App`.

**Controls.**

1. No import of `uruquim:web/internal/*`; asserted textually by the gate.
2. No textual access to `.private`; asserted textually, with the acknowledgement
   from [`gate.md`](gate.md) that grep catches accidents, not determined authors
   (**G-10**).
3. Behaviour tested entirely through `web.test_request` — no socket.
4. Per-request allocations measured and stated. If the claim is zero, it is
   measured; if it is not zero, the number is published.
5. **The ordering property is proven, not asserted:** a test in which the
   application registers its own routes *before* mounting the Crystal's router,
   and another in which it mounts first — both must serve correctly. Any
   ordering in which the Crystal alone poisons the application is a defect in
   ADR-C003, and the finding outranks the Crystal.
6. A `Recorded_Response` lifetime test: the response is valid only until the
   next `test_request`, so anything kept is copied.
7. If a "costs nothing when unused" claim is made at all, it uses the `nm`
   method **with its positive control**. If nobody wants to do that work, the
   claim is not made. Both outcomes are acceptable; an unmeasured claim is not.

**Rollback.** HIGH.

**Findings expected.** Whether the Router-returning shape is actually pleasant
to write and to call, or whether it reads as ceremony for two routes — and
whether the compatibility matrix catches a real drift when the core moves,
which it should during Phase 3.

---

## The review gate before anything becomes "official"

After CE1 and CE2, and before a third Crystal, a written assessment against the
criteria already fixed in [`first-crystal.md`](first-crystal.md):

* Did the core repository take **zero** commits caused by the ecosystem?
* Did two Crystals coexist without an ordering rule nobody had written down?
* Did the gate survive duplication, or did it drift within two Crystals — which
  would mean `dev/ledger` is needed earlier than [`ideas.md`](ideas.md) argues?
* Is any `CRYSTAL.md` longer than the Crystal, and does anyone read it?

**A negative answer is a result, not a failure.** The cheapest possible outcome
of this plan is discovering, after two small packages, that the idea does not
work — and the plan is shaped to make that discovery cheap and early rather than
after five Crystals and a database driver.

---

## What this plan deliberately does not include

* **Any change to the core.** Not one symbol. If a Crystal needs one, that is a
  finding for the core's own planning process, subject to G-09's eight pieces of
  evidence, and not something an ecosystem work package may smuggle.
* **A database Crystal.** Blocked on WP37 for the *example*, not the pool.
  Building the pool early is fine; documenting an interim global-state pattern
  as canonical is not (ADR-C006).
* **A CLI.** `uruquim new`, `uruquim dev`, `uruquim doctor` are attractive and
  premature. A CLI that orchestrates two Crystals is a wrapper; one that
  orchestrates eight might be worth it. Revisit at eight.
* **A catalogue, an index or badges.** Meaningless below roughly ten Crystals,
  and harmful if a listing is mistaken for an audit.
