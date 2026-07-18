# 03 — Proposed Architecture Decision Records

Status: **ALL PROPOSED. NONE ACCEPTED.** These ADRs record options and a
recommendation for the Phase-1 Spec Gate. Acceptance requires the ratifying
experiment to be executed on the pinned toolchain (baseline 01) and, where
noted, a human decision.

Each ADR: context · options · benefits · costs · risks · evidence ·
recommendation · documentation impact · reversibility.

---

## ADR-001 — App creation: by value vs explicit init
- **Context.** Canonical `app := web.app(); defer web.destroy(&app)` vs
  Advanced `app: web.App; web.app_init(&app)`.
- **Options.** (A) `app()` returns `App` by value. (B) `app_init(&app)` fills
  caller storage. (C) both — A canonical, B advanced.
- **Benefits.** A: one-liner, no pre-declared variable. B: caller owns storage
  from the first instruction (no return-copy question).
- **Costs.** A: by-value return copies the struct header; owned `[dynamic]`/map
  members must be copy-safe and destroyed once. B: two lines, less friendly.
- **Risks.** A: double-free if a stray copy is destroyed twice.
- **Evidence.** exp-01 (`self_addr` diagnostic + `defer destroy`).
- **Recommendation.** **C**: A canonical, B available in the Advanced API.
- **Doc impact.** none if exp-01 passes; if it fails, spec §Application +
  README + canonical-patterns switch the canonical example to B.
- **Reversibility.** HIGH pre-code; MEDIUM after examples ship.

## ADR-002 — `#optional_ok` on value extractors
- **Context.** `path_int(ctx,name) -> (int, bool)` — keep `#optional_ok`?
- **Options.** (A) keep it (stdlib idiom; bool droppable). (B) omit it
  (compiler forces handling the bool).
- **Benefits.** A: matches `map[k]`, familiar. B: hard guarantee against silent
  drop by a human or LLM.
- **Costs.** A: permits `id := path_int(...)` dropping the error. B: slightly
  less idiomatic; still `(value, ok)` at the call site.
- **Risks.** A: the canonical `if !ok { return }` is advisory, not enforced.
- **Evidence.** exp-04 (mechanism HIGH; diagnostic text decides policy).
- **Recommendation.** **Lean B for HTTP extractors** (safety > idiom, and the
  audience explicitly includes weaker LLMs), pending the exp-04 diagnostic.
  Either way call sites are identical.
- **Doc impact.** spec §Extractor Control Flow keeps the call-site form; only
  the `#optional_ok` sentence changes.
- **Reversibility.** HIGH — internal to signatures, call sites unchanged.

## ADR-003 — Response rendering by value/pointer via `$T`
- **Context.** `json(ctx, status, value: $T)`, with `ok`/`created` shorthands.
- **Options.** (A) parametric `$T` + `json.marshal(any)`. (B) require callers
  pass `any` explicitly. (C) code-gen per type.
- **Benefits.** A: one name, any serializable type, no user `any`. C: no
  runtime marshalling.
- **Costs.** A: `any` used internally (encapsulated). C: banned (no codegen).
- **Risks.** A: types the marshaller rejects surface as runtime errors (must be
  pre-commit).
- **Evidence.** exp-02 (`commit==1`, reject probe).
- **Recommendation.** **A.** `ok`/`created` are exact one-line delegations.
- **Doc impact.** none (matches current spec).
- **Reversibility.** HIGH.

## ADR-004 — Application state access
- **Context.** `web.state(ctx, T)` with no generic noise at call sites.
- **Options.** (A) `rawptr + typeid` on `App`, asserted accessor. (B)
  parametric `App(S)/Context(S)`. (C) closed accessor generated per app.
- **Benefits.** A: zero call-site type args, one sanctioned rawptr. B:
  compile-time wrong-type prevention.
- **Costs.** A: runtime assert; nil edge. B: type args at every handler; the
  generic noise the spec rejects. C: needs codegen (banned).
- **Risks.** A: nil/unregistered deref (→ AMEND-1).
- **Evidence.** exp-05 (both compile; A mutation-visible; B call-site noise).
- **Recommendation.** **A canonical; B reserved for Advanced typed context.**
  Adopt AMEND-1 (nil policy).
- **Doc impact.** spec §Application state + AMEND-1.
- **Reversibility.** MEDIUM (public accessor).

## ADR-005 — Middleware model
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
- **Context.** where do `body`-bound nested strings/slices live?
- **Options.** (A) request-lifetime arena, explicitly substituted. (B)
  `context.allocator`. (C) copy out of temp after unmarshal.
- **Benefits.** A: freed in one shot at request end; clear ownership. 
- **Costs.** B: lifetime unclear, leak risk. C: double copy.
- **Risks.** A: `json.unmarshal` must honor the substituted allocator for
  nested data.
- **Evidence.** exp-03 (`arena.offset>0`).
- **Recommendation.** **A.**
- **Doc impact.** spec §body + memory-model (Phase 4 doc).
- **Reversibility.** MEDIUM.

## ADR-007 — Request allocator vs temp allocator
- **Context.** views over transport buffers vs persistent copies.
- **Options.** (A) request arena for anything outliving a single parse step;
  temp for immediate scratch. (B) temp everywhere. (C) copy everything up front.
- **Benefits.** A: zero-copy views + explicit persist; matches spec ownership
  rule. 
- **Costs.** C: defeats the view design; B: dangling after temp reset.
- **Risks.** retaining a view past the request (mitigated by the physical demo).
- **Evidence.** exp-06.
- **Recommendation.** **A**, with the normative "copy to persist" rule.
- **Doc impact.** none (matches spec).
- **Reversibility.** MEDIUM.

## ADR-008 — Response commit semantics
- **Context.** exactly-one-commit; where onion "after" sits.
- **Options.** (A) framework-side single-commit guard (`committed` flag). (B)
  transport-enforced. (C) allow re-commit (last wins).
- **Benefits.** A: deterministic, testable without a real socket. 
- **Costs.** C: header/body races. B: couples semantics to backend.
- **Risks.** post-commit onion "after" touching a flushed response.
- **Evidence.** exp-08 (guard rejects 2nd commit); exp-07 (after==post-commit).
- **Recommendation.** **A** for buffered responses; revisit for streaming
  (out of MVP). Onion-after must not mutate a committed response — ties to
  ADR-005/C.
- **Doc impact.** spec §Response commit; test in WP6.
- **Reversibility.** MEDIUM.

## ADR-009 — Transport boundary shape
- **Context.** minimal internal contract; no backend type on public surface.
- **Options.** (A) minimal `Transport{data,serve,stop}`, private, unfrozen. (B)
  freeze a rich four-proc ABI now. (C) no boundary, call odin-http directly.
- **Benefits.** A: enough for bootstrap + test transport; free to change when a
  second adapter lands. 
- **Costs.** B: premature freeze against an unknown `core:net/http`. C: leaks
  backend types, breaks migration.
- **Risks.** A: shape churn across the first two adapters (acceptable — it is
  private).
- **Evidence.** exp-08; baseline (core:net/http absent).
- **Recommendation.** **A.** Freeze only the *conceptual* contract (accept →
  dispatch → commit → stop).
- **Doc impact.** none (matches amended spec).
- **Reversibility.** HIGH (private).

## ADR-010 — Advanced API policy
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

---

## Acceptance ledger

| ADR | Needs | Human decision? |
|---|---|---|
| 001 | exp-01 | no (unless it fails) |
| 002 | exp-04 diagnostic | **yes** — keep/drop `#optional_ok` |
| 003 | exp-02 | no |
| 004 | exp-05 + AMEND-1 | **yes** — confirm A-canonical |
| 005 | Phase-2 gate | **yes** — deferred |
| 006 | exp-03 | no |
| 007 | exp-06 | no |
| 008 | exp-07/08 | no |
| 009 | exp-08 | no |
| 010 | — | **yes** — confirm defer-to-post-Phase-1 |

Four ADRs (002, 004, 005, 010) carry an explicit human decision; these become
the gate's non-compile blockers.
