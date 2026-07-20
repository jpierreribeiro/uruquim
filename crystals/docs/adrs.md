# Crystal ecosystem — architecture decision records

**Status: ALL PROPOSED. None accepted.** Numbered `ADR-C0xx` so they never
collide with the core's `ADR-001…ADR-028` (`planning/adrs.md`), which govern the
framework and are not reopened by anything here.

Format follows the core's: context, options, benefits, costs, risks, evidence,
recommendation, reversibility. Reversibility is rated because it is the field
that most often changes a decision — a cheap-to-undo choice deserves less
argument than an expensive one.

---

## ADR-C001 — Dependency direction is one-way and mechanically checked

* **Status.** PROPOSED.
* **Context.** Can `uruquim:web` ever import, discover or initialise a Crystal?
* **Options.** (A) Never; the application links Crystals explicitly. (B) A
  registry or discovery mechanism in the core.
* **Benefits.** A: the core's import set stays pinned at five and its frozen
  surface is unaffected by anything the ecosystem does. B: less application
  boilerplate.
* **Costs.** A: the application writes its own composition, always. B: the core
  grows an extension surface it has spent two phases refusing.
* **Risks.** A: none identified. B: G-03 already forbids the obvious form, and
  G-07 points the other way.
* **Evidence.** `build/phase1-direct-dependencies.txt` pins the five imports
  and the freeze gate enforces the set — the mechanism for A already exists and
  already runs.
* **Recommendation.** **A.** This is not really a decision; it is a restatement
  of an existing enforced constraint. It is recorded so nobody proposes B as a
  convenience later.
* **Reversibility.** Choosing A is fully reversible. Choosing B is not — an
  extension point cannot be withdrawn once anything depends on it.

## ADR-C002 — Five categories, derived from two questions

* **Status.** PROPOSED.
* **Context.** How should Crystals be classified, so that obligations follow
  from the classification rather than being assigned by taste?
* **Options.** (A) A flat list of category names. (B) Derive from two
  properties: does it import `web`, and does it own app-lived memory — plus
  in-process vs out-of-process. (C) No categories; every Crystal documents
  itself.
* **Benefits.** B: the taxonomy is complete by construction, and a Crystal that
  does not fit is *visibly* two Crystals. C: no vocabulary cost.
* **Costs.** A: lists grow, and someone always proposes a sixth. C: every
  Crystal re-derives its own obligations, inconsistently.
* **Risks.** B: the two axes might be the wrong two.
* **Evidence.** The split is not invented here — **G-02** already forces
  domain code away from `uruquim:web`, which is exactly the Library/Request
  boundary.
* **Recommendation.** **B.** Tool (out of process); then the 2×2 of
  Library / Service / Request / Route.
* **Reversibility.** HIGH — categories are documentation, not code.

## ADR-C003 — The application owns composition; Crystals do not mutate the App

* **Status.** PROPOSED. **The most consequential decision here.**
* **Context.** A Route Crystal needs routes and possibly its own middleware.
  How does it contribute them?
* **Options.** (A) `crystal.install(&app)` mutates the App. (B) The Crystal
  returns a detached `web.Router`; the application mounts it. (C) The
  application writes every `web.get`/`web.use` call itself and Crystals export
  only handlers.
* **Benefits.** B: the Crystal cannot affect the App's ordering, gets its own
  middleware scope for free, and `mount` copies so ownership is unambiguous.
  C: maximum visibility. A: least typing.
* **Costs.** B: one extra `mount` line, and the application must destroy the
  Router. C: verbose for a Crystal with a dozen routes.
* **Risks.** **A is not merely unclear, it is unsafe.** `web.use` is rejected
  after any registration or `mount`, and rejection *poisons the whole
  application* — `serve` refuses to bind and every request answers 500
  (ADR-019, `web/middleware.odin`, `web/serve.odin`). An `install()` cannot know
  whether it is still allowed to call `use`, because that depends on what every
  other Crystal did first. Two correct Crystals in the wrong order produce a
  dead application and a misleading diagnosis.
* **Evidence.** `Router :: struct { using app: App }` — `web.use`, `web.get`
  and `web.destroy` all accept `&router` unchanged, and `mount` copies routes
  and chains into the App and closes the router (`web/router.odin`).
* **Recommendation.** **B for anything with routes; C for a single middleware
  or observer, exported as a value the application installs.** A is rejected.
* **Reversibility.** MEDIUM — it shapes every Route Crystal's public API, so
  changing it later rewrites call sites.

## ADR-C004 — No Crystal calls `web.observe`

* **Status.** PROPOSED.
* **Context.** Multiple Crystals may want framework events.
* **Options.** (A) Crystals call `observe` themselves. (B) Crystals export an
  observer procedure; the application installs one and fans out. (C) A fan-out
  Crystal owning a fixed array of observers.
* **Benefits.** B: no state, no concept, the one call stays visible. C: the
  fan-out is written once.
* **Costs.** B: the application writes a six-line procedure. C: a Crystal, with
  a capacity ledger, to replace six lines.
* **Risks.** **A silently destroys observability.** `observe` stores one
  procedure pointer and a later call replaces the earlier one with no
  diagnostic (`web/observer.odin`). Two observing Crystals means one stops
  working and nothing says so.
* **Evidence.** `web/observer.odin`: `a.private.observer = observer`, plain
  assignment; the "ONE observer per App … last wins" contract is documented at
  the call site and at the storage site.
* **Recommendation.** **B.** Revisit C only if a real program has four or more
  sinks and the hand-written fan-out has actually become a problem.
* **Reversibility.** HIGH.

## ADR-C005 — Reload is process restart; in-process reload is a different feature

* **Status.** PROPOSED.
* **Context.** What does "hot reload" mean for an Uruquim application?
* **Options.** (A) Watch, rebuild, restart the process. (B) `core:dynlib`,
  swapping handlers in a live process. (C) Both, under one name.
* **Benefits.** A: same build as production, same collections, zero core
  change, no plugin ABI, no risk of a procedure pointer into unloaded code.
  B: preserves in-memory state across a reload.
* **Costs.** B: needs request quiescence, handler generation counting,
  in-flight accounting and a stable ABI — because Uruquim stores procedure
  values in route tables and chains, and live requests hold slices into those
  chains.
* **Risks.** A: **no graceful shutdown exists before Phase 4**, so a restart
  cuts in-flight requests with no deadline. This must be documented, not
  glossed. C: hides a very large semantic difference behind one name.
* **Evidence.** `README.md` "Not yet" — graceful shutdown with a deadline is
  Phase 4. ADR-020 — the framework already expects to run under a supervisor.
* **Recommendation.** **A**, with the termination limitation stated in
  `CRYSTAL.md`. B stays an experiment under a different name. C rejected.
* **Reversibility.** HIGH — they are separate tools.

## ADR-C006 — Services are application-owned; there is no per-Crystal state registry

* **Status.** PROPOSED. **Depends on the core's WP37 and cannot be accepted
  before it.**
* **Context.** Where does a database pool live, and how does a handler reach it?
* **Options.** (A) One application-owned struct aggregating every service,
  reached through the future `web.state`. (B) Each Crystal registers its own
  state with the App. (C) Package-global state inside each Crystal.
* **Benefits.** A: one value, one lifetime, visible in the composition root,
  and it matches what ADR-004 actually accepted. B: less application code.
  C: works today.
* **Costs.** A: needs `web.state`, which does not exist yet. C: breaks multiple
  Apps in one process, breaks isolated tests, and turns initialisation order
  into implicit state.
* **Risks.** **B recreates the extension bag G-03 exists to forbid** — a
  keyed collection of type-erased state, assembled by whoever imported what.
* **Evidence.** ADR-004 is **ACCEPTED**: a single `rawptr` + `typeid` on the
  App with an asserted accessor, AMEND-1 rejecting nil and asserting exact type
  — *one* value, not a registry. `web.state` and `web.app_with_state` are
  already reserved names in `docs/ai-context.md` and
  `docs/canonical-patterns.md`, marked unavailable.
* **Recommendation.** **A.** C is acceptable only in a clearly labelled
  prototype and must never be documented as the canonical pattern. B rejected.
* **Reversibility.** LOW once applications store services — which is precisely
  why the canonical database example waits for WP37 rather than shipping C.

## ADR-C007 — One collection, one repository, to begin

* **Status.** PROPOSED.
* **Context.** Where do Crystals physically live?
* **Options.** (A) A monorepo `uruquim-crystals`, one collection root.
  (B) One repository per Crystal. (C) A directory inside the core repository.
* **Benefits.** A: one collection flag, one Odin pin, one matrix, atomic
  cross-Crystal changes while the core moves. B: independent cadence.
  C: zero setup.
* **Costs.** B: N submodules and N matrices, for an ecosystem with two members.
  C: puts optional code inside a repository whose value is a small, frozen,
  gate-enforced surface.
* **Risks.** C also works against a decision already taken — roadmap M5 plans to
  *retire* `planning/` and `experiments/` from the public tree.
* **Evidence.** Odin resolves collections to directory roots; packages are
  directories. Nothing in the language favours one repository per package.
* **Recommendation.** **A**, with a stated exit condition: a Crystal leaves when
  it grows a large native dependency, a different licence, a different
  maintainer, an independent cadence, or usefulness outside Uruquim.
* **Reversibility.** HIGH — moving a package between repositories is mechanical.

## ADR-C008 — Compatibility is declared against commits, not versions

* **Status.** PROPOSED.
* **Context.** How does a Crystal state what it works with?
* **Options.** (A) Commit-level: Odin release + commit + asset SHA, Uruquim
  commit and phase, Crystal commit, verified platform. (B) Semantic version
  ranges. (C) "Works with the latest."
* **Benefits.** A: every row is checkable, and it works today. B: familiar.
* **Costs.** B: **there is no Uruquim version.** No tag exists, and the roadmap
  says none before M2. A range over a set with no members is not a constraint.
* **Risks.** C: unreproducible builds and unreproducible bug reports.
* **Evidence.** `odin-version.txt` already pins release, commit and SHA-256 —
  the core calls this stronger than anything surveyed in the ecosystem.
  `planning/roadmap.md` M2 states only Linux x86-64 is tested.
* **Recommendation.** **A**, migrating to ranges once tags exist. Platform
  claims stay as narrow as the testing.
* **Reversibility.** HIGH.

---

## Decisions deliberately not taken yet

* **A `CRYSTAL.md` schema.** Two Crystals will teach more about what the
  document needs than any amount of designing it now.
* **An index, badges or a catalogue.** Meaningless below roughly ten Crystals,
  and actively harmful if a listing is mistaken for an audit.
* **Whether the concept budget is measurable per Crystal.** See
  [`open-questions.md`](open-questions.md) Q-4.
* **Anything about Druses beyond "it ships no code".** Nothing to compose yet.
