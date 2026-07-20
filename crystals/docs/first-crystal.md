# The first Crystal

**Status: RECOMMENDATION with the reasoning exposed.** The owner decides. This
document exists so the decision is made against an argument rather than against
an intuition.

---

## What the first Crystal is actually for

Not "the most useful package". The first one's job is to **find out whether the
idea works** — whether a package can be genuinely optional, genuinely
gate-able, and genuinely distributable in a language with no package manager,
without the core noticing it exists.

That reframes the choice. The first Crystal should maximise *what we learn per
unit of risk*, and the risk that matters is risk to the core, because the core
is the asset. Everything else is replaceable.

## The selection criteria, in priority order

1. **Blast radius on the core: as close to zero as possible.** The first
   experiment should not be able to damage the thing it is testing.
2. **Buildable today.** A first Crystal that waits for WP37 is a first Crystal
   that waits for most of Phase 3. Momentum matters for an idea that is still
   being judged.
3. **Genuinely wanted, daily.** If nobody reaches for it, it proves the
   machinery and nothing about the value.
4. **A real ownership and failure story.** Something with actual resources to
   manage, so the ownership table is load-bearing and not a formality.
5. **Exercises the machinery under test:** repository layout, the collection
   flag, the gate, `CRYSTAL.md`, the compatibility matrix.

## The recommendation

### First: `crystals:dev/watch` — reload on save

A Tool Crystal. A separate executable that watches files, debounces, runs the
real `odin build`, keeps the previous process alive when the build fails, and
restarts the server when it passes.

**Why it wins on criterion 1, decisively.** It never imports `uruquim:web`. It
is not in the server process. It cannot enter the request path, cannot touch the
frozen surface, cannot affect binary size, cannot allocate in a hot path,
cannot leak a request view. Its blast radius on the core is not "small" — it is
*structurally none*. For a first experiment whose real subject is the
machinery, that means the variable under test is the machinery and nothing else.

**Criterion 2:** buildable today, against Phase 2, with no core change at all.

**Criterion 3:** it is the thing most conspicuously missing when arriving from a
mature ecosystem, and the owner named it first.

**Criterion 4 is the surprise, and it is why this is not a trivial choice.** A
supervisor has a real and slightly nasty lifecycle: child processes, signal
handling, file descriptors, a debounce window that must not drop the last
event, and a build that can fail while a previous server is still serving. It
also collides with a genuine gap: **the core has no graceful shutdown until
Phase 4** (`README.md`, "Not yet"). So a restarting watcher cuts in-flight
requests with no deadline, and the honest `CRYSTAL.md` has to say so.

That collision is a feature of the choice. It forces the "state the perimeter,
never the adjective" discipline on the very first artifact, and it produces
exactly the evidence Phase 4 wants — Phase 5's entry condition is *"a real user
request for each item"*, and a watcher that must document its own abrupt
termination is a real user request for `web.stop`, written down, from use.

**What it deliberately does not attempt:** in-process reload via
`core:dynlib`. Uruquim stores procedure values in route tables and middleware
chains, and live requests hold slices into those chains. Swapping a library
under that needs quiescence, generation counting, in-flight accounting and a
stable ABI — four features nobody asked for, to avoid one process restart. If
anyone ever builds it, it gets a different name, because calling both things
"hot reload" would hide a very large difference in semantics.

### Immediately after: one small coupled Crystal

`dev/watch` proves distribution, gate and tooling. It proves **nothing about
the coupling contract**, because it never touches `uruquim:web`. Half the idea
would still be untested, and the half with all the danger in it.

So the second one should be the smallest thing that imports the framework and
still has to make a real claim. Two candidates:

* **`crystals:web/secure`** — security headers. A stateless `Handler`. Exercises
  the `Handler` shape, middleware ordering, `test_request`-based testing, and
  the per-request allocation measurement, in roughly forty lines.
* **`crystals:web/health`** — a health endpoint. Exercises the Route Crystal
  shape: build a detached `web.Router`, `use` inside it, hand it back for the
  application to `mount`. This is the pattern
  [`crystal-contract.md`](crystal-contract.md) §3 recommends, and it is the one
  that most needs to be proven in code rather than in prose.

**Recommend `web/health`**, because the Router-returning shape is the newest and
least-tested claim in the whole contract, and a security-headers middleware is
so simple that it would validate almost nothing.

Two Crystals, both small, and between them every category property is exercised
except app-lived state — which is blocked on WP37 and should stay blocked.

## What is explicitly not first, and why

| Candidate | Why not first |
|---|---|
| **Postgres pool** | The pool builds fine; the *canonical example* needs `web.state` (WP37), and teaching package-global state as the interim pattern would outlive the workaround. Build it in Tier 3, on purpose. |
| **SQL builder** | Zero risk, but large, and it tests the machinery no better than the watcher while costing ten times the effort. |
| **`dev/ledger`** (the gate as a reusable tool) | The most valuable idea on the list, and textbook premature abstraction if built first. Let two Crystals hand-roll their gates, let the duplication become obvious, then extract from working code. |
| **`dev/context`** (AI context bundle) | Genuinely novel and very much in this project's character — but it is meta. It produces no runtime value, and choosing it first would be choosing the clever thing over the useful one. |
| **Anything with a native dependency** | Adds a second failure mode (linking, platform) to an experiment that already has enough variables. |

## How we will know the idea worked

Stated in advance, so it cannot be graded on a curve afterwards:

* Two Crystals exist, each with a `CRYSTAL.md`, compiling examples and a gate
  that runs.
* A sample application consumes both with two `-collection:` flags and a
  recorded set of pinned SHAs, and someone other than the author builds it from
  a clean checkout.
* **The core repository has zero commits caused by the Crystals** — no new
  symbol, no widened surface, no "just this once" export. This is the real
  test. If the ecosystem cannot exist without the core bending, the ecosystem
  was a way of smuggling features into a frozen framework, and the honest
  response is to stop.
* The compatibility matrix caught at least one real drift — a toolchain bump or
  a core commit — rather than being decorative.

## How we will know it did not

* The first Crystal wants a core symbol that does not exist, and the discussion
  is about adding it.
* The `CRYSTAL.md` for a forty-line middleware is longer than the middleware,
  and nobody reads it.
* Two Crystals cannot coexist without the application knowing an ordering rule
  nobody wrote down.
* The gate is copy-pasted between Crystals and starts to drift within two
  Crystals, meaning the method does not survive duplication and `dev/ledger`
  was needed earlier than argued.

Any of these is worth a written finding, not a workaround.
