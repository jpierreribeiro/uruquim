# Uruquim

*A web framework for the Joy of Programming.*

An Odin microframework for real-world JSON APIs.

**Simple by default, explicit when needed, data-oriented underneath.**

**Positioning:** internally data-oriented and allocator-aware; externally simple,
productive, and predictable — for humans and for AI coding agents. No code
generator, no mandatory CLI, no heavy metaprogramming: ergonomics come from
extractors and canonical helpers.

Uruquim is built on three equally important commitments:

```text
Performance
    + memory correctness
    + predictable hot path

Productivity
    + safe defaults
    + simple CRUD
    + few mandatory concepts

AI readability
    + canonical API
    + compiling examples
    + no aliases, no magic
```

The target experience:

<!-- fragment: phase1/readme-taste -->
```odin
package main

import web "uruquim:web"

User :: struct {
	id:   int    `json:"id"`,
	name: string `json:"name"`,
}

main :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/users/:id", get_user)

	web.serve(&app, 8080)
}

get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	web.ok(ctx, User{id = id, name = "Jean"})
}
```

No allocator configuration, no transport selection, no manual context assembly.
The systems-level machinery exists — it lives behind the API, available through
an explicit advanced surface when needed.

## Transport direction

The future Odin `core:net/http` (expected to build on `core:nbio`) is the
desired canonical transport backend if and when its real API is available and
validated. Uruquim initially uses `laytan/odin-http` strictly behind an
internal adapter. No public Uruquim API exposes transport types, so migration
is confined to the adapter and conformance work; its difficulty is not assumed.

## Repository layout

```text
knowledge-base/          Normative specification (read these first)
├── 01-architecture-spec.md
├── 02-odin-idioms-guidelines.md
├── 03-development-phases.md
└── 04-local-agent-system-prompt.txt

docs/                    User- and agent-facing documentation
├── quick-start.md          Start here
├── canonical-patterns.md   The one blessed way to do each common task
├── ai-context.md           Compact API reference for coding agents
├── errors.md               The error envelope and every error code
├── middleware.md           The onion, its ordering rule, and its costs
└── transport-conformance.md  How transports are proven correct

examples/                Compiling programs (all built by the gate)
├── 01-hello-world/
├── 02-json-api/
├── 03-route-params/
├── 04-middleware/
├── 05-route-groups/
└── 06-authentication/
```

## Status

Phases 1 and 2 are complete: implementation finished, public contracts frozen
behind a gate. What "frozen" means, symbol by symbol and with the evidence
behind each one, is recorded in
[`planning/phase-1-freeze.md`](planning/phase-1-freeze.md) and
[`planning/phase-2-freeze.md`](planning/phase-2-freeze.md) — the Phase-2
freeze covers not only the API but the project's claims, lifetimes and
capacities. Phase 3 (the performance core) is planned in
[`planning/phase-3-plan.md`](planning/phase-3-plan.md) and has not started.

**What works today**

- A real HTTP server: `web.serve(&app, port)` binds a port and answers.
- Routing with static and `:param` segments; static routes win over
  parametric ones.
- Middleware with `web.use` — onion model, so code after `web.next` sees the
  response. Route groups under a prefix with `Router` and `mount`, and
  route-level middleware on the five verbs.
- Request header lookup (`web.header`, `web.bearer_token`) returning views,
  and correlation IDs (`web.request_id`) with a tested trust policy.
- One log line per request (`web.logger`) and a typed framework-error
  observer (`web.observe`) — each costs zero bytes in an application that
  does not use it, proven by `nm` in the gate.
- Path and query extractors that respond with a standardized `400` on bad
  input, so handlers only check a bool and return.
- JSON request bodies (`web.body`) with a fixed 4 MiB cap, decoded into a
  value you own.
- JSON, text and no-content responses, and the five error responders.
- Standardized error envelopes, including the automatic `404` and the `405`
  with an exact `Allow` header.
- Middleware: `web.use` and `web.next`, an onion that unwinds in exact reverse
  order and allocates nothing through the chain. Registration order is
  *enforced*, not documented — `use` after a route rejects the whole
  application and `serve` refuses to bind.
- Detached route collections: `web.router`, `web.mount`, and per-router
  middleware scope.
- Request header lookup (`web.header`) and a strict RFC 6750
  `web.bearer_token`.
- Framework-failure observability: `web.observe` with a typed
  `Framework_Event`, emitted exactly once per failure, identically on both
  transports.
- Two opt-in middlewares: `web.logger` and `web.request_id`.
- In-memory testing with `web.test_request` — real routing, no socket.
- HTTP/1 conformance: ambiguous or malformed framing is rejected and the
  connection closed, proven by a raw-wire corpus (see
  `docs/transport-conformance.md`).

**Public surface:** 44 application symbols + 2 test-support symbols = 46 —
frozen. The gate compares the compiler's own exported inventory, down to every
struct field, enum member and enum backing type, against
`build/phase1-public-signatures.txt`, and the direct import set against
`build/phase1-direct-dependencies.txt`. Changing any of it now requires a spec
amendment, not a snapshot refresh.

**Phase 2 froze more than the API.** It added three ledgers the symbol count
cannot express, and the gate enforces all three: a **claim ledger**, where every
guarantee the documentation makes carries a positive test, a negative control
and a stated non-guarantee; a **lifetime ledger**, which answers who owns each
value and until when; and a **capacity ledger**, which forbids the word
"bounded" anywhere a perimeter is not named — including for the limits this
framework does *not* impose.

Internals stay replaceable: the linear route table, the request arena and the
vendored backend are implementation, and may be rewritten as long as the
observable contracts hold.

**Not yet, and named honestly**

- Typed application state — Phase 3.
- Configurable limits and read/write timeouts — Phase 3.
- Graceful shutdown with a deadline — Phase 4.

**Never, and named just as honestly**

- Panic recovery. Odin has no recoverable panic, so a faulting handler aborts
  the process and Uruquim expects to run under a supervisor (ADR-020). The
  guarantee it *does* make is narrower and real: a handler that commits no
  response is finalized to a standardized 500, identically in tests and over a
  socket. `docs/errors.md` documents both halves.
- A closure-based `web.group`, now or in any future phase. Refused rather than
  deferred (ADR-024): a closure cannot be returned from a procedure in Odin,
  and `web.Router` plus `web.mount` do the job with visible ownership.

What exists today is usable for building and testing a JSON API, and
`web.serve` is a working bootstrap server. It is not hardened for unattended
production exposure — that is Phase 4's job, and the honest gap is named above
rather than implied. A frozen contract is not a released one: the semantic
version, the tag and any release remain the owner's decision.

Phase 3 — performance core, configurable limits and typed application state —
is planned in [`planning/phase-3-plan.md`](planning/phase-3-plan.md) and has
not started.

## Supported platform and toolchain

Stated honestly rather than implied:

- **Tested: Linux x86-64 only.** macOS, Windows and other architectures are
  **untested** today — they may work, and nobody has proven it.
- **The toolchain pin is part of the contract.** Odin ships monthly `dev-`
  releases with breaking changes and no package manager, so Uruquim pins one
  release, one commit and one asset checksum in
  [`odin-version.txt`](odin-version.txt), and the gate refuses any other
  compiler. Re-pinning is a deliberate, recorded change — not an upgrade that
  happens to you.
- **Consumption is by vendoring or a git submodule** at a pinned commit — the
  ecosystem's own convention, since Odin will never officially support a
  package manager.

The mandatory gate (`build/check.sh`) runs on the pinned toolchain and is the
single source of truth for what "passing" means in this repository.

## Where to start

- **`docs/quick-start.md`** — from nothing to a running API.
- **`examples/01-hello-world`** — the smallest complete program.
- **`examples/02-json-api`** — a CRUD-shaped JSON API.
- **`examples/03-route-params`** — path params and query extractors.
- **`examples/04-middleware`** — the onion model, short-circuits and `next`.
- **`examples/05-route-groups`** — `Router`, `mount` and shared prefixes.
- **`examples/06-authentication`** — the canonical auth pattern, with its
  revalidation cost stated instead of hidden.

All six examples compile in the mandatory gate.

## Licence, security and contributing

Uruquim is [MIT licensed](LICENSE).

It parses HTTP from untrusted clients, so it has a real attack surface. If you
find a security problem, please report it privately — [`SECURITY.md`](SECURITY.md)
explains how, and lists what is a documented limitation rather than a
vulnerability.

[`CONTRIBUTING.md`](CONTRIBUTING.md) explains the two things that surprise
people: the public API is frozen and the build enforces it, and growing it
requires measured evidence rather than agreement.

Notable changes are recorded in [`CHANGELOG.md`](CHANGELOG.md). There has been
no release: no tag exists, and cutting one is the owner's decision. What happens
next is planned in [`planning/roadmap.md`](planning/roadmap.md).

**Consuming Uruquim.** Odin has no package manager
[by design](https://odin-lang.org/docs/faq/), so vendor the `web/` directory or
add this repository as a submodule, and build with `-collection:uruquim=<path>`.
The Odin toolchain version is part of the contract — the pinned release, commit
and asset checksum are in `odin-version.txt`.

GitHub Actions is not required: a tracked pre-push hook runs the mandatory
gate, and the project VPS repeats it from a clean commit on an enabled systemd
timer. Current work-package status lives in `planning/phase-1-plan.md`.
