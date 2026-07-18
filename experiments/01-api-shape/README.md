# Experiment 01 — api-shape

**Question.** Can the canonical `app := web.app()` return an `App` by value and
then be used via `&app` for route registration and `serve`, without accidental
copies, with a stable address for the operating lifetime? How does it compare
with an explicit `app_init(&app)` (Advanced API) form?

**Hypothesis.** Returning a struct by value is fine in Odin; the caller's
`&app` is the stable operating address. Any address captured *inside* `app()`
before the return (`self_addr`) refers to the returning frame's local and is
**not** the caller's address — so the framework must never persist a
self-pointer captured before return. Registration and serve that take `^App`
operate on caller storage and see no copies.

**Command.**
```bash
odin run . -collection:uruquim=../..     # or: odin build . && ./api_shape
odin check .
```

**Expected result (to verify).**
- Compiles clean.
- `caller app addr` stays equal across `get`/`post`/`serve` calls (same `%p`
  printed by `serve`).
- `app.self_addr` (recorded inside `app()`) differs from `&app_val` — evidence
  for the "never persist a pre-return self pointer" rule.
- The `dynamic` array survives the by-value return because its backing pointer
  is copied, not the elements (Odin `[dynamic]T` is a small header; copying the
  header aliases the same backing store — `destroy` must run exactly once).

**Limitations.** Address stability of a `defer`-destroyed value is what we test;
this says nothing about heap arenas (experiment 06) or transport lifetime
(experiment 08). The `self_addr` trick is diagnostic only.

**Result.** `NOT_EXECUTED — pending compile on pinned toolchain (dev-2026-07a).`
Baseline: compiler unavailable in the authoring environment
(`planning/01-toolchain-baseline.md`).

**Conclusion (pending ratification).** If the expectations hold, ADR-001 (App
by value) is supported and `web.app()` / `web.destroy(&app)` can be frozen. A
single subtlety must be captured in docs: **do not store a self-pointer taken
before `app()` returns.** If instead a copy of the `[dynamic]` header caused a
double-free under `defer destroy`, that would push toward the `app_init(&app)`
form as canonical — the decisive evidence the runner must produce.
