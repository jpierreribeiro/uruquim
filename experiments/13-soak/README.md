# Experiment 13 — soak and the whole-system allocator audit (WP53 / WP54)

**Two questions, one instrument, because they are the same run seen twice.**

* **WP53** — does the server survive sustained load, including the workloads the
  plan named by hand: a slow client and a slow writer?
* **WP54** — does memory grow across that run? A leak is invisible in a
  request-scoped test and obvious over thousands of requests.

## How to run

```
bash experiments/13-soak/run.sh
```

It builds a consumer, drives it, and reports. It changes nothing in the tree.

## What it measures, and what it refuses to

**Measures:** requests completed, non-2xx responses, RSS at start and end, and
whether the process is still answering afterwards.

**Refuses to measure:** latency percentiles, and any per-request cost.
FINDING-A, re-verified at the Phase-3 freeze, puts this machine's noise floor at
**138%**, and the client is `curl` processes rather than a load generator.
**A p99 from this harness would be a number about process spawning.** WP53's
real answers are survival and memory, both coarse enough to survive the
instrument.

**RSS is the leak signal, and it is a weak one — stated rather than dressed up.**
An allocator that never returns pages to the OS shows flat RSS while leaking,
and one that does shows sawtooth while healthy. What RSS *can* catch is
**unbounded growth**, which is the failure that matters, and it cannot
distinguish a leak from a cache. WP54's stronger instrument — a tracking
allocator over the whole serve path — is recorded as **not delivered** in
`planning/phase-4-plan.md`, with its reason.
