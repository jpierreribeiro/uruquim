# 08 — Open Questions

Status: **PHASE-1 CRITICAL QUESTIONS RESOLVED.** Human decisions on 2026-07-18
closed OQ-2, OQ-3, OQ-4, OQ-5, OQ-6, and OQ-14. Remaining questions are
implementation checks or owned by later phases.

## Critical (block a WP)

### OQ-1 · Will the pinned toolchain run locally and on the VPS? (→ C-1, R-01)
- **Owner.** toolchain owner.
- **Evidence.** Local dev execution on `dev-2026-07-nightly:819fdc7` is complete:
  first run 5/9, corrected second run 9/9, and the extended handler suite
  10/10. VPS provisioning and odin-http vendoring remain WP0/WP8 concerns,
  not signature-ratification unknowns.
- **Deadline.** before WP1.
- **Note.** local toolchain aspect closed; clean VPS repetition remains.

### OQ-2 · RESOLVED — drop `#optional_ok` on HTTP extractors
- **Owner.** API owner.
- **Evidence.** exp-04 diagnostic (does the plain-form discard error read
  clearly?).
- **Deadline.** before WP5.
- **Decision.** drop it; the compiler-enforced result count is the safety
  guarantee. Call sites remain `(value, ok)`.

### OQ-3 · RESOLVED — fixed body cap + minimal 405 in Phase 1'
- **Owner.** product owner.
- **Evidence.** scope-review §contested; cost is a body-cap constant in the
  adapter + a 405 branch in the dispatcher (both cheap).
- **Deadline.** before WP4/WP7.
- **Decision.** fixed 4 MiB cap and minimal 405 with required `Allow` header.
  Configurable limits and timeouts remain Phase 3.

### OQ-4 · RESOLVED — `error.field` optional and omitted
- **Owner.** API owner.
- **Evidence.** audit A10; which errors carry a field.
- **Deadline.** before WP6.
- **Decision.** optional, omitted when absent (never `""`/`null`).

### OQ-5 · RESOLVED — `app()` by value is canonical
- **Owner.** API owner.
- **Evidence.** exp-01.
- **Deadline.** before WP1 freeze.
- **Decision.** yes, with no self-pointer before return and no copying or
  destroying copies. `app_init` remains future Advanced API.

### OQ-6 · RESOLVED — nil/wrong app-state is programmer error
- **Owner.** API owner.
- **Evidence.** exp-05.
- **Deadline.** before Phase-3 typed-state WP.
- **Decision.** `app_with_state` rejects nil; `state` asserts registration and
  exact type. This remains future Phase-3/Advanced scope.

### OQ-14 · RESOLVED BASELINE — Phase-1 JSON payloads are values
- **Owner.** API owner.
- **Evidence.** exp-02: `User`/`Big` values marshal; `^User` and proc values
  return `Unsupported_Type` on commit `819fdc7`; stdlib source explicitly
  rejects `runtime.Type_Info_Pointer` except its JSON `Null` sentinel.
- **Deadline.** before WP1 response signature freeze / WP6.
- **Decision.** canonical payloads are values. Docs explicitly reject
  `&value` and pointer-typed variables. Marshal rejection must be logged on
  the server before one complete pre-commit `internal_error`.
- **Non-blocking WP6 follow-up.** Prototype one-level pointer dereference. If
  clean, propose a spec amendment; if not, keep value-only.

## Non-critical (deferred, no WP blocked)

### OQ-7 · Onion vs pre-order middleware
Deferred to the **Phase-2 gate** (ADR-005). Evidence exp-07 gathered; no
Phase-1 impact.

### OQ-8 · Threading model of handlers
Deferred until the official `core:net/http` adapter exists. Handler API stays
synchronous from the app view regardless.

### OQ-9 · Path *string* extractor: empty vs missing
`path_int` is covered (exp-09). The empty-vs-missing semantics of a raw
`path(ctx,name) -> string` needs one test in WP5; low risk. Deferred to WP5
detail, not a gate blocker.

### OQ-10 · Configurable body limit / timeouts (Advanced API)
Phase-3/Advanced. Phase 1' at most ships a fixed cap (OQ-3).

### OQ-11 · Validation story (tags vs explicit vs codegen)
Deferred, prototype-gated, never a mandatory generator. Not Phase 1.

### OQ-12 · OpenAPI surface (`Route_Info`)
Phase 5 optional layer. Not Phase 1.

### OQ-13 · Collection name (`uruquim:web`) final?
Chosen; confirm in WP0. Trivial to change before 1.0.

## Routing table

| OQ | Critical? | Blocks | Due |
|---|---|---|---|
| OQ-1 | yes | all WPs | before WP1 |
| OQ-2 | resolved | — | accepted 2026-07-18 |
| OQ-3 | resolved | — | accepted 2026-07-18 |
| OQ-4 | resolved | — | accepted 2026-07-18 |
| OQ-5 | resolved | — | accepted 2026-07-18 |
| OQ-6 | resolved/deferred | P3 implementation only | accepted policy |
| OQ-14 | resolved baseline | WP6 ergonomic probe only | accepted baseline |
| OQ-7..13 | no | — | deferred |
