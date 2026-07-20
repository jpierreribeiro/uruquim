# Open Questions

Status: **MIXED.** Human decisions on 2026-07-18 closed the original Phase-1
Spec Gate questions OQ-2, OQ-3, OQ-4, OQ-5, OQ-6, and OQ-14. Research added
OQ-15 as the next implementation-blocking decision, owned narrowly by WP7; it
does not block WP3–WP6. All other remaining questions are implementation checks
or owned by later phases.

## Critical (block a WP)

### OQ-1 · RESOLVED — pinned toolchain runs locally and on the VPS
- **Owner.** toolchain owner.
- **Evidence.** Local dev execution on `dev-2026-07-nightly:819fdc7` is complete:
  first run 5/9, corrected second run 9/9, and the extended handler suite
  10/10. The SHA/commit-verified distribution is persistent at
  `/opt/uruquim-odin` on the Ubuntu VPS, and clean commit `4ae2d1c` passed its
  systemd verifier. odin-http vendoring remains a separate WP8 concern.
- **Deadline.** closed before WP1.

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

### OQ-15 · Repeated `web.body` call semantics
- **Owner.** WP7 / API owner.
- **Evidence required.** Disposable pinned-toolchain prototype covering a
  successful first bind, invalid first bind, empty body, and a second bind;
  demonstrate that the selected diagnostic cannot double-commit.
- **Deadline.** before WP7 production implementation.
- **Proposed direction.** ADR-012 option A: a request body has one canonical
  typed consumer. Do not infer replay merely because Phase 1 buffers input.

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

### OQ-16 · Trusted proxy policy
Phase-4 security gate (ADR-013). Default remains connected-peer only; no
forwarding header is trusted before the ADR and corpus are accepted.

### OQ-17 · Graceful drain definition
Phase-4 prototype using test transport and one real adapter must define
admission stop, in-flight work, absolute deadline, forced close, and exactly-once
cleanup before an ADR is proposed.

### OQ-18 · Public route-pattern accessor — CLOSED, 2026-07-20 (WP34)
**Answered: `web.route(ctx)` ships, and returns the registered pattern.** The
use case arrived with the observability work: WP20 gave an OBSERVER the route
identity, and an application that wanted to label its own metrics, logs or
spans by route had no way to obtain the same string — `ctx.request.path` is
precisely the wrong substitute, because route identity must be low-cardinality
(C-2). One symbol, ledger 44 → 45, approved under the ADR-029 delegation and
recorded as Amendment 10 of `planning/phase-1-freeze.md`.

The redaction rule travelled with it: the PATTERN, never the path, enforced by
a gate assertion on every write to the slot rather than by convention.

### OQ-19 · Adaptive overload policy
Deferred until deterministic bounded admission and shedding work independently.
Signals, thresholds, hysteresis, and recovery remain research.

### OQ-20 · Multipart temporary-file ownership
Phase 4. Prototype cleanup, quotas, persistence transfer, disk-full, timeout,
and disconnect behavior before proposing an ownership ADR.

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
| OQ-15 | yes | WP7 implementation | before WP7 code |
| OQ-7..13 | no | — | deferred |
| OQ-16..20 | no (phase-owned) | P4/Future features only | owning phase gate |

## Added after the Phase-1 freeze (post-Phase-1 audit)

None of these blocks Phase-2 planning. Each names the work package that will
decide it. **No decision below is accepted** — they are recorded so that the
owning WP does not rediscover them.

| OQ | Question | Recommended direction | Decided by | Owner approval? |
|---|---|---|---|---|
| OQ-21 | How does test-support grow so a JSON body can be tested in memory? | an explicit Odin procedure group `test_request :: proc{...}`, matching how `core:strings`/`core:net` add variants without creating a second name | first Phase-2 WP that needs it | **yes** — the test-support ledger grows beyond 2 |
| OQ-22 | Onion (post-`next`) middleware, or pre-order only? | prototype both on the bootstrap transport before choosing; the fit audit flags post-`next` as a foreign-abstraction risk | Phase-2 prototype WP | **yes** — it sets the shape of everything after it |
| OQ-23 | Should `Recorded_Response` ever carry headers? | not yet; needed for CORS, cookies and cache validators, which are all Phase 4 | Phase-4 WP that needs it | yes |
| OQ-24 | Configurable limits: an options struct with a package default constant, or individual setter procedures? | the options-struct shape, on `core:net`'s `DEFAULT_TCP_OPTIONS` precedent | Phase-3 limits WP | yes |
| OQ-25 | Does the framework ever terminate TLS, or is reverse-proxy termination the documented deployment? | document proxy termination as the supported path; treat in-process TLS as an optional package at most | Phase-4 spec gate | **yes** — materially changes Phase-4 scope |
| OQ-26 | What is the supported-Odin-version policy, given the pin is a nightly and `core:os` is mid-redesign in that very build? | state a single pinned version as the contract and re-pin deliberately | Phase-2 documentation WP | yes |
| OQ-27 | Does `ops/ci` stay, or move to `tools/`? | left open by the local cleanup plan | Phase-2 housekeeping WP | no |
| OQ-28 | Which licence? | MIT matches the vendored dependency and is lowest-friction | corrective PR, before Phase 2 | **yes** — cannot be defaulted by an agent |


## OQ — request-scoped typed state — CLOSED, 2026-07-20 (ADR-028, WP37)

**Answered: it does not exist, and it is not scheduled.** A middleware cannot
hand a typed value to a handler, and the canonical auth pattern pays for it —
`current_user` revalidates the token on every call. **That cost is permanent
until an ADR decides otherwise**, and `build/check_examples.sh` rejects a
comment that schedules its removal.

**This was never ADR-004,** and the conflation is what made the question worth
tracking separately. ADR-004 accepted `web.state` for APPLICATION state — one
`rawptr`+`typeid` on the App, set before serving — which WP37 shipped.
Per-request values have a different lifetime and a different owner, and
treating them as one produced a false promise in shipped documentation that had
to be corrected under G-08.

Research finding C-6 is the substance of the answer: Go's `context.WithValue`
and Rust's `http::Extensions` exist for type-erased, dynamically-keyed state
crossing library boundaries, which Uruquim does not have — so the finding
SUPPORTS G-03 rather than challenging it. ADR-028 accepted option 1 and placed
the burden of proof on reopening: the evidence must be **a real program that
cannot be written cleanly in this tree**, never a hypothetical. Option 1 is
also the only reversible arm — adding a mechanism later is a pure
strengthening, while shipping one and withdrawing it breaks applications at
compile time with no deprecation window that helps.
