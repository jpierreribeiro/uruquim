# Uruquim

An Odin microframework for real-world JSON APIs.

**Positioning:** internally data-oriented and allocator-aware; externally simple,
productive, and predictable — for humans and for AI coding agents.

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

The future Odin `core:net/http` (built on `core:nbio`) is the **canonical
transport backend**. Until it ships and stabilizes, Uruquim may run on
`laytan/odin-http` strictly behind an internal adapter. No public Uruquim API
exposes transport types, so migration requires no application changes.

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

Pre-implementation. The knowledge base is the governing specification; code
follows the phases defined in `knowledge-base/03-development-phases.md`.
