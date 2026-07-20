# The gate — what would make a Crystal trustworthy

**Status: PROPOSED.** A first Crystal does not need all of this. A Crystal
anyone else is told to depend on probably does.

The core's gate is roughly 4,000 lines of bash that runs before every push and
again from a clean commit on a timer. That is not a template to copy; it is a
*method* to copy, and the method is smaller than the implementation.

---

## The method, in five sentences

1. **Derive, never hand-maintain.** The symbol ledger comes from the compiler's
   own export list, not from a list someone edits. A list someone edits is a
   list that drifts.
2. **Every claim carries a negative control.** A test that cannot fail proves
   nothing. For each claim, there must be a deliberate break that turns the
   test red — and the gate must verify the break *does*.
3. **Never claim an adjective.** "Bounded", "safe", "zero-allocation" are not
   claims. State the number and what happens when it is reached.
4. **Examples compile in the gate.** Documentation that does not compile
   teaches an API that does not exist, to humans and agents equally.
5. **Growth carries its evidence in the same change.** Not in a follow-up.

---

## Proposed checks, by Crystal category

| Check | Tool | Library | Service | Request | Route |
|---|:-:|:-:|:-:|:-:|:-:|
| Examples compile on the pinned Odin | ● | ● | ● | ● | ● |
| Declared Uruquim commit builds against it | — | — | — | ● | ● |
| Public symbol inventory, derived from the compiler | ● | ● | ● | ● | ● |
| Direct-import inventory, pinned to a file | ● | ● | ● | ● | ● |
| No import of `uruquim:web/internal/*` | — | — | — | ● | ● |
| No textual access to `.private` | — | — | — | ● | ● |
| Ownership table exists and is complete | ○ | ● | ● | ● | ● |
| Capacity table, with overflow behaviour | ○ | ○ | ● | ○ | ○ |
| Allocation-failure tests | ○ | ● | ● | ● | ● |
| Tested through `web.test_request` | — | — | — | ● | ● |
| Per-request allocation measured | — | — | — | ● | ● |
| Binary-cost claim measured, if made | ○ | ○ | ○ | ○ | ○ |
| `CRYSTAL.md` present and current | ● | ● | ● | ● | ● |
| `docs/ai-context.md` present | ● | ● | ● | ● | ● |

● required ○ if applicable — not applicable

Two of these are worth their own sections because they are traps.

---

## The optionality trap

Every Crystal will want to say "it costs nothing if you do not use it." The
core has measured **two facts that pull in opposite directions**, and a Crystal
that knows only one of them will make a false claim.

**Fact 1 — an import costs, used or not.** WP6 measured `core:log` at
**~37 KiB added to every application, referenced or not**, because Odin links an
imported package regardless of use. This is why `web/logger.odin` imports
nothing at all, why `web.logger` has no latency field, and why WP23's request-ID
generator seeds from ASLR addresses rather than importing `core:time`
(`planning/phase-3-plan.md` FINDING-B).

**Fact 2 — not importing is not sufficient either.** `docs/middleware.md` once
said a program that never calls `use` "does not even link it". Phase 2 measured
that and found it **false**: eight symbols from `middleware.odin` link
unconditionally, because they are reachable from `dispatch` and `destroy`
whether or not you use middleware — by design, since ADR-019 requires the
fail-closed guard to sit on the shared dispatch path. The sentence was corrected
rather than quietly kept (`planning/phase-2-freeze.md`, "Claims examined and NOT
frozen").

**The consequence for the ecosystem is a clean rule:**

> **The unit of optionality is the import, not the symbol.** A Crystal is
> optional because a program does not import it. *Inside* a Crystal, "you do
> not pay for feature X unless you use it" is a separate claim about dead-code
> elimination, and it needs measurement or it must not be made.

The measurement that works, from the core's C-6:

* `nm` the binary of a program that does **not** use the feature → assert zero
  matching symbols.
* `nm` the binary of a program that **does** → assert a non-zero count.

The second half is not optional. Without it, a regex that matches nothing makes
the zero-assertion vacuous, and the test passes forever while proving nothing.

**And never assert a byte-identical binary.** Five builds of an identical,
unmodified tree produced five different binaries and five distinct checksums —
the vendored `nbio` emits polymorphic instantiations whose mangled names vary
between runs (`planning/phase-3-plan.md` FINDING-A). Binary size has a
**~100-byte noise floor**. A gate that fails on a 40-byte regression fails
randomly. Assert symbol counts, allocation counts, or behavioural equivalence —
never a hash.

---

## Proving the dependency arrow

The core already has the mechanism, and a Crystal should copy it rather than
invent one: `build/phase1-direct-dependencies.txt` records `package web`'s five
direct imports, and the gate fails if the set changes. A file, derived, diffed.

For a Request or Route Crystal, the same file plus two textual assertions:

```bash
# no reaching into internals
! grep -rn 'uruquim:web/internal' src/

# no reaching through the public field into private state
! grep -rnE '\.private\b' src/
```

Both are grep, and grep is a blunt instrument — the core's own **G-10** is
explicit that grep heuristics must not be marketed as semantic analysis. These
catch the accident, not the determined author. That is the correct ambition:
the contract is enforced by review and by the fact that internals get rewritten,
not by a script pretending to be a type system.

---

## Timing, if a Crystal ever claims performance

The toolchain's linker is nondeterministic, so code layout is too, and layout
moves branch prediction and cache behaviour. A single "8% faster" measurement
taken once is not evidence. Repeated alternating runs, reported as a
distribution. If a difference is inside the noise, the honest report is that it
is inside the noise.

---

## Trust levels

A gate answers "is this correct". It does not answer "should I depend on this",
which is a different question with a social answer.

| Level | What it means |
|---|---|
| **Experimental** | The idea is being validated. API will change. Not for production. |
| **Incubating** | Real use, examples, ownership documented. API may still change. |
| **Official** | Reviewed, compatibility declared against a commit, API stable within a release, lifecycle audited, maintenance accepted. |
| **Community** | Outside the project. May be listed; carries no guarantee from it. |
| **Deprecated** | Reason, alternative, transition window, last compatible commit. |

Promotion is not by popularity. The evidence is: a real problem, real users, a
small surface, correct ownership and teardown, predictable failure, no
dependency on internals, measured cost, compiling examples, and someone who has
agreed to maintain it.

**The first Crystal will be Experimental for a long time, and that is the
correct answer.** An ecosystem that hands out "Official" before it has learned
what the label costs has devalued it permanently.
