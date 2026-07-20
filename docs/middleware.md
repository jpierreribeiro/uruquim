# Middleware

Middleware arrived in Phase 2 (WP17): `web.use` registers it, `web.next` runs
the rest of the chain. A middleware is an **ordinary handler** — the frozen
`proc(ctx: ^web.Context)` shape. There is no `Middleware` type, no
configuration object, and no second registration form.

## Ordering is a security boundary — register `use` first

Every `web.use` must come before the first route registration. This is
**enforced, not advised**: `use` after any `get`/`post`/`put`/`patch`/`delete`
— or after the first dispatched request — rejects the whole application
fail-closed. Every request then answers `500`, `web.serve` refuses to start,
and a diagnostic naming the first unprotectable pattern is logged.

The rule exists because the alternative was measured. A prototype allowed this
program, which reads as "my admin routes and my auth middleware" and looks
correct:

<!-- pseudocode: the rejected mis-ordered shape -->
```odin
web.get(&app, "/admin/users", admin_users) // looks protected. WAS NOT.
web.use(&app, require_auth)
web.get(&app, "/admin/keys", admin_keys)   // was protected.
```

`/admin/users` served its response — an authentication bypass with no error,
no warning, and no runtime symptom, produced by moving one line. A rule
enforced only by a paragraph is not enforced, so the framework refuses the
program instead.

The canonical shape:

<!-- fragment: phase2/middleware-use -->
```odin
app := web.app()
defer web.destroy(&app)

web.use(&app, require_auth) // before any route — the order is enforced
web.get(&app, "/admin/users", list_users)

web.serve(&app, 8080)
```

## Writing middleware

Call `web.next(ctx)` to run the rest of the chain — later middleware, then the
route handler. Return **without** calling `next` to short-circuit: nothing
downstream runs, and your response is what the client receives.

<!-- fragment: phase2/bearer-auth -->
```odin
require_auth :: proc(ctx: ^web.Context) {
	token, ok := web.bearer_token(ctx)
	if !ok || !token_is_valid(token) {
		web.unauthorized(ctx, "authentication required")
		return
	}
	web.next(ctx)
}
```

(`web.bearer_token` rejects a sloppy `Authorization` — wrong scheme, doubled
or trailing whitespace — rather than repairing it, and the token is never
logged: header values are attacker-controlled.)

## Execution order

Middleware run in `use` order and unwind in exactly the reverse order — the
chain is an onion:

```text
use(A); use(B); use(C); get("/x", H)   =>   A > B > C > H < C < B < A
```

Code after `next` runs as your frame resumes, which is what makes timing and
"log the status we actually sent" possible:

<!-- fragment: phase2/middleware-unwind -->
```odin
observe_outcome :: proc(ctx: ^web.Context) {
	web.next(ctx)
	// the request is fully answered here
}
```

Rules you can rely on, each pinned by a test:

- **After `next` returns, the response is committed.** A response attempt from
  unwind code is rejected by the single-commit guard and the first response
  survives byte-identically. Read on the way out; never write.
- **A second `next()` call is a silent no-op.** The handler runs exactly once.
- **`next()` from a route handler is a no-op** — the chain is exhausted.
- **A middleware that neither calls `next` nor responds** leaves the response
  uncommitted; the driver answers the standard `500`, exactly as it does for a
  handler that forgot to respond.

## Misses are observed

App-level middleware run on **every** dispatch, including a `404` (no route)
and a `405` (path known under another method). The automatic envelope and the
`Allow` header are unchanged; your middleware simply sees the request enter
and unwind. Once audit or rate-limit middleware exist, "misses are invisible"
is exactly the hole an attacker probes — so they are not invisible.

`web.bare()` keeps the same observation mechanism with no response policy: on
a miss the chain runs, nothing is committed, and the driver's `500`
finalization applies, as always under `bare()`.

## Costs, stated plainly

- Dispatch through a middleware chain allocates **zero** bytes; chains are
  flattened once, at registration.
- The machinery present but unused costs **+2,424 bytes** of binary in a
  default build, **+1,488** with `-o:speed` (measured on the hello-world
  example against the Phase-1 baseline; a program that never calls `use` does
  not even link it).
- The chain runs by recursion: each middleware holds a stack frame while the
  rest runs (~80 bytes each in a debug build, ~16 with `-o:speed`). The
  practical depth bound is around one hundred thousand on the default stack —
  and **exceeding it is a segfault, not a diagnostic**. A realistic
  application registers fewer than twenty.

## What does not exist

- **No route-level middleware parameters.** The five registration signatures
  are frozen (ADR-025, option B); a route needing its own guard is a
  ONE-ROUTE `Router` mounted at the path — `use` on the router, then the one
  route, then `mount`. Router-level middleware follow every rule on this
  page, nested inside the app's globals (outermost first).
- **No recovery middleware, ever.** Odin has no recoverable panic; a faulting
  handler aborts the process (ADR-020). Run under a supervisor.
- **No built-in catalog yet.** The logging and request-ID middleware are later
  Phase-2 work packages.
