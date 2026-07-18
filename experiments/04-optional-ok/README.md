# Experiment 04 — optional-ok

**Question.** Is `#optional_ok` valid on the value-producing extractor
(`-> (value: int, ok: bool)`)? Can the `ok` be discarded (single-result call)?
What diagnostic does the compiler give? How does it compare with the plain
two-result form that lacks the directive — and what is the risk that a human or
LLM silently drops the bool?

**Hypothesis.** `#optional_ok` is legal for a proc whose two results end in
`bool`. With it, `id := path_int(ctx,"id")` compiles (bool discarded); without
it, discarding is a compile error. The canonical HTTP rule remains "always
check `ok`", precisely because `#optional_ok` makes silent-drop *possible*.

**Command.**
```bash
odin run . -collection:uruquim=../..
odin check .
```

**Expected result (to verify).**
- Compiles clean; `checked`, `discarded`, and `missing` lines print.
- `discarded` line proves the bool can be dropped under `#optional_ok`.
- Intended-failure probe: uncomment the plain-form discard
  (`p := query_int_plain(...)`) → compile error ("2 values, expected 1" or
  similar). Recorded as an **intended failure** with the exact diagnostic.

**Limitations.** This measures compiler behavior, not human behavior. The
"LLM/human risk" is a design judgment informed by the fact that `#optional_ok`
*permits* silent drop; the experiment can only confirm the mechanism, not the
misuse rate.

**Result.** `NOT_EXECUTED — pending compile on pinned toolchain.`

**Conclusion (pending ratification).** Two defensible outcomes for ADR-002:
1. Keep `#optional_ok` (matches stdlib idiom like `map[k]`), and rely on the
   canonical `if !ok { return }` pattern + lint/example discipline.
2. Drop `#optional_ok` so the compiler *forces* handling the bool, trading a
   little idiom for a hard guarantee against silent drop.
The runner's diagnostic text is the evidence that decides which is recommended.
Either way the *call-site* canonical form is unchanged.
