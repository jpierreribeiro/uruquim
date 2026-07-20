# Authoring a Crystal

**Status: PROPOSED, and deliberately short.** The first two Crystals will teach
more about what this document needs than any amount of writing it in advance.
Treat it as a starting shape, not a specification.

---

## Before writing any code, answer four questions

**1. Can a real program want this without the rest of what I am planning?**
If yes, that is one Crystal and the rest is another. This is the only reliable
test for where the boundary goes.

**2. Which category is it?** From [`crystal-contract.md`](crystal-contract.md)
§1: can it run out of process (**Tool**)? If not — does it import
`uruquim:web`, and does it own memory that outlives a request? Those two answers
give **Library**, **Service**, **Request** or **Route**, and the category
determines the obligations.

If the answer is "two categories", it is two Crystals. **G-02** already requires
the split for anything that mixes domain logic with HTTP.

**3. What does it own, and who frees it?** Write the ownership table before the
code. If it is hard to write, the design is not finished — that is the table
doing its job.

**4. What claim am I going to want to make, and can I measure it?** "Fast",
"bounded", "zero-allocation", "costs nothing when unused" are all claims that
need numbers. Decide now whether you will do the measurement or drop the claim.
Both are fine. Claiming without measuring is not.

---

## Directory shape

```text
crystals/dev/watch/
├── CRYSTAL.md              the contract (below)
├── README.md               what it is, in a paragraph
├── docs/
│   ├── quick-start.md
│   └── ai-context.md       compact, canonical, closed
├── examples/               compiled by the gate
├── tests/
└── *.odin
```

`docs/ai-context.md` is not optional and not a nicety. The core's version opens
with *"if something is not listed here, it does not exist"* and the gate checks
it against the compiler's export list. An agent given five Crystals and no such
document will invent procedures, and the invented ones will look plausible.

---

## The `CRYSTAL.md` template

Each heading exists because omitting it caused a problem somewhere. Delete a
section only if you can say why it does not apply.

```markdown
# <name>

**Category.** Tool | Library | Service | Request | Route
**Status.** Experimental | Incubating | Official | Deprecated

## Purpose
One paragraph. What problem, for whom.

## Non-goals
What it deliberately does not do, and where that lives instead.
Longer than you expect. This is the section that prevents scope creep.

## Compatibility
Odin release / commit / asset SHA
Uruquim commit + phase (or "does not import uruquim:web")
Platforms actually tested — not platforms assumed to work

## Direct imports
The complete list, pinned to a file the gate diffs.

## Public surface
Every exported symbol with its signature. Derived from the compiler,
not hand-maintained.

## Ownership and lifetimes
For each value crossing the boundary:
  who creates it | who owns it | valid until | who destroys it |
  may it be copied | may it escape

## Allocator behaviour
Which allocator, for which lifetime. Whether context.allocator is read
or replaced. What happens when an allocation fails.

## Threading
Safe to share across threads? Must init complete before concurrency?
What happens under simultaneous use?

## Hot-path operations   (Request and Route only)
What runs per request. Allocations per request, measured.
What was moved to init so it would not run here.

## Failure model
The typed error enum, each member's meaning, and what the caller is
expected to do. No HTTP status codes unless this is a web adapter.

## Capacity
Every bound, its number, and WHAT HAPPENS WHEN IT IS REACHED:
block, reject, drop, replace, or grow.

## Teardown
What destroy releases, whether it is idempotent, whether it is safe
after a failed init, and what order it must run in relative to
web.destroy.

## Measured claims
Each claim, its number, how it was measured, and its negative control.
Claims without all three do not go here.

## Examples
Paths to compiled examples. Not inline code that has never been built.

## Gate
The exact command that verifies all of the above.
```

---

## Common mistakes, in the order people make them

**Storing a request view.** The single most likely bug. Path, query, headers,
params, body and every arena-decoded string die with the request (**G-05**).
Copy explicitly or do not keep it. The failure will not reproduce under light
load, which is the worst property a bug can have.

**Calling `web.observe`.** One slot, last wins, silent replacement
(`web/observer.odin`). Export the observer procedure and let the application
install it (ADR-C004).

**Writing `install(&app)`.** It cannot know whether `use` is still legal, and
guessing wrong poisons the whole application fail-closed (ADR-019, ADR-C003).
Return a `web.Router` instead.

**Answering HTTP for a domain failure.** A database Crystal returns
`Not_Found`; the application decides that means 404. The first time someone needs
`409` instead of `400` for one constraint, they will have to fight you.

**Reading configuration at import time.** Odin package initialisation is not a
place to read the environment. Read config in an explicit `init` the application
calls, so it is visible and testable.

**Claiming "costs nothing when unused" without measuring.** Harder than it
looks in both directions — see [`gate.md`](gate.md) §The optionality trap.

**Making `close` unsafe after a failed `open`.** It breaks the
`defer`-immediately pattern, which is the pattern everyone will use because the
core teaches it.

---

## Documentation tone

Match the core's, because a reader moving between them should not have to
recalibrate:

* State what is **not** guaranteed as prominently as what is.
* Record the alternative you rejected, and why. That is the part the next reader
  needs; the signature is already in the code.
* When a sentence turns out to be false, **correct it and say that you did**.
  The core does this in public (`planning/phase-2-freeze.md`, "Claims examined
  and NOT frozen"), and it is the single habit that makes the rest of the
  documentation worth trusting.
