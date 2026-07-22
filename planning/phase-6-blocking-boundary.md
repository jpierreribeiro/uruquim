# Phase 6 blocking-boundary evidence (WP69)

**Status:** measured prototype, 2026-07-22. **No public concurrency shipped.**

The deterministic latch represents a synchronous PostgreSQL call without
letting a driver explain the result. Every test arm runs in a separate process:
the vendored backend is designed for one server lifetime, and reusing backend
event-loop state across mixed lane counts was measured to contaminate results.

## Admissible result

On loopback with a baseline below the pre-registered 25 ms noise ceiling:

```text
one-lane, one blocker      health_before_release=false
four lanes, three blockers health_before_release=true
four lanes, four blockers  health_before_release=false
record lower bounds        lane=72B connection=760B
```

The acceptance claim is ordering, not throughput: the four-lane candidate can
retain one live Handler lane while three synchronous calls are stopped at a
latch. Saturating all four removes that progress, exactly as specified.
Phase 4 remains the authoritative live measurement for full per-connection
memory (about 4.6 KiB in its 6,000-connection laboratory); 760 bytes is only
the backend record lower bound. A lane record adds 72 bytes before event-loop
and operating-system thread resources, so no RSS percentage is claimed.

Idle keep-alive, a partial request and a client retaining a 256 KiB response
with a 1 KiB receive buffer do not consume the synchronous Handler lane. Five
fresh startup/teardown cycles pass. A job pool cannot be selected yet because
the current `Dispatch_Proc` returns one complete `Outbound`; completing later
would require a continuation and new request/response ownership.

## Two findings that constrain WP70–WP72

1. **Admission follows the event-loop lane, not free Handler capacity.** The
   backend rearms a lane's accept before invoking the synchronous Handler. With
   one or two blocked lanes, a new connection can already belong to a blocked
   lane while another is free. WP71 must suspend that lane's accept while the
   Handler is active. Existing keep-alive connections remain lane-owned and are
   honestly inside the blocked lane's blast radius. WP72 repeats blocker counts
   one through three; all must preserve a newly connected health request.
2. **Concurrent drain is currently unsafe.** Calling shutdown while one of four
   lanes is held inside a Handler reproducibly terminates with
   `Segmentation_Fault`. This is retained as a RED process-isolated obligation.
   WP72 may turn it GREEN only by making cross-lane lifecycle exactly-once; it
   may not weaken or delete the case.

Arbitrary foreign blocking code is still not preemptible. Even after the
backend lifecycle defect is fixed, `max_drain_time` can cancel framework-owned
I/O but cannot unwind a user procedure stuck in a C call. That limitation is
part of the public concurrency contract, not an implementation bug.

## Reproduction

`build/check_wp69_controls.sh` runs five GREEN process-isolated obligations, the
RED drain obligation under an external timeout, the report executable and a
one-lane mutation of the candidate. A mutation that leaves the candidate green
invalidates this evidence.
