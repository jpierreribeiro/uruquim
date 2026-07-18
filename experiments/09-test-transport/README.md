# Experiment 09 — test-transport

**Question.** Does an in-memory dispatcher give *real behavior tests* for GET
static, path int (valid/invalid), query default (absent/malformed), invalid
body, `ok`, and 404 — using a deliberately **simple, non-radix** dispatcher (the
Phase-1 interim router)?

**Hypothesis.** A `switch`-based exact-match table plus one `:param` route is
enough to exercise the full public *behavior* the contract suite must pin,
without any router optimization. `core:testing` `@(test)` procedures drive it;
each asserts status + envelope code + single commit.

**Command.**
```bash
odin test . -collection:uruquim=../..
```

**Expected result (to verify).** All six tests pass:
- `test_static_ok` — 200 `pong`, one commit
- `test_path_int_valid` — `/users/42` → 200 `42`
- `test_path_int_invalid` — `/users/abc` → 400 `invalid_path_parameter`
- `test_query_default_absent` — `/list` → 200 `20` (default)
- `test_query_malformed` — `/list?limit=banana` → 400 `invalid_query_parameter`
  (**not** silently defaulted — pins the `query_int_or` semantics)
- `test_not_found` — unknown route → 404 `not_found`

**Limitations.** Body-binding is covered in experiment 03; this file focuses on
routing + extractors + envelope + commit. The dispatcher is intentionally
throwaway — Phase 3 replaces it with the radix tree, and *these same behavior
assertions must still pass unchanged* (the regression contract).

**Result.** `NOT_EXECUTED — pending compile on pinned toolchain.`

**Conclusion (pending ratification).** This is the prototype of the **contract
suite**. If it passes, it demonstrates that the public behavior of Phase 1 is
fully testable on the test transport before any real socket exists — the
central claim behind "conformance suite from Phase 1". It also ratifies the
`query_int_or` malformed-vs-absent rule with an executable test.
