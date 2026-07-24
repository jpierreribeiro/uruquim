# C-03 — The closed fault-injection campaign

**Status: LIVE (Closure, WP C-03).** Companion to
`planning/production-readiness-closure.md` §2.3. This is the **grid**: a fixed
scenario space, enumerated once, with every cell either pointing at the suite
that already proves it or naming the suite C-03 wrote to fill it.

---

## 0. What "closed" means, and why it is the point

Uruquim has found faults one at a time, and each time the finding was real: the
orphaned `recv` (WP58), the negative chunk size (patch 14), the multi-lane
shutdown crash (WP70), the use-after-free through a deferred dispatch (F-002),
the write deadline. Every one was discovered by *encountering* it.

A campaign is the opposite method. The axes below are not a list of bugs
anyone suspects; they are the **complete space of things that can go wrong at
each boundary** — what a client may send, what an application may do, what a
client may do with the response, and what a shutdown may land on top of. Filling
the grid does not prove there are no defects. It proves something weaker and far
more useful: **the space has been enumerated, so a future finding is a new cell,
not a new category.**

The campaign's other job is to stop the same measurement being written twice.
Where a green suite already drives a cell, C-03 **cites** it by test name rather
than re-measuring it: a second copy of a test is a second thing to keep true.

---

## 1. The grid

`✅` covered by an existing suite (named) · `🆕` filled by C-03 ·
`📕` declared: not testable in-process, and the reason is the answer ·
`🌐` external: belongs to the mandatory topology (C-06)

### A. Input — what a client can send

| # | Scenario | Proven by |
|---|---|---|
| A1 | Connect and send nothing, hold the socket | ✅ `wp41-fault` `phase_deadline_ends_a_held_connection` |
| A2 | One byte per second (slowloris) | ✅ `wp41-fault` `phase_deadline_bounds_a_trickling_client`, fault `Slow_Writer` |
| A3 | Truncated request line, socket held open | ✅ `wp41-fault` fault `Truncate_And_Hold`; `c01-async-ops` P2 |
| A4 | Truncated header block | ✅ `wp41-fault` `Truncate_And_Hold` at header offsets |
| A5 | Truncated fixed-length body | ✅ `wp9-wire` "truncated fixed body is rejected" |
| A6 | Truncated / malformed chunked body | ✅ `wp9-wire`; vendored patch 14 (negative chunk size was a remote process kill) |
| A7 | Ambiguous framing (CL+TE, duplicate CL) | ✅ `wp9-wire`; vendored patches WP9 D2 |
| A8 | Request fragmented at hostile offsets (mid-header, between CR and LF) | ✅ `wp41-fault` fault `Fragmented_Request` |
| A9 | Close with the request half-sent | ✅ `wp41-fault` fault `Close_Mid_Request` |
| A10 | **Sustained RST flood** | 🆕 `c03-fault-campaign` `c03_a_healthy_client_survives_an_rst_flood` — the inherited F-002 follow-up |

### B. Execution — what the application can do

| # | Scenario | Proven by |
|---|---|---|
| B1 | Handler blocks | ✅ `wp71`/`wp72-concurrent-serving`; `tests/support/blocking_lab` |
| B2 | Handler returns without responding | ✅ standardized 500 — `wp6-public-surface`, `docs/errors.md` |
| B3 | Handler responds, then faults | 📕 the process aborts, by construction. Odin has no recoverable panic (ADR-020) and Uruquim declines to fake one; a test that proved it would abort the runner. The supervisor is the answer, and C-06 tests that topology. |
| B4 | Every Handler lane busy when a request arrives | 🆕 `c03-fault-campaign` `c03_a_contended_lane_refuses_with_503_and_stays_alive` — the F-002 fix, under test rather than under an ad-hoc validation |
| B5 | Slow dependency inside the handler | ✅ `tests/support/web_blocking_lab` |
| B6 | Client disconnects while the handler runs | 🆕 `c03-fault-campaign` `c03_a_disconnect_during_the_handler_does_not_outlive_the_request` |

### C. Output — what the client does with the response

| # | Scenario | Proven by |
|---|---|---|
| C1 | Client never reads | ✅ `wp90-deadlines` `wp90_a_stalled_write_is_aborted_at_the_deadline` |
| C2 | Client reads slowly | ✅ `wp91-stream-security` `wp91_a_slow_consumer_receives_every_byte_exactly_once`; `wp92-backpressure` |
| C3 | Client reads part, then stops | ✅ `wp41-fault` fault `Slow_Reader`; `c01-async-ops` P3 |
| C4 | Response larger than the socket buffer pair | ✅ `wp90-deadlines` (8 MiB); `c01-async-ops` P3 |
| C5 | Error during `send` (peer gone mid-write) | 🆕 `c03-fault-campaign` `c03_a_send_error_retires_the_connection_without_a_second_write` |
| C6 | Keep-alive after a healthy response | ✅ `wp41-fault` `phase_keep_alive_serves_two_requests_on_one_connection` |
| C7 | Close before the response arrives | ✅ `wp41-fault` fault `Close_Before_Response` |

### D. Lifecycle — shutdown against every state

| # | Scenario | Proven by |
|---|---|---|
| D1 | Stop with no connections (the floor) | ✅ `wp58-drain` baseline; `c01-async-ops` P1 (**991 ms**, and C-01 named the mechanism) |
| D2 | Stop with idle keep-alive connections | ✅ `wp58-drain` idle phase (8 conns, 987 ms) |
| D3 | Stop with a `recv` holding a partial token | ✅ `c01-async-ops` P2 |
| D4 | Stop with a connection held `.Active` | ✅ `wp58-drain` `phase_obligation_3_stop_returns_with_a_connection_held_active` |
| D5 | Stop with a `send` in flight to a dead reader | ✅ `c01-async-ops` P3 (**1.544 s** = drain deadline + close delay; the write deadline played no part — F-C01-2) |
| D6 | Stop with detached streams open | ✅ `wp95-drain` `wp95_open_streams_terminate_within_the_drain_deadline` |
| D7 | Stop after a write-deadline abort | ✅ `c01-async-ops` P4 |
| D8 | A deadline and the shutdown expiring together | 🆕 `c03-fault-campaign` `c03_a_deadline_expiring_with_the_drain_does_not_double_close` |
| D9 | A second `stop` | ✅ `wp41-fault` `phase_stop_is_idempotent_and_stops_admission` |
| D10 | Stop after a FAILED listen (port occupied) | 🆕 `c03-fault-campaign` `c03_a_stop_after_a_failed_bind_returns` — probed during C-01, made permanent here |
| D11 | Supervisor kill after the drain deadline | 🌐 external — the mandatory topology, C-06 |

**Cells: 34. Covered by existing suites: 25. Filled by C-03: 6. Declared: 1.
External: 1. Unanswered: 0.**

---

## 2. The RST-flood wedge — the inherited finding

`docs/reports/2026-07-23-security-f001-f002.md` closed F-002 and recorded, as
out of scope, that *"under a SUSTAINED RST flood the server stops accepting (all
threads alive, listen backlog fills, no crash)."* The Closure owns it, and
owning it starts with measuring it rather than reasoning about it.

**Two candidate mechanisms, from the C-01 inventory, wanting opposite fixes:**

- **(a) The admission slot outlives the peer by 500 ms.** `connection_close`
  shuts down the send side, arms `Conn_Close_Delay` (500 ms, RFC 7230 6.6
  politeness so a client can finish reading a response), then closes; and
  `active_connections` is decremented in `connection_teardown`, at the *end* of
  that chain. A connection whose peer has already sent RST — where there is
  nobody left to be polite to — still holds one of
  `max_connections - reserved_conns` slots for half a second. A flood only needs
  to open connections faster than `budget / 500 ms` to make every subsequent
  client meet the admission refusal. The server is then alive, accepting, and
  refusing everyone.
- **(b) The accept re-arm is delayed 10 ms per transient failure.** An RST that
  lands before `accept` returns gives `ECONNABORTED`. Patch 21 tolerates it by
  re-arming after `URUQUIM_ACCEPT_RETRY_DELAY` (10 ms), so each lane spends
  10 ms not accepting per failure — roughly 100 accepts/s/lane — and the listen
  backlog fills behind it.

They are **distinguishable by what a healthy client sees**, which is why the
probe in `tests/c03-fault-campaign/rst_flood_test.odin` records the failure
*kind*: (a) predicts connect-succeeds-then-closed-with-no-reply; (b) predicts
connect itself failing while the backlog is full.

### The measurement

<!-- c03-rst-verdict:start -->
*(recorded below by the run; see §2.1)*
<!-- c03-rst-verdict:end -->

---

## 3. What C-03 does not claim

The grid is **complete for the boundaries it names**, not for every fault that
exists. Three exclusions, stated so they are choices rather than oversights:

- **No fuzzing.** The wire corpus (`wp9-wire`) and the seeded fault lab
  (`wp41-fault`, replayable trails) cover structured malformation. A fuzzer
  would be a different instrument with a different cost, and it is
  evidence-gated in the backlog, not silently skipped.
- **No multi-host or network-partition faults.** Everything here is loopback.
  Partition behaviour belongs to the topology (C-06) and to whatever the
  application does with its own dependencies.
- **No adversarial timing at nanosecond resolution.** The races this project has
  actually shipped (WP70's Date buffer, F-002's deferred dispatch) were found by
  reading ownership, which is C-01's instrument, not by winning a race in a
  test.
