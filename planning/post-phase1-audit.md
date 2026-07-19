# Post-Phase-1 strategic audit

Audited at `a7d2e9e` (WP11 merged, Phase 1 frozen), toolchain
`dev-2026-07-nightly:819fdc7`. Baseline reproduced locally:
`PASS=10 FAIL=0 SKIP=0`, ledgers 32 + 2 = 34, freeze gate green.

This document records what Phase 1 actually built, what debt it leaves, and
which items must be fixed, scheduled or explicitly accepted before Phase 2
starts. It is the evidence base for [`roadmap.md`](roadmap.md),
[`phase-2-plan.md`](phase-2-plan.md) and
[`later-phases-plan.md`](later-phases-plan.md), and it is a companion to
[`odin-fit-audit.md`](odin-fit-audit.md), which asks the separate question of
whether the design suits Odin.

## Executive summary

Phase 1 delivered a working, honestly-gated HTTP framework. The 34-symbol public
surface is frozen with per-symbol evidence, the transport is conformance-tested
against a raw-wire corpus, and the whole thing rebuilds green in about two
minutes. A five-route CRUD service is 32 lines and one cleanup call.

The debts are not in the shipped behaviour. They are in three places:

1. **A capability gap that will be felt immediately.** `test_request` carries no
   body, so the framework's headline JSON-binding feature cannot be
   unit-tested in memory at all.
2. **A lifecycle vacuum.** There is no stop, no shutdown, no documented
   single-server constraint — and the transport keeps package-level globals that
   silently cross-wire if a second server starts.
3. **Apparatus that has grown to match the project.** The gate is 2.4× the size
   of the framework code it guards, and about a third of it pins implementation
   text rather than contract, so honest refactors fail it.

**No P0 was found.** Nothing is remotely exploitable in the shipped surface, and
the WP9 conformance work closed the two DoS crashes and the smuggling vector it
found. Two items are classified CORRECTION and need a small dedicated PR before
Phase 2 (§4).

## 1. Capabilities actually proven

Not claims — each is backed by a permanent test that the gate runs.

| Capability | Evidence |
|---|---|
| Real HTTP server on a real port | `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops` |
| Static + `:param` routing, static wins | `tests/wp4-internal/wp4_internal_test.odin::wp4_static_route_matches_and_runs_handler_once` |
| 404, and 405 with an exact `Allow` | `tests/wp4-internal/wp4_internal_test.odin::wp4_allow_uses_the_canonical_method_order` |
| Path/query extraction with automatic 400 | `tests/wp5-internal/wp5_internal_test.odin::wp5_path_int_failure_commits_the_exact_envelope` |
| JSON body binding, 4 MiB cap, request arena | `tests/wp7-internal/wp7_internal_test.odin::wp7_one_over_the_limit_is_too_large_before_parse_and_arena` |
| Single-commit response guarantee | `tests/wp6-public-surface/contract_test.odin::wp6_the_first_response_wins` |
| Ten-code error envelope | `tests/wp6-internal/wp6_internal_test.odin::wp6_error_helpers_produce_the_ratified_envelopes` |
| In-memory testing, no socket | `tests/wp3-public-surface/contract_test.odin::wp3_test_request_runs_in_memory_without_routing` |
| HTTP/1 framing defence, no smuggling | `tests/wp9-wire/wire_test.odin::wp9_raw_wire_corpus` |
| Same semantics on both transports | `tests/wp9-semantic/http_factory_test.odin::wp9_semantic_matrix_on_the_real_http_transport` |
| Test-support costs nothing unused | `build/check_g11_teardown.sh` — 0 symbols vs 11 |

Measured ergonomics (ten programs compiled from public docs only): Hello World 6
concepts / 9 lines; five-route CRUD 14 concepts / 32 lines / one `defer
web.destroy`; in-memory tests 537 µs; examples build in ~2.2–2.5 s.

Measured cost: both query extractors add **64 bytes** of binary. The large
deltas (+40 KB marshal, +171 KB unmarshal) are `core:encoding/json`, not
framework overhead.

## 2. Findings

Classification: **P0** security/corruption · **P1** blocks the next phase ·
**P2** belongs to its owning phase · **P3** useful improvement · **FUTURE**
hypothesis. Disposition: **CORRECTION** (separate PR) · **PHASE_2/3/4** ·
**OPTIONAL** · **REJECTED**.

### P1 — must be resolved or explicitly accepted before Phase 2

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| A-1 | **`test_request` cannot carry a body or headers**, so body-binding handlers cannot be tested in memory. The framework's own tests reach the success path only by copying `web/*.odin` into a throwaway package (`build/check.sh:104`) — a user cannot. | `web/test_support.odin:80`; `tests/wp7-public-surface/contract_test.odin:65,80` state it explicitly | **PHASE_2** — first WP that needs it; grows the test-support ledger, so it needs owner approval |
| A-2 | **No `LICENSE`, `CHANGELOG`, `CONTRIBUTING` or `SECURITY.md`.** A public repo without a licence is "all rights reserved" by default. | repository root | **CORRECTION** — owner picks the licence |
| A-3 | **Eight comments assert shipped features are still stubs.** `web/extract.odin:1-2` says body binding "is still the WP7 stub"; `web.body` is at `:287` in that same file. | `extract.odin:1`, `errors.odin:82`, `boundary.odin:13`, `app.odin:73,100-108,121`, `context.odin:48`, `test_support.odin:71-106` | **CORRECTION** — comments only, no behaviour |
| A-4 | **Transport keeps package-level globals.** A second `serve()` overwrites `g_config`, so the first server answers with the second app's routes; `g_server` holds a stack address (`&s`) and is read non-atomically. | `web/internal/transport/odin_http_adapter.odin:26,29,42,44-45,73-75` | **PHASE_2** document the constraint; **PHASE_4** fix with per-server state |
| A-5 | **No stop or shutdown exists at all**, and `serve`'s doc comment does not say so. A Phase-1 app's only exit is a signal. | 32-symbol ledger; `web/serve.odin:14-15` | **PHASE_2** document; **PHASE_4** implement |
| A-6 | **A third of the gate pins implementation text.** Renaming the parameter `res` in `response_commit`, or splitting the 705-line `errors.odin`, fails the gate — with a message accusing the maintainer of needing a spec amendment. | `check_public_api.sh:705,763,845-861,306-314,874-882,349-357`; `check_docs.sh:157,164,263`; `check_g11_teardown.sh:145-149` | **PHASE_2** — gate restructuring WP |
| A-7 | **Response-buffer safety is conventional, not structural.** Three request-local scratch arrays are aliased by the committed response; correctness rests on six hand-written `if committed { return }` guards. A seventh responder that writes before checking reintroduces the bug and no gate catches it. | `web/context.odin:78,91,109`; guards at `respond.odin:71,124`, `errors.odin:50,290,489,512`; rationale at `errors.odin:273-278` | **PHASE_2** — first WP adding a responder |
| A-8 | **Inbound headers are allocated and copied every request, and no Phase-1 path can read them.** Phase 1 ships no header accessor by design. | `web/serve.odin:129-130`; ban at `check_public_api.sh:731` | **PHASE_2** (headers become readable) / **PHASE_3** (allocation work) |

### P2 — schedule in the owning phase

| # | Finding | Disposition |
|---|---|---|
| A-9 | Vendor carries **five hand-applied security patches** with no upstreaming path; updating upstream means re-applying all five by hand. | PHASE_4 |
| A-10 | Vendor patches are verified by **code-shape greps** (`check_public_api.sh:1105-1113`) that a correct re-application can fail and an unrelated line can satisfy. The raw-wire corpus is the real evidence. | PHASE_4 |
| A-11 | The adapter reads the backend's **private `req.headers._kv`** field — the hardest single coupling to reproduce when swapping backends. | PHASE_4/5 |
| A-12 | Static response headers are `strings.clone`d every request although `response.odin:164-166` states they are static strings. | PHASE_3 |
| A-13 | `Header_Pair` ≡ `transport.Header` structurally; two O(n) conversions per request purely to satisfy the one-way boundary. The honest price of ADR-009. | PHASE_3 (measure first) |
| A-14 | **Route registration is unguarded during dispatch.** `route_lookup` returns a pointer into the table and the "nothing registers during dispatch" invariant is comment-only, while `web.get` is public and callable from a handler. | PHASE_2 |
| A-15 | The throwaway-package copy block is **duplicated eight times** in `check.sh` plus two more variants; internal tests cannot be run from an editor. | PHASE_2 (with A-6) |
| A-16 | `Context_Internal` carries **four independent scratch arrays**; every new feature adds a field. | PHASE_3 |
| A-17 | Recorder has no synchronisation and grows monotonically until `destroy`. | PHASE_3 |
| A-18 | Comment-to-code is **5.33:1 in `context.odin`**, 3.96:1 in `app.odin`, and the two files with the most logic have the least explanation. 150 `WP<n>` and 41 `ADR-nnn` references in `web/`. | PHASE_2 onward, opportunistic |

### P3 / FUTURE

| # | Finding | Disposition |
|---|---|---|
| A-19 | The zero value of `App` is safe but dispatches 500 rather than behaving like `bare()`; undocumented. Core documents zero-value contracts where they hold. | PHASE_2 docs |
| A-20 | `allow_value` does a **third** full table scan on every 404/405. | PHASE_3 |
| A-21 | `ops/ci` may belong in `tools/`; the local cleanup plan leaves this open. | PHASE_2 |
| A-22 | No supported-Odin-version policy exists, and the pin is a nightly while `core:os` is mid-redesign in that very build. | PHASE_2 |

### Investigated and refuted

Recorded so they are not re-raised: the internals **are** data-oriented (flat
route table, no map on the hot path, params as views); **no** sensitive data can
reach a log line (the only logging path takes a `typeid` and a closed enum and
emits one of six constant strings, and `web/` imports neither `core:fmt` nor
`core:log`); the body cap **is** checked before both arena creation and parsing,
on both the adapter and core paths; `experiments/` is correctly archived and
excluded from scans; and the `web -> web/testing` / `web -> transport` boundaries
are genuinely one-way and compiler-proven.

## 3. Debt that is deliberate, not accidental

Worth separating, because a reader could mistake these for oversights. Each was
a ratified decision with recorded reasoning:

* The **linear route table** is an interim structure. Precedence comes from a
  `has_param` flag, not registration order, so Phase 3 can replace it with no
  public change.
* **No path normalisation**, no percent-decoding, no multi-value query access.
  Adopting any of these in Phase 1 would have frozen a policy by accident.
* **No header lookup**, so `Header_View` is opaque.
* **Fixed 4 MiB body cap**, deliberately not configurable.
* **413 is private** — real on the wire, absent from the public `Status`.
* **Value-only JSON payloads** (ADR-003), pointer payloads explicitly not adopted.

## 4. Items requiring a separate corrective PR before Phase 2

Neither touches behaviour; both are out of scope for a planning PR.

**C-1 — Add the product-track files (A-2).** `LICENSE` at minimum. MIT matches
the vendored dependency and is the low-friction choice, but the licence is the
owner's decision and cannot be defaulted by an agent. `CHANGELOG.md`,
`CONTRIBUTING.md` and `SECURITY.md` can follow in the same PR.

**C-2 — Correct the stale "still a stub" comments (A-3).** Comments only, no
behaviour, no ADR reopened, full gate re-run. Kept out of this PR because those
comments live in production `.odin` files.

Neither is a defect in shipped behaviour, so neither blocks planning — but C-2
should land before a Phase-2 agent reads `extract.odin` and believes its header.

## 5. What this means for sequencing

Phase 2 cannot simply start on middleware. Three of its WPs are really
Phase-1 debt being paid down, and they should come first because middleware work
sits directly on top of them:

1. the gate must stop punishing refactors (A-6, A-15) — Phase 2 adds files, and
   a gate that enumerates permitted filenames will fight every one of them;
2. test-support must be able to carry a body (A-1) — otherwise Phase 2's own
   middleware tests inherit the same blindness;
3. the response-commit invariant must become structural (A-7) — because Phase 2
   adds responders, which is exactly the scenario that breaks it.

Only then does the middleware prototype (the onion decision) make sense, and it
must be a prototype WP of its own: the fit audit classifies post-`next` semantics
as `FOREIGN_ABSTRACTION_RISK`, and committing to it without measurement would be
the single biggest design mistake available in Phase 2.
