# Phases 3 to 5 — work packages and research gates

**Status: DRAFT. Nothing here is frozen. No future signature is committed.**

Detail is deliberately **proportional to distance**. Phase 3 has defined work
packages with its representation decisions explicitly conditioned on
measurement. Phase 4 has capabilities and gates without invented APIs. Phase 5
is a prioritised backlog, not a product promise. Producing precise signatures
for work two years out would be false precision, and this document does not do
it.

Companion documents: [`post-phase1-audit.md`](post-phase1-audit.md) (the
evidence), [`odin-fit-audit.md`](odin-fit-audit.md) (design fit),
[`roadmap.md`](roadmap.md) (sequencing), [`phase-2-plan.md`](phase-2-plan.md).

---

## Findings from external research that constrain these phases

Recorded here because each one removes a choice or forces one. Sources in §5.

### C-1 — HEAD is effectively mandatory, and 501 is a SHOULD Uruquim currently declines

RFC 9110 §9.1: *"All general-purpose servers MUST support the methods GET and
HEAD. All other methods are OPTIONAL."* Uruquim registers GET, POST, PUT, PATCH
and DELETE only, and WP9 deliberately disabled the backend's HEAD→GET behaviour.

The same section splits the error cases: a method *unrecognized or not
implemented* SHOULD get **501**; a method *recognized but not allowed for this
resource* SHOULD get **405**. Uruquim collapses unknown methods into the 404/405
path, which WP9 ratified deliberately (D7: the transport must not invent a
status before the core sees the request).

Both are **SHOULD**, not MUST, so deviating is permitted — but it must be a
recorded decision rather than an omission. Phase 3 owns HEAD and OPTIONS; the
501 question should be decided at the same time, in the same ADR.

Cheap conformant HEAD: route to the GET handler and suppress the body. §9.3.2
explicitly permits omitting header fields "for which a value is determined only
while generating the content", so `Content-Length` need not be computed.

### C-2 — observability is blocked on one missing accessor, and the constraint is a MUST

The OpenTelemetry HTTP semantic conventions define `http.route` as *"the matched
route template … **MUST be low-cardinality** and include all static path
segments, with dynamic path segments represented with placeholders"*, and — the
load-bearing sentence — *"**MUST NOT be populated when this is not supported by
the HTTP server framework** … the URI path can NOT substitute it."* Span naming
adds: *"Instrumentation **MUST NOT** default to using URI path as a target."*

So today any conformant instrumentation is **required to omit** `http.route`
entirely and forbidden from falling back to the path. That means no per-route
latency metrics and degraded span names.

Uruquim already *has* the template — the App-owned `pattern` string, matched in
`web/dispatch_match.odin` — it simply never surfaces it. **Exposing the matched
pattern as a borrowed string is the single smallest change that unlocks the
entire observability story, and it costs nothing**: the pattern is already
App-owned and already viewed by `Route_Param.name`. This is a Phase-3/4 decision
worth making early.

Related: when the method is not recognised, the conventions expect
`http.request.method_original` to carry the raw token. Uruquim exposes no
`method_raw` publicly, so that attribute is unavailable to any future
instrumentation. Worth recording, not worth fixing before there is a consumer.

### C-3 — framing errors are response-**and-close**, not just response

RFC 9112 §6.3 states the close obligation three separate times: a
`Transfer-Encoding` that is not finally-chunked in a request → *"MUST respond
with 400 … and then close the connection"*; an invalid `Content-Length` → *"MUST
treat it as an unrecoverable error … respond with 400 … and then close"*; a
short read against a valid `Content-Length` → *"MUST consider the message
incomplete and close"*. §9.3 adds the rule that bites on early rejection: *"A
server MUST read the entire request message body or close the connection after
sending its response"* — otherwise leftover bytes are parsed as the next
request.

This is a **transport-layer contract**, and it interacts with Uruquim's
single-commit response guard: a 413 or 400 committed by the core must still
result in drain-or-close at the transport. WP9's corpus covers the rejection;
Phase 4 owns the connection-lifetime half. §9.6 also warns that closing without
a staged half-close can reset the client's buffers before it reads the 400 — so
the error the client never sees is a real failure mode.

### C-4 — no header-derived client identity is trustworthy

RFC 7239 §8.1: *"The 'Forwarded' HTTP header field cannot be relied upon to be
correct, as it may be modified … by every node on the way to the server,
including the client making the request."* And on the standard mitigation:
allowlisting trusted proxies *"has at least two weaknesses. First, the chain of
IP addresses listed before the request came to the proxy cannot be trusted."*

There is therefore **no spec-blessed way to derive a trustworthy client IP from
headers alone**. The only defensible design is: default to the peer address, and
require the number of trusted hops (or a trusted-proxy set) to be explicit
operator configuration. Anything that silently reads `X-Forwarded-For` ships a
spoofable identity. §8.2 adds that `Forwarded` must never be copied into a
response, since it reveals the proxy chain.

### C-5 — the radix-router justification is not what folklore says

Neither httprouter nor matchit — the two canonical implementations — states when
a radix tree is *not* worth it, and **neither compares against a linear scan at
small route counts**. Their documented wins are: allocation-free matching,
exactly-one-match semantics, and scaling to many or long routes. The first two
are achievable with a linear scan over pre-split segments as well. Only the
third is uniquely the tree's, and no author quantifies where it starts to matter.

Counter-datapoint from a standard library: Go 1.22's `ServeMux` deliberately did
**not** use a radix tree, choosing a backtracking decision tree instead, and it
resolves ambiguity by **panicking at registration** on conflicting patterns.

**Consequence for Phase 3: justify a router change by match semantics or by
Uruquim's own measurements — never by unsourced performance folklore.** Any
"linear scan is fine below N routes" claim in this project is engineering
judgement and must be labelled as such.

### C-6 — request-scoped state: both mainstream mechanisms are solving a problem Uruquim does not have

Go's `context.WithValue` costs one heap allocation per value plus a full
`Request` copy per middleware, with O(depth) lookup. Rust's `http::Extensions`
is a boxed `HashMap<TypeId, Box<dyn Any>>`. Both exist for type-erased,
dynamically-keyed state crossing library boundaries — which Uruquim does not
need. Struct fields in a request arena, which is what `Context_Internal` already
is, dominate both. If extensibility is ever genuinely required, a small fixed
`[N]{key, rawptr}` array in the arena beats both. This supports G-03 rather than
challenging it.

### C-7 — post-`next` middleware costs a frame per hop in every language that offers it

koa-compose allocates a closure and a promise per middleware per request. Axum's
ergonomic `from_fn` boxes "the rest of the chain" per call, even though Tower's
type-level `Layer` composition is in principle zero-cost. Go's `net/http` has no
middleware type at all and gets post-`next` free on the machine stack.

Uruquim's forced design (Phase 2, FINDING-B) — a cursor plus ordinary calls —
lands closest to Go's: post-`next` costs stack frames, not allocations. That is
a genuine advantage and Phase 3's chain work must not surrender it.

### C-8 — Odin will never have a package manager, and no library tags releases

The FAQ is explicit: *"Odin will **never** officially support a package
manager"*, and recommends *"copying and vendoring each package manually, and
fixing the specific versions down"*. A survey of the ecosystem found almost no
library tags releases at all; the best-run precedent (`DanielGavin/ols`) tags
against **the Odin release it builds for** (`dev-2026-05`, …). Odin itself ships
monthly `dev-YYYY-MM` releases, has no semver and no 1.0, and lands breaking
core-library changes in ordinary monthly releases — `core:os` was replaced
wholesale in `dev-2026-03`, with the old API retained only "until sometime in Q3
of 2026", which is approximately now.

**Uruquim is already ahead of the ecosystem here**: `odin-version.txt` pins a
release, a commit and an asset SHA-256, which is stronger than anything
surveyed. Keep it, state it in the README, and put **no** package-manager
integration on the roadmap. Budget one to two core-library migrations per year.

---

## Phase 3 — Performance core

**Entry:** Phase 2 frozen; a benchmark harness exists.
**Theme:** make it stay fast as route count and traffic grow, and let operators
bound it. Representation decisions are conditioned on measurement.

### Research gates (must complete before the implementation work packages)

| # | Gate | Question | Output |
|---|---|---|---|
| RG-1 | Benchmark harness | What is the methodology? Recorded hardware, warm-up, route distribution, concurrency levels, p50/p95/p99, allocations, binary size, build time, peak and retained memory | a harness in the gate, plus a recorded Phase-1 baseline to regress against |
| RG-2 | Router shootout | Pointer-based radix, index-based radix, hybrid, and improved linear — measured on Uruquim's own workloads at 5, 50 and 500 routes | a representation chosen from data, with **the losing candidates and their numbers recorded** |
| RG-3 | Allocation audit | Where does per-request allocation actually go? Includes audit A-8 (inbound headers built and never read), A-12 (static headers cloned) and A-13 (the `Header_Pair` ↔ `transport.Header` conversions) | a measured list, and a decision per item |
| RG-4 | Arena policy | What happens to a request arena after an unusually large body? Retain, trim or release (risk R-16) | a policy with numbers behind it |

### Work packages

| WP | Name | Type | Notes |
|---|---|---|---|
| P3-1 | Benchmark harness and Phase-1 baseline | TESTS | RG-1; nothing else may start first |
| P3-2 | Route representation shootout | PROTOTYPE | RG-2; **must not choose before measuring** (C-5) |
| P3-3 | Router implementation | IMPLEMENTATION | observable behaviour must stay byte-identical to Phase 1 for every existing test |
| P3-4 | Registration conflict diagnostics | IMPLEMENTATION | Phase 1 deliberately does not diagnose; Go panics at registration — decide and record |
| P3-5 | Path normalisation policy | SPEC + IMPLEMENTATION | Phase 1 normalises nothing on purpose; this is where a policy is chosen or the absence is ratified permanently |
| P3-6 | HEAD and OPTIONS, and the 501 decision | SPEC + IMPLEMENTATION | C-1; HEAD is effectively mandatory |
| P3-7 | Multi-param routes without a map | IMPLEMENTATION | small fixed inline array of views — the convergent design in every implementation surveyed (C-6) |
| P3-8 | Precomputed middleware chains | IMPLEMENTATION | must preserve Phase 2's zero-allocation dispatch (C-7) |
| P3-9 | Route identity accessor | SPEC + IMPLEMENTATION | C-2; the smallest change that unblocks observability. **Adds public surface — owner approval** |
| P3-10 | Arena, buffer reuse and oversize policy | IMPLEMENTATION | RG-4, risk R-16 |
| P3-11 | Configurable limits and timeouts | SPEC + IMPLEMENTATION | options struct with a package default constant, on `core:net`'s `DEFAULT_TCP_OPTIONS` precedent — **not** a builder. **Owner approval** |
| P3-12 | Typed application state | PROTOTYPE + IMPLEMENTATION | ADR-004; must not become a context extension bag (G-03). **Owner approval** |
| P3-13 | Phase-3 freeze | FREEZE | ledger, evidence, regression benchmark in the gate |

### Change classification, to be applied per work package

Phase 3 must state, for every change, which of these it is — the categories are
not interchangeable and the gate obligations differ:

* **internal only** — no observable difference; existing tests must pass
  unchanged and unmodified;
* **observable behaviour change** — needs a spec amendment and new tests;
* **public API change** — needs a ledger entry, G-09 evidence and owner
  approval;
* **Advanced API** — kept out of the common surface entirely.

---

## Phase 4 — Production

**Entry:** Phase 3 frozen; limits and timeouts exist.
**Theme:** make deployment defensible. This phase carries the most absolute
risk, because its mistakes are remotely exploitable rather than merely
inconvenient.

### Capabilities and their gates

| WP | Capability | Notes and constraints |
|---|---|---|
| P4-1 | Concurrency model and thread safety | must resolve audit A-4 (package-level transport globals) and A-14 (registration during dispatch). Today `serve` is single-threaded by construction; whether that changes is *the* Phase-4 architectural decision |
| P4-2 | Lifecycle: stop, shutdown with an absolute deadline, admission stop, exactly-once cleanup | audit A-5; there is no stop today. **Adds public surface — owner approval** |
| P4-3 | Per-server state replacing the globals | ADR-018; prerequisite for two servers or any embedded use |
| P4-4 | Connection lifetime: keep-alive, drain-or-close, staged close | C-3; the close obligation appears three times in RFC 9112 §6.3, and §9.6's staged close is what makes the client actually receive the 400 |
| P4-5 | Limits: connections, queue depth, header count and size, request line, minimum ingress rate | the slowloris mitigation is a minimum ingress rate; OWASP names it and gives no numbers, so Uruquim must pick and justify its own |
| P4-6 | Deterministic load shedding | bounded admission before any adaptive controller (research item 11 stays after this) |
| P4-7 | Trusted proxies and peer preservation | C-4; ADR-013 must be accepted first. Default to the peer address; trusted hops are explicit operator configuration; never echo `Forwarded` into a response |
| P4-8 | CORS | C-5 in §5: five headers, with `*` **not** sufficient under credentials and **not** covering `Authorization`; preflight restricted to an ok status; `Vary: Origin` required for dynamic origins. Candidate for an optional package |
| P4-9 | Secure headers, cookies | cookies force the `Recorded_Response` header decision (Phase-2 D-14.3) |
| P4-10 | Multipart and uploads | OWASP: allow-list extensions, validate after decoding the filename, generate the stored name, never trust `Content-Type`, size limits, storage outside the webroot, no execute permission. **Recommended as a separate package** |
| P4-11 | Static files | traversal, symlinks, ranges, cache validators — a security surface of its own. **Recommended as a separate package** |
| P4-12 | Observability, non-blocking | C-2; **must** key on the low-cardinality route pattern, never the raw path |
| P4-13 | Redaction policy | OWASP's do-not-log list is concrete: tokens, session identifiers, passwords, connection strings, keys, PII, payment data — plus CR/LF escaping against log injection. Phase 1's "nothing reaches a log line" property must be preserved deliberately, not by accident |
| P4-14 | TLS decision | **do not assume the framework terminates TLS.** Compare in-process termination, reverse-proxy termination (the common deployment, and free) and an optional adapter. Recommendation: document proxy termination as supported; in-process at most an optional package. **Owner approval** |
| P4-15 | Vendor maintenance policy | audit A-9/A-10: upstream the five security patches or record why not; replace code-shape greps with corpus assertions; define who watches upstream and how often |
| P4-16 | Fuzzing and an extended framing corpus | extends WP9's raw-wire corpus |
| P4-17 | Load, soak and fault-injection tests | must include a slow-client and a slow-writer workload |
| P4-18 | Allocator and lifetime audit | whole-system, with a tracking allocator |
| P4-19 | Operations documentation | how to deploy, what to bound, what to monitor, what is not hardened |
| P4-20 | Phase-4 freeze | FREEZE |

---

## Phase 5 — Ecosystem backlog

**Not a product promise.** Each item is spec-gated individually, may be
declined, and requires a real user request before it starts. Classification per
the Odin-fit audit.

| Item | Classification | Reasoning |
|---|---|---|
| `core:net/http` adapter | **NEEDS_PROTOTYPE, unscheduled** | **The package does not exist** — verified absent from both the pinned toolchain and the current official index. `core/net` is sockets, DNS and URL parsing; `core/nbio` is an event loop. Treat as a hypothesis with no date |
| OpenAPI generation | SHOULD_BE_OPTIONAL_PACKAGE | a layer over route information; never a generator requirement |
| Automatic documentation | SHOULD_BE_OPTIONAL_PACKAGE | follows OpenAPI |
| Validation | NEEDS_PROTOTYPE | tag-based validation edges toward the type-system cleverness Odin's own principles avoid; explicit validation may simply be the answer |
| WebSocket | SHOULD_BE_OPTIONAL_PACKAGE | its own protocol surface (RFC 6455) |
| Streaming request/response | SHOULD_BE_OPTIONAL_PACKAGE | changes the body-ownership model that ADR-006 and ADR-012 rest on |
| HTTP/2 | SHOULD_BE_OPTIONAL_PACKAGE | only as the transport permits; RFC 9113 is a large surface |
| Advanced API (`app_init`, `Advanced_Config`, `serve_transport`) | ACCEPTABLE_WITH_GUARDRAILS | ADR-010, still PROPOSED; must stay out of the common surface |
| Templates | **REJECT for core** | ecosystem territory |
| Database integration | **REJECT for core** | ecosystem territory; a Postgres *example* belongs in the release track (M4) instead |
| Package distribution and versioning | product track | C-8: vendoring and a pinned toolchain, tagged against the Odin release. **No package-manager integration, ever** |

---

## Product, adoption and maintenance track

Runs alongside the phases (roadmap M0 to M5), not after them.

| Item | When | Notes |
|---|---|---|
| `LICENSE` | **now** | the repository is legally unusable without it. **Owner decision** |
| `SECURITY.md` and a reporting channel | M0 | a framework that handles untrusted input needs a disclosure path before external users |
| `CONTRIBUTING.md` | M0 | must explain the ledger discipline and the gate, or contributors will fight both |
| `CHANGELOG.md` | M0 | |
| Supported Odin version policy | M2 | C-8; state one pinned version as the contract and re-pin deliberately. A CI matrix over the last N monthly releases, with a nightly job allowed to fail, is the early-warning system |
| Platform support, stated honestly | M2 | only Linux x86-64 is tested today. macOS, Windows and other architectures are **untested**, and saying so is the honest position |
| Release checklist and upgrade guide | M3 | |
| Recommended consumption | M2 | vendoring or a submodule; tag against the Odin release, following `ols`'s precedent |
| Beginner documentation, cookbook, full CRUD example, Postgres example | M4 | the cookbook is already a Phase-4 placeholder |
| User study | M5 | `odin-fit-audit.md` §13; **before** any 1.0 stability commitment |
| Retire `planning/`, `experiments/`, knowledge base from the public tree | M5 | per the local cleanup plan's Stage 4 |
| Issue triage and regression policy | M4 | |
| Vendor maintenance policy | P4-15 | |

---

## Sources

All accessed 2026-07-19.

| Source | Informs |
|---|---|
| [RFC 9110 — HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110) | C-1: HEAD mandatory; 405 vs 501; the `Allow` MUST |
| [RFC 9112 — HTTP/1.1 framing](https://www.rfc-editor.org/rfc/rfc9112) | C-3: response-and-close; drain-or-close; staged close |
| [RFC 7239 — Forwarded](https://www.rfc-editor.org/rfc/rfc7239) | C-4: no trustworthy header-derived client identity |
| [OpenTelemetry HTTP spans](https://opentelemetry.io/docs/specs/semconv/http/http-spans/) and [metrics](https://opentelemetry.io/docs/specs/semconv/http/http-metrics/) | C-2: `http.route` low-cardinality MUST; path must not substitute |
| [WHATWG Fetch](https://fetch.spec.whatwg.org/) | P4-8: CORS preflight requirements |
| [OWASP Cheat Sheets](https://cheatsheetseries.owasp.org/) — File Upload, Logging, DoS | P4-5, P4-10, P4-13 |
| [Odin FAQ](https://github.com/odin-lang/odin-lang.org/blob/master/content/docs/faq.md) and [releases](https://github.com/odin-lang/Odin/releases) | C-8: no package manager; monthly `dev-` releases; breaking changes |
| [httprouter](https://github.com/julienschmidt/httprouter), [matchit](https://github.com/ibraheemdev/matchit), [Go `routing_tree.go`](https://github.com/golang/go/blob/master/src/net/http/routing_tree.go) | C-5: radix tradeoffs, and the absence of small-N guidance |
| [koa-compose](https://github.com/koajs/compose), [Tower `Layer`](https://docs.rs/tower/latest/tower/trait.Layer.html), [axum `from_fn`](https://github.com/tokio-rs/axum/blob/main/axum/src/middleware/from_fn.rs) | C-7: what post-`next` costs at runtime |
| [Go `context`](https://github.com/golang/go/blob/master/src/context/context.go), [`http::Extensions`](https://github.com/hyperium/http/blob/master/src/extensions.rs) | C-6: request-scoped state tradeoffs |

### Where the evidence is thin — stated so it is not overclaimed

* **No primary source gives small-route-count guidance for radix routers.**
  Neither httprouter nor matchit addresses it. Any "linear scan is fine below N
  routes" claim in this project is engineering judgement, not citable.
* **"Go's `net/http` has no middleware type"** is absence of evidence; no
  maintainer statement says it is deliberate.
* **RFC 9110's 501 rule is a SHOULD, not a MUST** — Uruquim may deviate, but the
  deviation must be recorded as a decision.
* **OWASP is guidance, not a specification**, and its DoS sheet names techniques
  without numbers. Uruquim must choose and justify its own limits.
* No framework's self-published benchmarks were used as evidence about anything,
  and none should be.
