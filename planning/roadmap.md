# Uruquim roadmap — Phases 2 to 5 and the release track

Living document. Written after the Phase-1 freeze (`a7d2e9e`) from the evidence
in [`post-phase1-audit.md`](post-phase1-audit.md) and
[`odin-fit-audit.md`](odin-fit-audit.md).

Detail is deliberately **proportional to distance**. Phase 2 is complete
([`phase-2-plan.md`](phase-2-plan.md), [`phase-2-freeze.md`](phase-2-freeze.md)).
Phase 3 is planned to hand-off depth ([`phase-3-plan.md`](phase-3-plan.md));
Phases 4 and 5 have defined work packages and research gates but no frozen
signatures ([`later-phases-plan.md`](later-phases-plan.md)). Precision about
work that is two years away would be false precision.

## Where the project is

*(Updated 2026-07-20, after the Phase-2 freeze.)*

Phases 1 and 2 are complete and frozen: 44 application symbols + 2 test-support
symbols, protected by an executable gate that now freezes claims, lifetimes and
capacities as well as signatures. On top of Phase 1's server, routing,
extractors, JSON body binding, error envelope and socket-free testing, Phase 2
shipped middleware (onion, ADR-005), route groups (`Router`/`mount`),
request-header lookup, correlation IDs with a tested trust policy, a
per-request logger and a typed framework-error observer — each costing zero
bytes when unused, proven by `nm`. Phase 3 is planned in `phase-3-plan.md`
(reviewed twice, all corrections applied) and has not started; ADR-028 is its
open owner decision. The project is usable for building and testing a JSON API.
It is not hardened for unattended production exposure, and no release has been
made.

## What each phase is for, in plain terms

| Phase | The user-visible promise | Why it exists |
|---|---|---|
| **2 — Composition** | "I can share behaviour across routes: auth, logging, request IDs, and I can group routes under a prefix." | Today every handler repeats itself. There is no way to require authentication once, or to log every request, without copying code into each handler. |
| **3 — Performance core** | "It stays fast as my route table and traffic grow, and I can tune the limits." | The route table is a linear scan and every limit is fixed. Neither is wrong today; both stop being fine at scale. |
| **4 — Production** | "I can run this facing real traffic: shut it down cleanly, sit behind a proxy, bound its resources, and see what it is doing." | Today there is no way to stop the server, no timeouts, no proxy handling, and no observability. This is the phase that makes deployment defensible. |
| **5 — Ecosystem** | "The optional pieces I need exist, without bloating the core." | Uploads, static files, WebSocket, OpenAPI. Each is real demand; none belongs in a 34-symbol core. |

## Sequencing, and why this order

```
Phase 1 (frozen)
   │
   ├── C-1  licence + product files      ─┐ small corrective PRs,
   ├── C-2  stale-comment correction     ─┘ before Phase 2 starts
   │
Phase 2 — Composition
   │   debt first: gate restructuring, test-support body, commit invariant
   │   then: middleware prototype (onion decision) → chain → groups → defaults
   │
Phase 3 — Performance core            requires Phase 2's chains to exist
   │   research gate (benchmarks) → router representation → limits/timeouts
   │
Phase 4 — Production                  requires Phase 3's limits and timeouts
   │   lifecycle/shutdown → proxies → observability → hardening
   │
Phase 5 — Ecosystem                   optional packages, each spec-gated
```

Three dependencies are hard and worth stating:

* **Phase 3 cannot precede Phase 2.** Precomputed middleware chains are a
  Phase-3 optimisation target, and they cannot be optimised before they exist.
* **Phase 4 cannot precede Phase 3.** Graceful shutdown with a deadline is
  meaningless without timeouts, and load shedding is meaningless without limits.
* **Phase 2 cannot start on middleware.** Three items of Phase-1 debt sit
  directly underneath it (audit §5): a gate that punishes adding files, a test
  facility that cannot send a body, and a response-commit invariant held together
  by hand-written guards that a new responder would break.

## Value, risk and effort

Relative, not absolute. "Effort" is measured in work packages, since a WP is
sized to be reviewable by one person.

| Phase | Value to users | Risk | Effort | Biggest risk in one line |
|---|---|---|---|---|
| C-1/C-2 corrections | **High** (unblocks any use at all) | Low | 2 small PRs | none; the licence is an owner decision |
| **Phase 2** | **High** | **Medium-High** | ~12 WPs | onion middleware is a foreign abstraction risk; prototype before committing |
| **Phase 3** | Medium | Medium | ~10 WPs | choosing a router representation before measuring |
| **Phase 4** | **High** for anyone deploying | **High** | ~14 WPs | security surface: proxies, limits, uploads, TLS |
| **Phase 5** | Low per item, high in aggregate | Low | per-item | scope creep — everything wants to be in core |

Phase 2 carries more risk than its size suggests, because it is where the API
shape for everything after it gets set. Phase 4 carries the most absolute risk,
because it is where mistakes become remotely exploitable rather than merely
inconvenient.

## Entry and exit criteria

A phase may not start until its entry criteria hold, and may not be declared
complete until its exit criteria are gate-verified — the same discipline WP11
applied to Phase 1.

### Phase 2 — Composition

**Entry:** Phase 1 frozen and merged ✅; the independent verifier green on the
merged commit; C-1 and C-2 landed.
**Exit:** the onion-vs-pre-order decision is recorded as an accepted ADR with a
prototype behind it; middleware ordering, short-circuit and unwind are
behaviour-tested; recovery/logger/request-ID cost **zero bytes** in an app that
does not use them, proven by `nm` as G-11 was; the Phase-2 ledger is frozen with
per-symbol evidence; documentation parity holds; full gate green with no skips.

### Phase 3 — Performance core

**Entry:** Phase 2 frozen; a benchmark harness exists with recorded hardware,
warm-up, route distribution, concurrency and p50/p95/p99 methodology.
**Exit:** the router representation is chosen **from measurements**, not
preference, with the losing candidates recorded; observable routing behaviour is
byte-identical to Phase 1 for every existing test; configurable limits and
timeouts exist with an options struct and a package default constant; a
regression benchmark runs in the gate.

### Phase 4 — Production

**Entry:** Phase 3 frozen; limits and timeouts exist.
**Exit:** shutdown with an absolute deadline, admission stop and exactly-once
cleanup, all tested; per-server state replaces the transport globals (audit
A-4); trusted-proxy handling with ADR-013 accepted; fuzzing and a soak test in
CI; observability using **low-cardinality route identity**, never raw paths;
an operations document.

### Phase 5 — Ecosystem

**Entry:** Phase 4 frozen; a real user request for each item.
**Exit:** per item — each is spec-gated individually and may be declined.

## Release and adoption track

This runs alongside the phases, not after them. A framework nobody may legally
use is not a framework.

| Milestone | Contents | Gate |
|---|---|---|
| **M0 — usable by others** (before Phase 2) | `LICENSE`, `SECURITY.md` + reporting channel, `CONTRIBUTING.md`, `CHANGELOG.md` | ✅ done — all four files exist; MIT chosen by the owner |
| **M1 — Phase 2 shipped** | middleware, groups, header lookup; docs and examples updated | Phase-2 exit criteria |
| **M2 — honest preview** | supported-Odin-version policy; platform support stated honestly (only Linux x86-64 is tested today); upgrade guide | policy documented, not implied |
| **M3 — Phase 4 shipped** | operations doc, security policy exercised, soak/fuzz results | Phase-4 exit criteria |
| **M4 — external users** | full CRUD example, a Postgres example, beginner documentation, cookbook | examples compile in the gate |
| **M5 — 1.0 candidate** | user study (`odin-fit-audit.md` §13) run and acted on; `planning/`, `experiments/` and the knowledge base retired from the public tree per the local cleanup plan | study completed; tree matches the target layout |

**Versioning stays a human decision.** Odin has no official package manager by
design, so consumption is by vendoring or submodule and the pinned toolchain
version is part of the contract. No tag should be cut before M2 at the earliest,
and 1.0 should not be cut before the user study in M5.

## Governing rules for all future phases

Carried forward from Phase 1 because they are why Phase 1 stayed small:

1. **The 32+2 freeze is not an allowance to grow freely.** Every phase declares
   its own ledger, and every new symbol carries owner, use case, binary cost,
   dependencies, an example, a behaviour test, ownership and a rollback path.
2. **No aliases, no second canonical way.** This is Odin's own stated rule.
3. **Defaults must be lazily linked** — an application that does not use a
   feature pays zero bytes for it, proven by `nm`, as G-11 established.
4. **Optional means optional.** Uploads, static files, TLS, OpenAPI, WebSocket
   and streaming are candidates for separate packages, not core growth.
5. **Measurements decide performance questions**, not preference — and the
   losing options get recorded.
6. **No decision is marked accepted without the owner.** ADR-010, ADR-013 and
   ADR-028 remain PROPOSED (ADR-005 was accepted by the owner on 2026-07-19).
   The owner-facing queue, in plain language, is
   [`decisoes-do-dono.md`](decisoes-do-dono.md).
