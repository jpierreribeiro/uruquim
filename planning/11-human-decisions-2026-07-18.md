# Human Decisions — 2026-07-18

This ledger records explicit human acceptance before the Phase-1 Spec Gate
was recomputed. Git metadata was later connected and the accepted amendments
were recorded in commit `e9a0987`.

## Accepted

1. ADR-002: remove `#optional_ok` from fallible HTTP extractors.
2. ADR-001: keep canonical `app()` by value; no self-pointer before return;
   App is non-copyable and copies are never destroyed.
3. Phase-1 scope: fixed 4 MiB body cap and minimal 405 with RFC-required
   `Allow`.
4. AMEND-2: `error.field` is optional and omitted when absent.
5. ADR-003 baseline: concrete JSON payload values only.
   - Mandatory: log marshal failure server-side before returning one fresh
     complete pre-commit `internal_error`.
   - Mandatory: canonical-patterns and ai-context show payload by value and
     explicitly reject `&value` and pointer-typed payload variables.
   - Non-blocking WP6 recommendation: prototype one-level pointer dereference;
     amend the spec before adopting it.
6. ADR-004-A + AMEND-1: future typed app state uses private rawptr+typeid,
   rejects nil, and asserts registration/type on access.
7. AMEND-4: phase markers in `docs/ai-context.md`.
8. AMEND-3: progressive defaults, aligned with item 3.
9. GitHub Actions is unavailable; the official verification policy is a
   mandatory tracked pre-push gate plus clean repetition on the project VPS.
10. Echo-style returned errors are not adopted speculatively. A disposable
    Odin prototype and ADR-011 must compare the existing handler, a typed
    returned error, and an explicit result before any signature change.
11. Gjallarhorn is a comparative reference only; no code or architecture is
    copied wholesale.
12. Gin/Echo research is retained as non-normative input. Its accepted lesson
    is public-API anti-accretion governance in planning/15; it does not reopen
    the void handler, add a Phase-1 linter, or treat internal transport
    documentation as public leakage.

ADRs 006–009 retain their prototype-supported recommendations as accepted
implementation constraints. ADR-005 and ADR-010 remain deferred to later
gates and are not Phase-1 blockers.

## Normative files amended

- `knowledge-base/01-architecture-spec.md`
- `knowledge-base/02-odin-idioms-guidelines.md`
- `knowledge-base/03-development-phases.md`
- `knowledge-base/04-local-agent-system-prompt.txt`
- `docs/canonical-patterns.md`
- `docs/ai-context.md`
- `docs/errors.md`
- `docs/middleware.md`

## Verification

After applying the amendments:

```text
odin version dev-2026-07-nightly:819fdc7
PASS=10 FAIL=0 SKIP=0
```

The full actual run is pasted into `planning/07-spec-gate-phase-1.md`.
No production package existed or was created while these decisions were
applied.
