# Crystals — an optional ecosystem around Uruquim

**Status: IDEA UNDER DEVELOPMENT. Nothing here is decided, nothing is frozen,
and no Crystal exists.** These documents exist to make the idea concrete enough
to judge — to find out whether it is coherent and worth building — not to
constrain anyone before that judgement is made.

Read everything below as **proposals with their reasoning attached**. Where a
document sounds firm, it is stating a *consequence* of something the core has
already measured or decided, and it says which one. Everything else is open.

## Why the idea exists

Uruquim's core has a hard rule against absorbing convenience. Guardrail
**G-07** (`planning/public-api-guardrails.md`):

> Templates, static hosting, alternate serializers, WebSocket, streaming,
> OpenAPI, code generation, CLI, TLS/QUIC-specialized entry points, and proxy
> policy do not enter the Phase-1 package. Later features require their own
> phase/ADR and **should prefer optional packages or adapters when feasible.**

A rule that forbids something without naming where it should go instead is only
half a rule. Crystals are a proposal for the other half: small, strictly
optional Odin packages and tools that sit *beside* the framework, so the core
can keep saying no without the ecosystem having nowhere to say yes.

Coming from a language with a mature ecosystem, the missing pieces are obvious
daily: reload-on-save, a query layer, migrations, a CLI. Odin has almost none
of it. That gap is real, and it is worth designing for deliberately rather than
filling by accident, one convenience symbol at a time, inside a frozen core.

## What the idea is not

* **Not a second framework.** No runtime, no daemon, no registry, no lifecycle
  the application does not start and stop itself.
* **Not a plugin system.** Nothing in the proposal has Uruquim discover, load,
  enumerate or initialise a Crystal. The dependency arrow points one way.
* **Not scheduled work.** `planning/roadmap.md` places the ecosystem in
  **Phase 5**, entry condition "Phase 4 frozen; a real user request for each
  item". Phase 3 has not started. [`docs/roadmap.md`](docs/roadmap.md) is
  honest about what could begin sooner and what genuinely cannot.

## Read in this order

**Start here — the open, exploratory half:**

| Document | What it is |
|---|---|
| [`docs/glossary.md`](docs/glossary.md) | The vocabulary, and what it costs to introduce it |
| [`docs/ideas.md`](docs/ideas.md) | The candidate Crystals, including the speculative ones. Deliberately unfiltered |
| [`docs/style.md`](docs/style.md) | The Odin taste a Crystal should have, derived from the project's own idiom guide |
| [`docs/vision.md`](docs/vision.md) | What a day of development should feel like if this works |

**Then the half that has consequences:**

| Document | What it is |
|---|---|
| [`docs/crystal-contract.md`](docs/crystal-contract.md) | What a Crystal may touch and must not, and *why* each rule exists |
| [`docs/adrs.md`](docs/adrs.md) | The decisions, with alternatives, costs and reversibility |
| [`docs/distribution.md`](docs/distribution.md) | Where Crystals live, and how a project consumes them with no package manager |
| [`docs/gate.md`](docs/gate.md) | What evidence would make a Crystal trustworthy |
| [`docs/authoring-a-crystal.md`](docs/authoring-a-crystal.md) | How to write one; the `CRYSTAL.md` template |
| [`docs/first-crystal.md`](docs/first-crystal.md) | Which one to build first, and the argument for it |
| [`docs/implementation.md`](docs/implementation.md) | A concrete plan: CE0–CE2, with entry and exit criteria |
| [`docs/open-questions.md`](docs/open-questions.md) | What is genuinely undecided, and who decides it |

## The one-paragraph version

An application imports `uruquim:web` and whatever Crystals it wants. Each import
is visible in the source. Each Crystal is initialised and destroyed by explicit
calls the application writes. Each one either does not import `uruquim:web` at
all, or uses only its public frozen symbols. Nothing installs itself, nothing
registers itself, and the composition root of a program using ten Crystals is
still a `main :: proc()` you can read top to bottom — because the ecosystem is
designed to make that the easy way, not because anyone is policing it.

## Provenance

The concept and the first architectural draft came from the owner and from an
external planning pass without repository access. That draft was audited
against the tree on 2026-07-20. Its architectural direction survived; the
corrections it needed are recorded in
[`docs/open-questions.md`](docs/open-questions.md) §Prior art so the next reader
does not re-derive them.
