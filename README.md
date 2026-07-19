# Uruquim

An Odin microframework for real-world JSON APIs.

**Simple by default, explicit when needed, data-oriented underneath.**

**Positioning:** internally data-oriented and allocator-aware; externally simple,
productive, and predictable — for humans and for AI coding agents. No code
generator, no mandatory CLI, no heavy metaprogramming: ergonomics come from
extractors and canonical helpers.

*A web framework for the Joy of Programming.*

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
├── errors.md               The error envelope and every Phase-1 code
└── transport-conformance.md  How transports are proven correct

examples/                Compiling Phase-1 programs (built by the gate)
├── 01-hello-world/
├── 02-json-api/
└── 03-route-params/
```

## Status

Phase 1 is complete: WP0 through WP11 are done, and the public surface is
frozen by an executable gate. The freeze manifest and its per-symbol
evidence live in `planning/phase-1-freeze.md`; the gate that enforces it is
`build/check_phase1_freeze.sh`, run as the final step of `build/check.sh`.

**What works today**

- A real HTTP server: `web.serve(&app, port)` binds a port and answers.
- Routing with static and `:param` segments; static routes win over
  parametric ones.
- Path and query extractors that respond with a standardized `400` on bad
  input, so handlers only check a bool and return.
- JSON request bodies (`web.body`) with a fixed 4 MiB cap, decoded into a
  value you own.
- JSON, text and no-content responses, and the five error responders.
- Standardized error envelopes, including the automatic `404` and the `405`
  with an exact `Allow` header.
- In-memory testing with `web.test_request` — real routing, no socket.
- HTTP/1 conformance: ambiguous or malformed framing is rejected and the
  connection closed, proven by a raw-wire corpus (see
  `docs/transport-conformance.md`).

**Public surface:** 32 application symbols + 2 test-support symbols = 34. That
count is enforced by the build gate.

**Not yet, and named honestly**

- Middleware, route groups and typed application state — Phase 2 and Phase 3.
- Panic recovery — Phase 2.
- Configurable limits and read/write timeouts — Phase 3.
- Graceful shutdown with a deadline — Phase 4.
- Request header lookup — Phase 2.

Phase 1 is usable for building and testing a JSON API. It is not yet hardened
for unattended production exposure. Frozen means: the Phase-1 contracts are
protected by the gate and changing one now requires a spec amendment;
internals stay replaceable; a tag or release remains a separate human
decision by the owner.

## Where to start

- **`docs/quick-start.md`** — from nothing to a running API.
- **`examples/01-hello-world`** — the smallest complete program.
- **`examples/02-json-api`** — a CRUD-shaped JSON API.
- **`examples/03-route-params`** — path params and query extractors.

All three examples compile in the mandatory gate.

GitHub Actions is not required: a tracked pre-push hook runs the mandatory
gate, and the project VPS repeats it from a clean commit on an enabled systemd
timer. Current work-package status lives in `planning/phase-1-plan.md`.
