// WP10 — compilable fixtures for the documentation fragments.
//
// Every `<!-- fragment: phase1/... -->` block in an active document appears
// here as real, compiling code. A fragment is not a complete program, so it
// cannot be an `examples/` file; without this fixture it would be prose that
// nobody ever compiles — and prose drifts.
//
// The gate resolves each `fragment:` marker to a `fragment: <name>` comment in
// this directory, so a documented fragment with no fixture fails the build.
//
// This is an ordinary external consumer of `uruquim:web`: it uses only the
// public surface, exactly like an application.
package wp10_doc_fixtures

import "core:testing"
import web "uruquim:web"

User :: struct {
	id:   int    `json:"id"`,
	name: string `json:"name"`,
}

Create_User :: struct {
	name:  string `json:"name"`,
	email: string `json:"email"`,
}

// fragment: phase1/readme-taste
// The README's opening taste of the API: create, register, serve, and one
// handler that reads a path parameter and answers with JSON.
readme_taste :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/users/:id", get_user)

	web.serve(&app, 8080)
}

// fragment: phase1/path-int
// The canonical fallible-extractor shape: check `ok`, return on failure.
get_user :: proc(ctx: ^web.Context) {
	id, ok := web.path_int(ctx, "id")
	if !ok {
		return
	}

	web.ok(ctx, User{id = id, name = "Ada"})
}

// fragment: phase1/body
// The destination-filling extractor: it fills a value you own and returns bool.
create_user :: proc(ctx: ^web.Context) {
	input: Create_User
	if !web.body(ctx, &input) {
		return
	}

	web.created(ctx, User{id = 1, name = input.name})
}

// fragment: phase1/errors
// The error responders answer for you; the handler returns straight after.
deny :: proc(ctx: ^web.Context) {
	web.bad_request(ctx, "email is required")
}

// fragment: phase1/query
// `query` never responds by itself; `query_int_or` uses its default ONLY when
// the parameter is absent, and answers 400 when it is present but malformed.
search :: proc(ctx: ^web.Context) {
	q, found := web.query(ctx, "q")
	if !found {
		web.bad_request(ctx, "the 'q' parameter is required")
		return
	}

	limit, ok := web.query_int_or(ctx, "limit", 20)
	if !ok {
		return
	}

	web.ok(ctx, User{id = limit, name = q})
}

// fragment: phase1/routing
// Registration is one call per method. A static route wins over a parametric
// one regardless of the order they are registered in.
register :: proc(app: ^web.App) {
	web.get(app, "/users/me", ping)
	web.get(app, "/users/:id", get_user)
	web.post(app, "/users", create_user)
	web.put(app, "/users/:id", get_user)
	web.patch(app, "/users/:id", get_user)
	web.delete(app, "/users/:id", ping)
}

// fragment: phase1/app-lifecycle
// Create, register, serve. `destroy` runs exactly once, on the value `app()`
// returned.
run :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.get(&app, "/ping", ping)

	web.serve(&app, 8080)
}

// fragment: phase1/responses
// One helper per output kind. Payloads are passed BY VALUE.
respond_examples :: proc(ctx: ^web.Context) {
	web.ok(ctx, User{id = 1, name = "Ada"})
	web.created(ctx, User{id = 2, name = "Grace"})
	web.json(ctx, .Accepted, User{id = 3, name = "Queued"})
	web.text(ctx, .OK, "pong")
	web.no_content(ctx)
}

// fragment: phase1/copy-to-persist
// Request-derived strings are views valid only during the request. Copy
// explicitly, with an explicit allocator, to keep one.
keep_a_path :: proc(ctx: ^web.Context) -> string {
	name := web.path(ctx, "name")
	return clone_for_later(name)
}

@(private)
clone_for_later :: proc(s: string) -> string {
	out := make([]u8, len(s))
	copy(out, s)
	return string(out)
}

ping :: proc(ctx: ^web.Context) {
	web.text(ctx, .OK, "pong")
}

// fragment: phase1/test-request
// The in-memory driver: real routing, no socket. It takes a method and a path.
check_ping :: proc() -> bool {
	app := web.app()
	defer web.destroy(&app)
	web.get(&app, "/ping", ping)

	res := web.test_request(&app, .GET, "/ping")
	return res.status == .OK && res.body == "pong"
}

// fragment: phase2/middleware-use
// The canonical WP17 shape: every `use` BEFORE the first route. A middleware
// is an ordinary Handler that calls `web.next` to run the rest of the chain.
middleware_app :: proc() {
	app := web.app()
	defer web.destroy(&app)

	web.use(&app, require_auth) // before any route — the order is enforced
	web.get(&app, "/admin/users", list_users)

	web.serve(&app, 8080)
}

// fragment: phase2/middleware-guard
// A guard: respond and return WITHOUT calling next to short-circuit. The
// credential here is a query token only because header lookup is a later work
// package; the pattern is the point.
require_auth :: proc(ctx: ^web.Context) {
	token, found := web.query(ctx, "token")
	if !found || token != "expected" {
		web.unauthorized(ctx, "authentication required")
		return
	}
	web.next(ctx)
}

list_users :: proc(ctx: ^web.Context) {
	web.ok(ctx, []User{{id = 1, name = "Ada"}})
}

// fragment: phase2/middleware-unwind
// Code after `next` runs as the chain unwinds — the response is committed by
// then, so read, never write (a late response attempt is rejected and the
// first response survives).
observe_outcome :: proc(ctx: ^web.Context) {
	web.next(ctx)
	// the request is fully answered here
}

// The fixtures are compiled as a test package, so one live assertion keeps the
// runner honest about actually having built them.
@(test)
wp10_fixtures_compile_and_run :: proc(t: ^testing.T) {
	testing.expect(t, check_ping(), "the documented test_request fragment must work")

	app := web.app()
	defer web.destroy(&app)
	register(&app)

	// Static beats parametric, as the routing fragment claims.
	res := web.test_request(&app, .GET, "/users/me")
	testing.expect_value(t, res.status, web.Status.OK)
	testing.expect_value(t, res.body, "pong")
}
