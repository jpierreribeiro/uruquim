// Uruquim example 07 — typed application state.
//
// A real service has things it needs everywhere and creates once: a database
// pool, a configuration struct, a template cache. `web.app_with_state` attaches
// exactly one such value to the application, and `web.state` reads it back
// TYPED inside any handler or middleware.
//
//	app := web.app_with_state(&state)     // once, in main
//	s := web.state(ctx, App_State)        // anywhere, typed
//
// THE CALL SITE HAS NO TYPE ARGUMENTS ON THE HANDLER. That is the whole reason
// this shape was chosen (ADR-004 option A): the alternative was a parametric
// `App(S)`/`Context(S)`, which would put a type parameter on every handler
// signature in your program. The price is that a wrong type is caught at
// RUNTIME by an assert rather than by the compiler — and that assert aborts,
// which is the framework's documented fault model. You will meet it on your
// first request, not in production.
//
// THE POINTER IS YOURS. The App stores the address, not a copy: a handler
// writing through it mutates the value you created, which is what makes a
// connection pool work and a copy would break. The value must OUTLIVE the App
// — put it in `main`, next to the App, exactly as below. A pointer to a local
// in a procedure that has already returned is a dangling pointer, and no assert
// can catch that: the type is still right and the memory is still mapped.
//
// WHAT THIS IS NOT: per-request storage. There is none, and there is not going
// to be one — ADR-028 decided that question and closed it. `ctx` is not an
// extension bag; a value a middleware computes for a handler is passed down by
// calling a procedure, or recomputed. That cost is permanent until an ADR says
// otherwise.
//
// Run it from the repository root:
//
//	odin run examples/07-app-state -collection:uruquim=.
//
// Try it:
//
//	curl http://localhost:8080/config          -> the greeting, from state
//	curl -X POST http://localhost:8080/visit   -> 204, and the counter moves
//	curl http://localhost:8080/stats           -> the counter, shared by both
package main

import web "uruquim:web"

// The one value every handler needs. An ordinary struct: the framework does not
// require an interface, a registration macro or a particular field.
App_State :: struct {
	greeting: string,
	visits:   int,
}

Greeting :: struct {
	greeting: string `json:"greeting"`,
}

Stats :: struct {
	visits: int `json:"visits"`,
}

main :: proc() {
	// Created BEFORE the App and living for as long as it does. This is the
	// lifetime rule in one line of layout: both are locals of `main`, and
	// `main` outlives every request.
	state := App_State {
		greeting = "hello from application state",
	}

	// `app_with_state` is `app()` with a value attached: the same automatic 404
	// and 405, the same everything else. A nil pointer here would reject the
	// application fail-closed rather than abort inside the first request.
	app := web.app_with_state(&state)
	defer web.destroy(&app)

	web.get(&app, "/config", show_greeting)
	web.post(&app, "/visit", record_visit)
	web.get(&app, "/stats", show_stats)

	web.serve(&app, 8080)
}

// Reading. `web.state(ctx, App_State)` returns a `^App_State` — the type you
// named, not a `rawptr` you have to cast and hope about.
show_greeting :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	web.ok(ctx, Greeting{greeting = s.greeting})
}

// Writing. The pointer is the one `main` created, so this increments the
// caller's own counter and every later request sees it.
//
// One honest caveat, stated because the capacity ledger requires costs to be
// named rather than discovered: this is a plain `+= 1` with no lock. That is
// correct under the framework's current model — one server per process, one
// event loop — and it is the same assumption the request-ID counter is
// documented under. Concurrency is Phase 4's, and it owns this line with it.
record_visit :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	s.visits += 1
	web.no_content(ctx)
}

show_stats :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	web.ok(ctx, Stats{visits = s.visits})
}
