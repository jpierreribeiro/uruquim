# Glossary — and what the vocabulary costs

**Status: PROPOSED.** Names are the cheapest thing to change and the most
expensive thing to change *late*. Argue with them now.

## The terms

### Crystal

One optional Odin package or tool that does one thing, has a stated boundary,
and is not required to build or run an Uruquim application.

A Crystal is a *unit of optionality*. The test of whether something is one
Crystal or two: **can a real program want the first without the second?** If
yes, they are two Crystals. A query builder and a Postgres driver are two,
because a program can build SQL it sends somewhere else, and a program can send
hand-written SQL through a pool.

### Druse

**Not a technical artifact. The image of the whole idea.**

A druse is the geological formation where small crystals line the surface or
the interior of a cavity in another rock. The metaphor is exact, and it is the
metaphor that explains the architecture:

* **The rock is the application.** It is the thing being built, and it is the
  only thing that has a shape of its own.
* **The cavity is the space the framework deliberately leaves empty.** Uruquim
  does not fill it — no ORM, no CLI, no config loader, no reload. The emptiness
  is a decision, enforced by G-07, not an omission waiting to be corrected.
* **The crystals are what the developer chooses to line it with**, one at a
  time, visibly, each one optional.

What follows from taking the image seriously: crystals grow *into* the cavity
from its walls. They do not grow into the rock, they do not restructure it, and
removing one leaves the cavity — not a hole in the rock. That is the dependency
direction and the deletability property, stated as a picture instead of a rule.

**An earlier draft of this document made "Druse" a deliverable** — a named,
tested combination with a compatibility matrix and a governance process. That
was a mistake, and an instructive one: it took a metaphor and manufactured an
artifact from it, which is the exact accretion this project exists to refuse.
A combination of Crystals that are known to work together is a **tag on a
repository**. It does not need a word, a document, or a promotion process.

The word stays because it names the philosophy, and philosophy is worth naming.
It buys no mechanism, and it should never be asked to.

### Crystal Tool

A Crystal that is a separate executable and is never linked into the server
binary. A file watcher, a migration runner, a project doctor.

Worth a distinct word because the distinction has teeth: a Tool cannot affect
the server's binary size, hot path, allocation behaviour, or memory
correctness, because it is not in the same process. That makes Tools the
cheapest possible thing to get wrong, which is a real property when the
ecosystem is new.

## Terms deliberately not used

| Word | Why not |
|---|---|
| **Plugin** | Implies the host loads it. Uruquim never loads anything; the application links it. |
| **Extension** | Implies the core has extension points. It has none, and G-03 forbids the obvious one (`Context` as a bag). |
| **Module** | Odin has packages and collections. Inventing a third word for the same thing costs a concept and buys nothing. |
| **Middleware** (for a Crystal) | `Handler`-shaped middleware is a *core* concept with frozen semantics. A Crystal may *ship* middleware; it is not itself middleware. |
| **Gem / Crate / Package** | Borrowed identity from ecosystems with a package manager. Odin has none by design (C-8), and the name would promise resolution and installation that will never exist. |

## The concept-budget question

The core counts concepts, not just symbols. Phase 2 measured a guarded CRUD
service at **23 concepts**, and Phase 3 caps the same lab program at **25**
(`planning/phase-3-plan.md` FINDING-D). That budget is the reason the core can
refuse a feature that is individually reasonable.

**Proposal: Crystal vocabulary never counts against the core budget, and each
Crystal carries a budget of its own.**

The reasoning is that the budget measures *what a developer must hold in their
head to write a guarded CRUD service using the framework*. A developer who
imports no Crystals learns none of these words — that is the entire point of
optionality, and if it were not true the ecosystem would have failed at its one
job. But a developer who *does* import a Crystal pays for its concepts in full,
so the budget does not vanish; it moves and becomes per-Crystal.

A workable form, open to argument:

* **Ecosystem vocabulary** (Crystal, Druse, Crystal Tool) — 3 concepts, paid
  once, by anyone who reads the ecosystem documentation at all.
* **Per-Crystal budget** — each Crystal states, in its `CRYSTAL.md`, how many
  concepts its canonical usage costs, measured the same way the core measures
  its lab program. A Crystal that costs more concepts than the entire core is
  not a Crystal; it is a competing framework.
* **A Druse's budget is the sum of its members'**, with no discount. Bundling
  does not make things simpler to learn; it only makes them arrive together.

What is genuinely unresolved: whether "concepts" is even measurable outside the
core's specific lab program. The core has one instrument and one program. An
ecosystem has neither. See [`open-questions.md`](open-questions.md) Q-4.

## Naming inside a Crystal

Package names are lowercase and short; the import alias at the call site is what
readers actually see, and it should read as a noun that owns the operation:

```odin
import sql   "crystals:sql"
import pg    "crystals:db/postgres"
import watch "crystals:dev/watch"
```

`sql.select(...)`, `pg.open(...)`, `watch.run(...)`. This follows the core's own
package style — packages are libraries, not pseudo-namespaces
(`knowledge-base/02-odin-idioms-guidelines.md` §Package style) — and it means a
reader can tell which Crystal a line came from without leaving the line.
