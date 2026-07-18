# Experiment 06 — request-views

**Question.** Can `Request` expose `method/path/query/headers/body` as **views**
(strings/slices aliasing a mutable transport buffer)? Can we *demonstrate*
invalidation when the buffer is reused, and support explicit persistent copies
via a chosen allocator?

**Hypothesis.** Odin `string`/`[]byte` are pointer+len views; slicing `buf`
yields aliases with zero copy. Overwriting `buf` (simulating the transport
reusing its buffer for the next request) corrupts the views — visible proof of
the request-lifetime rule. `strings.clone(view, allocator)` produces an
independent copy that survives the reuse.

**Command.**
```bash
odin run . -collection:uruquim=../..
odin check .
```

**Expected result (to verify).**
- Compiles clean; first line shows correct `method/path/query/body`.
- After clobbering `buf` with `#`, the aliased `req.path` prints garbage
  (`######`), while `saved` still prints `/users`.
- This is the normative rule made physical: *do not retain request-derived
  views past the request; copy explicitly to persist.*

**Limitations.** The parser is a toy; real header/body parsing belongs to the
transport (experiment 08 / WP2). The buffer reuse is simulated manually rather
than driven by an event loop.

**Result.** `NOT_EXECUTED — pending compile on pinned toolchain.`

**Conclusion (pending ratification).** Supports ADR-007 (request vs temp
allocator) and the `Request` view design: framework-owned *abstraction*,
transport-owned *storage*, request-scoped validity, explicit copy to persist.
Decisive negative: if views could not be sliced without copying, or if the
clone did not survive reuse, the ownership model would need rework before WP2.
