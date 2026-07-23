# Process remodel & repository hygiene — a transition manifest

**Status: DRAFT MANIFEST, 2026-07-23.** Owner-authorized to decide. **Plan
only** — nothing is moved or deleted under it yet; it is designed to execute as
one clean PR **alongside the Production Readiness Closure** (C-07), on a quiet
`main` (a parallel job recently touched `main`; structural moves wait for it to
settle). This document is **self-consuming**: it authorizes shrinking the
top-level `planning/` view and is itself archived once executed.

The principle: **keep only what is load-bearing at the top level; move
superseded working documents to history; make the PRC matrix the single source
for current limitations.** History is preserved (moved, not destroyed) unless a
file is genuinely dead.

---

## 0. The three accumulations the remodel rationalizes

Measured on `origin/main` (2026-07-23): `planning/` 56 files, `build/` 47 (42
gate scripts, ~27 per-WP controls), `docs/` 13.

1. **Superseded working docs at the top level** — phase prototypes, evidence,
   audits, shootouts. Their phase freeze is the durable record; they clutter the
   live view. **→ archive.**
2. **The known-limitations scatter** — the same "not bounded / no X / known
   limitation" statements maintained in **11 places** (operations, quick-start,
   canonical-patterns, standards-registry, transport-conformance, and 6 phase
   freezes). **→ the PRC resource matrix becomes canonical; docs point to it.**
3. **Per-WP control gates of frozen phases** running on every gate invocation
   (check_wp16…41). **→ consolidate under a per-phase runner; retire only what
   the freeze gate provably absorbs.**

---

## 1. The classification rule (so every file has one home)

| Class | Rule | Action |
|---|---|---|
| **Governance (live)** | Rules/decisions still consulted to make new work correct | Stay top-level `planning/` |
| **Freeze (durable history)** | The one per-phase record of what shipped/was refused | Stay top-level (one per phase) |
| **Current/next plan** | The phase in flight and the one after | Stay top-level |
| **Superseded working doc** | A prototype/evidence/audit whose phase is frozen; the freeze captured its result | **`planning/history/`** |
| **Gate-locked** | Referenced by a gate script (even if superseded) | Stay **until** the gate is amended to drop the reference; then reclassify |
| **Dead** | Nothing references it and its content is obsolete, not historical | Delete (owner-confirmed) |

**The gate-lock caveat is absolute:** a file a `build/check_*.sh` names cannot
move without breaking that gate. Those stay put here regardless of age; the
remodel only touches gate-unreferenced files.

---

## 2. planning/ decisions (56 → ~35 top-level + history/)

**KEEP top-level — governance (live):** `adrs.md`, `public-api-guardrails.md`,
`roadmap.md`, `phases-6-8-program.md`, `later-phases-plan.md`,
`open-questions.md`, `architecture-evidence-questions.md`, `risk-register.md`,
`future-research.md`, `decisoes-do-dono.md`, `production-service-bom.md`,
`vendor-policy.md`, `numeric-contract.md`, `arena-policy.md`,
`benchmark-methodology.md`, `sync-async-evaluation.md`.

**KEEP top-level — freezes (durable history, one per phase):**
`phase-1-freeze.md`, `phase-2-freeze.md`, `phase-3-freeze.md`,
`phase-4-freeze.md`, `phase-5-freeze.md`, `phase-6-freeze.md`,
`phase-7-freeze.md`.

**KEEP top-level — current/next & new plans:** `phase-8-plan.md`,
`phase-7.5-plan.md`, `production-readiness-closure.md`, `process-remodel.md`
(this file, until executed).

**KEEP top-level — GATE-LOCKED (superseded but a gate names them; move only
after the gate drops the reference):** `phase-1-plan.md`, `phase-2-plan.md`,
`phase-2-spec.md`, `phase-2-baseline.md`, `phase-4-spec.md`, `phase-6-plan.md`,
`phase-6-spec.md`, `phase-6-concurrency.md`, `phase-6-concurrent-serving.md`,
`phase-7-spec.md`, `phase-7-plan.md`. *(These carry 1–2 gate references — see
the measured table in the analysis. The Closure's C-02 may relocate some once
the phase-spec gates stop reading them; until then they stay.)*

**ARCHIVE → `planning/history/` (superseded working docs, gate-unreferenced,
safe now):**
`phase-2-prototype-middleware.md`, `phase-2-prototype-recovery.md`,
`phase-3-plan.md`, `phase-3-spec.md`, `phase-4-plan.md`, `phase-4-concurrency.md`,
`phase-4-soak.md`, `phase-5-spec.md`, `phase-5-uploads-spec.md`,
`phase-6.5-plan.md`, `phase-6-blocking-boundary.md`, `phase-6-thread-safety.md`,
`phase-7-ingest-spec.md`, `phase-7-streaming-evidence.md`, `post-phase1-audit.md`,
`allocation-audit.md`, `odin-fit-audit.md`, `research-synthesis.md`,
`router-shootout.md`, `router-implementation.md`.

*(≈20 files. All are the working artifacts a freeze already summarized. Archive,
do not delete — the phase-6.5 corrective and the router shootout in particular
are evidence someone may re-read.)*

**REVIEW for delete vs archive (owner call — content-dependent):**
`qa-agent.md` (a process doc that the PRC's method may supersede outright).

---

## 3. docs/ — the limitations scatter collapses onto the matrix

After the Closure ships its resource × property matrix (C-02) and closure record
(C-07), **that matrix is the single canonical list of current framework
limitations.** Then:

- `docs/operations.md` §10, `docs/quick-start.md` "Current limitations",
  `docs/canonical-patterns.md`: keep a **one-line pointer** to the matrix
  instead of each restating the list. The prose that explains a *specific*
  behaviour stays; the *enumeration* lives in one place.
- **Phase freezes keep their own non-deliveries** — that is a freeze's job (the
  record of what *that phase* did not deliver, as history). They are not the
  *current* limitations list; the matrix is.
- `docs/standards-registry.md`, `docs/transport-conformance.md`: unchanged
  (they document contracts, not limitations).

Net: the "what doesn't this bound?" answer stops being maintained in 11 places
and drifting; it is maintained once, gate-checked by `check_readiness_matrix.sh`
(C-02).

---

## 4. build/ — gate consolidation (careful, staged)

**Do not blindly retire per-WP controls.** They encode mutation coverage the
freeze gates do not restate. Instead:

- **Consolidate invocation:** group the frozen-phase per-WP controls
  (check_wp16…41) behind a single `check_frozen_controls.sh` that runs them,
  so `build/check.sh` reads one line per frozen phase, not 24. No coverage is
  lost; the top of `check.sh` stops being a wall of per-WP lines.
- **Retire only with proof:** a per-WP control may be dropped **only** if its
  phase freeze gate is amended to assert the same mutation it proved. Each such
  retirement is its own recorded decision, not a sweep. Default: keep.
- **The Closure adds, it does not fork:** `check_readiness_matrix.sh` (C-02)
  and the fault-campaign suite (C-03) reuse existing WP41/58/72/90/91/92
  coverage by reference where possible, rather than duplicating it.

---

## 5. What the remodel deliberately does NOT touch

- **Frozen ledgers, freeze documents, ADRs, guardrails** — the discipline's
  spine. Untouched.
- **Gate-referenced files** — every `check_*.sh` dependency stays until the gate
  itself is amended, and amending a *frozen-phase* gate is a recorded decision.
- **`experiments/`** — disposable prototypes are already gated by
  `run_checks.sh`; they are history-by-design and stay where they are (moving
  them would break the runner for no gain).
- **`tests/`, `web/`, `vendor/`** — code and its tests are load-bearing; hygiene
  there is the Closure's job (dead-test detection), not this manifest's.

---

## 6. Execution plan (one PR, on a quiet main, with the Closure)

1. `git mv` the §2 archive set into `planning/history/` (a pure move — no gate
   references them, verified; the full `check.sh` stays green).
2. Add `planning/history/README.md` (one line: "superseded working documents;
   the durable record of each phase is its `phase-N-freeze.md`").
3. Introduce `check_frozen_controls.sh` (§4) and collapse the per-WP lines in
   `check.sh` to per-phase invocations — behaviour identical, gate re-run to
   confirm.
4. After the Closure's matrix lands (C-02/C-07), replace the docs limitation
   enumerations with pointers (§3).
5. Delete this manifest and `phase-7.5-plan.md`/`production-readiness-closure.md`
   are **not** deleted — they become the phase records until their own freezes,
   then follow the same archive rule.

**Verification:** the full `build/check.sh` must stay green after step 1 and
step 3 (both are refactors, not behaviour changes). Step 4 re-runs
`check_docs.sh`.

---

## 7. The one-sentence outcome

Top-level `planning/` goes from a 56-file mix of live rules and dead scaffolding
to **governance + freezes + the two current plans**, with superseded working
docs preserved in `history/`; the "what isn't bounded" answer lives once in the
Closure matrix instead of drifting across 11 documents; and `check.sh`'s frozen
controls read as a handful of per-phase lines instead of a wall — **without
weakening a single gate or losing a page of history.**
