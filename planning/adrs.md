# Architecture Decision Records

Status: **MIXED.** Human decisions recorded on 2026-07-18 accept ADR-001,
ADR-002, ADR-003's value-only baseline, ADR-004, ADR-006, ADR-007, ADR-008,
ADR-009, and ADR-011. Decisions recorded on 2026-07-19 accept ADR-005 (with
ADR-019) and ADR-020. ADR-010 and ADR-013 remain PROPOSED/deferred to their
owning gates. Reproducible compiler evidence lives
in `experiments/` and the permanent work-package tests.

Each ADR: context · options · benefits · costs · risks · evidence ·
recommendation · documentation impact · reversibility.

---

## ADR-001 — App creation: by value vs explicit init
- **Status.** **ACCEPTED** — option C, with A canonical and B future Advanced.
- **Context.** Canonical `app := web.app(); defer web.destroy(&app)` vs
  Advanced `app: web.App; web.app_init(&app)`.
- **Options.** (A) `app()` returns `App` by value. (B) `app_init(&app)` fills
  caller storage. (C) both — A canonical, B advanced.
- **Benefits.** A: one-liner, no pre-declared variable. B: caller owns storage
  from the first instruction (no return-copy question).
- **Costs.** A: by-value return copies the struct header; owned `[dynamic]`/map
  members must be copy-safe and destroyed once. B: two lines, less friendly.
- **Risks.** A: double-free if a stray copy is destroyed twice.
- **Evidence.** exp-01 PASS: caller address stable; pre-return `self_addr`
  differs as expected; both deferred destroys completed once.
- **Decision.** **C**: A canonical, B available in the future Advanced API.
  The returned App stores no self-pointer before return and is non-copyable by
  contract; only the original caller-owned value may be destroyed.
- **Doc impact.** none if exp-01 passes; if it fails, spec §Application +
  README + canonical-patterns switch the canonical example to B.
- **Reversibility.** HIGH pre-code; MEDIUM after examples ship.

## ADR-002 — `#optional_ok` on value extractors
- **Status.** **ACCEPTED** — option B for HTTP extractors.
- **Context.** `path_int(ctx,name) -> (int, bool)` — keep `#optional_ok`?
- **Options.** (A) keep it (stdlib idiom; bool droppable). (B) omit it
  (compiler forces handling the bool).
- **Benefits.** A: matches `map[k]`, familiar. B: hard guarantee against silent
  drop by a human or LLM.
- **Costs.** A: permits `id := path_int(...)` dropping the error. B: slightly
  less idiomatic; still `(value, ok)` at the call site.
- **Risks.** A: the canonical `if !ok { return }` is advisory, not enforced.
- **Evidence.** exp-04 second run PASS: the directive permits silent discard;
  the separate plain-form probe fails with `Assignment count mismatch '1' =
  '2'`.
- **Decision.** **B for HTTP extractors** (safety > idiom, and the audience
  explicitly includes weaker LLMs). The exp-04 diagnostic proves that the
  plain form makes an ignored bool a compile error. Call sites remain
  identical.
- **Doc impact.** spec §Extractor Control Flow keeps the call-site form; only
  the `#optional_ok` sentence changes.
- **Reversibility.** HIGH — internal to signatures, call sites unchanged.

## ADR-003 — Response rendering by value/pointer via `$T`
- **Status.** **ACCEPTED BASELINE** — value-only for Phase 1; one-level pointer
  dereference remains a non-blocking WP6 prototype.
- **Context.** `json(ctx, status, value: $T)`, with `ok`/`created` shorthands.
- **Options.** (A) parametric `$T` + `json.marshal(any)`. (B) require callers
  pass `any` explicitly. (C) code-gen per type.
- **Benefits.** A: one name, any serializable type, no user `any`. C: no
  runtime marshalling.
- **Costs.** A: `any` used internally (encapsulated). C: banned (no codegen).
- **Risks.** A: types the marshaller rejects surface as runtime errors (must be
  pre-commit).
- **Evidence.** **REOPENED:** after fixing the recorded import collision,
  values serialize and commit once, but `^User` and proc payloads return
  `Unsupported_Type` in the pinned official marshaller.
- **Decision.** Phase 1 accepts concrete value payloads and explicitly rejects
  `&value` and pointer-typed variables. Any marshal failure is logged on the
  server before a fresh standardized `internal_error` is written, while
  uncommitted; silent 500 and partial JSON are forbidden. In WP6, prototype a
  one-level pointer dereference. Adopt pointer support only if it compiles
  cleanly and a spec amendment is approved; otherwise retain value-only.
  `ok`/`created` remain exact one-line delegations either way.
- **Doc impact.** architecture spec, idioms, canonical patterns, AI context,
  errors, WP6.
- **Reversibility.** HIGH.

## ADR-004 — Application state access
- **Status.** **ACCEPTED** — option A, future Phase-3/Advanced API only.
- **Context.** `web.state(ctx, T)` with no generic noise at call sites.
- **Options.** (A) `rawptr + typeid` on `App`, asserted accessor. (B)
  parametric `App(S)/Context(S)`. (C) closed accessor generated per app.
- **Benefits.** A: zero call-site type args, one sanctioned rawptr. B:
  compile-time wrong-type prevention.
- **Costs.** A: runtime assert; nil edge. B: type args at every handler; the
  generic noise the spec rejects. C: needs codegen (banned).
- **Risks.** A: nil/unregistered deref (→ AMEND-1).
- **Evidence.** exp-05 PASS for correct-type access: both alternatives compile
  and rawptr+typeid mutation is visible on the original state. Nil/wrong-type
  policy remains pending.
- **Decision.** **A canonical; B reserved for Advanced typed context.**
  AMEND-1 applies: registration rejects nil and access asserts registration
  plus exact type before casting.
- **Doc impact.** spec §Application state + AMEND-1.
- **Reversibility.** MEDIUM (public accessor).

## ADR-005 — Middleware model
- **Status.** **ACCEPTED** (owner, 2026-07-19) — option **B (onion)**, with
  registration-order enforcement per ADR-019 below.
  Evidence: `planning/phase-2-prototype-middleware.md` (WP12).
- **Outcome.** The prototype showed the mechanism is not a choice to be made but
  a consequence: middleware is the frozen `Handler` shape (a `bool`-returning
  form would be a second handler shape, which ADR-011 forbids), so `next` is an
  ordinary call that returns, and code written after it inevitably runs. There
  is no unwind machine to adopt or reject. Measured: `A>B>C>H<C<B<A`, exact
  reverse unwind, **0 allocations** through a 5-middleware chain, and a
  post-`next` response attempt rejected by the existing single-commit guard.
  Option A was therefore not available without deliberately crippling the
  mechanism, and option C's condition is satisfied.
- **Superseded status line.** **PROPOSED / DEFERRED** — Phase-2 Spec Gate.
- **Context.** cursor `next`, global/group/route/handler, short-circuit, unwind.
- **Options.** (A) pre-order only (no code after `next`). (B) onion
  (before+after `next`). (C) onion only if the transport guarantees safe
  post-commit execution.
- **Benefits.** A: simplest, no post-commit hazard. B: familiar (Gin/Axum),
  after-hooks for latency/logging.
- **Costs.** B: "after" runs post-commit (exp-07) — safe only if headers/buffer
  are still valid.
- **Risks.** committing to B before the transport is known.
- **Evidence.** exp-07 (mechanism works; after == post-commit).
- **Recommendation.** **C — decide at the Phase-2 gate.** Phase 1 ships only the
  cursor mechanism; no onion promise.
- **Doc impact.** none now (spec already conditional).
- **Reversibility.** HIGH (Phase 1 exposes no middleware API).

## ADR-006 — Request body ownership
- **Status.** **ACCEPTED** — option A.
- **Context.** where do `body`-bound nested strings/slices live?
- **Options.** (A) request-lifetime arena, explicitly substituted. (B)
  `context.allocator`. (C) copy out of temp after unmarshal.
- **Benefits.** A: freed in one shot at request end; clear ownership.
- **Costs.** B: lifetime unclear, leak risk. C: double copy.
- **Risks.** A: `json.unmarshal` must honor the substituted allocator for
  nested data.
- **Evidence.** exp-03 PASS (`arena.offset = 68`; all failure branches observed).
- **Decision.** **A.**
- **Doc impact.** spec §body + memory-model (Phase 4 doc).
- **Reversibility.** MEDIUM.

## ADR-007 — Request allocator vs temp allocator
- **Status.** **ACCEPTED** — option A.
- **Context.** views over transport buffers vs persistent copies.
- **Options.** (A) request arena for anything outliving a single parse step;
  temp for immediate scratch. (B) temp everywhere. (C) copy everything up front.
- **Benefits.** A: zero-copy views + explicit persist; matches spec ownership
  rule.
- **Costs.** C: defeats the view design; B: dangling after temp reset.
- **Risks.** retaining a view past the request (mitigated by the physical demo).
- **Evidence.** exp-06 second run PASS after the recorded syntax correction:
  the reused buffer invalidates the view while the explicit clone survives.
- **Decision.** **A**, with the normative "copy to persist" rule.
- **Doc impact.** none (matches spec).
- **Reversibility.** MEDIUM.

## ADR-008 — Response commit semantics
- **Status.** **ACCEPTED** — option A for buffered Phase-1 responses.
- **Context.** exactly-one-commit; where onion "after" sits.
- **Options.** (A) framework-side single-commit guard (`committed` flag). (B)
  transport-enforced. (C) allow re-commit (last wins).
- **Benefits.** A: deterministic, testable without a real socket.
- **Costs.** C: header/body races. B: couples semantics to backend.
- **Risks.** post-commit onion "after" touching a flushed response.
- **Evidence.** exp-08 PASS (single commit); exp-07 PASS (after==post-commit).
- **Decision.** **A** for buffered responses; revisit for streaming
  (out of MVP). Onion-after must not mutate a committed response — ties to
  ADR-005/C.
- **Scope of the guarantee (amended in WP2).** The guard ensures
  that the supported `web.*` response paths do not overwrite an
  already-produced response. It is NOT a security boundary against deliberate
  manipulation of framework internals: application and framework share one
  program. Odin's `@(private)` hides a declaration's name, not the
  reachability of fields through a public field, and per-field privacy is a
  syntax error. Designs that add indirection (opaque handles, side tables) to
  resist deliberate tampering are REJECTED as useless complexity.
- **Doc impact.** spec §Response commit; test in WP6.
- **Reversibility.** MEDIUM.

## ADR-009 — Transport boundary shape
- **Status.** **ACCEPTED** — option A, explicitly private and unfrozen.
- **Context.** minimal internal contract; no backend type on public surface.
- **Options.** (A) minimal `Transport{data,serve,stop}`, private, unfrozen. (B)
  freeze a rich four-proc ABI now. (C) no boundary, call odin-http directly.
- **Benefits.** A: enough for bootstrap + test transport; free to change when a
  second adapter lands.
- **Costs.** B: premature freeze against an unknown `core:net/http`. C: leaks
  backend types, breaks migration.
- **Risks.** A: shape churn across the first two adapters (acceptable — it is
  private).
- **Evidence.** exp-08 PASS; installed stdlib has `core:net`/`core:nbio` and no
  verified `core:net/http` import yet.
- **Decision.** **A.** Freeze only the *conceptual* contract (accept →
  dispatch → commit → stop).
- **Doc impact.** none (matches amended spec).
- **Reversibility.** HIGH (private).

## ADR-010 — Advanced API policy
- **Status.** **PROPOSED / DEFERRED** — post-Phase-1 gate.
- **Context.** allocators, transport injection, typed context.
- **Options.** (A) present but undocumented in Quick Start; frozen later. (B)
  ship in Phase 1. (C) omit entirely.
- **Benefits.** A: keeps ordinary path simple, preserves systems power.
- **Costs.** B: complexity tax on Phase 1; C: loses the systems audience.
- **Risks.** A: Advanced surface leaking into canonical docs (audit A22).
- **Evidence.** spec §Advanced API; exp-05 (B typed context feasible).
- **Recommendation.** **A** — `app_init` + `Advanced_Config` designed now,
  implemented post-Phase-1, never in the Quick Start.
- **Doc impact.** none now.
- **Reversibility.** HIGH.

## ADR-011 — Handler return and centralized errors
- **Status.** **ACCEPTED** — option A for Phase 1; B/C deferred as a possible
  future breaking design, never as a second canonical handler.
- **Context.** Echo returns a dynamic Go `error` from every handler, enabling a
  global error handler. Uruquim currently uses `Handler :: proc(ctx)` and
  self-responding extractors/responders. Odin has no equivalent universal
  `error`, and `any` is forbidden as public error transport.
- **Options.** (A) keep void handler; framework failures flow through an
  internal typed error event before responding/logging. (B) return a closed
  `Handler_Error`. (C) return `Handler_Outcome{Response|Error|Already_Responded}`.
- **Benefits.** A preserves the simplest extractor flow and current evidence.
  B centralizes returned failure formatting. C defers all normal response
  commit to dispatch.
- **Costs.** B changes every handler/responder/middleware and cannot carry
  arbitrary application errors without mappers or dynamic storage. C adds a
  second response representation and an `Already_Responded` state.
- **Risks.** Odin permits silently discarding returned procedure results, so B
  does not guarantee propagation. An unnamed result rejects the canonical
  extractor `return`; named results introduce a subtle language rule for every
  handler. B would also pre-decide Phase-2 middleware semantics.
- **Evidence.** exp-10: A/B/C compile and pass the same four contract tests on
  `819fdc7`. The ignored-result probe compiles; the bare-return probe fails
  with `Expected 1 return values, got 0`. Independent Gjallarhorn audit finds
  another working Odin framework using a void handler and self-responding
  binder, not Echo-style propagation.
- **Decision.** **A for Phase 1.** Keep `Handler :: proc(ctx: ^Context)`.
  Framework-detected errors SHALL pass through one private typed error-report
  path for logging/formatting before a response, with exactly-one-commit.
  Application domain errors remain typed outside the framework and are mapped
  explicitly at the HTTP boundary. Phase 2 specifies a typed observer/policy
  for logging/Sentry-style integration without arbitrary error storage.
- **Doc impact.** architecture handler/error sections, idioms, Phase 2 scope,
  canonical patterns, AI context, gate C-8.
- **Reversibility.** MEDIUM before v1; breaking after handlers ship.

## ADR-012 — Request body consumption and repeated typed binding
- **Status.** **ACCEPTED** — option A, ratified in WP7 by the disposable
  prototype below (human decisions carried by the WP7 prompt, 2026-07-19).
- **Context.** `web.body(ctx, &dst)` consumes a request-owned byte view. A
  buffered Phase-1 transport could decode the same bytes more than once, but
  hidden replay/caching would make transport and memory behavior less obvious.
- **Options.** (A) single consumer: the first binding attempt consumes the
  typed-body capability. (B) replay the immutable buffered body on every call.
  (C) cache a decoded dynamic representation for later conversions.
- **Benefits.** A is explicit, bounded, and easy for humans and agents to
  reason about. B is convenient but silently repeats parsing. C enables reuse
  but adds dynamic storage/reflection pressure and unclear ownership.
- **Costs.** A needs a clear diagnostic for an accidental second call. B spends
  CPU repeatedly and makes streaming migration harder. C conflicts with the
  small typed procedural core.
- **Risks.** A poorly specified second call can emit two responses or hide a
  programming error. B can make the test transport promise replay that a
  future streaming adapter cannot provide.
- **Evidence.** WP7 ran the disposable prototype required by OQ-15 on
  dev-2026-07-nightly:819fdc7 (in `/tmp`, not versioned). It established:
  - `json.unmarshal` HONORS a substituted `mem.Dynamic_Arena` allocator for
    nested strings and slices (R-06 resolved): decoded values survived a wipe
    of the raw buffer, and destroying the arena left a `mem.Tracking_Allocator`
    with zero live allocations and zero bad frees. No explicit post-unmarshal
    copy pass is needed.
  - `unmarshal_any` runs `is_valid(data, spec)` before parsing, so EVERY
    parse-level failure — empty body, truncation, and the rejected JSON5
    constructs — collapses to `Unmarshal_Data_Error.Invalid_Data`. A destination
    the decoder cannot fill returns `Unsupported_Type_Error`, and a nil or
    non-pointer destination returns `Invalid_Parameter`/`Non_Pointer_Parameter`.
    This gives a clean split: `Invalid_Data` (and any bare `json.Error`) is the
    client's malformed JSON → 400; everything else is a decoder/destination
    fault → 500 through the typed report.
  - Strict `.JSON` mode rejects comments, unquoted keys and single-quoted
    strings, but on 819fdc7 it LENIENTLY accepts a single trailing comma
    (`{"a":1,}` parses). WP7 uses strict mode and documents this as a pinned-
    toolchain deviation rather than hand-rolling a second tokenizer to catch one
    cosmetic edge; a future toolchain bump or work package may tighten it.
- **Decision.** **A.** A request body has exactly one typed consumer. The
  capability is consumed the moment the first `web.body` call begins — before
  the limit check and before the parser — so a first attempt that fails still
  consumes it. A second call parses nothing, logs a private typed diagnostic,
  and: if no response is committed yet, produces `internal_error`/500; if the
  first call already committed a response, leaves it untouched. There is no
  replay, no dynamic cache, and never a double commit.
- **Doc impact.** architecture body section, canonical patterns, AI context,
  WP7 tests, and error documentation.
- **Reversibility.** MEDIUM before streaming; difficult after applications rely
  on replay.

## ADR-013 — Trusted proxy and effective client-address policy
- **Status.** **PROPOSED / DEFERRED** — Phase-4 security gate.
- **Context.** `Forwarded` and `X-Forwarded-For` are client-controlled unless
  the connected peer belongs to an explicitly trusted deployment boundary.
- **Options.** (A) distrust by default; configure trusted CIDRs and walk the
  chain from the nearest hop outward. (B) trust a fixed hop count. (C) trust
  forwarding headers automatically.
- **Benefits.** A ties trust to administered network identity and preserves the
  real peer for audit. B is simple for fixed topologies. C has no safe default.
- **Costs.** A requires IPv4/IPv6 CIDR configuration and careful parsing. B
  breaks when proxy topology changes.
- **Risks.** Incorrect trust changes audit logs, rate limits, allowlists, and
  authorization inputs. Private address ranges are not inherently trusted.
- **Evidence.** RFC 7239 says forwarded information cannot be trusted by
  default. NGINX and Envoy require configured trust and evaluate proxy chains
  from the connected side.
- **Recommendation.** **A.** Default effective address is the connected peer;
  forwarding headers are ignored until trusted proxies are configured. Keep
  both peer and effective addresses internally. Exact header support and
  public configuration follow the Phase-4 prototype.
- **Doc impact.** Phase-4 security specification, deployment documentation,
  conformance corpus, and future configuration API.
- **Reversibility.** LOW after users base security or audit policy on it;
  therefore ADR required before implementation.

## ADR-014 — Response body ownership in Phase 1
- **Status.** **ACCEPTED** — option A, human decision recorded 2026-07-19,
  ratified for WP6.
- **Context.** WP6 renders JSON and text bodies of arbitrary size. The body must
  outlive the handler, because the transport (or the WP3 recorder) reads the
  committed response AFTER `dispatch` returns, and it must be released exactly
  once — `odin test` enables memory tracking, so a leak turns the suite red.
  WP2 deliberately left this open: `Response.body` is documented as a
  non-owning view, and "WP6 defines the concrete allocation and lifetime of a
  rendered response". Nothing in the codebase owns request-lifetime storage
  yet. WP4 and WP5 avoided the question entirely by writing into fixed
  request-local buffers (`allow_buffer`, `error_buffer`), which works only
  because a 405 `Allow` value and a 400 envelope have a computable worst case.
  A user payload does not.
- **Options.** (A) the internal `Response` OWNS dynamically rendered bodies:
  allocated with `context.allocator`, ownership transferred only after the
  render completes, released exactly once by a private idempotent teardown the
  response driver calls after capture. (B) pull WP7's request-lifetime arena
  (ADR-006) forward and render into it. (C) render into a fixed request-local
  buffer, as WP4/WP5 do. (D) `context.temp_allocator`.
- **Benefits.** A keeps WP6 self-contained, adds no subpackage, crosses no work
  package boundary, and stays entirely behind `@(private)`. B is the eventual
  end state and would not need redoing.
- **Costs.** A introduces an ownership rule that WP7's arena will probably
  absorb — but `Response` is fully internal, so that churn is invisible to
  applications. B makes WP6 absorb a file and a decision the plan assigns to
  WP7, and widens the checker's file-set contract.
- **Risks.** C is REJECTED outright: it would cap response size at a number no
  work package ratified, turning an internal storage choice into a public
  behavioral limit. D is REJECTED: ADR-007 restricts the temp allocator to
  immediate scratch, and a temp-allocated body would have to survive across the
  dispatch boundary — exactly the dangling-view class of bug the ownership
  rules exist to prevent.
- **Evidence.** WP5 established that fixed request-local storage is correct for
  BOUNDED content and measured it as allocation-free; the same measurement is
  what shows it cannot generalize to an unbounded payload.
- **Decision.** **A.** The WP7 arena is NOT anticipated. When it lands it may
  replace this mechanism without any public API change, because neither
  `Response`, nor the ownership flag, nor the teardown is exported.
- **Doc impact.** `web/response.odin` ownership comments, WP6 plan entry,
  architecture spec §Response helpers, memory-model (Phase 4).
- **Reversibility.** HIGH — everything involved is package-private.

---

## Acceptance ledger

| ADR | Needs | Human decision? |
|---|---|---|
| 001 | exp-01 | **ACCEPTED** — App by value, Advanced init later |
| 002 | exp-04 diagnostic | **ACCEPTED** — remove `#optional_ok` |
| 003 | exp-02 | **ACCEPTED BASELINE** — value-only; WP6 deref probe |
| 004 | exp-05 + AMEND-1 | **ACCEPTED** — rawptr+typeid, future only |
| 005 | Phase-2 gate | **PROPOSED / DEFERRED** — not a Phase-1 blocker |
| 006 | exp-03 | **ACCEPTED** — request allocator |
| 007 | exp-06 | **ACCEPTED** — temp only for immediate scratch |
| 008 | exp-07/08 | **ACCEPTED** — framework commit guard |
| 009 | exp-08 | **ACCEPTED** — conceptual/private boundary |
| 010 | later Advanced gate | **PROPOSED / DEFERRED** — not a Phase-1 blocker |
| 011 | exp-10 + comparative audit | **ACCEPTED** — void handler; typed observer later |
| 012 | WP7 repeated-binding prototype | **ACCEPTED** — single body consumer; no replay; arena-owned |
| 013 | Phase-4 proxy corpus | **PROPOSED / DEFERRED** — must close before trusted-proxy code |
| 014 | WP6 ownership decision | **ACCEPTED** — Response owns rendered bodies; no WP7 arena |

No accepted Phase-1 ADR has been reopened. ADR-012 is a new, narrowly owned WP7
decision. ADR-005 was accepted at the Phase-2 gate on WP12 evidence; ADR-010 and
ADR-013 remain owned by later gates and cannot expand earlier scope.

---

## Proposals recorded after the Phase-1 freeze

**Status of every entry below: PROPOSED.** None is accepted. They are recorded
so the owning work package inherits the reasoning instead of rediscovering it,
and each requires the owner's approval before it may be marked accepted. See
`post-phase1-audit.md` and `odin-fit-audit.md` for the evidence.

### ADR-015 (SUPERSEDED by ADR-021) — test-support grows by procedure group

**Superseded.** Accepted as ADR-021 on 2026-07-19, with the objective sharpened
to remaining one public name. Original proposal retained below.

**Context.** `test_request` takes only `(app, method, path)`, so a handler that
calls `web.body` can never be exercised in memory: it always sees
`invalid_json`. The framework's own tests reach the success path only by copying
`web/*.odin` into a throwaway package, which a user cannot do.

**Proposal.** Add a body-carrying variant through an explicit Odin procedure
group — `test_request :: proc{...}` — rather than a second name such as
`test_request_with_body`. In the pinned toolchain's own `core/`, procedure
groups are exactly how variants are added without creating a dialect
(`strings.builder_make`, `net.dial_tcp`, `net.recv`).

**Alternatives.** Changing the frozen signature (rejected: breaks the freeze);
a request-builder type (rejected for now: adds a lifetime and a second mental
model); enriching `Recorded_Response` (orthogonal — that concerns responses);
leaving advanced testing internal-only (rejected: leaves users stuck).

**Requires owner approval** — the test-support ledger grows beyond 2 symbols.

### ADR-016 (RESOLVED by WP12) — middleware execution order

**Outcome.** Resolved. The prototype ran; ADR-005 is accepted as onion with
enforcement. See ADR-019 and `planning/phase-2-prototype-middleware.md`. The
proposal text is retained below for the record.

### ADR-016 (original proposal text)

**Context.** Phase 2 needs `web.use` and `web.next`. Post-`next` (onion)
semantics requires an unwind machine at runtime, which the Odin-fit audit
classifies as `FOREIGN_ABSTRACTION_RISK`: hidden control flow is what Odin's own
FAQ argues against when it rejects exceptions.

**Proposal.** Prototype both onion and pre-order on the bootstrap transport,
measure per-request allocation and binary cost for each, and only then choose.
Flatten chains at registration either way, so dispatch stays flat data.

**Requires owner approval** — it sets the execution model for every later phase.

### ADR-017 (PROPOSED) — the response-commit invariant should be structural

**Context.** Three request-local scratch arrays on `Context_Internal` are
aliased by the committed response. Correctness rests on six independently
hand-written `if committed { return }` guards placed before each buffer write. A
seventh responder that writes before checking reintroduces a response that
reports one status while serving another body, and no gate check would catch it.

**Proposal.** Route scratch writes through a single helper that consults
`committed` first, or add a gate assertion on guard ordering, before Phase 2
adds responders.

Internal only; no public surface change; no owner approval required.

### ADR-018 (PROPOSED) — per-server state replaces the transport globals

**Context.** The adapter keeps package-level `g_server`/`g_config`. A second
`serve()` overwrites `g_config`, so the first server begins answering with the
second application's routes; `g_server` also briefly holds the address of a
stack local and is read non-atomically.

**Proposal.** Document the single-server constraint in Phase 2. In Phase 4,
which owns lifecycle, replace the globals with per-server state and introduce
the stop API at the same time.

**Requires owner approval when implemented** — Phase 4 adds public surface.


---

## ADR-019 — Middleware registration order is enforced, not documented

- **Status.** **ACCEPTED** (owner, 2026-07-19).
- **Owner.** Phase 2, implemented in WP17, specified in WP15.
- **Context.** With chains flattened at registration, `use()` cannot affect a
  route registered before it. WP12 measured what that costs when a programmer
  gets the order wrong: the mis-ordered program serves `/admin/users` with
  **`200 OK` to an unauthenticated caller**, purely because `get()` precedes
  `use(auth)`. There is no error, no warning and no runtime symptom. Moving one
  line fixes it.
- **Options.**
  (A) **Forbid `use()` after any route has been registered — fail at boot.**
  (B) No retroaction, documented in prose only.
  (C) Retroactive `use()`: a second pass re-flattens earlier routes.
- **Decision: (A).**
- **Rationale (owner).** An authentication boundary must not depend on the
  programmer remembering the order in which they wrote two lines. Option B
  leaves the 200-OK hole open, and **for security, prose is not enforcement**.
  Option C makes order "not matter" in a way that misleads anyone reading the
  file top to bottom, which is the opposite of Odin's explicitness. Option A is
  fail-closed and costs one guard at registration.
- **Costs.** A program that was legal becomes a boot failure. This is intended:
  it converts a silent security defect into a loud startup error, before any
  request is served.
- **Precedent.** Go's `ServeMux` panics at registration on conflicting patterns
  rather than resolving them silently (`planning/later-phases-plan.md` C-5).
  Rejecting a malformed application at boot is established practice, not a
  novelty.
- **Reversibility.** HIGH while Phase 2 is unfrozen; the guard is one check.
- **Sub-decisions — all four SETTLED by the owner, 2026-07-19.**

  **1. Does the rule apply inside a `Router`? YES.** `use()` must precede any
  route within the router too. A guard that only works at the top level merely
  moves the hole down one level: a `Router` that registers a route before its
  own auth serves the same 200-OK in silence. *A guard that only works at the
  top is not a guard.*

  **2. Does `mount()` close the window? YES.** `mount()` brings already-registered
  routes into the app, so a global `use()` after a `mount()` is rejected exactly
  as it is after a `get()`. Anything else falls back into the retroactivity
  already rejected. Practical rule: **global middleware before the mounts; a
  mount counts as a route registration.**

  **3. Failure mechanism — the earlier recommendation in this ADR was WRONG and
  is corrected.** A dry abort at the point of the offending call fails on two
  counts that the project's own discipline exposes:

  * *It breaks testability.* `use()` returns void, so it cannot signal by return
    value; the only options are aborting or registering-and-refusing. Aborting
    at the call site makes it impossible to write the test proving "a
    mis-ordered app is rejected" without killing the test runner — the same
    dead-end WP13 hit with `panic` in a handler.
  * *It breaks transport parity (R-10).* If the guard lived only in `serve()`,
    `test_request` — which never calls `serve()` — would dispatch the
    unprotected route in memory: **200 in the test, 500 on the socket.** The two
    transports would diverge on exactly the security property they exist to keep
    identical.

  The guard is therefore fail-closed, **detected at registration**, and must
  satisfy three properties:

  * **(a) identical on both transports** — it lives on the dispatch path, not
    only in `serve()`;
  * **(b) observable to a test** — a private "poisoned app" predicate, in the
    spirit of WP11's `nm` assertions, rather than an abort that kills the
    runner;
  * **(c) a diagnostic that names the offending pattern and says what to do.**

  The exact mechanism — poison the `App` so every request becomes a 500 and
  `serve()` refuses to bind, versus a cured abort — is a **WP17 prototype**. The
  three properties are the requirement. This is *more* fail-closed than a dry
  abort, and unlike it, testable.

  **4. Does `bare()` enforce it too? YES.** `bare()` omits the default 404/405
  responders; it does not exist to switch off a safety interlock in the
  middleware mechanism. If `use()` is available in `bare()`, the same guard
  applies. **`bare()` means "no default policy", not "no safety".**

## ADR-020 — Recovery is the driver guarantee, not a middleware

- **Status.** **ACCEPTED** (owner, 2026-07-19).
- **Owner.** Phase 2, WP21. Public surface: **zero symbols.**
- **Context.** The Phase-2 scope promised "recovery middleware — becomes
  default-on in `web.app()`" and a gate item "recovery converts panic to
  standardized 500". WP13 established two language facts that make this
  impossible rather than merely difficult, both reproduced independently:
  1. **`app()` can never install a hook.** Odin's `context` is an implicit
     by-value parameter, so a callee's assignment dies with its frame — the
     caller still sees the old value.
  2. **A working hook would not be enough.** Only `panic`, `assert` and failed
     type assertions reach `assertion_failure_proc`. Bounds-check failures, nil
     dereferences and divide-by-zero do not; `bounds_check_error` is
     `proc "contextless"` and cannot consult the hook even in principle.
- **Options.**
  (A) "Last gasp": write a 500 from a fault hook, then abort.
  (B) **Redefine recovery as the existing WP8 driver guarantee** — an
      uncommitted response is finalized to a standardized 500 — plus honest
      documentation that Odin aborts on panic.
  (C) `setjmp`/`longjmp` to continue after a fault.
  (D) Remove the item entirely.
- **Decision: (B).** Option (A) is deferred to Phase 4 as a **"last-gasp
  responder"**, a name that must never be shortened to "recovery".
- **Rationale (owner).** The promise as written is not hard, it is impossible,
  and freezing it would freeze a lie. The alternatives are worse and measured:
  (C) leaks **8,250 bytes per recovered fault**, linear — a 4 GiB container dies
  in about 8 minutes while answering 500s and never signalling its supervisor;
  (A) exports a raw file descriptor through the ADR-009 boundary and becomes
  cross-connection response injection as soon as more than one thread serves.
  (B) is the only option that neither widens the public surface nor opens a hole.
- **Accepted cost, stated plainly.** A panicking handler closes the connection —
  the client sees `curl: (52) Empty reply from server` — and the process falls
  over for a supervisor to restart. That is standard behaviour for a serious
  runtime, and it is accepted deliberately rather than discovered later.
- **Evidence.** `planning/phase-2-prototype-recovery.md`.
- **Doc impact.** `knowledge-base/03-development-phases.md` §Phase 2 scope and
  Test Gate are amended; `planning/phase-2-plan.md` WP21 drops to zero symbols.
- **Reversibility.** HIGH — nothing is exported, so Phase 4 may add a last-gasp
  responder without a breaking change.


## ADR-021 — Test-support grows by procedure group, under one public name

- **Status.** **ACCEPTED** (owner, 2026-07-19). Supersedes ADR-015 (PROPOSED).
- **Owner.** Phase 2, WP14.
- **Context.** `test_request` takes only `(app, method, path)`, so a handler
  calling `web.body` can never reach its success path in memory — it always sees
  `invalid_json`. The framework's own tests reach it only by copying
  `web/*.odin` into a throwaway package, which a user cannot do.
- **SCOPE, as accepted by the owner.** **WP14 owns `body` + `query`.** Request
  **header injection moves to WP19**, together with the `web.header` and
  `web.bearer_token` lookups that make headers publicly observable — Phase 1
  exports no header accessor, so a `headers` parameter added now would be
  **write-only**: settable, and readable by nothing. `Header_Pair` is not
  exported and no test-only header type is introduced. **Response-header
  recording stays outside WP14** entirely (see D-14.3).

- **On public impact, corrected.** An earlier note called the choice between a
  procedure group and a default parameter "no public impact either way". That is
  wrong, and the distinction is the whole reason for the decision: the **symbol
  count** is identical, but the **callable contract** is not. A group over
  private members leaves that contract invisible to the snapshot and free to
  change; a default parameter puts it in the frozen record. The default
  parameter is preferred precisely because its full public contract is
  inspectable and frozen.

- **AMENDED 2026-07-19 — the mechanism changes, the objective does not.** The
  variant is added by a **default parameter on the existing procedure**, not by
  a procedure group. One public name, ledger unchanged at 2, existing call sites
  untouched — every goal below is still met, by a simpler means.

  **Why the group was withdrawn.** Measured on the pinned compiler: `odin doc`
  renders a group as `name :: proc{member_a, member_b}` — member names only.
  With `@(private)` members those names resolve to nothing else in the doc
  output, so the freeze snapshot pins the group's name and **not its signature**.
  Rewriting a member's parameters from `(Method, string, string)` to
  `(Method, string, []u8, int)` left the snapshot line byte-identical while the
  symbol stayed publicly callable. A group over private members is therefore
  unfreezable, and `build/check_phase1_freeze.sh` now rejects the construct
  outright rather than pretending to freeze it.

  A default parameter keeps the entire contract in the frozen record:

  ```
  test_request :: proc(a: ^App, method: Method, path: string,
                       body: string = "") -> Recorded_Response
  ```

  It also introduces no new concept, and matches how `core` adds optional
  behaviour everywhere (`allocator := context.allocator`, 726 occurrences).

- **Superseded decision.** Add the body/header-carrying variant through an
  explicit Odin **procedure group**, with the objective of **remaining ONE
  public name**: `test_request`.
- **Why a group and not a second name.** This is the whole reason the audit
  recommended a group. If the variants stay `@(private)` under the group, the
  **test-support ledger stays at 2** and only the signature snapshot changes.
  A second name (`test_request_with_body`) would be a second canonical way to do
  one operation, which G-01 rejects, and would grow the ledger for no gain.
- **If the toolchain will not allow a single name.** WP14's D-14.1 compile probe
  decides this. If an exported procedure group cannot have private members on
  the pinned compiler, the growth goes to **the minimum** — and the number is
  reported before it is adopted, not after.
- **Route to acceptance: a freeze amendment.** Either way this lands by amending
  the freeze rather than bypassing it: update
  `build/phase1-public-signatures.txt`, the manifest in
  `planning/phase-1-freeze.md`, and the gate's ledger numbers, in the same
  change, with the evidence attached.
- **On whether this violates the freeze — it does not.** Freeze never meant
  "never changes". It meant "changes only with evidence and a recorded
  amendment". WP11 built that door deliberately. Using it here is the system
  working as designed, not an exception to it. The gate's named assertions still
  fire: a snapshot cannot be refreshed to launder a change, because the
  assertions encode the decision rather than the current state.
- **Reversibility.** HIGH — the group reduces to its single Phase-1 member, and
  every existing call site is untouched because the simple form is a member of
  the group.
