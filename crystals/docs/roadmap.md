# Roadmap — and how it fits the core's phases

**Status: PROPOSED.** The stages below are a shape, not a schedule. No dates,
because there are none.

---

## Sequencing honesty — read this first

`planning/roadmap.md` places the ecosystem in **Phase 5**, with the entry
condition:

> **Entry:** Phase 4 frozen; a real user request for each item.

Phase 3 has not started. Taken literally, none of this begins for a long time,
and the temptation is to quietly reinterpret the roadmap. That temptation should
be resisted, because the roadmap is right about the thing it is protecting:
**the core's attention**. A framework that stops hardening in order to grow an
ecosystem gets a large ecosystem around a weak core.

So the honest position is a distinction rather than a reinterpretation:

* **Writing down the contract costs the core nothing.** These documents can
  exist now, and are cheaper now than after the packages exist.
* **A Tool Crystal costs the core nothing either.** `crystals:dev/watch` never
  imports `uruquim:web` and is not in the server process. It cannot consume core
  scope unless someone decides it should.
* **A Crystal that imports `uruquim:web` should be treated as scope**, because
  it couples to a surface Phase 3 is actively changing — limits, timeouts, route
  representation, application state. Building against a moving surface produces
  rework, and rework is the tax the roadmap is trying to avoid.

That is the trade, stated plainly. It is a decision for the owner and it is
recorded as entry condition CE-E4 in [`implementation.md`](implementation.md),
not assumed here.

**One genuine argument in the other direction:** Phase 5 wants "a real user
request for each item". Those requests have to come from *somewhere*, and a
watcher that has to document its own abrupt termination is exactly such a
request for `web.stop`, written from use rather than from imagination.

---

## The stages

### CE0 — Contract

The documents in this directory, reviewed and amended. No code.

**Done when:** the ADRs are accepted, amended or rejected with reasons, and the
categories survive an attempt to classify every candidate in
[`ideas.md`](ideas.md).

### CE1 — Development loop

`crystals:dev/watch`, plus the repository, collection, gate, `CRYSTAL.md` and
compatibility matrix that it forces into existence.

**Goal:** make daily development pleasant without changing the runtime by a
single byte.

**Done when:** someone other than the author builds a sample project from a
clean checkout with two collection flags and a set of pinned SHAs.

### CE2 — Coupling

`crystals:web/health`, and then the written assessment. The first Crystal that
imports the framework, chosen because it tests the newest claim in the contract
— that a Route Crystal returns a `Router` rather than mutating an `App`.

**Goal:** find out whether the coupling contract is real or merely well-written.

**Gate before CE3:** the four questions in
[`implementation.md`](implementation.md) §review gate. A negative answer stops
the ecosystem rather than expanding it.

### CE3 — Data

Driver, pool, transactions, SQL builder, migrations.

**Blocked** on the core's WP37 for the *canonical example* — not for the code.
The pool and the builder can be developed and tested with no framework
involvement at all. What must wait is the blessed integration pattern, because
teaching package-global state in the interim would outlive the workaround
(ADR-C006).

**Goal:** a real JSON API backed by Postgres, without the user assembling the
entire data layer themselves.

### CE4 — Application

Configuration, validation, authentication primitives, sessions, email.

The layering rule from **G-02** applies to every one of them: the generic
library never learns what a status code is, and a thin adapter is the only place
the two vocabularies meet.

**Goal:** cover recurring needs without the `Context` becoming a service
container — which **G-03** forbids outright and which no Crystal may achieve by
the back door.

### CE5 — Production

Structured logging sinks, metrics, tracing, health, security headers, a
deployment cookbook, fault injection, soak tests.

Mostly **blocked on the core's Phase 4**, which owns graceful shutdown, trusted
proxies and low-cardinality route identity. A tracing Crystal built before route
identity exists would key on raw paths, which the core's own roadmap explicitly
rejects.

### CE6 — Discovery

An index, metadata, badges, agent tooling, more than one maintainer.

**Not before roughly ten Crystals.** Below that a catalogue is a directory
listing with ambition, and a badge that means nothing is worse than no badge —
it converts "unknown" into "endorsed" with no evidence in between.

---

## Dependencies on the core, in one table

| Ecosystem stage | Needs from the core | Available? |
|---|---|---|
| CE0 | nothing | now |
| CE1 | nothing | now |
| CE2 | the frozen Phase-2 surface | now, but it moves in Phase 3 |
| CE3 | `web.state` (WP37) — for the example only | Phase 3 |
| CE4 | a stable error-envelope shape | Phase 3 touches limits |
| CE5 | graceful shutdown, route identity (WP34), trusted proxies | Phase 3–4 |
| CE6 | nothing technical; needs Crystals to exist | — |

Two of these are worth noticing: **most of the ecosystem is not blocked on the
core at all**, and the parts that are, are blocked on things the core is already
planning to build for its own reasons. That is a good sign for the idea. It
would be a bad sign if half this table said "needs a new core symbol".

---

## What would make this roadmap wrong

* **The first two Crystals need a core change.** Then the ecosystem is not
  optional and the contract is wrong somewhere fundamental.
* **Nobody uses the watcher.** Then the ecosystem is solving a problem that was
  interesting rather than felt.
* **Phase 3 breaks CE2 badly.** Then coupled Crystals really must wait for a
  frozen Phase 3, and the sequencing above was too eager.
* **The gate turns out to be unaffordable per Crystal.** Then `dev/ledger` moves
  from speculative to required, and it moves to the front.

Each of these is cheap to detect and expensive to ignore, which is why CE1 and
CE2 are deliberately small.
