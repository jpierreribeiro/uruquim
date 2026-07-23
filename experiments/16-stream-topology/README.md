# Experiment 16 — streaming topology candidates (WP86)

**Question** (evidence backlog §3, trigger Phase-7 entry, fired): *is response
streaming contained above the connection backend* — and which of the four
pre-registered API topologies can carry it? The observable decision is the
WP88–WP92 architecture, not a preferred implementation.

**Baseline and the claim it does not support.** The shipped baseline is the
buffered `Inbound → Dispatch_Proc → Outbound` boundary. It supports no claim
about long-lived responses: today a response either completes inside the
Handler or does not exist.

**The four arms** (phase-7-plan.md §WP86), each sending the same ten updates:

- **A — Handler stays alive and writes synchronously.** VETOED ON PAPER,
  pre-registered before any prototype ran, on two grounds that need no
  stopwatch: (1) the Phase-6 inheritance forbids using the synchronous Handler
  frame as stream ownership (phase-6-plan.md §13, carried by the handoff and
  the spec); (2) arithmetic — G7-6 requires 3,000 open streams, `max_handlers`
  caps lanes at 256, and a lane-per-stream model cannot express the gate at
  any setting. Losing-arm numbers: 3,000 required > 256 available, recorded.
- **B — Handler returns a producer polled by the lane** (`candidate-b/`).
- **C — detached stream + stale-safe value token** (`candidate-c/`).
- **D — SSE-specific API, no generic stream** (`candidate-d/`).

**Kill/tie rules, pre-declared.** An arm dies if it cannot express: bounded
cross-thread delivery with a typed full result, stale refusal after slot
reuse, close under user saturation, and drain. Semantic equivalence (the ten
updates arrive in order) precedes any cost comparison. The tie arm is the
smallest one that passes all four; timing is not a criterion at this stage
(the WP26 noise-floor lesson).

## Results (pinned toolchain dev-2026-07a, this tree)

| Criterion | B | C | D |
|---|---|---|---|
| ten updates, in order, cross-thread | PASS (via app-built buffer) | PASS | PASS (SSE-framed) |
| Handler lane occupied after return | poll per stream per tick (counted `empty_polls`) | no — enqueue wakes the owner lane | no |
| cross-thread correctness owned by | **the application** (its own mutex/cap/full policy) | the framework (typed `Send_Result`) | the framework |
| bounded-full is a framework contract | **no — convention only** (an app may ship an unbounded feed; nothing refuses it) | yes (`Full` refusal, control slot reserved for close) | yes, same machinery |
| stale identity after slot reuse | **absent** — no token, no generation; a freed feed is indistinguishable at the type level | PASS (generation bumped at close-accept, before release) | needed and present — D saved nothing |
| close against a full queue | n/a (close = stop polling) | PASS (reserved control path) | PASS |
| racing producers, final slot | n/a | exactly one `Sent` | not exercised (same code shape as C) |
| per-event cost | copy into app buffer + copy at poll | one copy on enqueue, zero dynamic alloc on send path | one copy + SSE text expansion |
| public concepts | smallest (1 proc type) but every app rebuilds the queue | token + send result + 3 procs | same count as C, protocol-locked |
| generic bytes (progress/download, WP99) | yes | yes | **no** — newline in `data` corrupts framing unless the core learns SSE splitting |

**Decision recorded.** **C** is the productive arm: it is the only one where
G7-2/G7-3/G7-4 are framework contracts rather than application conventions.
B's simplicity is real but it exports the hard part (bounded synchronized
hand-off) to every user and has no stale safety to offer WP88. D reproduces
C's machinery while surrendering the generic byte path and moving protocol
text into the core against CE-E3 — SSE is a Crystal over C (WP97). This
matches, and now evidences, the plan's recommended starting arm.

**Containment answer:** yes — everything the candidates needed (slot registry,
generation, bounded ring, owner-lane drain, wakeup) lives above the backend;
the only backend obligations are the WP90 list (commit without body, chunk
write, wakeup, cancel), already scoped as BRIDGE patches.

These prototypes are disposable, are never imported by `web`, and freeze no
name (`Send_Result` here is a lab label, not a ledger candidate).
