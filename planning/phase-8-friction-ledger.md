# Phase 8 — friction ledger

**Status: LIVE.** The evidence instrument of proof-by-use
(`planning/phase-8-plan.md` §2). Every friction the reference application
(`uruquim-board`) hits against the **public** framework surface is recorded here
with all nine fields. A core/Crystal change happens only in a separately
reviewed corrective WP with its original gates — this ledger is a **veto and
evidence source, not an accretion exception.**

`application-specific?` = the friction is the app's own design problem, not the
framework's. Only non-application-specific items are candidate framework
findings.

---

## F8-1 — the public `web.Status` enum has no 503 (nor 429)

| Field | Value |
|---|---|
| **1. Task attempted** | A `/ready` readiness endpoint that answers **503 Service Unavailable** when the database pool is exhausted or the database is unreachable — the universal Kubernetes/load-balancer readiness pattern (WP103). |
| **2. Public API used** | `web.text(ctx, status, body)`; the public `web.Status` enum. |
| **3. Boilerplate / concepts** | The application must **cast a raw integer**: `web.text(ctx, web.Status(503), ...)`. There is no named member. |
| **4. Safety / ownership problem** | The cast defeats the enum's purpose — the type exists so a status is a checked, named value, and `web.Status(503)` bypasses that. Any typo (`web.Status(530)`) compiles. It is also **undiscoverable**: nothing in the public surface tells a new contributor that 503 must be spelled as a cast. |
| **5. Workaround** | `web.Status(503)` — a raw int cast. It works because `web.Status` is `enum int` and the respond path forwards the numeric value. |
| **6. Application-specific?** | **No.** 503 (readiness, pool exhaustion, backpressure) and 429 (rate limiting) are needed by essentially every production service. The framework's OWN reference app already reaches for `web.Status(503)` — `crystals examples/notes/notes.odin:356` — for the identical bounded-pool case. Two independent applications hit it. |
| **7. Smallest candidate improvement** | Add the operationally-essential codes the enum omits to the public `web.Status` enum: **`Service_Unavailable = 503`** and **`Too_Many_Requests = 429`** (and, on the same review, consider `Conflict = 409` — already needed by the unique-violation path — and `Payload_Too_Large = 413`, currently a private value). No behaviour change; a name for a number applications already produce. |
| **8. Public cost / reversibility** | Additive to a frozen public enum — a ledger-growing change (the Phase-1 freeze evidence-matrix ritual), but purely additive: no existing member moves, no signature changes, fully reversible before any release. Enum additions do not break existing `case` matches on the current members. |
| **9. RED test** | A public-surface test that asserts `web.Status.Service_Unavailable == 503` and that `web.text(ctx, .Service_Unavailable, "x")` produces a `503` status line on the wire — RED today (the member does not exist), GREEN after the addition. It distinguishes *improvement* (a named 503 exists and works) from *preference* (nothing about the cast is a matter of taste — the cast is unsafe and undiscoverable). |

**Disposition:** RECORDED. The board uses the `web.Status(503)` workaround to
proceed (`board/routes.odin`). The candidate improvement is a real, additive,
well-evidenced finding — two independent applications, a universal pattern —
and is the kind of change the corrective-WP process exists for. **Not applied in
Phase 8; carried as the first framework finding for the owner's review.**
