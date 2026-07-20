# Phase 4 — Production: work package plan

**Status: DRAFT, written 2026-07-20 — before Phase 3 has run, and on purpose.**
The shape of Phase 4 is already fixed by research that Phase 3 cannot change
(C-1…C-8 and the RG-P4 gates in `later-phases-plan.md`), so writing the shape
now costs nothing and lets the Phase-3 agent see where its outputs land. The
details Phase 3 **will** change are collected in §0 as a mandatory refresh, and
E-4 makes that refresh an entry condition. **Nothing here freezes a signature**
— precision about unstarted work would be false precision, and this plan does
not pretend to it.

Work packages continue the numbering: **WP39 – WP56**, mapping the
`P4-1 … P4-20` slots (with the consolidations §4 records).
`later-phases-plan.md` stays authoritative for the research findings; this
plan supersedes its Phase-4 table for sequencing and scope.

The theme in one line: **make deployment defensible — this is the phase where
mistakes stop being inconvenient and become remotely exploitable, so
fail-closed stops being a preference and becomes the whole method.**

---

## 0. The hand-over: what WP38 must deliver into this plan

Mandatory refresh, applied and recorded before any Phase-4 package starts
(that is E-4). Each row names what can invalidate what.

| Phase-3 output | What in this plan it feeds or can change |
|---|---|
| WP36's options struct and derived `Server_Runtime` | WP46 builds **on** it — connection, queue and ingress limits become new rows in the same boot-derivation, never a second mechanism. If the shape shipped differently, WP46 is amended first. |
| WP35's arena policy and the R-16 outcome | WP54's audit baseline — and whether **slot reuse exists at all**, which decides if generational tokens are in scope (P-T7's rule: no reuse, no abstraction). |
| WP29's router representation | Feeds WP41's fault menu (what conflict diagnostics exist to trip) — by design it changes nothing else here, because it was internal-only. |
| WP34's route identity accessor | WP50 depends on it existing; observability keys on the pattern, never the path. |
| FINDING-A's status on the then-pinned toolchain | Every measurement methodology in WP53; if the toolchain was re-pinned, the nondeterminism finding is re-verified, not inherited. |
| The concept-budget headroom after WP38's lab re-run | The budget WP44's public stop/shutdown surface spends from. |
| Any ADR accepted or amended during Phase 3 | The §2b table below is re-checked row by row. |

---

## 1. Entry conditions (not work packages)

| ID | Item |
|---|---|
| E-1 | Phase 3 frozen — WP38 merged, full gate green on `main` |
| E-2 | Configurable limits and timeouts exist (WP36 shipped) — the roadmap's hard dependency: shutdown with a deadline is meaningless without timeouts |
| E-3 | The full gate exits 0 on `main` at the moment Phase 4 starts |
| E-4 | **This plan re-reviewed against §0**, amendments applied and recorded the way the Phase-3 plan's §4b records its own — a plan that skips its refresh is folklore with a section number |

---

## 2. Work package sequence

| WP | P4 | Name | Type | Approval |
|---|---|---|---|---|
| 39 | RG-P4-A | Lifecycle state machine | SPEC | resolved (§2b) |
| 40 | RG-P4-B | Capacity and overload ledger | SPEC | resolved (§2b) |
| 41 | RG-P4-C | Deterministic transport fault laboratory | TESTS | resolved (§2b) |
| 42 | P4-1 | Concurrency model | PROTOTYPE + ADR-030 | **deliberately open — see §2b** |
| 43 | P4-3 | Per-server state replaces the transport globals | IMPLEMENTATION | internal only |
| 44 | P4-2 | Lifecycle: stop, shutdown, deadline, cleanup | SPEC + IMPLEMENTATION | resolved in principle (§2b); surface sized at spec time |
| 45 | P4-4 | Connection lifetime: keep-alive, drain-or-close, staged close | IMPLEMENTATION | behaviour per RFC (C-3) |
| 46 | P4-5 | Limits: connections, queue, headers, ingress rate | SPEC + IMPLEMENTATION | builds on WP36; ledger amendment |
| 47 | P4-6 | Deterministic load shedding | IMPLEMENTATION | resolved (§2b) |
| 48 | P4-7 | Trusted proxies | SPEC + IMPLEMENTATION | ADR-013, already accepted in direction |
| 49 | P4-9 | Secure headers and cookies | SPEC + IMPLEMENTATION | forces the D-14.3 header decision |
| 50 | P4-12+13 | Observability with the redaction policy as its spec half | SPEC + IMPLEMENTATION | resolved (§2b) |
| 51 | P4-15 | Vendor maintenance policy | SPEC | resolved (§2b) |
| 52 | P4-16 | Fuzzing and the extended framing corpus | TESTS | resolved (§2b) |
| 53 | P4-17 | Load, soak and fault-injection tests | TESTS | methodology inherits WP26 |
| 54 | P4-18 | Allocator and lifetime audit, whole-system | TESTS | resolved (§2b) |
| 55 | P4-19 | Operations documentation | DOCS | resolved (§2b) |
| 56 | P4-20 | Phase-4 freeze | FREEZE | delegated to the gate, WP38-style |

**Dependencies:** {39, 40, 41} first — the same structural decision as Phase 3,
for the same reason: a production phase that starts by implementing has chosen
its failure modes by taste. Then 42 → {44, 45, 46, 47} (the concurrency
decision shapes all four); 43 → 44 (there is nothing to stop until state is
per-server); 44 → 45; {36 (Phase 3), 40} → 46 → 47; 48, 49, 50 and 51 are
independent of each other once 42 lands; 52 and 53 run against whatever
exists and grow with it; all → 54 → 55 → 56.

---

## 2b. Approvals resolved in advance (ADR-029), and the one that is not

Same regime as the Phase-3 plan's §2b, same condition on every row: **if the
work package's own spec or prototype work contradicts the decided arm, the
agent stops and records the finding instead of proceeding.**

| Matter | Decided arm | Grounds |
|---|---|---|
| **CORS (P4-8), uploads (P4-10), static files (P4-11)** | **Out of core, ratified.** Each becomes an optional package, spec-gated Phase-5 style, and the core never grows them. | Each is a security surface of its own; the recorded constraints (Fetch spec for CORS, OWASP for uploads, traversal/symlinks/ranges for static files) travel with the packages, in `later-phases-plan.md`. The mission keeps the core small; G-04 already said optional means optional. |
| **TLS (P4-14)** | **Reverse-proxy termination is the supported deployment**, documented as such in WP55. In-process TLS is at most a future optional package, unscheduled. | The common deployment is free and removes an enormous attack surface from the core. Terminating TLS in-process would import exactly the class of risk this phase exists to reduce. |
| **Trusted proxies (WP48)** | ADR-013's accepted direction: peer address by default, explicit trust configuration, `Forwarded` never echoed. | Decided 2026-07-20; the fail-closed arm. WP48 owns signatures and the CIDR corpus, not the direction. |
| **The three gates (WP39–41)** | Approved as specs and tests — they add no public surface and no capability. | They are the phase's instruments; refusing them is refusing to look. |
| **WP44 stop/shutdown surface** | Approved **in principle**: real demand exists (there is no way to stop a server today). The exact symbols are sized at spec time under G-09 evidence, smallest surface that gives admission stop, an absolute deadline and exactly-once cleanup. | A promise made now about symbol names would be the false precision this plan refuses. |
| **WP47 shedding** | Deterministic, bounded admission **before** any adaptive controller; rejection measured cheaper than admitted work. | Research item 10 before 11; an adaptive controller on top of unmeasured shedding is two unknowns multiplied. |
| **WP50** | Redaction policy is the spec half and lands **first**; observability keys on the route pattern, never the raw path; drop policy observable. | Separating redaction from observability invites shipping them in the wrong order. Phase 1's "nothing reaches a log line" property is preserved deliberately, not by accident. |
| **WP56 freeze** | Delegated to the gate, WP38-style: freeze if and only if every gate is green, every ledger amended, seeds and soak results recorded. Any breach stops and goes to the owner. | Same reasoning as WP38: criteria met and refused is ceremony; criteria breached and passed is a lie. |
| **WP42 concurrency — THE OPEN ONE** | **Not pre-resolved, deliberately.** Whether `serve` stays single-threaded by construction is the phase's architectural decision (audit A-4, A-14), and deciding it today, without prototypes, would be taste wearing a delegation. What is written instead is the **procedure**: prototype both arms — the current single-threaded event loop, and a threaded model — measure both under WP53's workloads (including slow-client and slow-writer), and decide by **ADR-030** with the losing arm's numbers recorded. Two constraints bind whichever wins: fail-closed (no shared-mutable `App` state without a guard equivalent to the existing poison mechanism), and the Phase-3 decision that registration after `serve` begins is rejected — WP42 inherits that, it does not reopen it. | C-5's lesson generalises: "real systems use threads" is not evidence about Uruquim's workloads. The mission's tie-breaker applies only after the measurements. |

---

## 3. The work packages

Concise on purpose — full per-package prose is written at E-4 time, when the
Phase-3 outputs are real. What is fixed now is each package's **contract**:
objective, the research that binds it, and rollback.

### WP39 — Lifecycle state machine (RG-P4-A)

**SPEC.** `Configuring → Serving → Draining → Stopped`, plus `→ Failed`, as
**data, not booleans** — the failure this prevents is `stopping`, `draining`
and `failed` as flags admitting combinations no reviewer can enumerate. Same
reasoning that made `Framework_Error` a closed union. Proof obligations that
travel to WP44: admission stop, close-after-send, an absolute deadline, and
cleanup that runs exactly once. **Rollback: HIGH** — a spec ships nothing.

### WP40 — Capacity and overload ledger (RG-P4-B)

**SPEC.** One row per resource — connections, accept queue, ingress, response
buffers, timers — each stating capacity, behaviour when full, the diagnostic,
who owns cleanup, and **the minimum reserved for stop/close**. The reservation
is the point: the fatal failure is not running out of capacity, it is running
out and having none left to shut down with. Rows land in the capacity ledger
at WP56. **Rollback: HIGH.**

### WP41 — Deterministic transport fault laboratory (RG-P4-C)

**TESTS.** This is **P-T5**, deferred here by name from the Phase-3 plan.
Seeded and reproducible: fragmentation, slow reader/writer, timeout before and
after completion, concurrent close, failure after N bytes, slot reuse, an
artificially small pool, shutdown during a request. Success criterion, stated
before it is built: **replay the same seed and get the same trail, and find at
least one mutation the current tests miss** — a lab that cannot demonstrate a
missed mutation has not earned its complexity. **Rollback: HIGH** (tests only).

### WP42 — Concurrency model (ADR-030)

**PROTOTYPE + ADR.** See §2b — the procedure is the deliverable, plus the
decision it produces. Resolves the direction of audit A-4 (package-level
transport globals) jointly with WP43. **Rollback: decays fast** — this is why
it precedes every package it shapes.

### WP43 — Per-server state replaces the transport globals

**IMPLEMENTATION, internal only.** ADR-018's direction; the prerequisite for
two servers in one process, for embedded use, and for WP44 having something
coherent to stop. Existing tests pass unchanged and unmodified. **Rollback:
HIGH while internal — defend that classification exactly as WP29 does.**

### WP44 — Lifecycle: stop, shutdown with a deadline, exactly-once cleanup

**SPEC + IMPLEMENTATION, public surface.** The smallest surface that gives:
admission stop first, an **absolute** deadline (never "wait forever"), and
cleanup proven exactly-once by the WP41 lab. G-09 evidence per symbol at spec
time. **Rollback: LOW once shipped** — operators build scripts and systemd
units on a stop command within days; size it like WP36 sized its options
struct, because every symbol is a promise.

### WP45 — Connection lifetime: keep-alive, drain-or-close, staged close

**IMPLEMENTATION.** C-3 binds it three times over: 400-and-close on framing
errors, drain-or-close after every early rejection (§9.3 — leftover bytes are
the next request smuggled), and the staged close of §9.6, because a 400 the
client never receives is a real failure mode. Extends the WP9 corpus with
connection-lifetime assertions. **Rollback: MEDIUM** — observable wire
behaviour, but behind spec-recorded RFC obligations rather than taste.

### WP46 — Limits: connections, queue depth, headers, minimum ingress rate

**SPEC + IMPLEMENTATION.** New rows in WP36's boot-derived runtime — the same
validate-once pattern, never a second mechanism. The slowloris mitigation is a
minimum ingress rate; OWASP names the technique and no numbers, so the chosen
numbers are recorded **as judgement, not as citation** (the C-5 honesty rule),
in the capacity ledger with behaviour-when-full. **Rollback: MEDIUM** — a
default, once shipped, is a promise about traffic.

### WP47 — Deterministic load shedding

**IMPLEMENTATION.** Bounded admission per WP40's reservation rows. The claim
"rejection is cheaper than admitted work" enters the claim ledger **with a
measurement and a negative control**. **Rollback: MEDIUM.**

### WP48 — Trusted proxies

**SPEC + IMPLEMENTATION** under ADR-013's accepted direction. IPv4/IPv6 CIDR
corpus; direct-spoof negative controls; both peer and effective addresses kept
internally; `Forwarded` never echoed. **Rollback: LOW once anyone's audit or
rate-limit policy depends on it — which is exactly why the ADR preceded the
implementation.**

### WP49 — Secure headers and cookies

**SPEC + IMPLEMENTATION.** Forces the `Recorded_Response` header decision that
Phase 2 deferred (D-14.3) — resolve it in the spec half, not in passing.
**Rollback: MEDIUM.**

### WP50 — Observability, with redaction as its spec half

**SPEC + IMPLEMENTATION.** The redaction policy lands first: OWASP's
do-not-log list made concrete (tokens, session identifiers, passwords,
connection strings, keys, PII, payment data), CR/LF escaping against log
injection, and the standing rule that metrics and spans key on the **route
pattern from WP34's accessor, never the raw path**. Non-blocking, with an
observable drop policy — a logger that can apply backpressure to requests has
inverted the hierarchy. **Rollback: MEDIUM.**

### WP51 — Vendor maintenance policy

**SPEC.** Audit A-9/A-10: upstream the security patches or record why not;
replace code-shape greps over vendored sources with corpus assertions (a
correct re-application of a patch, written differently, must still pass);
name who watches upstream and how often. **Rollback: HIGH.**

### WP52 — Fuzzing and the extended framing corpus

**TESTS.** Extends WP9's raw-wire corpus to response framing and the C-3
cases. Body policy (HEAD, 1xx, 204, 304) stays internally separate from
framing (fixed length, chunked, close-delimited) so the combinations remain
enumerable — neither concept becomes public API. **Rollback: HIGH.**

### WP53 — Load, soak and fault-injection tests

**TESTS.** Includes a slow-client and a slow-writer workload. Methodology
inherits WP26 wholesale: two instruments, status distribution reported,
hardware-keyed baselines, distributions never single figures. **Rollback:
HIGH.**

### WP54 — Allocator and lifetime audit, whole-system

**TESTS.** Tracking allocator over the full serve path; baseline is WP35's
shipped policy. Generational tokens for slots and timers **only if reuse
exists by now** — P-T7's discipline restated: the abstraction arrives with the
reuse, never before. **Rollback: HIGH.**

### WP55 — Operations documentation

**DOCS.** How to deploy — reverse-proxy TLS termination as the documented
topology (§2b) — what to bound, what to monitor, what is **not** hardened, and
the supervisor expectation stated for operators (ADR-020: a faulting handler
aborts the process; that is the contract, not a bug). Points at `uruquim
doctor` on the product track. **Rollback: HIGH.**

### WP56 — Phase-4 freeze

**FREEZE.** Everything WP38 required, plus: a capacity-ledger row for every
WP40 resource; the fault-lab seeds recorded as data; a claim-ledger row with a
negative control for every shed/stop/drain promise; soak results recorded; the
usage lab re-run — the concept budget conversation does not end at Phase 3.
Approval delegated to the gate exactly as WP38's was.

---

## 4. Deliberately not in this phase

* **CORS, uploads, static files** — out of core by §2b; their recorded
  constraints travel with the future optional packages.
* **In-process TLS** — §2b; the ops doc documents proxy termination instead.
* **Adaptive overload control** — only after WP47's deterministic shedding has
  shipped and been measured (research items 10 → 11, in that order).
* **HTTP/2, WebSocket, streaming** — Phase-5 backlog, spec-gated, may be
  declined.
* **Rewriting the HTTP server** — R-T3, rejected and staying rejected.
* **Anything Phase 5 wants early.** A Phase-4 package that finds it needs one
  writes the finding down; it does not absorb the scope.

---

## 5. Risks this plan does not resolve

| Risk | Why it stays open |
|---|---|
| **The concurrency decision invalidates WP44–47 details** | That is why WP42 precedes them and why E-4 forces the refresh; the §3 prose is deliberately contract-level until then. |
| **The fault menu is finite** | A real network invents faults nobody seeded. WP53's soak is the partial answer; humility in the freeze wording is the rest. |
| **Slowloris numbers are judgement** | OWASP gives none. The ledger records them as engineering judgement, revisable with operational evidence — never as citation. |
| **Timing claims inherit FINDING-A** | Unless the toolchain changed and was re-verified (§0), every timing claim in this phase is a distribution or it is not made. |
| **The stop surface is LOW-reversibility** | WP44 ships the smallest surface for exactly this reason, and the spec half exists to be argued with before anything is promised. |

---

## 6. The Tina dossier — Phase-4 mapping

The rules of the Phase-3 plan's §6 apply unchanged and are not repeated in
full: **reference, never architecture; never a dependency; never committed;
never cited as evidence; its absence never blocks.** Phase 4 is where the
dossier is at its most useful — a runtime that supervises faults for a living
has answered these questions explicitly — and at its most dangerous, because
its answers are sized for a runtime Uruquim is not.

| Work package | Read | What is in there |
|---|---|---|
| **WP39, WP44** | `docs/03-io-scheduler-e-lifecycle.md` | Lifecycle states, cancellation, completion ordering |
| **WP40, WP46, WP47** | `docs/02-memoria-ownership-e-backpressure.md` | Backpressure, bounded pools, behaviour-when-full discipline |
| **WP41** | `docs/04-supervisao-falhas-e-dst.md` | Deterministic fault testing — this is P-T5's home |
| **WP42** | `docs/01-arquitetura-do-runtime.md` | The thread-per-core design — **first entry on the not-adopt list; read to understand, not to copy** |
| **WP52** | `docs/05-tina-http.md` | A second HTTP implementation's framing decisions |
| **WP54** | `docs/02-…` P-T7 | Generational tokens, arriving only with reuse |
| **WP56** | `docs/09-…` P-T1/P-T2, `docs/10-…` | Claim discipline and self-bounding, as in every freeze |

Not adopted, restated from the dossier's own impact document: thread-per-core
as a requirement, isolate-per-connection in the API, global arenas, signal
recovery, a messaging protocol, the Tina backend in core.

---

## 7. What an implementation agent should read first

1. **§0 and E-4 of this document.** If the refresh has not been applied, the
   first work package is the refresh.
2. `planning/later-phases-plan.md` §Phase 4 — C-1…C-8 and the RG-P4 gates
   remain authoritative for the questions they cover.
3. `planning/phase-3-plan.md` §2b and **ADR-029** — how approvals work now;
   the reserved matters that still stop for the owner.
4. `planning/phase-2-freeze.md`, and the Phase-3 freeze once it exists — the
   ledgers this phase amends and the claims it must not break.
5. `planning/adrs.md` — an ACCEPTED ADR supersedes plan text when they
   disagree; ADR-013 and ADR-020 bind this phase directly.
6. `tina/` — the mapped document only (§6), when the environment supplies it.
7. **The code and tests of the work package before it** — this project has had
   documented behaviour the code did not have; never conclude from documents
   alone.
