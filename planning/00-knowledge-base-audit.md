# 00 — Knowledge Base Audit

Status: **COMPLETE; AMENDMENTS ACCEPTED AND APPLIED 2026-07-18.** The original
matrix is preserved as historical audit evidence. AMEND-1 through AMEND-4
were accepted by the human owner and applied to the normative knowledge base
and docs; exact application is recorded below.

Post-audit note: the matrix preserves the state at the end of the original
uncompiled audit. C-1 has since executed on commit `819fdc7`; current compile
states and both runner passes are authoritative in
`planning/07-spec-gate-phase-1.md` and
`planning/10-c1-execution-evidence.md`. Do not read the historical
`UNVALIDATED` rows below as the current gate state.

## Method

Each normative decision, proposed public signature, default promise, and phase
requirement is one auditable row. Documents are compared under the stated
hierarchy: `01-architecture-spec.md` wins over `02-odin-idioms` over the docs;
`docs/canonical-patterns.md` is normative for canonical forms; `ai-context.md`
must match the public API.

Status vocabulary: **CONSISTENT**, **AMBIGUOUS**, **CONTRADICTORY**,
**PREMATURE**, **UNVALIDATED**, **MISSING**, **READY_FOR_GATE**.

At original audit time the pinned toolchain was unreachable, so rows whose
only gap was compilation were marked `UNVALIDATED`. They are intentionally not
rewritten in place; the post-audit ledger records what subsequently passed,
failed, was corrected, or remains a human decision.

## Audit matrix

| # | Decision / signature | Source | Status | Evidence | Risk | Action |
|---|---|---|---|---|---|---|
| A1 | `app()` returns App by value; `destroy(&app)` | spec §Application L170-193 | UNVALIDATED | signature in spec; no compile | double-free of `[dynamic]` header on by-value return | exp-01 ratify; ADR-001 |
| A2 | `json(ctx,status,$T)` single renderer | spec §Response L… | UNVALIDATED | `$T`→`any` unverified | marshaller rejects some `$T` | exp-02; ADR-003 |
| A3 | `ok`/`created` exact shorthands of `json` | spec + canonical-patterns L… | CONSISTENT | both docs state exact equivalence | drift if reimplemented | exp-02 asserts commit==1 |
| A4 | `body(ctx, &dst) -> bool` | spec §Extractors | UNVALIDATED | `json.unmarshal(^$T,alloc)` unverified | nested alloc not honoring substituted allocator | exp-03; ADR-006 |
| A5 | value extractors use `#optional_ok` | spec §Extractor Control Flow | UNVALIDATED | directive legality unverified | silent bool-drop by human/LLM | exp-04; ADR-002 |
| A6 | `state(ctx,T)` rawptr+typeid | spec §App state L785-799 | UNVALIDATED | assert/cast unverified; nil unhandled | nil-state deref UB | exp-05; ADR-004; **AMEND-1** |
| A7 | `Request` fields are views over transport buffer | spec §Request ownership | UNVALIDATED | view aliasing unverified | retained view after request | exp-06; ADR-007 |
| A8 | query family `query`/`query_int`/`query_int_or` | spec §query family | CONSISTENT | one canonical set, no generic | — | exp-09 pins malformed rule |
| A9 | `query_int_or` default only on absence | spec + canonical-patterns L… | CONSISTENT | table with `?limit=banana → 400` | — | exp-09 test present |
| A10 | error envelope `{code,message,field}` | spec §Std Errors; errors.md | AMBIGUOUS | `field` shown in examples; some errors have no field | is `field` optional/omitted/empty? | **AMEND-2** |
| A11 | `web.app()` full defaults (recovery,limit,timeouts,404/405,shutdown) | ai-context L19-20; canonical L38-39 | CONTRADICTORY | docs promise all NOW; phases L24-27 deliver progressively | user expects body-limit/405/timeouts in Phase 1 build | **AMEND-3** |
| A12 | oversized body → `body_too_large` | canonical L139-140; ai-context | CONTRADICTORY | promised as available; phases place limits in Phase 3 (L211) | Phase-1 build returns 200, docs say 413-class | **AMEND-3** |
| A13 | `405 method_not_allowed` behavior | spec L187; app() default L187 | AMBIGUOUS | listed as default; phases place 405 at Phase 3 (radix) L206/225 | 405 promised but not in Phase-1 dispatcher | **AMEND-3** |
| A14 | ai-context lists Phase 2/3 surfaces (`use`,`router`,`group`,`mount`,`logger`,`state`,`app_with_state`) | ai-context L28,37-38,90,152,159-165 | AMBIGUOUS | full target surface shown; status line says "frozen target" | Phase-1 coding agent hallucinates middleware/groups work | **AMEND-4** |
| A15 | response single-commit rule | spec (tests "cannot commit twice"); Response.committed | UNVALIDATED | rule stated; not prototyped | double-commit races | exp-08; ADR-008 |
| A16 | transport is conceptual contract, ABI not frozen | spec §Transport (post-amend) | CONSISTENT | explicit "private, may change" | premature freeze if a dev freezes it | exp-08; ADR-009 |
| A17 | onion post-`next` conditional on transport | spec §Execution model | CONSISTENT | flagged as Phase-2 gate decision | committing to onion too early | exp-07 (evidence only) |
| A18 | vocabulary "provisionally frozen" | spec §Canonical vocabulary | CONSISTENT | wording matches freeze discipline | "frozen" misread as ratified | note in gate |
| A19 | `path(ctx,name) -> string` present-when-matched | spec + ai-context L86 | CONSISTENT | consistent across docs | empty vs missing param ambiguity | exp-09 covers int; path string TBD |
| A20 | collection import `uruquim:web` | README; ai-context L… | UNVALIDATED | name chosen; not built | collection wiring (WP0) | WP0 defines `-collection:uruquim` |
| A21 | `header`/`bearer_token` return `(string, found)`, no auto-response | ai-context L88-89 | CONSISTENT | consistent | — | — |
| A22 | Advanced API `app_init` + `Advanced_Config` | spec §Advanced API | PREMATURE (for Phase 1) | correctly deferred | leaking into Phase 1 docs | keep out of Phase-1 surface |
| A23 | no `web.object` untyped literal | (removed earlier) | CONSISTENT | grep: none | — | — |
| A24 | examples 01-10 compile in CI | spec §Reference structure; phases | MISSING | examples not yet authored | claimed contract with no files | WP10 creates them |

## Spec amendments — accepted and applied

The proposal text below is retained for traceability. Human acceptance was
received on 2026-07-18; the implemented wording may be more explicit while
preserving the approved decision.

### AMEND-1 — `web.state` nil policy (A6)

**Status: ACCEPTED AND APPLIED.** Applied to architecture, idioms, agent
prompt, canonical patterns, and AI context; implementation remains Phase 3.

**Current (spec §Application state):** the asserted accessor validates the
`typeid` but says nothing about a `nil` registered state.

**Proposed addition:**
> `app_with_state` SHALL reject a nil state pointer at registration
> (assertion/precondition). `web.state(ctx, T)` SHALL assert both that a state
> was registered and that `T` matches the registered type before returning.
> Dereferencing an unregistered or nil state is a programmer error, not a
> request-time failure.

**Motivation:** removes an undefined-behavior edge. **Evidence:** exp-05
(nil discussion). **Impact:** one sentence in spec; assertion in WP-that-adds-
state (Phase 3), not Phase 1.

### AMEND-2 — `error.field` optionality (A10)

**Status: ACCEPTED AND APPLIED.** `field` is omitted when absent.

**Current:** the envelope is shown as `{code, message, field}`; several errors
(`invalid_json`, `internal_error`) have no meaningful field.

**Proposed addition (to `docs/errors.md`, normative):**
> `error.field` is OPTIONAL. It is present only for errors bound to a specific
> input (`invalid_path_parameter`, `invalid_query_parameter`, validation). When
> absent it SHALL be omitted from the JSON object entirely (not `""`, not
> `null`). Clients MUST NOT rely on `field` being present.

**Motivation:** stabilizes the wire contract before code depends on it.
**Evidence:** error-code list vs examples. **Impact:** `errors.md` + the
envelope encoder; affects WP6.

### AMEND-3 — `web.app()` defaults are progressive; docs must not overpromise (A11/A12/A13)

**Status: ACCEPTED AND APPLIED WITH SCOPE DECISION.** Phase 1 includes fixed
4 MiB cap and minimal 405 with `Allow`; later policies are phase-marked.

**Current:** `docs/ai-context.md` L19-20 and `docs/canonical-patterns.md`
L38-39 state `web.app()` provides recovery, body limit, timeouts, 404/405, and
graceful shutdown as if all are active now; `03-development-phases.md` L24-27
says the contract is delivered progressively (recovery P2, limits/timeouts P3).
Oversized-body → `body_too_large` (canonical L139-140) and 405 are therefore
promised but not present in a Phase-1 build.

**Proposed addition (to both docs, one line each):**
> The `web.app()` default-policy set is the *end-state contract*. Policies are
> activated across phases (recovery from Phase 2; body limit, timeouts, and 405
> from Phase 3). A given build provides the policies activated up to its phase;
> see `knowledge-base/03-development-phases.md`.

**Motivation:** prevents a Phase-1 user/agent from expecting 413/405/timeout
behavior that is not wired yet. **Evidence:** grep above. **Impact:**
documentation only; no signature change. **Alternative considered:** pull
body-limit + 405 forward into Phase 1 (they do not need radix). Recorded as
open question OQ-3 for the scope review.

### AMEND-4 — mark not-yet-available surfaces in `ai-context.md` (A14)

**Status: ACCEPTED AND APPLIED.** Middleware/groups are marked Phase 2 and
typed application state Phase 3/Advanced.

**Current:** `ai-context.md` presents the full target surface (middleware,
groups, typed state) with only a global "frozen target surface" status line. A
Phase-1 coding agent can copy `web.use` / `web.group` / `web.logger()` and
expect them to exist.

**Proposed addition:** annotate each not-yet-available section with an inline
marker, e.g. `// available from Phase 2` / `// available from Phase 3`, and add
at the top:
> Sections marked *available from Phase N* do not exist in earlier builds. For
> the current build, use only the unmarked (Phase-1) surface.

**Motivation:** the document's whole purpose is to stop hallucinated usage;
un-phased surfaces defeat it. **Evidence:** A14 lines. **Impact:** `ai-context`
only; no API change.

## Summary

- CONSISTENT: 10 rows — the core canonical decisions hold together.
- UNVALIDATED (compile-pending): 8 rows — all mapped to an experiment.
- AMBIGUOUS: 3 rows (A10, A13, A14) — AMEND-2/-3/-4.
- CONTRADICTORY: 2 rows (A11, A12) — AMEND-3 (docs overpromise vs progressive).
- PREMATURE: 1 row (A22) — correctly deferred, watch for leakage.
- MISSING: 1 row (A24) — examples authored in WP10.
- READY_FOR_GATE at original audit: **0**. Current gate evidence is maintained
  separately; the corrected runner is 9/9 and the accepted amendments close
  the original human-decision blockers.

No CONTRADICTORY finding blocks the architecture; all four amendments are
documentation-or-one-sentence changes. The gate (07) carries A11/A12/A13 as the
only findings that touch *build behavior* and assigns them owners.
