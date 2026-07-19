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
├── canonical-patterns.md   The one blessed way to do each common task
├── ai-context.md           Compact API reference for coding agents
└── ...                     Remaining docs are produced by their phases
```

## Status

Phase-1 Spec Gate: **READY** (2026-07-18). Production implementation has not
started. The knowledge base is the governing specification; implementation
now follows one approved work package at a time as defined in
`planning/05-phase-1-implementation-plan.md`.

WP0 is complete. GitHub Actions is not required: a tracked pre-push hook runs
the mandatory gate, and the project VPS repeats it from a clean commit on an
enabled systemd timer. WP1 is authorized by the gate but has not started.
