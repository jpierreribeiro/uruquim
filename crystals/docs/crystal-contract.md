# The Crystal contract

**Status: PROPOSED, first draft.** This is the half of the idea that has
consequences, so it is written precisely — but precision is not the same as
being settled. Every rule below states *why* it exists, and a rule whose reason
you can refute is a rule that should change.

Most of this is not new policy. Four of the core's accepted guardrails already
say most of it for application code, and a Crystal is application code that
happens to be reusable. Where this document adds something, it is marked
**[new]**.

---

## 0. The one rule everything else follows from

```text
Application
 ├── imports uruquim:web
 ├── imports Crystal A
 └── imports Crystal B

Crystal ────────> uruquim:web        (allowed, public symbols only)
uruquim:web ──X──> Crystal           (never)
```

Uruquim never imports, discovers, enumerates, loads or initialises a Crystal.
There is no registry, no interface, no `map[string]any`, no plugin ABI, no
directory the core walks.

This is not a new decision. `build/phase1-direct-dependencies.txt` pins
`package web`'s direct imports at exactly five and the freeze gate fails if the
set changes. The mechanism to enforce the arrow already exists and already runs.

**Consequence worth stating:** a Crystal can be deleted from a project by
deleting an import and the calls that use it. If removing a Crystal requires
touching anything else, that Crystal violated this rule somewhere.

---

## 1. Categories, derived rather than listed

Two questions decide everything about a Crystal's obligations. Ask them in
order.

**Q1 — Is it in the server process at all?**

If no, it is a **Tool Crystal**: a separate executable. A watcher, a migration
runner, a doctor. Its blast radius on a running server is *none*, because it is
not in it. Tools have the lightest obligations in this document and should be
preferred whenever the job can be done out of process.

**Q2 — For in-process Crystals: does it import `uruquim:web`, and does it own
memory that outlives a request?**

|  | **does not import `web`** | **imports `web`** |
|---|---|---|
| **owns nothing app-lived** | **Library** — pure computation. A query builder, a validator, a hashing routine. | **Request** — a `Handler` or an extractor. Touches `^Context` during a request and nothing else. |
| **owns an app-lived resource** | **Service** — a pool, a client, a sink. Created and destroyed by the application. | **Route** — produces routes and their middleware for the application to mount. |

Five categories, and none of them is a special case of the framework. They are
the four combinations of two independent properties, plus the out-of-process
degenerate case.

**A Crystal that would land in two boxes is two Crystals.** A Postgres pool
that also answers HTTP is a Service Crystal and a Request Crystal, and G-02
already requires the split:

> **G-02** — Domain services, repositories, and business rules must not import
> `uruquim:web` or accept framework request/response/context types.

So `crystals:db/postgres` knows nothing about HTTP, and `crystals:web/postgres`
— if it ever needs to exist — is the thin adapter where the two vocabularies
meet. That boundary is the project's, not this document's.

---

## 2. Coupling to `web.Context`

A Request Crystal may accept `^web.Context`. It may read the request through
public extractors, produce a response through public responders, be used as a
`web.Handler`, and call `web.next` if it is middleware.

**It reads `ctx.private` never.** The `Context` has a public field named
`private` whose type is package-private, so application code cannot name the
type but can still reach the fields. The core is explicit that this is
encapsulation *by contract* and not a compiler guarantee (`web/context.odin`,
ADR-008). A Crystal that reaches into it is not exploiting a loophole; it is
depending on internals the core reserves the right to replace wholesale — the
route table, the arena and the vendored backend are all named as replaceable in
the README.

There is also no `ctx` → `App` backpointer, deliberately (`web/context.odin`,
WP4 D3). A Request Crystal therefore cannot reach the application from a
request, and should not try to route around that.

### Lifetime — the rule a Crystal is most likely to break

**G-05**, verbatim:

> Request-derived strings, slices, headers, params, query, and body are
> temporary views unless explicitly copied with an appropriate allocator.
> Background work must receive owned application data, never capture `ctx` or
> request views.

Everything the request gives you is borrowed: path, query, headers, params,
body, bearer token, and every string decoded into the request arena. None of it
survives the request. A Crystal that stores any of it, or hands it to anything
asynchronous, has a use-after-free that will not reproduce under light load.

**The one documented exception** is the matched route pattern
(`Framework_Event.route`), which is App-owned and valid until `destroy` — the
lifetime ledger in `planning/phase-2-freeze.md` records it as the one string an
observer may keep by value.

**[new]** A Crystal that returns request-derived data to the application must
say, in its signature's doc comment, whether the result is a view or a copy.
"The caller owns it" and "this dies with the request" are both fine answers.
Silence is not.

---

## 3. Coupling to `web.App` — and the composition-order hazard

This is the part the ecosystem is most likely to get wrong, because the
dangerous version looks convenient.

### The mechanism

`web.use` is rejected after **any** registered route, after any `mount`, and
after the first dispatch. Rejection is not a no-op — it **poisons the whole
application**: `serve` refuses to bind, and every request on the dispatch path
answers a standardized 500 (`web/middleware.odin`, `web/serve.odin`, ADR-019).
Fail-closed, by design, so both transports reject identically.

### Why that makes a generic `install()` unsafe, not merely unclear

Consider the shape every ecosystem eventually invents:

```odin
// The dangerous version.
health.install(&app)
telemetry.install(&app)
security.install(&app)
```

`security.install` wants to add middleware. `health.install` registers a route.
If they run in that order, the application is poisoned and the server refuses to
start — and the developer's diagnosis is "the health Crystal broke the security
Crystal", which is not what happened.

The problem is not that `install()` hides what it does. The problem is that
**`install()` cannot know whether it is still allowed to call `use`**, because
that depends on what every other Crystal did first. A procedure whose
correctness depends on invisible global ordering is a procedure that will be
called in the wrong order.

### The proposed answer: a Route Crystal returns a `Router`, it does not mutate the `App`

`web.Router` embeds an `App` (`Router :: struct { using app: App }`), which
means `web.use`, `web.get` and the rest accept `&router` unchanged, and a
Router has **its own middleware scope**. `web.mount` then *copies* the router's
routes and chains into the application, and closes the router.

So a Route Crystal builds a detached Router and hands it back:

```odin
// The Crystal. It never sees the application.
routes :: proc() -> web.Router {
    r := web.router()
    web.use(&r, require_api_key)     // this Crystal's own middleware scope
    web.get(&r, "/health", handle_health)
    web.get(&r, "/health/ready", handle_ready)
    return r
}
```

```odin
// The application decides the prefix and the moment.
h := health.routes()
defer web.destroy(&h)
web.mount(&app, "/health", &h)
```

Three properties fall out of this, and they are why it is the recommended
shape rather than merely a permitted one:

* **The Crystal cannot poison the application's ordering**, because it never
  touches the application. It only ever mis-orders *itself*, and a poisoned
  Router is rejected at `mount` with its own diagnostic.
* **The Crystal gets middleware scoping for free.** Its `use` applies to its
  routes and nothing else — no global middleware added on its behalf.
* **Ownership is unambiguous.** `mount` copies, so App and Router are two
  owners, each destroyed exactly once, in either order
  (`web/router.odin`, OWNERSHIP).

**The application still owns the order**, and one rule survives for it:
**every `web.use(&app, …)` comes before every registration and every `mount`.**
That is the core's rule, not the ecosystem's, and no Crystal can remove it.

### Naming, when a Crystal must touch the App anyway

Sometimes a Crystal genuinely has one thing to contribute and returning a
Router would be theatre — a single stateless middleware, say. Then export the
value and let the application install it:

```odin
web.use(&app, secure.headers)             // yes — one visible call, app decides order
web.observe(&app, telemetry.observer)     // yes — see §4
```

```odin
secure.install_defaults(&app)             // no — what did it add, and where?
```

The distinction, from [`style.md`](style.md) §7: a helper may remove
*mechanical steps*; it may not remove a *decision*.

---

## 4. Observability — the ecosystem's first real conflict

`web.observe` stores **one** procedure pointer and a second call replaces the
first, silently (`web/observer.odin`). Two Crystals that both call it means one
of them stops working and nothing says so. For an observability feature, silent
loss is the worst available failure.

**Proposed rule: no Crystal calls `web.observe`.** A Crystal that wants
framework events exports an observer procedure; the application installs one
observer and fans out itself.

```odin
web.observe(&app, application_observer)

application_observer :: proc(event: web.Framework_Event) {
    metrics.record(event)
    tracing.record(event)
}
```

Six lines, in the application, visible. The alternative — a fan-out Crystal
owning an array of observers — is real and is written up in
[`ideas.md`](ideas.md), but it adds a concept and state to solve a problem the
application solves with a procedure.

Two facts a Crystal's observer must respect: a 404 is *not* a framework failure
and emits no event (`tests/wp20-public-surface`), and an observer cannot change
the response — the framework has already committed by the time it runs.

---

## 5. Prohibitions, with the reason attached

A prohibition without a mechanism is a preference. Each of these has one.

### Imports and internals

| A Crystal must not | Because |
|---|---|
| import `uruquim:web/internal/*` | that is the transport boundary and adapter; the README names the vendored backend as replaceable |
| import the vendored transport directly | same, and it would put a backend name in a public signature (**G-06**) |
| read or write `ctx.private` / `app.private` | encapsulation by contract; the route table, arena and backend may be rewritten as long as observable contracts hold |
| reinterpret framework memory through `rawptr` | the idiom guide sanctions exactly one `rawptr`, and it is the core's own future `web.state` |
| retain `^web.App` after composition | the App is not copyable and its internals are lazy; holding a pointer invites use after `destroy` |
| key a global registry by App address | that is a plugin registry with extra steps, and it breaks the moment a process has two Apps |

### Lifetime and memory

| A Crystal must not | Because |
|---|---|
| retain a `^Context` or any request view | **G-05**; the arena is released at request end |
| hand out a slice whose owner is unstated | the core answers this in one place (`docs/canonical-patterns.md` ownership table); a Crystal must too |
| allocate at `init` with one allocator and free at `destroy` with another | the idiom guide requires paired init/destroy per lifetime |
| store `context.temp_allocator` data in anything that outlives the call | explicitly forbidden by the idiom guide |
| swap `context.allocator` around `web.next` to observe downstream allocations | it would silently change the allocator for the rest of the chain and for the core itself |
| start background work holding borrowed request data | **G-05**, second sentence |

### Hot path

A Request Crystal must not silently introduce, per request: a map, heavy
reflection, filesystem access, environment reads, dynamic library loading, a
global mutex, an unbounded queue, unbounded retries, configuration parsing, or a
blocking call to an external exporter.

The core's rule is that work which can be done at registration is done at
registration. Configuration is read and validated at `init`; what reaches the
hot path is a prepared value.

### Composition

A Crystal must not call `web.serve`, call `web.destroy` on the application's
App, create the App on the application's behalf, or register anything as a side
effect of being imported. Anything that owns the server owns the program.

---

## 6. What a Crystal must declare

Not a form to fill in — a set of questions whose answers are load-bearing, and
which the author is the only person who can answer.

**Ownership.** For every value the Crystal hands out or takes in: who creates
it, who owns it, how long it is valid, who destroys it, whether it may be
copied, whether it may escape.

**Capacity.** For every bound: the number, and **what happens when it is
reached** — block, reject, drop, replace, or grow. The core's capacity ledger
exists because "bounded" without that second half is not a claim.

**Threading.** Whether its types may be shared across threads, whether `init`
must complete before concurrency starts, what happens under simultaneous use.
`web.serve` blocks and promises nothing about threads; a Crystal cannot inherit
a guarantee that was never made.

**Failure.** Its own typed error enum, in its own domain vocabulary. A database
Crystal returns `Not_Found`; the application decides whether that is a 404. A
Crystal that answers HTTP for a domain failure has taken a decision that was not
its to take — and the first time someone needs `409` instead of `400` for one
constraint, they will have to fight it.

**Cost.** Anything the Crystal claims about binary size or allocations, and how
it was measured. This is harder than it looks and has its own document:
[`gate.md`](gate.md) §The optionality trap.

---

## 7. What this contract does not yet answer

* **Stateful middleware before `web.state` exists.** Odin has no capturing
  closures, so a `Handler` cannot carry configuration. Until WP37 lands,
  the only honest options are package-global state — which breaks multiple Apps
  and isolated tests — or the application writing a four-line adapter. The
  contract does not bless the global. See [`open-questions.md`](open-questions.md) Q-1.
* **Whether the Router-returning shape survives Phase 3**, which rewrites the
  route representation (WP28/WP29). The *public* contract of `mount` should
  hold; the recommendation rests on that and would need re-checking at the
  Phase-3 freeze.
* **Versioning.** No Crystal can declare compatibility with an Uruquim
  *version*, because there is no tag and no release. Compatibility is stated
  against a commit. See [`distribution.md`](distribution.md).
