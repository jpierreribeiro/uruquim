# Open questions

**Status: GENUINELY OPEN.** Nothing here has an answer that the author is
hiding. Each entry names who decides and what evidence would settle it, so the
list shrinks by decision rather than by drift.

---

## Q-1 — Stateful middleware before `web.state` exists

**The problem.** Odin has no capturing closures, so a `web.Handler` — which is
`proc(ctx: ^Context)` — cannot carry configuration or a pointer to a pool. A
Crystal that wants configurable middleware today has three options and none is
good:

1. Stateless middleware only. Works, but rules out most interesting middleware.
2. Package-global state inside the Crystal. Works today; breaks multiple Apps in
   one process, breaks isolated tests, and turns initialisation order into
   implicit state.
3. The application writes a four-line adapter that fetches typed state and calls
   into the Crystal. Clean — and needs `web.state`, which is WP37.

**Who decides.** The owner, informed by the core's WP37.

**What would settle it.** WP37 landing makes (3) canonical and the question
closes. Before that, the only real decision is whether (2) is permitted in an
Experimental Crystal — and the proposed answer is *yes, if it is labelled a
prototype and never documented as the canonical pattern* (ADR-C006).

**Note:** WP37 answers *two* questions and this one depends only on the first.
Application state is ADR-004, **already accepted**. Request-scoped state is
ADR-028, **undecided**, and its own recommendation is option 1 — no
request-scoped state, permanently. Nothing in these documents needs it.

---

## Q-2 — May coupled Crystals be built before Phase 3 freezes?

**The problem.** `planning/roadmap.md` places the ecosystem in Phase 5, entry
"Phase 4 frozen". Phase 3 changes limits, timeouts, route representation and
application state. A Crystal built against the current surface may need rework.

**Who decides.** The owner. Recorded as entry condition CE-E4.

**What would settle it.** Nothing settles it in advance — it is a judgement
about how much rework is acceptable. What can be said: a **Tool** Crystal is
unaffected either way, which is a large part of why
[`first-crystal.md`](first-crystal.md) recommends one.

---

## Q-3 — Does the Router-returning shape survive Phase 3?

**The problem.** ADR-C003 recommends that a Route Crystal return a detached
`web.Router` for the application to `mount`. That rests on `mount` copying
routes and chains into the App, and on `Router` embedding `App`. Phase 3's
WP28/WP29 replace the route representation wholesale.

**Who decides.** The core's Phase-3 work packages, not this document.

**What would settle it.** The public contract of `mount` and `Router` surviving
the Phase-3 freeze unchanged. The core is explicit that internals are
replaceable *as long as observable contracts hold*, so the expectation is
positive — but "expected" is not "verified", and CE2 should be re-run against
the Phase-3 freeze.

---

## Q-4 — Is the concept budget measurable outside the core?

**The problem.** The core caps its guarded lab program at 25 concepts and
measured 23 (`planning/phase-3-plan.md` FINDING-D). That works because there is
one instrument and one program. [`glossary.md`](glossary.md) proposes a
per-Crystal budget, and it is not obvious the instrument transfers.

**Who decides.** Whoever writes the second Crystal, from experience.

**What would settle it.** Trying to count the concepts in `dev/watch` and
`web/health`. If the count is contentious for a forty-line middleware, the
metric does not transfer and should be dropped rather than kept as a ritual.

---

## Q-5 — When does the gate become unaffordable?

**The problem.** The core's gate is ~4,000 lines of bash. Per-Crystal gates that
are 5% of that are still 200 lines each. At ten Crystals that is 2,000 lines of
duplicated, drifting shell.

**Who decides.** Evidence, at CE2's review.

**What would settle it.** Whether the two hand-rolled gates drift within two
Crystals. If they do, `crystals:dev/ledger` moves from speculative to required
and moves to the front of the roadmap — extracted from two working
implementations rather than designed in advance.

---

## Q-6 — Is "Druse" worth the word? — **CLOSED, 2026-07-20**

**How it was asked.** A Druse ships no code, so a concept that adds a word and
no mechanism looked like a concept that should not exist.

**The answer, from the owner: the question was wrong.** A druse is the
formation where small crystals line a cavity in another rock — the application
is the rock, the cavity is the space the framework deliberately leaves empty,
and the crystals are what the developer chooses to put there. It is an
**exemplification of the philosophy**, not a deliverable.

**What this closed, and what it corrected.** The earlier draft had turned the
metaphor into a technical artifact: a named, tested combination with a
compatibility matrix and a promotion process. That was accretion of exactly the
kind this project refuses, committed in the ecosystem's own documentation. A
tested combination of Crystals is a **tag on a repository** and needs no
vocabulary at all.

The word stays, naming the idea. It carries no mechanism, and asking it to
carry one is the failure mode to watch for.

---

## Q-7 — What happens to a Crystal when the core deprecates something?

**The problem.** The core has no release, no tag and no deprecation policy —
those are Phase-4/M2 concerns. A Crystal pinned to a core commit is safe, but a
Crystal pinned to a core commit is also *stuck*. There is currently no process
for "the core changed; here is the window in which Crystals must follow".

**Who decides.** The owner, at M2 (supported-version policy).

**What would settle it.** The core's own versioning policy arriving. Until then
the compatibility matrix is the whole mechanism, and it is honest but manual.

---

## Prior art — the external draft, and what it got wrong

The first architectural draft for this idea came from a planning pass without
repository access. It was audited against the tree on 2026-07-20. Its
architectural direction survived intact — one-way dependencies, no registry, no
auto-discovery, application-owned composition, services aggregated by the
application rather than self-registering, restart-based reload over
`core:dynlib`. All of that is preserved here.

Recorded so nobody re-derives them, the corrections that audit produced:

| The draft said | Actually |
|---|---|
| `web.state` / `web.app_with_state` are future work of uncertain shape | **ADR-004 is ACCEPTED** — `rawptr` + `typeid`, asserted accessor, AMEND-1. Both names are already reserved in `docs/ai-context.md` and `docs/canonical-patterns.md` as Phase-3-unavailable. |
| A Startup Crystal modifies the `App` | It should return a **detached `web.Router`**. `Router` embeds `App`, so `use`/`get`/`destroy` accept `&router`, and `mount` copies. This removes the ordering hazard entirely (ADR-C003). |
| Dependency direction needs a new ADR | It is already **G-06/G-07**, and the enforcement mechanism already exists: `build/phase1-direct-dependencies.txt` plus the freeze gate. |
| The ecosystem needs an E0–E6 roadmap | `planning/roadmap.md` already has **Phase 5 — Ecosystem**, and `later-phases-plan.md` has a backlog. The stages here reconcile with those rather than running in parallel. |
| An import can pull unused code into the binary | True, and stronger than stated: WP6 measured `core:log` at **~37 KiB, referenced or not**. But the converse also holds — Phase 2 found 8 middleware symbols link even without an import, because they are reachable from `dispatch`. See [`gate.md`](gate.md) §The optionality trap. |
| `install()` hides too much | True, but the real objection is stronger: it **cannot know whether `use` is still legal**, and guessing wrong poisons the application fail-closed. |
| Restart-based reload is straightforward | It is, except that the core has **no graceful shutdown before Phase 4**, so a restart cuts in-flight requests with no deadline. That must be documented by the Crystal. |
| Crystal/Druse are established terms here | They appear nowhere in the repository. This is entirely new vocabulary, and [`glossary.md`](glossary.md) accounts for what it costs. |

Two claims in the draft were checked and were **correct**, which is worth
recording too: the README is stale (it still describes Phase 1 at 32+2=34, while
Phase 2 froze 44+2=46), and WP37 is indeed the typed-application-state work
package.

**The README staleness is a real defect in the core, unrelated to this idea.**
It is noted here only so it is not lost; fixing it belongs to the core's own
process, not to an ecosystem work package.
