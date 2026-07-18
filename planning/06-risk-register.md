# 06 — Risk Register

Status: **COMPLETE.** Each risk: probability · impact · early signals ·
mitigation · fallback · resolution phase.

Scale: probability/impact ∈ {Low, Med, High}.

## R-01 · Pinned toolchain / vendor egress blocked
- **Prob** High · **Impact** High (blocks all ratification and WP0/WP8).
- **Signals.** `curl` 403 from GitHub (already observed); CI cannot fetch
  dev-2026-07a or laytan/odin-http.
- **Mitigation.** obtain the toolchain where GitHub egress is allowed; cache the
  artifact and vendor odin-http into the repo; run `run_checks.sh` there.
- **Fallback.** perform ratification on a developer machine; commit the runner
  output as evidence; keep the audit/plan (compiler-independent) as the
  deliverable meanwhile.
- **Resolution.** WP0 (before WP1). **This is the gate's primary blocker.**

## R-02 · odin-http is beta / API-unstable
- **Prob** Med · **Impact** Med (WP8 churn).
- **Signals.** compile breaks against the vendored version; routing/pattern
  differences.
- **Mitigation.** confine to the adapter; pin the exact odin-http commit;
  conformance suite (WP9) catches behavior drift.
- **Fallback.** the test transport proves the core with no odin-http at all;
  ship Phase 1' on the test transport if the adapter slips.
- **Resolution.** WP8.

## R-03 · `core:net/http` never arrives / arrives with a hostile model
- **Prob** Med · **Impact** Med (Phase 5, not Phase 1).
- **Signals.** no release; an API that forces async handlers or backend types.
- **Mitigation.** conceptual boundary + conformance suite already isolate this;
  handler API stays synchronous from the app view.
- **Fallback.** odin-http (or a core:net adapter) remains the backend
  indefinitely; migration stays optional.
- **Resolution.** Phase 5.

## R-04 · Request/Response ownership wrong (dangling views)
- **Prob** Med · **Impact** High (memory bugs).
- **Signals.** exp-06 shows a retained view surviving; sanitizer/UB in tests.
- **Mitigation.** view-invalidation test in WP2; normative "copy to persist";
  request arena freed once.
- **Fallback.** copy request fields up front (perf cost) if views prove unsafe.
- **Resolution.** WP2 / exp-06.

## R-05 · Response committed before an error is known
- **Prob** Med · **Impact** Med (garbled responses).
- **Signals.** marshal error after headers written; double-commit in tests.
- **Mitigation.** single-commit guard (exp-08); render into a buffer, commit
  once, errors resolved pre-commit.
- **Fallback.** for streaming (future) define a separate contract.
- **Resolution.** WP6 / exp-08.

## R-06 · `json.unmarshal` ignores the substituted allocator for nested data
- **Prob** Low · **Impact** Med (leaks / wrong lifetime).
- **Signals.** exp-03 `arena.offset == 0` after a nested bind; leaks under
  tracking allocator.
- **Mitigation.** verify in exp-03; if true, copy nested strings into the arena
  post-unmarshal.
- **Fallback.** WP7 adds an explicit copy pass.
- **Resolution.** WP7 / exp-03.

## R-07 · `#optional_ok` enables silent error-drop (ADR-002 unresolved)
- **Prob** Med · **Impact** Med (correctness holes in user handlers).
- **Signals.** exp-04 confirms the bool is droppable; reviews find `id :=
  path_int(...)` in the wild.
- **Mitigation.** ADR-002 decision (lean: drop the directive for HTTP
  extractors); examples/lint enforce `if !ok`.
- **Fallback.** keep directive + a vet rule.
- **Resolution.** WP5 (needs the human decision at the gate).

## R-08 · App by-value double-free (ADR-001 unresolved)
- **Prob** Low · **Impact** Med.
- **Signals.** exp-01 double-free under `defer destroy`.
- **Mitigation.** exp-01; if it fails, canonical switches to `app_init(&app)`.
- **Fallback.** `app_init` form (already designed).
- **Resolution.** WP1 / exp-01.

## R-09 · Docs overpromise `web.app()` defaults (audit A11/A12/A13)
- **Prob** High (present now) · **Impact** Low-Med (user trust).
- **Signals.** Phase-1 build returns 200 for oversized body / no 405 while docs
  promise 413/405.
- **Mitigation.** scope-review decision (include body-cap + minimal 405 in
  Phase 1') OR AMEND-3 wording.
- **Fallback.** AMEND-3 documentation note.
- **Resolution.** WP4/WP7 + doc edit (WP10).

## R-10 · Contract vs conformance suite divergence (test transport lies)
- **Prob** Low · **Impact** High (green tests, broken sockets).
- **Signals.** behavior differs between test transport and odin-http.
- **Mitigation.** conformance suite from Phase 1 (WP9); a small e2e suite over a
  real socket.
- **Fallback.** expand e2e coverage.
- **Resolution.** WP9.

## R-11 · Freeze-discipline violation (freezing un-ratified signatures)
- **Prob** Med · **Impact** Med (spec decouples from language).
- **Signals.** a signature marked frozen with no executed experiment.
- **Mitigation.** WP11 computes the gate from *executed* runner output only.
- **Fallback.** un-freeze pre-1.0.
- **Resolution.** WP11.

## R-12 · Scope creep into Phase 1 (middleware/radix/typed-state)
- **Prob** Med · **Impact** Med (delays the slice).
- **Signals.** PRs adding `use`/groups/radix under Phase 1.
- **Mitigation.** scope-review categories; gate rejects category-2/4 items.
- **Fallback.** move work to its phase branch.
- **Resolution.** ongoing; enforced at WP11.

## Heat summary

| Risk | Prob | Impact | Phase |
|---|---|---|---|
| R-01 egress | High | High | WP0 |
| R-04 ownership | Med | High | WP2 |
| R-10 suite divergence | Low | High | WP9 |
| R-02 odin-http beta | Med | Med | WP8 |
| R-05 commit ordering | Med | Med | WP6 |
| R-07 optional_ok | Med | Med | WP5 |
| R-09 doc overpromise | High | Low-Med | WP4/7/10 |
| R-03 net/http | Med | Med | P5 |
| R-06 unmarshal alloc | Low | Med | WP7 |
| R-08 app double-free | Low | Med | WP1 |
| R-11 freeze violation | Med | Med | WP11 |
| R-12 scope creep | Med | Med | WP11 |

**R-01 is the dominant risk** and is the concrete reason the gate cannot read
plain READY from this environment.
