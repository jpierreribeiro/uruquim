# 22 — Future Research Backlog

Status: **PHASE-OWNED / NON-IMPLEMENTING.** Items below are questions and
disposable evidence tasks. They do not authorize production code or public API.

| Order | Topic | Owner / due | Required evidence | Promotion condition |
|---:|---|---|---|---|
| 1 | Repeated body binding | WP7, before implementation | Pinned-toolchain prototype for success, invalid first bind, empty body, and second bind | ADR-012 decided; tests written first |
| 2 | HTTP/1 framing corpus | WP9 | Same raw corpus against bootstrap and future real adapters | Wire behavior documented per adapter; no core parser ABI |
| 3 | Router layout shootout | Phase-3 Spec Gate | Pointer, indexed, and hybrid layouts on static/param/wildcard workloads; allocations, latency, footprint, build cost | Representation chosen from recorded measurements |
| 4 | Arena oversize/retention | Phase-3 Spec Gate | Normal, burst, and giant-body workloads; peak/retained memory and reset cost | Bypass and retention policy recorded without arbitrary constants |
| 5 | Request-view debug tooling | Phase-3 Test Gate | Pinned `base:sanitizer`, poison/unpoison, immediate reuse and quarantine variants | Limitations and supported platforms documented; zero release hot-path cost |
| 6 | Graceful drain | Phase-4 Spec Gate | Test transport plus one real adapter; slow headers/body/writer, keep-alive, deadline races | ADR candidate defines admission, in-flight, deadline, forced close, once-only cleanup |
| 7 | Trusted proxies | Phase-4 Spec Gate | IPv4/IPv6 CIDR corpus; direct spoofing, multiple proxies, malformed chains | ADR-013 decided before any public configuration |
| 8 | Route-pattern telemetry | Phase-4 Test Gate | 200, random 404, parametrized 405, slow/stuck exporter, bounded queue | One series per pattern; no raw-path fallback; dropped events observable |
| 9 | Multipart ownership | Phase-4 Spec Gate | Memory/file spill, partial writes, disconnect, timeout, disk-full and persist failure | Ownership, cleanup, quotas and error categories ready for ADR |
| 10 | Deterministic shedding | Phase-4 | Fixed in-flight/queue limits under cheap, slow-body and slow-writer workloads | Memory/queues bounded; rejection cheaper than admitted work |
| 11 | Adaptive overload | Future, after item 10 | Binary/scaled signals, hysteresis and recovery measurements | No oscillation; deterministic mode remains independently usable |

## Research invariants

- Every experiment is disposable and isolated from production packages.
- Compiler evidence uses the project-pinned Odin version.
- Benchmarks record hardware, workload, compiler, commit, and allocation data.
- A useful mechanism is not automatically a public API.
- A debug detector is not described as a correctness or security guarantee.
- A feature cannot move earlier merely because an external framework ships it.
