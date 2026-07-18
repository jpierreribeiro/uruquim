# Experiment 05 — typed-state

**Question.** For application state, compare **(A)** a `rawptr + typeid` stored
on `App` and read through an asserted `state(ctx, T)` accessor, vs **(B)** a
parametric `App(S)/Context(S)` that is type-closed by construction. Behavior
across: correct type, wrong type, `nil` state, and state lifetime.

**Hypothesis.**
- A: compiles; correct type returns a usable `^App_State` aliasing the caller's
  object (mutation visible on the original → same lifetime). Wrong type trips
  the `assert` at runtime. `nil` is the sharp edge — must be rejected at
  registration or checked in the accessor.
- B: correct case needs no runtime check (wrong type is a **compile** error),
  but every call site shows `App_State` type arguments — the generic noise the
  canonical API is trying to avoid.

**Command.**
```bash
odin run . -collection:uruquim=../..
odin check .
```

**Expected result (to verify).**
- Both A and B compile and print the correct `db="primary"`.
- A: `st.hits` becomes 1 after the handler mutates through the accessor →
  confirms shared lifetime (no copy).
- A wrong-type probe (uncomment): assertion fires with the spec's message.
- B: attempting a wrong-type call cannot even be written (compile error).

**Limitations.** `nil`-state handling is discussed, not fully exercised (deref
of nil is UB and would crash the run). The decision on where the nil-guard
lives is a design output, not a measurement.

**Result.** `NOT_EXECUTED — pending compile on pinned toolchain.`

**Conclusion (pending ratification).** This is the evidence for ADR-004.
Expected recommendation: **A for the canonical API** (single sanctioned
`rawptr+typeid`, zero generic noise at call sites, one asserted boundary),
with **B reserved for the Advanced typed-context** where users opt into the
type parameters. The nil rule (`app_with_state` rejects nil; `state` asserts
registration happened) must be frozen alongside the signature. Decisive
negative: if the `assert` cannot see `typeid` equality reliably, or if A's
`cast(^T)` misbehaves, the canonical accessor reopens.
