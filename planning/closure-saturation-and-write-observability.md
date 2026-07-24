# C-05 — Combined saturation, and the write-observability gap

**Status: PERIMETER 6 DONE (measured, and it found a wedge). PERIMETER 7
SPECIFIED, NOT IMPLEMENTED (Closure, WP C-05).** Answers §4's perimeters 6 and
7 of `planning/production-readiness-closure.md`.

---

## 1. Perimeter 6 — which queue saturates first

A request passes through several bounded resources in series: the kernel's
accept backlog, the admission budget (`max_connections − reserved_conns`), a
synchronous Handler lane, and process memory. The matrix (C-02) says what each
does *alone*. Nobody had asked what they do *together* — the architecture
backlog's "which queue saturates first" question, unmeasured since it was
written.

`tests/c05-saturation` ramps concurrent clients against a server with
`max_connections = 24`, `reserved_conns = 4` (budget 20) and a handler that
dwells 40 ms, and **classifies every request by the outcome that identifies
which resource refused it**:

| Outcome | Means |
|---|---|
| `200` | served |
| `503` | the **Handler lane** refused (the F-002 refuse-and-retry) |
| connected, then EOF with nothing written | the **admission budget** refused |
| connect failed | the kernel **backlog** or the fd table refused |
| timeout | nothing refused; something is merely slow |

Telling the middle two apart is the whole instrument. An admission refusal
accepts the TCP connection and then closes it unwritten, so a client that counts
only "errors" cannot distinguish it from a backlog drop — the same distinction
C-03's RST-flood probe needed, and the reason both suites can *name* a binding
constraint instead of guessing at one.

### The result

On an 8-core development box, representative run:

| clients | served | 503 (lane) | admission | connect fail | timeout |
|---|---|---|---|---|---|
| 4 | 3 | **1** | 0 | 0 | 0 |
| 12 | 8 | 4 | 0 | 0 | 0 |
| 24 | 6 | 2 | **7** | 0 | 9 |
| 48 | 9 | 3 | 0 | 0 | 36 |

**F-C05-2 — the binding constraint is the Handler lane, and it binds at four
concurrent clients.** Not the connection budget, which has twenty slots and does
not refuse anything until twenty-four clients; not the backlog, which never
refused at all. With a synchronous handler occupying its lane for 40 ms, **one
request in four is already refused with 503 at a concurrency of four.**

That is worth stating plainly because it inverts the intuitive tuning move. An
operator seeing 503s under load would reach for `max_connections` — and
`max_connections` is not the constraint. The knob that matters is
`max_handlers`, and behind it the handler's own dwell: **capacity is
`lanes ÷ dwell`, and connection slots only decide how many clients get to wait.**
The degradation is honest — every refusal is a refusal the design names, and
`malformed` was zero at every level in every run — but "honest" is not the same
as "expected", and this number belongs in the operations documentation rather
than in a reader's mental model.

It also corrects something C-03 wrote. The B4 cell's note reasoned that the 503
path was reachable only through a narrow race window inside
`handler_lane_enter`'s spin. Under real concurrency that window is not narrow at
all: it is the common case, because with N lanes and more than N concurrent
requests, arriving requests routinely land on a lane already inside a handler.

### H-4 follow-ups (the operational corrections this measurement demanded)

1. **The 503 now carries `Retry-After: 1`** (vendored change at the
   `dispatch_exchange` refusal path). A refusal that does not say *when* to come
   back invites an immediate retry onto the same contended pool, which collides
   again — the refusal creates the retry storm it was trying to shed. One second
   is the smallest honest hint (a synchronous handler's dwell is the thing being
   waited out). The C-05 ramp asserts the property over real 503s:
   `Lane_Refused_No_Retry` must be zero and `Lane_Refused` must be non-zero.

2. **The lane pool has no queue and no work-stealing, deliberately, and this is
   RECORDED AS A REFUSAL rather than a gap.** A request that lands on a busy lane
   is refused, not queued and not moved to an idle lane. Queueing is the obvious
   improvement and it is exactly what F-002 was: the `next_tick` deferral of a
   dispatch, which was a use-after-free because everything the dispatch names —
   `req`/`res` into `conn.loop`, the inbound views, the `Exchange` itself — lives
   in the connection's temp arena, which `clean_request_loop` frees. **A queue is
   sound only after that ownership changes** (the `Exchange` and its views would
   have to outlive the connection teardown, refcounted or copied out). That is a
   dedicated concurrency-architecture study, requested separately by the owner;
   this WP only pins the current refusal and its reason so the `next_tick` UAF
   cannot be reintroduced as a throughput "fix". Matrix row 4 carries the same
   note.

---

## 2. F-C05-1 — the unbounded accept-cancel spin wedges shutdown

**CLASSIFICATION: production-blocking absence.** *Fixed in-phase (vendored patch
27). Pre-existing: reproduces on `origin/main`.*

The saturation ramp did not only measure. It **hung**, and the hang is a defect
worth more than the measurement that found it.

`handler_lane_enter` suspends a lane's `accept` before running a synchronous
handler. Because `nbio.remove` is asynchronous, it then waits for the
cancellation to be observed:

```odin
for target.accept.client == 0 && target.accept.err == nil {
    _ = nbio.tick(time.Millisecond)
}
```

**No iteration cap, no deadline.** C-01 inventoried this as F-C01-3 and
classified it as an acceptable limitation, on the argument that `io_uring`
always delivers a completion for a cancelled submission so the loop must
terminate. **The measurement refutes the argument.**

| Tree | `web.stop` returns | runs |
|---|---|---|
| pristine `origin/main` (dbbd522) | **NO** | **4 of 6 wedged** |
| pristine, wedged runs | did not return in **15 s**, and in a longer probe not in **60 s** | — |
| with vendored patch 27 | **yes**, at ~0.5 s or ~3.0 s | **11 of 11** |

Note what the fixed timings say: the runs that used to wedge now return at
**~3.0 s**, which is exactly `max_drain_time`. The drain deadline finally bounds
shutdown, as it is documented to.

**Why one lane stops the whole server.** The spin runs on the lane thread. A
lane parked in it never returns to its event loop, never observes `s.closing`,
and never calls `_server_thread_shutdown` — and `serve` waits on
`threads_closed` for *every* lane. So one lane in the spin is a process that
cannot be stopped, **past `max_drain_time`**, which bounds the drain and cannot
bound a lane that never reaches the drain.

**The fix** caps the wait at 250 ms. On expiry it abandons the wait and leaves
the operation record **detached** rather than returning it to the pool:
reattaching a record whose completion may still arrive would hand the pool an
entry the kernel can still write to, trading a wedge for a use-after-free. One
leaked `Operation` per occurrence is the correct price. Abandoning is safe
because `nbio.remove` has already guaranteed the callback will never run; what
the wait exists for is the narrow case where the accept *won* the race and holds
a connected client — worth waiting for, not worth waiting forever for.

### The methodological finding

This is the second time in this phase that a cell classified by **reasoning**
turned out to be wrong, and the first time was the same cell. The inventory's
ten questions found the operation and asked the right question of it — question
9, "is there a maximum deadline?", answered "no". What failed was the step
after: **accepting a reason instead of demanding a test.** Question 10 exists to
stop exactly that, and this cell answered it "n/a — it is not an operation".

The rule now written into `planning/closure-async-op-inventory.md`: *a cell
whose safety rests on reasoning rather than on a test is not answered, it is
deferred.*

---

## 3. Perimeter 7 — write observability: specified, not implemented

**The gap, unchanged and now precisely stated.** The core's entire public
observability surface is **one counter**, `web.refused_connections()`, plus the
typed `Framework_Event` observer, which reports per-request framework *errors*
and carries no counters. Consequently an operator **cannot see**:

- how many responses were sent, or how many bytes they carried;
- how many sends failed, or how many connections the write deadline aborted;
- any of the three stream-registry counters — `refused_stream_full`,
  `refused_budget_full`, `aborted_slow` — which **exist and are maintained** in
  `web/internal/stream` and are reachable from no public API. A slow-consumer
  abort is counted and then invisible.

C-05 does **not** ship this, for the reason C-04 did not ship
`max_response_bytes`: it mints public surface, and a ledger-growing change is a
twelve-file ritual (`build/check_public_api.sh`, `check_phase1_freeze.sh`, the
signature snapshot, `planning/phase-1-freeze.md`, `check_docs.sh`,
`docs/ai-context.md`, and the rest) that deserves its own work package and its
own gate run rather than being appended to an audit phase.

### The specification, handed forward

One accessor, one struct, `+2` on the application ledger (73 → 75):

```odin
Server_Stats :: struct {
    refused_connections:  int, // == web.refused_connections(), for one call site
    responses_sent:       int,
    response_bytes:       i64,
    send_errors:          int,
    write_deadline_aborts:int,
    stream_refused_full:  int, // registry: per-stream event/byte cap
    stream_refused_budget:int, // registry: process-wide byte budget
    stream_aborted_slow:  int, // registry: owner tore down on write error/deadline
}
stats :: proc() -> Server_Stats
```

- **Redaction holds by construction** (WP20 §3.1): every field is a plain
  integer, so no request-derived byte can reach it — the same argument that put
  `refused_connections` inside the permitted set.
- **Plumbing:** four atomic counters on the backend `Server` (incremented in
  `on_response_sent` and in the sweep's write branch), surfaced through
  `web/internal/transport` beside `refused_connections`, joined there with
  `stream.counters(&runtime.streams)` — which already returns exactly the three
  stream fields.
- **Zero on a stopped server**, matching `refused_connections`'s existing rule.
- Keep `web.refused_connections()` as-is: it is in the frozen ledger, and
  removing it to tidy the surface would be a breaking change for a cosmetic gain.

**Trigger to promote this from recommendation to requirement:** the first
production deployment that runs detached streams. Slow-consumer aborts are the
one failure this framework can perform silently, and §1's finding — that the
lane binds first, at a concurrency far below the connection budget — means an
operator will reach for these numbers sooner than the matrix's amber cell
suggested.
