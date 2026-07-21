# Architecture Decision Records

Status: **MIXED.** Human decisions recorded on 2026-07-18 accept ADR-001,
ADR-002, ADR-003's value-only baseline, ADR-004, ADR-006, ADR-007, ADR-008,
ADR-009, and ADR-011. Decisions recorded on 2026-07-19 accept ADR-005 (with
ADR-019), ADR-020, ADR-021 (as amended), and — at the WP15 Spec Gate —
ADR-022 through ADR-027 (ADR-025 as option B, against the WP15
recommendation). ADR-010 and ADR-013 remain PROPOSED/deferred to their owning
gates. Reproducible compiler evidence lives
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
- **Status.** **ACCEPTED** (2026-07-20, decided under the ADR-029 delegation) —
  option **A**, with activation deferred: the Advanced API stays
  designed-not-shipped until a real external user request exists, and it never
  appears in the Quick Start. Activation is itself a recorded decision.
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
- **Status.** **ACCEPTED IN DIRECTION** (2026-07-20, decided under the ADR-029
  delegation) — option **A**: the default effective address is the connected
  peer, forwarding headers are ignored until trusted proxies are explicitly
  configured, and `Forwarded` is never echoed into a response. This is the
  fail-closed arm, which is why deciding the direction early is safe. Exact
  header support and public configuration signatures remain owned by the
  Phase-4 prototype (P4-7), as the Recommendation below already states.
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

---

## WP15 Spec Gate decisions

**Status: ALL SIX DECIDED by the owner, 2026-07-19, in the PR #30 review of
the WP15 Spec Gate.** ADR-022, -023, -024, -026 and -027 are ACCEPTED as
recommended; ADR-025 is ACCEPTED as **option B** — the reviewer's
counter-recommendation, not the WP15 recommendation. The option analysis below
is retained verbatim as presented; each entry's Status line records the
outcome. Evidence citations refer to
`planning/phase-2-prototype-middleware.md` (WP12) and
`planning/phase-2-prototype-recovery.md` (WP13), which carry the verbatim
commands and outputs.

## ADR-022 — the post-`next` promise: B1 or B3

- **Status.** **ACCEPTED** (owner, 2026-07-19) — **B1**, as recommended.

- **Question.** ADR-005 accepted the onion mechanism, in which code written
  after `next(ctx)` inevitably runs. What does the specification promise about
  it? B2 ("leave it unspecified") was rejected on sight by the plan: observable
  but undocumented is the worst of both.
- **Options.** **(B1)** Specified and tested: exact reverse unwind order; a
  post-commit response attempt is rejected by the single-commit guard with the
  first response byte-identical; a second `next()` is a no-op with the handler
  running exactly once. **(B3)** Documented as forbidden, untested, no
  guarantee — the code still runs.
- **Recommendation. B1.** The behaviour is the direct consequence of `next`
  being a call (WP12 P4), cannot be prevented without removing `web.next`, and
  the one dangerous act — responding late — is already rejected byte-identically
  on both commit paths (P5, P5b). The no-op double-`next` is a DESIGN
  CONSTRAINT, not a free property: the WP12 integrator's counter-example cursor
  (also monotonic, also per-request) runs the handler TWICE when the terminal
  handler sits outside the index bound. B1 therefore obliges WP17 to ship a
  test that fails if a refactor moves the terminal handler outside the bound.
- **Strongest argument against.** B1 freezes exact-reverse unwinding across
  implementation changes nobody has prototyped: an iterative dispatcher, an
  async transport, or a chain resumed on another thread would have to reproduce
  reverse order without a live frame per middleware, which is expensive. B3
  keeps that door open at the price of an honesty gap that lasts until the
  first user writes a statement after `next`. Note also the coupling: under
  B3, WP22's latency-measuring logger is descoped — it needs post-`next`.
- **Public impact.** No symbol either way; B1 adds normative text and tests.
- **Reversibility.** B1 → B3 is a broken promise (LOW after applications rely
  on after-hooks); B3 → B1 is a pure strengthening (HIGH).

## ADR-023 — app-level middleware observe 404/405 (the miss chain)

- **Status.** **ACCEPTED** (owner, 2026-07-19) — option **A**, as recommended,
  including the sub-decision: the fail-closed guard also rejects `use()` after
  the first dispatch, so the miss chain is built lazily once and never
  invalidated.

- **Question.** Chains attach to routes; a miss has no route. Do app-level
  middleware observe a 404/405, and does `bare()` behave the same?
- **Options.** **(A)** Yes, via a second flattened chain of the app-level
  globals terminating in the automatic 404/405 responder (WP12 P13: measured
  `A>B><B<A` around both, envelopes and `Allow` unchanged); `bare()` runs the
  same chain with a no-op terminal. **(B)** As (A) but `bare()` misses skip
  middleware (the prototype's measured inconsistency, documented). **(C)** No —
  middleware run on matched routes only; users register a catch-all route to
  observe misses.
- **Recommendation. A.** Otherwise `logger` silently misses most hostile
  traffic and `request_id` cannot correlate a 404 — and once audit/rate-limit
  middleware exist, "misses are invisible" is the hole an attacker probes. For
  `bare()`, ADR-019's own principle extends: `bare()` means no default POLICY,
  not no mechanism; its no-op terminal commits nothing and the driver 500
  finalization applies unchanged. Sub-decision, recommended together: the
  ADR-019 guard also rejects `use()` after the FIRST DISPATCH, which closes the
  one remaining stale-chain edge (use → dispatch-a-miss → use again, legal
  today because no route exists) and lets the miss chain be built lazily once
  and never invalidated — deleting P13's rebuild-on-invalidation pool growth
  (`[3, 6, 10, 15]`) entirely.
- **Strongest argument against.** P13's own cost sheet: this is the most
  complexity per unit of value in Phase 2 — a second chain, lazy construction,
  a `bare()` rule, and an App back-pointer on the Context that `context.odin`
  documents as deliberately absent (avoidable only by special-casing the miss
  terminal in the dispatcher, at the cost of a branch in `next`). Option C
  needs none of that machinery and is defensible prose.
- **Public impact.** No symbol. Behavioural surface: misses become observable
  to middleware.
- **Reversibility.** MEDIUM once shipped — applications will rely on loggers
  seeing 404s; withdrawing it is a silent behaviour change.

## ADR-024 — `Router` + `router` + `mount`; `web.group` rejected

- **Status.** **ACCEPTED** (owner, 2026-07-19) — option **A**, as recommended.
  `web.group` does not exist; the phases-doc scope line is amended
  accordingly.

- **Question.** The phases doc lists `web.router`, `web.group`, `web.mount`.
  Once a detached `Router` can be mounted at a prefix, is `web.group` a second
  canonical way to do one operation?
- **Options.** **(A)** `Router` + `router()` + `mount()` only; no `web.group` —
  `group(&app, "/admin")` is exactly "make a router, mount it here", which
  G-01 rejects; amend the phases doc. **(B)** `web.group` only, no detachable
  `Router` — one concept, but a module can no longer export its routes for an
  application to mount, which is the capability WP18 exists to deliver.
  **(C)** Both — maximally convenient, and a textbook G-01 violation.
- **Recommendation. A.** +3 symbols, one ownership story (two owned values,
  `App` and `Router`, each destroyed once, never copied — the same rule
  restated), and module-exported routes fall out. This is presented fairly, not
  rubber-stamped: (B) genuinely is smaller for single-file applications, and
  the owner should weigh that against losing mountable modules.
- **Strongest argument against.** For the dominant small application,
  `group(&app, "/admin", auth)` is one line where (A) needs three
  (`r := web.router()`, registrations, `web.mount(&app, "/admin", &r)`), plus a
  second owned value with a `destroy` obligation. G-01 rejects synonyms, but
  (B) is not a synonym if `Router` never ships — the rejection of `group`
  presupposes choosing the `Router` capability first.
- **Public impact.** +3 application symbols (`Router`, `router`, `mount`);
  amends `knowledge-base/03-development-phases.md` §Phase 2 scope (exact text
  in `planning/phase-2-spec.md` §10.1).
- **Reversibility.** Adding `group` later is HIGH (additive sugar, though a
  permanent G-01 scar); removing a shipped `Router` is LOW.

## ADR-025 — route-level middleware as a variadic on the five verbs

- **Status.** **ACCEPTED** (owner, 2026-07-19) — option **B**, AGAINST the
  WP15 recommendation. The owner's review weighed the ADR's own
  argument-against as decisive: the variadic is the only Spec Gate item with
  LOW reversibility, it mutates five frozen Phase-1 signatures for a
  convenience, `get(&app, "/x", h, auth, audit)` gives the reader five
  positional arguments with no cue which are middleware, and WP12 recommended
  it without having built the alternative it competes with. Route-level
  middleware is therefore expressed as a **one-route `Router`** mounted at the
  path; the five verbs stay frozen. B → A later is HIGH reversibility: the
  variadic remains available by freeze amendment if real usage proves the
  need.

- **Question.** How does one route get its own middleware: a variadic tail on
  the five frozen registration signatures, or a one-route `Router`?
- **Options.** **(A)** `get :: proc(a: ^App, pattern: string, handler: Handler,
  middleware: ..Handler)` on all five verbs — a ratified freeze amendment to
  five Phase-1 signatures, through the same door as WP14's Amendments 1–2.
  WP12 P12 measured: all three Phase-1 examples compile unchanged; the
  variadic adds zero heap allocations (3 → 3 with 0, 1 or 2 route middleware);
  the exact `odin doc` delta is five mutated signatures plus the two new names
  `use`/`next`. **(B)** No signature change — a route needing middleware is
  written as a one-route `Router` and mounted.
- **Recommendation. A.** Zero new names, zero allocation, proven source
  compatibility, and the freeze-amendment path exists precisely for
  evidence-backed changes like this. (B) makes the common case ("this one
  route needs auth") the most ceremonious construction in the framework.
- **Strongest argument against.** It mutates five frozen signatures for a
  convenience, and a variadic tail is the least readable way to say "this
  route has an auth guard": `get(&app, "/x", h, auth, audit)` is five
  positional arguments with no cue which are middleware or what order they run
  in. (B) leaves the freeze untouched and states intent explicitly. WP12 made
  its recommendation without having built the alternative it competes with.
- **Public impact.** Zero new symbols either way; (A) changes five frozen
  signature lines in `build/phase1-public-signatures.txt` via recorded
  amendment.
- **Reversibility.** (A) is LOW once call sites use the tail — removing a
  variadic breaks source. (B) → (A) later is HIGH.

## ADR-026 — `Framework_Event` field set and redaction policy

- **Status.** **ACCEPTED** (owner, 2026-07-19) — option **A**, as recommended.

- **Question.** ADR-011 promised a Phase-2 typed observer. What exactly does
  the event carry, and what can never reach it?
- **Options.** **(A)** `Framework_Event{kind: Framework_Error, method: Method,
  route: string, status: Status, payload_type: typeid}`, passed by value;
  `route` is the REGISTERED PATTERN (App-owned) and `""` on a miss; no message
  string; `observe(a, proc(event: Framework_Event))`, one observer, last
  registration wins. `Framework_Error` is the existing private closed enum
  made public. **(B)** As (A) plus a `message: string` of the static
  diagnostic constant. **(C)** As (A) plus the raw request path for
  debuggability.
- **Recommendation. A.** The hard constraint is external and normative: the
  OpenTelemetry HTTP conventions require `http.route` to be low-cardinality,
  forbid populating it when the framework cannot supply it, and state the URI
  path cannot substitute for it — so (C) is rejected outright as both a
  cardinality explosion and a PII leak. No message string, because
  `framework_report` emitting only compile-time constants is precisely why the
  audit could refute log leakage; (B) surrenders nothing today but invites a
  future formatted message. Under (A) the safety is BY TYPE: the only string
  field is the App-owned pattern, so an observer that stores the event cannot
  dangle and no request byte is reachable — a property WP16/WP20 turn into a
  gate assertion.
- **Strongest argument against.** (A) may be too spartan to be useful: an
  observer wiring Sentry gets a kind, a method, a pattern and a status, but no
  request correlation (no request ID field, no timestamp) and no human text,
  so every consumer immediately needs its own enum-to-message table — six
  copies of the constants the framework already has. Growing the event later
  is a frozen-struct change; starting minimal bets that Phase 4's observability
  work can pay for the growth properly.
- **Public impact.** +3 application symbols (`observe`, `Framework_Event`,
  `Framework_Error` — the enum already exists privately).
- **Reversibility.** Adding fields to a frozen public struct is a spec
  amendment; removing them is breaking. Start minimal (HIGH → LOW as consumers
  appear).

## ADR-027 — request-ID trust policy and the header overlay

- **Status.** **ACCEPTED** (owner, 2026-07-19) — option **A**, as recommended:
  strict charset/length, never echo or log an invalid inbound value, the
  header overlay. `request_id` is +1; the +2 accessor contingency is closed
  unless implementation evidence reopens this ADR (owner approval required).

- **Question.** Is a client-supplied `X-Request-Id` honoured, how are IDs
  generated, and how does a handler read the effective ID? This is a security
  boundary: the inbound value is attacker-controlled.
- **Options.** **(A)** Accept the client value only if it matches charset
  `[A-Za-z0-9._-]` and length 1..64; otherwise generate fresh and DISCARD the
  client value, never logging or echoing it. Generation: counter + process-
  start entropy, allocation-free, documented as NOT unguessable. The
  middleware writes the effective ID into a private request-header overlay
  that `web.header` consults (documented as "the effective request header"),
  and sets the response header. +1 symbol (`request_id`). **(B)** As (A) but
  no overlay: a public `request_id_value(ctx)` accessor instead. +2 symbols.
  **(C)** Always generate; never honour the client value. **(D)** Echo
  whatever arrives (rejected on sight: CR/LF header injection and log
  poisoning).
- **Recommendation. A.** The strict charset makes header injection impossible
  by construction (and WP23 tests CR/LF anyway); honouring well-formed inbound
  IDs is what makes cross-service correlation work behind a gateway that
  already stamps them. The overlay keeps one canonical read path (`web.header`)
  instead of a second name, per G-01.
- **Strongest argument against.** The overlay makes `web.header` answer with a
  byte sequence that never arrived on the wire — implicit mutation of an
  otherwise pure lookup, discovered rather than declared unless the
  documentation is read carefully. (B) costs one honest symbol and keeps
  `header` strictly "what arrived". And against honouring inbound IDs at all
  (for (C)): any accepted client value appears in the operator's logs, so a
  well-formed-but-hostile ID can still spoof correlation across tenants;
  always-generate is the only variant with zero attacker influence.
- **Public impact.** +1 application symbol (`request_id`), +2 if the overlay
  is rejected. Trust policy becomes documented, tested security behaviour.
- **Reversibility.** Tightening the charset later is HIGH; loosening or
  switching overlay↔accessor after applications read IDs is LOW.

## ADR-028 — request-scoped typed state: does it exist at all?

- **Status.** **ACCEPTED** (2026-07-20, decided under the ADR-029 delegation) —
  option **A**: no request-scoped state. The revalidation cost is ratified,
  and the documented workaround — call `current_user` once and pass the `User`
  down as an ordinary parameter — is the answer, not a mitigation. Grounds:
  C-6's research conclusion, the observed datapoint below, and the fact that
  (A) is the only reversible option, which a delegated decision must weigh
  heaviest. **Reopening requires a real program measured in this tree** that
  cannot be written cleanly; the named successor, should that evidence ever
  arrive, is option (C). Opened 2026-07-20 by the Phase-3 planning pass; owned
  by WP37. The G-08 history stands: a correction was already required because
  shipped documentation promised an outcome before any decision existed.

- **Question.** Can a middleware hand a typed value to a handler? Today it
  cannot, and the canonical auth pattern pays for it: `current_user`
  REVALIDATES the token on every call, because there is nowhere to put the
  `User` that `require_auth` already built.

  This is **not** the question ADR-004 answered. ADR-004 accepted
  `web.state(ctx, T)` for APPLICATION state — one `rawptr` + `typeid` on the
  `App`, set before serving, for a database handle or configuration. Per-request
  values have a different lifetime, a different owner and a different failure
  mode, and conflating the two is exactly the error that produced the false
  promise this ADR now exists to prevent.

- **Options.**
  **(A) No request-scoped state, permanently.** Ratify the revalidation cost.
  The documented workaround — call `current_user` once at the top of the
  handler and pass the `User` down as an ordinary parameter — becomes the
  answer rather than a mitigation.
  **(B) A small fixed `[N]{typeid, rawptr}` array** in request storage, typed
  at access. Bounded, no map, no allocation. This is C-6's own fallback
  phrasing: *"if extensibility is ever genuinely required"*.
  **(C) A single typed slot for one application value**, mirroring the
  WP19/WP23 header-overlay design: one slot, known capacity, one writer
  ratified per phase, no general-purpose store.

- **Recommendation. (A), and the burden of proof is on anyone proposing
  otherwise.** Research finding C-6 examined the two mainstream mechanisms —
  Go's `context.WithValue` (one heap allocation per value, a full `Request`
  copy per middleware, O(depth) lookup) and Rust's `http::Extensions` (a boxed
  `HashMap<TypeId, Box<dyn Any>>`) — and concluded that both exist for
  type-erased, dynamically-keyed state crossing library boundaries, which
  Uruquim does not have. Its conclusion is that struct fields in request
  storage dominate both, and that this **supports G-03 rather than challenging
  it**. Option (A) is also the only reversible one: adding a mechanism later is
  a pure strengthening, while shipping one and withdrawing it breaks
  applications.

- **Strongest argument against (A).** The cost is real and it is paid by the
  most common middleware there is. An application whose validation is a
  database round-trip pays it per call, and the workaround — threading a
  parameter through every procedure that needs the user — is exactly the
  boilerplate a framework is supposed to remove. If a real application is
  measured writing that thread through five call sites, (C) becomes serious.
  **Evidence for (B) or (C) must be a real program that cannot be written
  cleanly today, never a hypothetical.**

- **Observed datapoint (2026-07-20, reference only).** One external real
  program was examined: `arturfil/coffees_odin`, a third-party CRUD service
  written against the same odin-http backend Uruquim vendors. Its auth
  middleware validates the JWT and **discards the claims**; its `/auth/me`
  handler then re-validates the same token itself. So a real program on this
  exact backend pays the revalidation cost today — at string-comparison cost,
  with no database round-trip — and its author neither threads the user down
  as a parameter nor works around the repetition. Recorded as an observation
  from a reference program, not as evidence for any option: the burden of
  proof above is unchanged, and it names a real program **measured in this
  tree**.

- **Public impact.** (A) zero symbols. (B) and (C) add public surface, a
  capacity-ledger row, a lifetime-ledger row, and a claim with a negative
  control.

- **Reversibility.** (A) → (B)/(C) is HIGH — a pure strengthening.
  (B)/(C) → (A) is LOW once applications store values.

## ADR-029 — the mission, and how decisions are made from here

- **Status.** **ACCEPTED** (owner, 2026-07-20). This ADR records a decision
  the owner made directly, and it is the authority every later *"decided under
  the ADR-029 delegation"* note points back to.

- **Context.** The governing rule was "no decision is marked accepted without
  the owner" (roadmap rule 6), which had produced a queue of PROPOSED matters
  and pending approvals. On 2026-07-20 the owner delegated those decisions and
  future work-package approvals to the executing agent, and named the value
  that decides them: ***A web framework for the Joy of Programming*** — the
  README's own line.

- **Decision 1 — the mission is a rule, not a slogan.** Precedence is fixed
  and explicit:
  1. **Discipline first.** Measurement decides performance; fail-closed is the
     default; security decisions take the distrusting arm; the guardrails
     G-01…G-11, the ledgers and the gated words are never overruled by joy.
  2. **Joy second.** When discipline does not decide, choose the option that
     makes writing a program feel better: fewer concepts to hold (FINDING-D's
     budget is joy made measurable), diagnostics at registration or boot
     rather than at 3 a.m., less ceremony, clearer names.
  3. **Convenience last.** A pleasant idea that grows public surface is not
     joy; it is scope. Joy may never be cited to justify a new symbol — G-09
     evidence still does that.

- **Decision 2 — the delegation.** From 2026-07-20 the executing agent decides
  PROPOSED matters and work-package approvals itself, under three conditions:
  * every such decision is **recorded** where the project records decisions
    (this file, the plan, the freeze), marked *"decided under the ADR-029
    delegation"*, with its grounds;
  * where the evidence does not clearly favour one arm, the agent takes the
    **most reversible** arm;
  * a pre-approval is **conditional**: if the work package's own spec or
    prototype work contradicts the decided arm, the agent stops and records
    the finding instead of proceeding.

- **Decision 3 — reserved matters.** These still stop for the owner, always:
  * cutting any release, tag or version (the roadmap already says this);
  * changing `LICENSE`;
  * changing the mission itself;
  * making Tina a dependency, or committing `tina/` — owner decisions already
    recorded, listed here so the delegation can never be read as loosening
    them;
  * rewriting published git history;
  * anything the agent itself judges both hard to reverse and genuinely
    uncertain — the delegation is a licence to decide, not an obligation to
    guess.

- **Revocation.** The owner revokes or narrows this delegation by saying so,
  in a sentence, in any session. No ceremony.

- **Consequences applied the same day.** ADR-010 (A, activation deferred),
  ADR-013 (A, in direction) and ADR-028 (A) moved to ACCEPTED under this
  delegation, and the Phase-3 plan's owner-approval points were resolved in
  advance (plan §2b).

- **Reversibility.** HIGH — revoking the delegation restores the previous
  regime untouched, and every decision made under it is individually
  revisitable by the owner at any time.

## ADR-031 — read and write deadlines: built in the core, not delegated to a proxy

- **Status.** **ACCEPTED** (2026-07-20, decided under the ADR-029 delegation).
  Supersedes nothing: the question had never been decided, only deferred, and
  WP36 deferred it with evidence rather than by preference.

- **Context.** Phase 3 shipped `web.Limits` **without timeout fields**. The
  WP36 prototype found the vendored server has no read or write deadline to
  configure: `Server_Opts` carries `limit_request_line` and `limit_headers` and
  nothing temporal, and its request read still carries an unfinished-work
  comment asking for a timeout. Shipping a field that did nothing would have
  been a lie with a version number on it, so `Limits` shipped with three byte
  budgets and no time budget. **That left a real hole, and this ADR closes it
  rather than documenting it.**

  A framework with no read deadline cannot defend itself against a client that
  opens a connection and sends one byte a minute. That is slowloris, it is
  cheap, and no amount of byte limits reaches it — the request never gets large,
  it only gets slow. Phase 4's own theme is *"mistakes stop being inconvenient
  and become remotely exploitable"*; a missing deadline is exactly that class.

- **Options.**
  - **(A) Delegate to the reverse proxy.** Document that the supported topology
    terminates TLS and enforces timeouts upstream, and state the absence.
  - **(B) Build deadlines in the core**, as new rows in WP36's boot-derived
    runtime, enforced on the serving path.
  - **(C) Replace the vendored server** with one that has deadlines.

- **Benefits and costs.**
  - **A** costs nothing and is honest, and the topology it names is the one
    most deployments already use. Its cost is that the framework's *own*
    guarantee stops at the byte budget: `web.serve` bound directly to a port is
    not a defensible configuration, and every document has to keep saying so.
  - **B** costs a vendored patch and the obligation to prove it. Its benefit is
    that the guarantee becomes the framework's, and the sentence *"Uruquim
    bounds its own per-request working memory"* gains a time dimension it
    currently lacks.
  - **C** is R-T3, rejected and staying rejected.

- **Evidence, and it is the reason this ADR exists at all.** The primitive is
  present in the pinned toolchain: `core:nbio` exports `timeout(duration, cb)`
  and `close(subject)`, and **the vendored server already uses both** — a fixed
  close delay and a one-second date tick. So a per-connection deadline is a
  timer armed beside an existing read and a close on expiry, not a new
  concurrency mechanism and not a rewrite. What it does require is touching the
  vendored server's connection handling, because the adapter does not see
  individual connections; `http.serve` owns the loop.

  **That is a known, disciplined path in this repository rather than new
  territory: five vendored patches already ship, and the WP9 corpus asserts
  their behaviour rather than their text**, so a correct re-application written
  differently still passes.

- **Decision. Option B.** Read and write deadlines are built, and they are
  **rows in `web.Limits`** — the same boot-derived, validated-once runtime WP36
  established, never a second mechanism. Three constraints bind the work:

  1. **`Limits` grows by amendment, and the fields are named at spec time.**
     WP36's rule stands: every field is a promise kept for as long as the type
     exists. The number of new fields is decided against the fault lab's menu,
     not against a wish list.
  2. **The vendor patch is governed before it is written.** WP51's vendor
     maintenance policy therefore moves **before** the package that patches —
     see the Phase-4 plan's sequencing amendment. A patch that predates the
     policy governing patches is how a fork starts.
  3. **It is proven by the WP41 fault laboratory, not by a unit test.** A
     deadline is a claim about a slow client, and the only honest proof is a
     seeded slow client. The claim ledger row carries that as its positive test
     and an unbounded-read variant as its negative control.

- **Risks.** The patch is on the connection read path, which is the hottest and
  least forgiving code in the tree; a deadline that fires early is a broken
  server, and one that never fires is a claim that lies. Both are why the fault
  lab precedes it. Second risk: the deadline interacts with the concurrency
  decision (ADR-030) — if `serve` becomes threaded, timer ownership changes.
  This ADR therefore **does not fix the mechanism**, only the requirement and
  the shape; WP42 lands first and WP46 inherits whatever it decides.

- **Doc impact.** The capacity ledger's timeout row (currently *"still not
  configurable, and not on a schedule"*) becomes a bounded, configurable row at
  the Phase-4 freeze. `docs/ai-context.md` and `docs/canonical-patterns.md`
  currently instruct agents that no timeout field exists and none may be
  invented; both are amended in the same change that ships the fields, never
  before.

- **Reversibility. LOW once shipped**, and deliberately so: an operator who
  configures a deadline builds a timeout budget around it, and withdrawing the
  field breaks the build while withdrawing the DEFAULT breaks their traffic
  silently. That asymmetry is the argument for shipping the smallest set of
  fields that the fault lab can actually demonstrate, exactly as WP36 sized its
  byte budgets.

### Amendment 1 (2026-07-20) — the requirement stands; the MECHANISM was decided too early

**What was wrong with this ADR as first written.** It fixed the mechanism —
patch the vendored connection read — *before* WP41's fault laboratory exists to
say how that server actually behaves under a slow client, a concurrent close or
a fragmented read. That inverts this project's own method, which is measure
first and decide second, and it was decided partly on a design constraint
inferred from an offhand instruction rather than from evidence. The owner
subsequently withdrew that constraint and asked for **the recommended solution**
instead. This amendment is that correction, recorded rather than rewritten,
because a decision log that quietly changes its mind teaches nothing.

**The comparison that reframes it, and it is evidence rather than analogy.**
The stated target is *"what Gin is in Go"*. **Gin does not implement timeouts.**
It is a thin routing-and-middleware layer over `net/http`, and read, write and
idle deadlines come from `http.Server` — the standard library's server, not the
framework. Gin never patched `net/http`, because it never had to.

So the gap here is **not a framework-design gap, it is a foundation gap**:
Uruquim is already the thin, fast layer, and the server beneath it is not yet
production-grade. Naming it correctly changes what the right fix is.

**What stands.**

* **The requirement.** A framework whose server can be held open indefinitely by
  a slow client has a real hole, and byte budgets cannot reach it. Delegating
  the deadline to a reverse proxy still leaves WP44's shutdown without a clock
  to bound in-flight work with. Option A remains rejected as the *final* answer.

**What changes.**

* **The mechanism is no longer fixed here.** WP46 chooses it *after* WP41, with
  the lab's evidence in hand, from: upstreaming to `odin-http`; a carried
  vendored patch; or the deadline living in whatever transport WP42/WP43 leave
  behind.
* **Upstream is worth ONE attempt, but it is NOT a dependable path — checked,
  not assumed.** `laytan/odin-http`'s own README states *"This is beta
  software... can certainly contain edge cases and bugs"* and *"I do not
  hesitate to push API changes at the moment, so beware"*, with 17 open issues
  and 8 open pull requests against a single principal maintainer (checked
  2026-07-20). An upstreamed timeout would wait in one maintainer's queue and
  then have to be re-vendored across an API its author says moves. Code we do
  not own is code we do not maintain — but a plan may not be built on someone
  else's merge. See **ADR-033**, which makes the foundation itself the question
  rather than this one field.
* **It lands after WP42/WP43, not before.** Per-connection timers have lifetime
  and cancellation semantics that the concurrency decision changes. Building
  them first means building them twice, and timer-after-close is a classic
  use-after-free — exactly the class of defect that "will not cause problems"
  rules out.
* **The interim is a documented boundary, not a hidden hole.** Until deadlines
  ship, direct exposure without a proxy is **not a supported deployment**, and
  WP55 says so in those words. That is what Gin's users do in practice too; the
  difference is that this project writes it down.

**The plan's own sequencing already protected against this error** — WP41
precedes WP46 in §2c — which is the argument for the discipline rather than a
coincidence. The ADR simply should not have pre-empted the package.

**Reversibility of this amendment: HIGH.** It removes a commitment and adds
none; the requirement it keeps is the one nobody disputes.

## ADR-032 — the ecosystem's relationship to the core, and when it may start

- **Status.** **ACCEPTED** (2026-07-20, decided under the ADR-029 delegation).
  Scope: the two questions PR #49 (`crystals-ecosystem-plan`, draft) leaves as
  unmet entry conditions CE-E3 and CE-E4. It does **not** accept ADR-C001…C008,
  which remain the ecosystem's own to settle.

- **Context.** A draft proposes an optional-package ecosystem ("Crystals"):
  fourteen documents, no code, every ADR PROPOSED. Its own bookkeeping records
  three of four entry conditions unmet, all of them owner decisions rather than
  engineering blockers. Two of the three are cheap to answer and cost nothing
  to hold; leaving them open costs something real, because the documents were
  written against a 44-symbol Phase-2 core and decay as the tree moves.

- **Decision 1 — CE-E3 is ACCEPTED, and it is a rule about THIS repository.**
  *No ecosystem work may add, widen or change a core symbol.* If an optional
  package cannot be written against the frozen surface, the finding is written
  down and the package waits; it does not become a reason to export something.
  This is stated here, in the core's own ADR log, rather than in the
  ecosystem's, because **it is a promise the core makes about itself** — the
  ecosystem cannot bind the core, and a rule kept only in the dependent
  repository is a rule the dependency can talk its way out of.

  The reasoning is the one the draft states about itself and is worth adopting
  verbatim: *"If the ecosystem cannot exist without the core bending, the
  ecosystem was a way of smuggling features into a frozen framework, and the
  honest response is to stop."* Three phases of anti-accretion gating exist
  precisely so that sentence has teeth.

- **Decision 2 — CE-E4: ecosystem work waits until after WP44.** Not until
  Phase 4 freezes — after the **stop/shutdown** package specifically. Two
  reasons, and the first is concrete rather than about priorities:

  1. **The recommended first Crystal is a restart-on-save watcher, and the core
     cannot shut down.** It would ship a tool whose central defect is a hole
     WP44 is scheduled to close, and teach the ecosystem to route around it. A
     first Crystal should test the idea, not the workaround.
  2. **Phase 4 is what makes the framework usable; the ecosystem is what makes
     it pleasant.** The mission's precedence — discipline, then joy, then
     convenience — settles the order when both are wanted.

- **Decision 3 — when it does start, the first Crystal is a Route Crystal, not
  the watcher.** The draft recommends `dev/watch` on the grounds that its blast
  radius on the core is structurally none. That is true and it is the reason to
  choose something else: it *"proves nothing about the coupling contract,
  because it never touches `uruquim:web` — half the idea would still be
  untested, and the half with all the danger in it"* (the draft's own words). A
  ~40-line `web/health` returning a detached `web.Router` tests the load-bearing
  mechanism and simultaneously exercises the draft's own failure criterion —
  whether a `CRYSTAL.md` for a forty-line middleware is longer than the
  middleware.

- **Two of the draft's blockers have already cleared, and this ADR records it
  so nobody re-derives them.**
  - **ADR-C006 depended on `web.state`** and could not be accepted before it.
    **WP37 shipped it.** Services are application-owned and reached through
    `web.state`; the per-Crystal registry stays rejected, since it would
    recreate the extension bag G-03 forbids.
  - **Open question Q-3 asked whether the detached-`Router` shape survives
    Phase 3's wholesale router replacement.** **It did, and this is verified
    rather than expected:** WP29 replaced the representation and WP30 added
    conflict poisoning, both inside the index; `Router :: struct { using app:
    App }` and `mount`'s copy semantics are byte-identical in the freeze
    snapshot across the phase.

- **What is NOT decided here.** Whether the ecosystem exists at all, its
  categories, its distribution shape, and every ADR-C are the ecosystem's own
  matters. This ADR fixes only the core's side: the core does not bend, and the
  clock starts after WP44.

- **Doc impact.** PR #49 stays a draft. `planning/roadmap.md` places the
  ecosystem in Phase 5; Decision 2 is a narrowing of that placement, not an
  exception to it.

- **Reversibility. HIGH.** Nothing ships. Decision 1 is a refusal, which costs
  nothing to hold and can only be loosened deliberately; Decision 2 is a date.

## ADR-033 — the transport foundation: keep it, patch it, or own it

- **Status.** **CLOSED 2026-07-21 — KEEP AND PATCH (option A/B).** Decided by
  the criteria fixed in advance: WP41's fault laboratory, then WP46's
  containment result. The reasoning below is left as written, with the outcome
  appended, because an ADR that is edited to match its conclusion teaches
  nothing.

  Originally: **OPEN, with the deciding evidence and the criteria fixed in
  advance.** Decided at **WP41**, from the fault laboratory's results, and not
  before. Same treatment ADR-030 (concurrency) gets, for the same reason: the
  question is real, the evidence does not exist yet, and writing the procedure
  now is what stops the decision being made later by whoever is tired.

- **Context, and it is the most consequential thing Phase 4 has to face.**
  Uruquim is a thin, fast layer — a radix router with flat dispatch, chains
  flattened at registration, a frozen 50-symbol surface, and gates that hold all
  of it. **The layer is in good shape. The foundation under it is not
  established.** Three facts, each checked rather than recalled:

  1. **The vendored server declares itself beta.** `laytan/odin-http`'s README:
     *"This is beta software, confirmed to work in my own use cases but can
     certainly contain edge cases and bugs"*, and *"I do not hesitate to push
     API changes at the moment, so beware."* 419 stars, 17 open issues, 8 open
     pull requests, one principal maintainer. The vendored snapshot is commit
     `112c49b` (2026-04-11), vendored 2026-07-19.
  2. **Most of what Phase 4 has left is SERVER work, not framework work.**
     Read/write deadlines, connection lifetime and keep-alive, drain-or-close,
     connection and queue limits, load shedding, stop and graceful shutdown,
     response framing — WP44 through WP47 and WP52 all live BELOW the boundary.
     Implementing them as patches on someone else's beta server means **writing
     a server anyway, as a patch set against a moving target**, which is the
     worst of both arms.
  3. **The portability already lives in Odin's core, not in the dependency.**
     `core:nbio` provides the event loop and the platform back-ends (io_uring,
     IOCP, KQueue). What `odin-http` adds above it is the HTTP/1.1 parsing and
     connection state machine — exactly the part Phase 4 must control, and
     exactly the part that is beta.

- **Why this is not simply reopening R-T3.** R-T3 ("rewrite the HTTP server")
  was rejected as SCOPE, correctly, while the router was the priority and no
  acceptance tests for a server existed. Three things have changed, and they are
  why this is a question again rather than a settled one: the public surface is
  frozen and the router is finished; the dependency has since declared its own
  API unstable; and **the project now owns the acceptance tests for a server it
  does not have** — WP9's raw-wire framing corpus, the conformance matrix that
  runs identically against any transport, and WP41's planned fault laboratory.
  That is an unusually strong position, because the tests were built before the
  decision rather than to justify it.

- **Options.**
  - **(A) Keep and patch.** Stay on the vendored snapshot, carry patches for
    deadlines and connection lifetime, re-vendor deliberately.
  - **(B) Keep, and offer each patch upstream first.** A, plus a dependency on
    one maintainer's queue.
  - **(C) Own the connection layer.** An HTTP/1.1 connection state machine over
    `core:nbio`, behind the existing ADR-009 boundary, as a **second adapter**
    that must pass the same conformance matrix as the first — never a big-bang
    replacement.

- **Costs, without flattering any arm.** A is cheapest today and accumulates a
  maintenance debt whose size is set by someone else's release cadence. B is A
  plus a queue nobody here controls. **C is materially more work and is the only
  arm that ends with the foundation as reviewed as the layer above it** — and
  its risk is the classic one: a hand-written HTTP parser is where security bugs
  live, which is precisely why it may only proceed against the existing corpus
  and never ahead of it.

- **The decision procedure, fixed now.** At WP41 the fault laboratory runs
  **against the vendored server**, and its own success criterion already
  requires it to find at least one defect the current tests miss. Then:
  - the vendored server survives the seeded menu, and the deadline work is a
    contained patch → **A or B**, and this ADR closes;
  - the lab must reach into the connection loop to make faults reachable, or the
    deadline patch spreads across the read path, keep-alive and close → that is
    the evidence for **C**, which then proceeds as a **second adapter behind the
    boundary**, gated on passing the full conformance matrix and the WP9 corpus
    before it is ever made the default;
  - **a tie means A.** The arm already shipping wins when the evidence does not
    separate them.

- **First evidence in, 2026-07-21 (WP41).** The fault laboratory shipped and
  ran against the vendored server. Two results bear on this ADR:
  - **The faults were reachable from OUTSIDE.** A hostile client over a real
    socket was enough to produce every fault in the menu; the lab never had to
    reach into the connection loop. By §the decision procedure that is evidence
    toward **A/B (keep)** rather than toward C.
  - **It found the hole anyway.** A truncated or trickling client is held open
    indefinitely — the vendored server has no read deadline, exactly as
    §ADR-031 predicted from reading it. So "keep" does not mean "nothing to
    do"; it means the work is a patch rather than a replacement.
  **The ADR stays open**, because the second half of its criterion is whether
  the deadline patch stays CONTAINED, and only WP46 can answer that.

- **CLOSED, 2026-07-21 — option A/B (KEEP AND PATCH).** WP46 answered the
  second half of the criterion, and the answer was unambiguous.

  **The deadline patch stayed contained.** It is one option field, one struct
  field, one periodic sweep beside the server's existing date tick, and two
  timestamp lines. It did **not** spread across the read path, keep-alive and
  close — which §the decision procedure named as the evidence for owning the
  connection layer. Combined with WP41's result (every fault reachable from
  outside; the lab never had to enter the connection loop), **both criteria
  point at keep.**

  **Recorded honestly: this is a decision about the work THIS phase needed, not
  a verdict on the dependency.** The README still says beta and still says the
  API moves. What changed is that the one intervention Phase 4 required turned
  out to be small, and a decision to own a connection layer must be paid for by
  evidence of need rather than by a general unease. **A tie means keep**, and
  this was not even a tie.

  **What would reopen it** is unchanged and now sharper: a second patch that
  does NOT stay contained. WP45's connection lifetime work is the next test of
  it, and the vendor policy's disposition table is where the count lives.

- **What was decided while it was open, and remains true.** The supported
  deployment is **behind a reverse proxy, under a supervisor**, and WP55
  documents it in those words. That is also how Gin is deployed in practice; the
  difference is that this project writes the boundary down instead of leaving it
  folklore. **The read deadline narrows what the proxy is load-bearing for — it
  no longer carries slowloris alone — but it does not replace the topology.**

- **Reversibility.** A or B keeps C available at any later date, because the
  boundary and the corpus are what make a swap possible and both already exist.
  C is expensive to undo, which is why it needs evidence first and a second
  adapter rather than a rewrite.

## ADR-030 — the concurrency model: single-threaded, with the burden on threading

- **Status.** **ACCEPTED** (2026-07-21, decided under the ADR-029 delegation,
  by the procedure the Phase-4 plan pre-registered before any prototype
  existed). Evidence: `planning/phase-4-concurrency.md`,
  `experiments/12-concurrency-arms/`.

- **Context.** Whether `web.serve` stays single-threaded by construction is the
  phase's architectural decision (audit A-4, A-14). The plan deliberately left
  it open and wrote the PROCEDURE instead: prototype both arms, measure, decide
  with the losing arm's numbers recorded, and — the part that matters —
  **an inconclusive prototype means single-threaded.** That rule was fixed in
  advance precisely because at decision time the temptation would be to read a
  wide noise band as a mild preference.

- **Options.** (A) single-threaded event loop, `thread_count = 1`, the status
  quo. (B) threaded, `thread_count = core count` — which the vendored server
  already supports, so this is a ONE-LINE change in the adapter.

- **Evidence — the timing.** 400 requests, 16 concurrent clients, `-o:speed`:
  single-threaded **1,861 ms**, threaded **1,288 ms**, both answering 400/400
  with HTTP 200. Threaded finished ~31% sooner.

  **That is not a result.** FINDING-A's noise floor on this machine, derived by
  the WP26 harness at the Phase-3 freeze, is **13,821 basis points — 138%**.
  31% sits far inside it, and the workload is partly bound by spawning client
  processes rather than by the server. **Inconclusive**, in the sense the rule
  gave that word in advance.

- **Evidence — the correctness reading, which is what actually decides.**
  Three shipped guarantees become false the moment `thread_count > 1`:
  1. **the request-ID counter is non-atomic**, and its own comment says a
     multi-threaded dispatcher "must make this an atomic increment or two
     requests can be handed the same ID". The Phase-1 freeze records it as a
     frozen assumption;
  2. **the miss chain is built lazily on the first miss**, guarded by a
     `miss_built` flag — a check-then-act into an append-only pool, whose
     failure is a WRONG CHAIN rather than a wrong label;
  3. **`dispatched` and `web.state`** are shared per-request writes, and
     `examples/07-app-state` documents its counter as correct "under the
     framework's current model — one server per process, one event loop".

- **What the evidence does NOT show, recorded because the ADR is weaker
  without it.** A request-ID collision was **not observed**: 300 requests over
  12 concurrent clients against the threaded arm produced no duplicate. The race
  is real by construction; "the code cannot be safe" and "I saw it fail" are
  different claims and only the first is supported. Separately, an apparent
  finding — 141 of 300 empty responses under threading — **evaporated against
  its control**: the single-threaded arm produced 133 of 300, so the empties
  were an artefact of the probe's own shell redirection. That control is the
  only reason it did not become a published defect.

- **Decision. Option A — single-threaded.** Adopting B today would require, in
  the same change, an atomic counter, a synchronised miss-chain build, a
  synchronised `dispatched`, and a documented rule for `web.state` under
  concurrency: **four amendments to shipped guarantees, in exchange for a
  speed-up this machine cannot measure.** This is not a refusal of threading
  forever; it is a refusal to adopt it as the side effect of a one-line change,
  which is exactly what it would otherwise have been.

- **Consequences that bind the rest of the phase.** WP43's per-server state,
  WP44's stop and drain, WP45's connection lifetime, WP46's limits and WP47's
  shedding are all designed against ONE event loop. Each may assume it; none may
  quietly rely on it without saying so, because the reopening conditions below
  are real.

- **What reopens it**, written now so it is not written later to fit a
  preference: (1) a workload measured on an instrument whose noise floor is
  materially below the observed difference — WP53's job, not a rerun of this
  one; (2) the four amendments prototyped and passing the WP41 fault lab; (3)
  evidence that a real deployment is CPU-bound in the FRAMEWORK rather than in
  the handler, since a threaded server does not help a program whose time is
  spent in its database.

- **Reversibility. HIGH today, and it decays.** Nothing ships, and the vendored
  server keeps the capability, so the change stays one line plus the four
  amendments. It decays because every later package that assumes one loop
  without saying so adds to the amendment list — which is why this ADR asks each
  of them to say so.
