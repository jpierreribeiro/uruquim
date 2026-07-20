# Ideas — candidate Crystals, unfiltered

**Status: BRAINSTORM. Nothing here is committed, and several of these are
probably bad.** The point of this document is to have the whole space written
down before choosing, so the first choice is a choice and not an accident.

Each entry carries three honest columns:

* **Needs from core** — what must exist in `uruquim:web` first. `nothing` means
  it can be built today against the frozen surface, or without importing `web`
  at all.
* **Blast radius** — what it can break in the core if it is wrong. A Crystal
  that never imports `web` and runs in its own process has a blast radius of
  **none**, which is a real engineering property, not a technicality.
* **Novel?** — whether this exists in every ecosystem already, or whether
  Uruquim would be doing something its own way.

---

## Tier 1 — buildable now, no coupling to the framework

These import nothing from `uruquim:web`. They cannot violate the frozen
surface, cannot enter the request path, and cannot affect binary size or memory
correctness of a server, because they are not in the server.

### `crystals:dev/watch` — reload on save

Watch files, debounce, run the real `odin build`, keep the old process alive if
the build fails, restart if it passes.

*Needs from core:* nothing. *Blast radius:* none. *Novel:* no — and that is
fine; it is the single most missed thing coming from a mature ecosystem.

The interesting part is not the watching, it is the **termination contract**.
The core has no graceful shutdown until Phase 4 (`README.md`, "Not yet"), so a
restarting supervisor cuts in-flight requests with no deadline today. That must
be stated, not glossed. It also makes the watcher a *forcing function*: it is
the first thing that will want `web.stop`, and it will produce the real user
request Phase 4 wants as evidence.

Explicitly **not** in scope: in-process hot patching via `core:dynlib`. Uruquim
stores procedure values in route tables and middleware chains, and live requests
hold slices into those chains. Unloading a library under that would need
quiescence, a handler generation counter, in-flight accounting and a stable ABI
— four features nobody has asked for, to avoid one process restart. If it is
ever attempted it gets a different name, because calling both things "hot
reload" would hide a very large semantic difference.

### `crystals:sql` — query construction, no database

Builds SQL text plus ordered bindings. Knows nothing about connections,
transactions, HTTP, or `web.Context`.

*Needs from core:* nothing. *Blast radius:* none. *Novel:* no.

Valuable precisely because it is separable: a program can build SQL and send it
through something else entirely, and the builder can be tested with zero
infrastructure. The design risk is the usual one — a builder that starts
composable and ends up needing a schema, then a mapper, then an ORM. The
[layering in `vision.md`](vision.md) exists to keep that from happening by
default.

### `crystals:dev/doctor` — is this project actually buildable?

Verify the Odin release/commit/checksum against `odin-version.txt`, check the
collections resolve, check native dependencies exist, compile a minimal
program, report what does not match.

*Needs from core:* nothing. *Blast radius:* none. *Novel:* mildly — the pin
file is stronger than most ecosystems have, and nothing currently reads it on
the consumer's side.

### `crystals:dev/pin` — a lock file for a world with no package manager

Odin will never have an official package manager (C-8), and the project already
treats that as settled rather than as a gap to paper over. But "no resolver" is
not the same as "no record". This tool would write and verify a lock: Odin
release + commit + asset SHA, Uruquim commit, each Crystal's commit, native
libraries and their versions — then verify a checkout against it and say
exactly what drifted.

*Needs from core:* nothing. *Blast radius:* none. *Novel:* **yes**, in a small
way. It is the honest version of dependency management: no downloads, no
resolution, no network at build time, just a checked statement of what you
built against. It is also the piece that makes a Druse mean anything.

---

## Tier 2 — needs only the frozen Phase-2 surface

These import `uruquim:web` and use only symbols that are already frozen. They
are where the *coupling* half of the contract actually gets tested.

### `crystals:web/secure` — security headers

A stateless `Handler`: sets a documented set of response headers, calls
`web.next`.

*Needs from core:* `use`, `next`, `header`-setting. *Blast radius:* small — a
middleware, on the request path, but stateless. *Novel:* no.

Tiny, which is exactly why it is a good contract test: it exercises the
`Handler` shape, middleware ordering, `test_request` testing and the
"costs nothing when unused" measurement, in about forty lines. If the contract
cannot describe *this* cleanly, the contract is wrong.

### `crystals:web/health` — a health endpoint

Registers `GET /health` (and optionally a readiness route) on an `App` or a
`Router`.

*Needs from core:* `get`, `router`, `mount`. *Blast radius:* small. *Novel:*
no.

Its real value is as the first **Startup Crystal**, which is where the
ordering hazard bites: `use` is rejected after any route registration and
poisons the whole application (ADR-019). A Crystal that registers a route ends
the middleware phase for every other Crystal. See
[`crystal-contract.md`](crystal-contract.md) §Composition order — this one
example is the reason that section exists.

### `crystals:web/fanout` — more than one observer

`web.observe` has exactly one slot and a second call silently replaces the
first (`web/observer.odin`). The moment two Crystals both want framework
events, they conflict, and the failure is *silent loss of observability* —
which is the worst possible failure mode for an observability feature.

*Needs from core:* `observe`, `Framework_Event`. *Blast radius:* small.
*Novel:* no, but necessary.

The honest options are (a) a Crystal that owns a small fixed array of observer
procedures and installs one fan-out procedure, or (b) documenting that the
application writes the six-line fan-out itself and no Crystal ever calls
`observe`. **(b) is probably right** — it is smaller, it has no state, and it
keeps the one call visible. Recorded here because the conflict is real either
way and the ecosystem must answer it before it ships two observers.

### `crystals:web/replay` — record real requests, replay them in tests

`web.test_request` performs real routing with no socket, which is a less common
capability than it looks. A Crystal could capture request shapes (method, path,
query, headers, body) from a running system or from a log, and replay the
corpus deterministically through `test_request` in a normal test binary.

*Needs from core:* `test_request`, `Recorded_Response`. *Blast radius:* none at
runtime — it lives in test binaries. *Novel:* **yes**, moderately. Most
frameworks need a socket or a mock server for this; here it is just a loop.

Watch the lifetime rule: `Recorded_Response` is valid only until the next
`test_request` (`planning/phase-2-freeze.md` lifetime ledger), so a corpus
runner must copy anything it wants to keep.

---

## Tier 3 — blocked on Phase 3

### `crystals:db/postgres` — pool and driver

*Needs from core:* nothing to *build*, but **WP37** (typed application state)
before the integration can be shown canonically. Until `web.state` exists, a
handler cannot reach a per-application pool without package-global state, and
teaching global state as the canonical pattern would be a mistake that outlives
the workaround.

*Blast radius:* medium. *Novel:* no.

The pool itself can be prototyped and tested with zero framework involvement.
It is only the *example* that has to wait.

### `crystals:db/migrate` — migrations

A separate executable. Stable identifiers, checksums, an advisory lock, history,
explicit failure, and a defined answer for a partially applied migration.

*Needs from core:* nothing. *Blast radius:* none (separate process). *Novel:*
no. Listed in Tier 3 rather than Tier 1 only because it is pointless before a
driver exists.

The one design commitment worth making early: the server does not run
migrations at boot by default. Migration is a deploy step, and coupling it to
process start makes progressive deploys unsafe.

### `crystals:config` and `crystals:validate`

Read and validate configuration at startup; validate values with no knowledge of
HTTP, plus a thin `crystals:web/validate` adapter that maps a validation
failure to the standard 400 envelope.

*Needs from core:* the adapter needs the error envelope shape to be stable, and
Phase 3 touches limits. *Blast radius:* small. *Novel:* no.

This pair is the clearest illustration of the two-layer rule — the generic
library must not know what a status code is, and the adapter is the only place
the two vocabularies meet.

---

## Tier 4 — speculative, and the reason to have this document

These are the ones worth arguing about. Two of them are the only genuinely
novel things on the list.

### `crystals:dev/context` — a dependency-scoped AI context bundle

Uruquim's third pillar is AI readability, and `docs/ai-context.md` is an unusual
artifact: a compact, canonical, deliberately closed API reference whose header
says *"if something is not listed here, it does not exist"*, enforced by the
gate against the compiler's own export list.

That works because there is one package. Add five Crystals and an agent needs
five such documents — but only the five the project actually vendors, not the
whole catalogue.

This tool would read the project's collections and lock, and emit a single
context bundle containing exactly the `ai-context.md` of the core plus each
vendored Crystal, plus the project's own rules.

*Needs from core:* nothing. *Blast radius:* none. *Novel:* **yes.** No
ecosystem currently ships per-project, dependency-scoped agent context as a
first-class build artifact. It is a direct extension of something this project
already does better than its neighbours, which is usually where the good ideas
are.

Risk: it is meta. It produces no runtime value, and building it first would be
choosing the clever thing over the useful thing.

### `crystals:dev/ledger` — the project's own gate discipline, as a reusable tool

The most transferable thing this project has invented is not the router. It is
the **method**: a symbol ledger derived from the compiler's export list, claims
that must each carry a negative control, `nm`-based proof of "costs nothing
when unused" with a mandatory positive control, a capacity ledger that forbids
the word "bounded" without naming the bound, and a lifetime ledger that names
who frees what.

Right now that method exists as ~4,000 lines of bash specific to one
repository. As a tool, any Odin package could adopt it.

*Needs from core:* nothing. *Blast radius:* none. *Novel:* **yes**, and more
than the rest of this list combined. It is also the only item here that would
make the *ecosystem* trustworthy rather than merely larger — every Crystal
needs a gate, and writing eleven bespoke ones is how the discipline dies.

Risk: it is a build tool, and building it before there is a single Crystal to
point it at is textbook premature abstraction. The honest sequencing is that
the first two Crystals hand-roll their gates, the duplication becomes obvious,
and *then* this gets extracted from working code rather than imagined.

### `crystals:web/spec` — OpenAPI from the DTOs

The core already uses struct tags (`json:"id"`) and `core:reflect` exists. A
Crystal could derive a JSON Schema / OpenAPI document from the application's
request and response types plus its registered routes.

*Needs from core:* route enumeration — **WP34, "Route identity accessor"**, is
exactly this, and it is in the Phase-3 plan for observability reasons. *Blast
radius:* small if it runs at startup or in a test; large if anyone tries to
serve it dynamically from the hot path. *Novel:* moderately, for Odin.

Flagged as speculative because reflection-heavy schema derivation is precisely
the "heavy metaprogramming" the README rejects. It might only be defensible as a
build-time tool that emits a file, never as a runtime feature.

### Things deliberately rejected here, so nobody proposes them twice

* **A `Crystal` interface or base type.** There is nothing to abstract over.
  Odin has no interfaces, the categories do not share a signature, and a
  universal `install(^App)` shape is actively harmful — see the contract's
  composition-order section for the mechanism, not just the taste.
* **A dependency resolver.** Not "not yet". C-8 is settled: Odin will never
  officially support one, and a third-party resolver for a five-package
  ecosystem would be more machinery than the ecosystem it manages.
* **A Crystal that wraps `web.serve`.** Anything that owns the server owns the
  program, and the ecosystem's whole premise is that the application does.
* **Background jobs, queues, WebSocket, streaming, uploads.** Not because they
  are bad ideas, but because every one of them depends on transport and
  lifecycle behaviour the core has not built yet. Proposing them now produces
  designs against an imagined core.
