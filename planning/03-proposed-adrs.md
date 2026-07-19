# 03 — Proposed Architecture Decision Records

Status: **MIXED.** Human decisions recorded on 2026-07-18 accept ADR-001,
ADR-002, ADR-003's value-only baseline, ADR-004, ADR-006, ADR-007, ADR-008,
ADR-009, and ADR-011. ADR-005, ADR-010, ADR-012, and ADR-013 remain
PROPOSED/deferred to their owning gates. Reproducible compiler evidence lives
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
- **Status.** **PROPOSED / DEFERRED** — Phase-2 Spec Gate.
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
- **Status.** **PROPOSED** — blocks WP7 implementation, not earlier work.
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
- **Evidence.** External research consistently recommends an explicit body
  state machine, but no pinned-toolchain Uruquim prototype has tested the
  second-call behavior yet.
- **Recommendation.** **A**, subject to a WP7 disposable prototype. The
  prototype must decide when consumption occurs and how a second call is
  reported without double-commit. No replay cache enters Phase 1 by default.
- **Doc impact.** architecture body section, canonical patterns, AI context,
  WP7 tests, and error documentation after acceptance.
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
| 012 | WP7 repeated-binding prototype | **PROPOSED** — must close before WP7 implementation |
| 013 | Phase-4 proxy corpus | **PROPOSED / DEFERRED** — must close before trusted-proxy code |

No accepted Phase-1 ADR has been reopened. ADR-012 is a new, narrowly owned WP7
decision; ADR-005, ADR-010, and ADR-013 remain owned by later gates and cannot
expand earlier scope.
