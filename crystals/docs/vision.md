# Vision — what a day should feel like

**Status: ASPIRATION.** Every code sample below is illustrative. Names are
placeholders, several APIs do not exist, and the ones marked **(Phase 3)** are
reserved in the core's documentation but unavailable today. Nothing here is a
promise.

The point of writing it out is that "productive" is not a design constraint
until you can see the code it produces. A vision you cannot read as a program is
a mood.

---

## The shape of the whole thing

```text
Uruquim core            small, frozen, measured, gate-enforced
    ↓ (one-way)
Crystals                optional packages and tools
    ↓
Druses                  tested combinations — documentation, no code
    ↓
Tooling                 out-of-process, never required to build or run
```

The property to preserve at every layer: **you can delete a layer and the ones
above it stop existing, but the ones below it do not notice.**

---

## Starting a project

Manual, and it stays possible:

```bash
mkdir my-api && cd my-api && git init
git submodule add <uruquim>  vendor/uruquim
git submodule add <crystals> vendor/crystals
```

A generator may exist later. If it does, it emits something small enough to read
in a few minutes:

```text
my-api/
├── cmd/api/main.odin
├── internal/
├── migrations/
├── tests/
├── vendor/{uruquim,crystals}
└── odin-version.txt
```

Not a directory tree that takes a tutorial to explain.

## Developing

```bash
odin run ./tools/dev -collection:crystals=./vendor/crystals
```

Watch, rebuild with the *real* build command, keep the old process on failure,
restart on success, show the compiler's own errors with nothing wrapped around
them. The server binary is unchanged and contains no development code, because
the watcher is a different program.

Honest today: a restart cuts in-flight requests with no deadline, because the
core has no graceful shutdown before Phase 4.

## Adding a database

```odin
App_State :: struct {
    db:     pg.Pool,
    config: Config,
}

main :: proc() {
    config, config_ok := config_load()
    if !config_ok { return }

    state: App_State
    if !pg.open(&state.db, config.database) { return }
    defer pg.close(&state.db)

    app := web.app_with_state(&state)      // (Phase 3)
    defer web.destroy(&app)

    web.use(&app, web.request_id)
    web.use(&app, web.logger)

    health := health.routes()
    defer web.destroy(&health)
    web.mount(&app, "/health", &health)

    web.get(&app, "/users/:id", get_user)

    web.serve(&app, config.port)
}
```

Read that top to bottom and you know: what the application owns, when it is
created, when it is destroyed, what middleware runs and in what order, what is
mounted where, and what port it listens on. Nothing was configured by an
environment variable a package read behind your back. Nothing registered itself.

The `defer` order is doing real work: `web.destroy(&app)` runs before
`pg.close(&state.db)`, so the App stops using the pool before the pool closes.
That is Odin's ordinary LIFO, not a framework feature — which is exactly the
point.

## Writing a handler

```odin
get_user :: proc(ctx: ^web.Context) {
    id, ok := web.path_int(ctx, "id")
    if !ok {
        return
    }

    state := web.state(ctx, App_State)      // (Phase 3)

    user, err := users.find(&state.db, id)
    switch err {
    case .None:
    case .Not_Found:
        web.not_found(ctx, "user")
        return
    case:
        web.internal_error(ctx)
        return
    }

    web.ok(ctx, user)
}
```

Three things about this, all deliberate:

* It is the **same handler shape as a Crystal-free program**. The ecosystem
  changed one line — where `state` comes from — and nothing else.
* The **error mapping is in the application**, visible and editable. When someone
  eventually needs `409` for one specific constraint, they change a line instead
  of fighting a Crystal that decided the status for them.
* A reader needs to know Odin, Uruquim, and the one Crystal named on the line
  they are looking at. Not the whole ecosystem.

## Querying

The layering that keeps a query builder from becoming an ORM by accident:

```text
Layer 1  driver      connect, exec, query, transaction, rows, typed errors
Layer 2  builder     SQL text + ordered bindings. No connection, no HTTP.
Layer 3  mapper      row → struct, struct → parameters
Layer 4  conventions CRUD, pagination, timestamps — optional, on top
```

Each layer is usable without the ones above it, and the explicit path stays
available at every level. An ORM, if one is ever wanted, is built *on* these and
does not fuse them — because the day someone needs a query the ORM cannot
express, the layers underneath must still be there.

## Testing

```odin
res := web.test_request(&app, .GET, "/users/42")
```

Real routing, no socket, no port. Crystals that touch HTTP work here too, and a
Crystal whose functionality genuinely needs a socket should say so rather than
pretending.

Database Crystals bring their own tools — a transaction rolled back per test, a
disposable test database, fixtures. What they must not bring is a global "test
mode" that silently changes semantics, because then the thing under test is not
the thing that ships.

## Deploying

```text
build binary → copy → run migrations → start process → supervisor watches it
```

An Odin executable. No ecosystem runtime, no sidecar, no metadata server, no
dependency download at startup. Migrations are a deploy step, not a boot step,
so progressive deploys stay safe.

---

## The line that decides everything

> A helper may remove **mechanical steps**. It may not remove a **decision**.

Fine:

```odin
db, ok := pg.open(config)         // saves you a dozen lines of setup
web.use(&app, secure.headers)     // one visible call, you chose the order
```

Not fine:

```odin
import "crystals:postgres"        // …and this reads env vars, opens a global
                                  //    pool, registers teardown, runs migrations
security.install_defaults(&app)   // …and "defaults" is four policies whose
                                  //    order and content you cannot see
```

Both of the second pair are *convenient*. Both hide a decision someone will
eventually need to make differently, and the hiding is what makes them expensive
— not at the moment they are written, but at the moment they are wrong.

---

## What success looks like, and what failure looks like

**Success:** a developer writes a Postgres-backed JSON API with migrations,
validation and reload-on-save, and the resulting `main` is still a procedure you
can read in one screen. The framework's properties — measured hot path, explicit
ownership, no magic — are unchanged, because nothing in the ecosystem was
permitted to change them.

**Failure, and it has a recognisable shape:** the ecosystem grows a convenience
layer, the convenience layer needs a core hook, the core grows the hook "just
this once", and eighteen months later Uruquim has an extension surface it spent
two phases refusing. Every rule in [`crystal-contract.md`](crystal-contract.md)
exists to make one specific step of that sequence impossible.
