# 15 — Public API Anti-Accretion Guardrails

Status: **HUMAN-ACCEPTED PLANNING POLICY.** These guardrails make existing
Knowledge Base constraints testable across work packages. They do not add a
public feature, reopen ADR-011, or change the Phase-1 scope.

## Purpose

Uruquim should remain small because each public concept earns its place, not
because the repository happens to be young. Convenience requests must not
silently create aliases, a god context, transport leakage, hidden ownership,
or a kitchen-sink `App`.

The project is not branded or designed as “anti-Gin.” Gin, Echo, Gjallarhorn,
and other frameworks are comparative evidence only. Positive Uruquim
principles remain authoritative: one canonical path, explicit ownership,
typed boundaries, transport isolation, and predictable behavior for humans
and coding agents.

## Mandatory guardrails

### G-01 — One public name per operation

A proposed public procedure must show that no existing canonical operation
already solves the task. Exact fixed-status delegation (`ok`/`created` to
`json`) is allowed only because equivalence is normative and behavior-tested.
Aliases, spelling variants, and subtly different convenience families are
rejected.

### G-02 — Framework types stop at the HTTP boundary

Handlers and typed HTTP extraction procedures may accept `^web.Context`.
Domain services, repositories, and business rules must not import `uruquim:web`
or accept framework request/response/context types. They receive application
DTOs and return application-domain types.

### G-03 — Context is not an extension bag

The canonical `Context` must never expose `user_data`, `locals`, `values`,
`map[string]any`, `map[any]any`, public `rawptr`, or equivalent dynamic
storage. Future typed state remains phase-gated and cannot become a tax on the
Productive API.

### G-04 — Response side effects are singular and visible

Fallible HTTP extractors may write their standardized error because that is
the one canonical contract. Documentation and examples must immediately
return on `false`. Response commit is single-write: continued handler code
cannot overwrite an extractor error. Framework errors pass through the
private typed report path; handler signatures remain void under ADR-011.

### G-05 — Request views never escape implicitly

Request-derived strings, slices, headers, params, query, and body are temporary
views unless explicitly copied with an appropriate allocator. Background work
must receive owned application data, never capture `ctx` or request views.

### G-06 — Transport names stay behind the boundary

Backend-specific names may appear in architecture and adapter documentation,
but not in exported `web` signatures, canonical application examples, or the
public `Context`. A textual mention in an internal design document is not by
itself leakage.

### G-07 — Optional features do not enlarge core by default

Templates, static hosting, alternate serializers, WebSocket, streaming,
OpenAPI, code generation, CLI, TLS/QUIC-specialized entry points, and proxy
policy do not enter the Phase-1 package. Later features require their own
phase/ADR and should prefer optional packages or adapters when feasible.

### G-08 — Defaults are claimed only when delivered

Documentation must distinguish current defaults from end-state intent. Every
default requires an owning work package and behavior test. A safe progressive
default is preferable to an unimplemented production promise.

### G-09 — Public growth carries evidence in the same change

Every public API addition or change must include:

1. owning phase and specification clause;
2. proof it is not a synonym;
3. compiling example on the pinned Odin toolchain;
4. behavior test;
5. canonical-pattern and AI-context parity;
6. ownership/allocation/commit notes where relevant;
7. dependency and transport-leak review;
8. rollback or compatibility impact.

Without all eight, the symbol remains private or proposed.

### G-10 — No Phase-1 linter or analyzer product

Phase 1 enforces these rules through compile contracts, behavior tests, static
repository assertions, and review. A flow-aware extractor linter may be
researched later only after real misuse evidence; grep heuristics must not be
marketed as semantic analysis. This guardrail does not authorize a CLI or code
generator.

### G-11 — Test-support surface is a separate ledger

The `web.test_request` / `web.Recorded_Response` test-support facade (WP3) is
public — documented, compiled, behavior-tested, and protected against
accidental change exactly like the application surface — but it is tracked in a
**separate ledger**, not folded into the frozen application count. Rationale:
it is a test utility, exercised only from test binaries, and conflating it with
the application API would let the two grow against each other under one number.

`build/check_public_api.sh` therefore makes THREE surface assertions once WP3
lands: the application ledger is exactly 32; the test-support ledger is exactly
2 (`Recorded_Response`, `test_request`); their exported union is exactly 34,
with no other symbol. The facade lives in package `web` (`web/test_support.odin`);
the machinery lives in `web/testing` and imports neither `uruquim:web` (cycle)
nor `core:testing`. Documentation presents the application inventory and a
separate "Testing" section, states the `Recorded_Response` lifetime and the
absence of sockets/ports/transport types, and promises no direct import of
`web/testing`. Growth of either ledger still carries G-09 evidence.

Because package `web` imports the test machinery, WP3 must measure a minimal
application that never calls `test_request`. Lazy runtime allocation alone is
not sufficient evidence: the gate also verifies no test-support package init
side effect and records the binary-size delta. Any unexplained shipped cost is
a human-review item before WP3 can be marked complete. The package probes from
the pre-WP3 amendment must become committed, executable checks; an external
scratch prototype is supporting evidence, not the permanent ratification.

## False-positive rules

- Do not flag `ok`/`created` when exact delegation remains proven.
- Do not flag the two canonical extractor shapes as duplicate APIs.
- Do not flag backend names in internal architecture/adapter documents;
  inspect exported signatures and application examples.
- Do not call `^web.Context` lock-in merely because it appears in an HTTP
  handler; flag it only beyond the HTTP boundary.
- Do not treat experiments or historical patches as shipped API.
- Do not emit hypothetical findings when the forbidden pattern is absent.

## Work-package enforcement map

| Gate | Required evidence |
|---|---|
| WP1 | exact exported-symbol inventory; no aliases, future surfaces, untyped context fields, or transport types |
| WP2 | view invalidation/copy tests; single commit; Context shape assertion |
| WP3 | dual-ledger surface (32 application + 2 test-support = 34); committed one-way/cycle probes; `web/testing` imports neither `uruquim:web` nor `core:testing`; unused-facade binary/init measurement; two-response lifetime and destroy cleanup (G-11) |
| WP5 | extractor errors commit once; canonical examples return immediately; plain result forces `ok` capture |
| WP6 | exact responder delegation; marshal logging; no partial/double response; private typed error path |
| WP8 | adapter dependency inventory; backend-type export scan; core remains usable through test transport |
| WP10 | all examples compile; phase markers and canonical vocabulary match code |
| WP11 | public API/dependency inventory reviewed; every export has compiling and behavioral evidence |

## Reviewer checklist

For each PR that touches `web/` or canonical docs:

- Does it add an exported name?
- Is there already a canonical way to do the task?
- Is a framework type moving beyond the HTTP boundary?
- Does it add dynamic request-local storage?
- Can it commit or rewrite a response unexpectedly?
- Does request-derived data escape without a copy?
- Does a backend type or dependency reach public code?
- Is a later-phase feature leaking into Phase 1?
- Do canonical patterns and AI context change together?
- Is rollback/compatibility impact explicit?

Any “yes” without ratifying evidence blocks that work package gate.
