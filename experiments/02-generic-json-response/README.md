# Experiment 02 — generic-json-response

**Question.** Can `json(ctx, status, value: $T)` serialize structs, pointers to
structs, slices and large nested values via `core:encoding/json`? Do `ok` and
`created` delegate to `json` exactly once with a fixed status and no extra
behavior? What does the official marshaller reject?

**Hypothesis.** `json.marshal(value, allocator)` accepts `any`, so a parametric
`$T` wrapper compiles and covers value, pointer, and slice inputs. `ok`/
`created` are one-line delegations, so `commit_count == 1` after each. `any` is
used only *inside* the renderer as an encapsulated stdlib detail — never as
framework storage or public API.

**Command.**
```bash
odin run . -collection:uruquim=../..
odin check .
```

**Expected result (to verify).**
- Compiles clean; three prints show valid JSON bodies.
- `commit_count == 1` for `ok`, `created`, and `json`.
- Pointer input (`&u`) marshals identically to the value (marshaller
  dereferences) — confirms handlers may pass either.
- Intentional-failure probe (uncomment the `proc` value): `json.marshal`
  returns an error, exercising the pre-commit error path. Recorded separately
  as an **intended failure**.

**Limitations.** Uses `temp_allocator` for the marshalled bytes; real ownership
(request arena vs temp) is decided in experiments 03/06, not here. Says nothing
about streaming large bodies.

**Result.** `NOT_EXECUTED — pending compile on pinned toolchain.`

**Conclusion (pending ratification).** If expectations hold, ADR-003 (response
by value/pointer via `$T`) and the `ok`/`created` exact-shorthand contract are
supported and freezable. The decisive negative evidence would be either (a) the
parametric wrapper failing to pass `$T` to `any` cleanly, or (b) `ok`/`created`
needing more than one statement — either would reopen the response API.
