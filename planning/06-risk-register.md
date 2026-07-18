# 06 — Risk Register

Status: **COMPLETE.** Each risk: probability · impact · early signals ·
mitigation · fallback · resolution phase.

Scale: probability/impact ∈ {Low, Med, High}.

## R-01 · Pinned toolchain / VPS egress blocked
- **Prob** High · **Impact** High (blocks all ratification and WP0/WP8).
- **Signals.** `curl` 403/truncated download; VPS cannot fetch dev-2026-07a,
  the public repository, or the future vendored adapter.
- **Mitigation.** SHA-verified installer with retries; cache a verified
  artifact; vendor odin-http; local pre-push remains authoritative if the VPS
  is temporarily unavailable.
- **Fallback.** perform ratification on a developer machine; commit the runner
  output as evidence; keep the audit/plan (compiler-independent) as the
  deliverable meanwhile.
- **Resolution.** Local compiler and clean-verifier mechanism are proven;
  real VPS provisioning remains WP0 and adapter vendoring remains WP8. A
  truncated archive is rejected before extraction.

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

## R-07 · `#optional_ok` enables silent error-drop (resolved policy)
- **Prob** Med · **Impact** Med (correctness holes in user handlers).
- **Signals.** exp-04 confirms the bool is droppable; reviews find `id :=
  path_int(...)` in the wild.
- **Mitigation.** Accepted ADR-002 drops the directive for HTTP extractors;
  the compiler rejects capturing only one of two results. Examples enforce
  `if !ok`.
- **Fallback.** none needed; a negative compile probe guards the policy.
- **Resolution.** Policy resolved at the Spec Gate; WP5 implements/tests it.

## R-08 · App by-value double-free (accepted invariant)
- **Prob** Low · **Impact** Med.
- **Signals.** exp-01 double-free under `defer destroy`.
- **Mitigation.** exp-01 passed; App is non-copyable by contract, stores no
  pre-return self-pointer, and only the caller-owned original is destroyed.
- **Fallback.** `app_init` form (already designed).
- **Resolution.** WP1 / exp-01.

## R-09 · Docs overpromise `web.app()` defaults (resolved specification)
- **Prob** High (present now) · **Impact** Low-Med (user trust).
- **Signals.** Phase-1 build returns 200 for oversized body / no 405 while docs
  promise 413/405.
- **Mitigation.** Accepted split: Phase 1 fixed 4 MiB cap plus minimal 405 with
  `Allow`; later defaults are phase-marked in normative docs.
- **Fallback.** gate fails if implementation/tests do not match this split.
- **Resolution.** Specification resolved; behavior lands in WP4/WP7.

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

## R-13 · Official JSON rejects pointer payloads (baseline resolved)
- **Prob** High when callers pass pointers · **Impact** Med (unexpected 500 or
  pressure for reflection-heavy behavior).
- **Signals.** exp-02 `^User -> Unsupported_Type`; pinned stdlib rejects
  `runtime.Type_Info_Pointer` except JSON `Null`.
- **Mitigation.** Accepted value-only baseline; canonical/AI docs explicitly
  reject `&value` and pointer-typed payload variables. Marshal failure is
  logged server-side before one complete pre-commit `internal_error`.
- **Fallback.** WP6 prototypes one-level dereference. It is adopted only after
  clean compiler evidence and an approved spec amendment.
- **Resolution.** Baseline resolved at the Spec Gate; ergonomic probe in WP6.

## Heat summary

| Risk | Prob | Impact | Phase |
|---|---|---|---|
| R-01 egress | Med (CI/vendor remains) | High | WP0/WP8 |
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
| R-13 pointer JSON | High when used | Med | WP1/WP6 |

The local R-01 condition and all Phase-1 decision blockers are resolved.
Remaining risks are owned by their implementation work packages or later
phase gates.
