// Experiment 01 — api-shape
// Question: can `app := web.app()` return an App by value, be passed by
// pointer to route registration and serve, without accidental copies, and
// with a stable address for the duration of use?
//
// THROWAWAY. Not imported by any product package. Compile-ratification only.
package api_shape

import "core:fmt"

// --- candidate public shapes (stubs; no HTTP behavior) ---

Handler :: proc(ctx: ^Context)

Context :: struct {
	// plain, non-parametric (canonical). fields trimmed to what the shape test needs.
	app_ptr: rawptr,
	marker:  int,
}

Route :: struct {
	method:  string,
	path:    string,
	handler: Handler,
}

App :: struct {
	routes:      [dynamic]Route,
	self_addr:   uintptr, // recorded at app() to detect later copies
	destroyed:   bool,
}

app :: proc() -> App {
	a: App
	a.routes = make([dynamic]Route)
	a.self_addr = uintptr(rawptr(&a)) // NOTE: address of local; see README caveat
	return a
}

destroy :: proc(a: ^App) {
	delete(a.routes)
	a.destroyed = true
}

register :: proc(a: ^App, method, path: string, h: Handler) {
	append(&a.routes, Route{method, path, h})
}

get  :: proc(a: ^App, path: string, h: Handler) { register(a, "GET", path, h) }
post :: proc(a: ^App, path: string, h: Handler) { register(a, "POST", path, h) }

// serve stub — records the address it actually receives.
serve :: proc(a: ^App, port: int) {
	fmt.printfln("[serve] port=%d routes=%d app_addr=%p", port, len(a.routes), a)
}

// --- alternative: explicit init form (Advanced API comparison) ---
app_init :: proc(a: ^App) {
	a.routes = make([dynamic]Route)
	a.self_addr = uintptr(rawptr(a))
}

// --- demonstration handler ---
ping :: proc(ctx: ^Context) { ctx.marker = 1 }

main :: proc() {
	// Canonical form: value return, then take address once.
	app_val := app()
	defer destroy(&app_val)

	get(&app_val, "/ping", ping)
	post(&app_val, "/users", ping)

	// The address we operate on is &app_val (the caller's storage), which is
	// stable for the rest of main. app()'s internal self_addr recorded the
	// *returned-from* local and is expected to differ — that is the point the
	// README discusses (do not rely on addresses captured before return).
	fmt.printfln("caller app addr = %p ; app.self_addr(recorded in app()) = %x",
		&app_val, app_val.self_addr)
	serve(&app_val, 8080)

	// Advanced form for comparison: caller owns storage from the start.
	app2: App
	app_init(&app2)
	defer destroy(&app2)
	get(&app2, "/health", ping)
	serve(&app2, 8081)
}
