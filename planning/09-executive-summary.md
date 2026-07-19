# 09 — Executive Summary

## Headline

**Phase-1 Spec Gate = READY as of 2026-07-18.**

The fixed Odin toolchain is available at `/tmp/uruquim-odin-toolchain` and
identifies itself as `dev-2026-07-nightly:819fdc7`. After the original failed
run was preserved and four transparent throwaway-source corrections were
made, the suite passed. A final verification after normative amendments also
produced **PASS=9 FAIL=0 SKIP=0**. Real transcripts and intended negative
probes are recorded in `planning/07-spec-gate-phase-1.md` and
`planning/10-c1-execution-evidence.md`. The later handler study extended the
suite to **PASS=10 FAIL=0 SKIP=0** and closed C-8 without changing the public
handler signature.

## Closed decisions

- HTTP extractors omit `#optional_ok`; ignoring `ok` is a compiler error.
- `web.app()` returns App by value. App stores no pre-return self-pointer, is
  non-copyable by contract, and only the original is destroyed.
- Phase 1 has a fixed 4 MiB request-body cap and minimal 405 with required
  `Allow`; configurable limits/timeouts remain Phase 3.
- `error.field` is optional and omitted when absent.
- Phase-1 JSON response payloads are concrete values. `&value` and
  pointer-typed variables are unsupported in the accepted baseline.
- Marshal failure is logged server-side before one fresh complete
  `internal_error` is written, while uncommitted; partial JSON is forbidden.
- WP6 will prototype one-level pointer dereference. This is non-blocking and
  changes the baseline only through a later approved amendment.
- Typed application state uses one private rawptr+typeid pair in future Phase
  3; registration rejects nil and access asserts presence/type.
- Future surfaces in `ai-context.md` are explicitly phase-marked.
- The Phase-1 handler remains `proc(ctx: ^Context)`. Framework failures use a
  private typed report path; application-domain failures are mapped explicitly
  at the HTTP boundary. A typed observer/policy is Phase-2 scope.

ADRs 001, 002, 003-baseline, 004, 006, 007, 008, 009, and 011 are accepted.
ADR-005 (middleware semantics) and ADR-010 (remaining Advanced API) stay
proposed and owned by later gates; neither can expand Phase 1.

## Approved Phase-1 vertical slice

The slice contains the compiling public API skeleton, Request/Response views
and single-commit, in-memory test transport, simple static+`:param`
dispatcher, canonical path/query/body extractors, JSON/text/error responses,
fixed body cap, 404, minimal 405+`Allow`, bootstrap transport adapter,
transport conformance baseline, and examples 01–03.

Middleware, groups, radix, public typed state, configurable limits/timeouts,
production hardening, OpenAPI, streaming, WebSocket, code generation, and CLI
remain out of scope.

## Implementation sequence

Execute exactly one package at a time under
SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE:

1. WP0 — toolchain and repository baseline
2. WP1 — compiling public API skeleton
3. WP2 — request/response model
4. WP3 — in-memory test transport
5. WP4 — minimal registration and dispatch
6. WP5 — canonical extractors
7. WP6 — JSON responses and error envelope
8. WP7 — JSON body binding
9. WP8 — bootstrap real transport adapter
10. WP9 — transport conformance baseline
11. WP10 — Phase-1 docs and examples
12. WP11 — implementation gate and freeze

WP0 is complete. The pinned checker accepts `819fdc7`, rejects a divergent
compiler and ambient `ODIN_ROOT`, and observes 10/10 prototypes. GitHub Actions
is unavailable; a tracked pre-push hook is the mandatory local gate. The real
Ubuntu VPS verified clean commit `4ae2d1c` green and its five-minute systemd
timer is enabled and active. WP1 is now technically authorized but has not
started; see `planning/12-wp0-gate.md`.

## Parity statement

All ten prototype packages compile/run on the pinned compiler. Static scans
found no accepted response example using `&payload`; the sole occurrence is a
comment explicitly marked “not accepted”. The repository still has no `web/`
or `examples/` directory, so literal product-example compilation cannot be
claimed yet. WP1 and WP10 make compilation of every documented/example
surface a hard gate.

## Production state

No `web/` package or production framework implementation exists. The only
source changes before READY were disposable experiments and normative/planning
documents.

**Nenhuma implementação de produção foi iniciada.**
