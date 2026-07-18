# 08 — Open Questions

Status: **TRACKED.** Critical questions have owner, evidence needed, and a
deadline tied to a gate/WP. Non-critical questions are explicitly deferred.

## Critical (block a WP)

### OQ-1 · Will the pinned toolchain run in CI and dev? (→ C-1, R-01)
- **Owner.** toolchain owner.
- **Evidence.** `run_checks.sh` output on dev-2026-07a; CI able to fetch the
  artifact and vendor odin-http.
- **Deadline.** before WP1.
- **Note.** dominant blocker; today GitHub egress is denied here.

### OQ-2 · Keep or drop `#optional_ok` on extractors? (→ C-2, ADR-002, R-07)
- **Owner.** API owner.
- **Evidence.** exp-04 diagnostic (does the plain-form discard error read
  clearly?).
- **Deadline.** before WP5.
- **Lean.** drop for HTTP extractors (safety over idiom); call sites unchanged.

### OQ-3 · Body-limit + 405 in Phase 1', or defer with AMEND-3? (→ C-5, R-09)
- **Owner.** product owner.
- **Evidence.** scope-review §contested; cost is a body-cap constant in the
  adapter + a 405 branch in the dispatcher (both cheap).
- **Deadline.** before WP4/WP7.
- **Lean.** include both in Phase 1' → removes the A11/A12/A13 contradiction now.

### OQ-4 · `error.field` optional/omitted vs always present? (→ C-6, AMEND-2)
- **Owner.** API owner.
- **Evidence.** audit A10; which errors carry a field.
- **Deadline.** before WP6.
- **Lean.** optional, omitted when absent (never `""`/`null`).

### OQ-5 · `app()` by value confirmed canonical? (→ C-4, ADR-001, R-08)
- **Owner.** API owner.
- **Evidence.** exp-01.
- **Deadline.** before WP1 freeze.
- **Lean.** yes; fallback `app_init(&app)` ready.

### OQ-6 · Nil app-state policy (→ AMEND-1, ADR-004)
- **Owner.** API owner.
- **Evidence.** exp-05.
- **Deadline.** before Phase-3 typed-state WP.
- **Lean.** `app_with_state` rejects nil; `state` asserts registration+type.

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
| OQ-2 | yes | WP5 | before WP5 |
| OQ-3 | yes | WP4/WP7 | before WP4 |
| OQ-4 | yes | WP6 | before WP6 |
| OQ-5 | yes | WP1 freeze | before WP1 |
| OQ-6 | yes | P3 typed-state | before P3 |
| OQ-7..13 | no | — | deferred |
