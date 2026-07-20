// WP37 public-surface contract — typed application state.
//
// TWO SYMBOLS, ledger 45 → 47: `app_with_state` builds the application around
// one value, `state` reads it back typed. ADR-004 option A, delivered — a
// `rawptr` plus a `typeid` privately, and an accessor that asserts before it
// casts.
//
// THE CALL SITE IS THE POINT. `web.state(ctx, App_State)` carries no generic
// noise, which is exactly what ADR-004 chose option A for: option B — a
// parametric `App(S)`/`Context(S)` — would put a type argument on every handler
// signature in the program. The price is a runtime assert instead of a compile
// error, and this suite is where that price is looked at rather than assumed.
//
// WHAT THIS IS NOT. There is no request-scoped state and there will not be one
// (ADR-028, option 1, ACCEPTED). This is ONE value, APP-scoped, set before
// serving. The auth example's revalidation cost is unaffected and nothing here
// promises to remove it.
package test_wp37_public

import "core:log"
import "core:strings"
import "core:testing"
import web "uruquim:web"

@(private = "file")
Quiet :: struct {
	inner: log.Logger,
}

@(private = "file")
quiet_logger_proc :: proc(
	data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	record := (^Quiet)(data)
	if level == .Error && strings.contains(text, "uruquim:") {
		return
	}
	if record.inner.procedure != nil {
		record.inner.procedure(record.inner.data, level, text, options, location)
	}
}

@(private = "file")
quiet_logger :: proc(record: ^Quiet) -> log.Logger {
	record.inner = context.logger
	return log.Logger {
		procedure = quiet_logger_proc,
		data = rawptr(record),
		lowest_level = .Debug,
		options = context.logger.options,
	}
}

@(private = "file")
App_State :: struct {
	name:  string,
	calls: int,
}

@(private = "file")
Other_State :: struct {
	n: int,
}

@(private = "file")
read_name :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	web.text(ctx, .OK, s.name)
}

@(private = "file")
bump :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	s.calls += 1
	web.no_content(ctx)
}

// Both signatures are pinned by ASSIGNMENT for `state`'s non-generic half and
// by USE for the generic one: a parametric procedure cannot be stored in a
// variable, so the shape is pinned by the fact that these calls compile at all.
// A changed parameter or result is a build failure in the contract suite.
@(test)
wp37_the_state_signatures_are_pinned :: proc(t: ^testing.T) {
	value := App_State{name = "pinned"}
	app := web.app_with_state(&value)
	defer web.destroy(&app)

	web.get(&app, "/name", read_name)
	res := web.test_request(&app, .GET, "/name")
	testing.expect_value(t, res.status, web.Status.OK)
	testing.expect_value(t, res.body, "pinned")
}

// THE PROPERTY THAT MAKES IT USEFUL: the App holds the POINTER, so a handler
// writing through it mutates the caller's own value. A copy would be a second
// database pool, which is the failure this design exists to avoid.
@(test)
wp37_a_handler_mutates_the_original_value :: proc(t: ^testing.T) {
	value := App_State{name = "counter"}
	app := web.app_with_state(&value)
	defer web.destroy(&app)

	web.post(&app, "/bump", bump)
	web.test_request(&app, .POST, "/bump")
	web.test_request(&app, .POST, "/bump")
	web.test_request(&app, .POST, "/bump")

	testing.expect_value(t, value.calls, 3)
}

// TWO APPLICATIONS, TWO STATES. There is no global slot and no registry: the
// value hangs off the App, so two Apps in one program never see each other's.
@(test)
wp37_two_applications_hold_distinct_states :: proc(t: ^testing.T) {
	first_value := App_State{name = "first"}
	second_value := App_State{name = "second"}

	first := web.app_with_state(&first_value)
	defer web.destroy(&first)
	second := web.app_with_state(&second_value)
	defer web.destroy(&second)

	web.get(&first, "/name", read_name)
	web.get(&second, "/name", read_name)

	testing.expect_value(t, web.test_request(&first, .GET, "/name").body, "first")
	testing.expect_value(t, web.test_request(&second, .GET, "/name").body, "second")

	// And they stay distinct after a mutation to one of them.
	web.post(&first, "/bump", bump)
	web.test_request(&first, .POST, "/bump")
	testing.expect_value(t, first_value.calls, 1)
	testing.expect_value(t, second_value.calls, 0)
}

// `app_with_state` gives the SAME defaults as `app()` — the automatic 404 and
// 405 — because it is `app()` with a value attached, not a third constructor
// with its own policy.
@(test)
wp37_an_app_with_state_keeps_the_default_responses :: proc(t: ^testing.T) {
	value := App_State{name = "defaults"}
	app := web.app_with_state(&value)
	defer web.destroy(&app)

	web.get(&app, "/name", read_name)

	testing.expect_value(
		t,
		web.test_request(&app, .GET, "/absent").status,
		web.Status.Not_Found,
	)
	testing.expect_value(
		t,
		web.test_request(&app, .POST, "/name").status,
		web.Status.Method_Not_Allowed,
	)
}

// The state survives the whole application, not one request: a value written
// during the first request is still there for the second. That is the LIFETIME
// difference between this and everything else reachable from a `^Context`.
@(test)
wp37_the_state_outlives_a_request :: proc(t: ^testing.T) {
	value := App_State{name = "persistent"}
	app := web.app_with_state(&value)
	defer web.destroy(&app)

	web.post(&app, "/bump", bump)
	web.get(&app, "/name", read_name)

	web.test_request(&app, .POST, "/bump")
	testing.expect_value(t, web.test_request(&app, .GET, "/name").body, "persistent")
	testing.expect_value(t, value.calls, 1)
}

// A NIL STATE REJECTS THE APPLICATION (AMEND-1). Fail-closed at construction is
// the same answer registration gives every other unusable input, and it is
// strictly better than the alternative: an App that accepted nil would abort
// inside the first request instead — the same failure, later, in front of a
// client.
@(test)
wp37_a_nil_state_rejects_the_application :: proc(t: ^testing.T) {
	quiet: Quiet
	context.logger = quiet_logger(&quiet)

	nothing: ^App_State
	app := web.app_with_state(nothing)
	defer web.destroy(&app)

	web.get(&app, "/name", read_name)
	res := web.test_request(&app, .GET, "/name")
	testing.expect_value(t, res.status, web.Status.Internal_Server_Error)
}

// The state a handler reads is the state the App was built with, even when the
// same type is used by a Router mounted into it: `mount` copies routes, not
// state, and a mounted handler reads the APPLICATION's value.
@(test)
wp37_a_mounted_handler_reads_the_applications_state :: proc(t: ^testing.T) {
	value := App_State{name = "mounted"}
	app := web.app_with_state(&value)
	defer web.destroy(&app)
	r := web.router()
	defer web.destroy(&r)

	web.get(&r, "/name", read_name)
	web.mount(&app, "/api", &r)

	testing.expect_value(t, web.test_request(&app, .GET, "/api/name").body, "mounted")
}

// Middleware reads it too — the same Context, the same accessor. There is no
// separate "middleware state", which is the point of there being one name.
@(test)
wp37_middleware_reads_the_same_state :: proc(t: ^testing.T) {
	value := App_State{name = "shared"}
	app := web.app_with_state(&value)
	defer web.destroy(&app)

	web.use(&app, count_in_middleware)
	web.get(&app, "/name", read_name)

	web.test_request(&app, .GET, "/name")
	testing.expect_value(t, value.calls, 1)
}

@(private = "file")
count_in_middleware :: proc(ctx: ^web.Context) {
	s := web.state(ctx, App_State)
	s.calls += 1
	web.next(ctx)
}

// The type registered is the type that must be asked for. This is the half a
// test cannot execute — a wrong type aborts the process by design (ADR-020),
// and a test that could observe it would mean the assert was not an assert —
// so what is pinned here is that the DISTINCT type exists and is not
// accidentally interchangeable at the Odin level: `^Other_State` and
// `^App_State` are different types, and `web.state(ctx, Other_State)` returns
// the former. The runtime half is the assert in `web/state.odin`, and the
// negative control for it is `build/check_wp37_controls.sh`.
@(test)
wp37_the_requested_type_decides_the_result_type :: proc(t: ^testing.T) {
	other := Other_State{n = 7}
	app := web.app_with_state(&other)
	defer web.destroy(&app)

	web.get(&app, "/n", read_other)
	testing.expect_value(t, web.test_request(&app, .GET, "/n").status, web.Status.OK)
	testing.expect_value(t, other.n, 8)
}

@(private = "file")
read_other :: proc(ctx: ^web.Context) {
	s := web.state(ctx, Other_State)
	s.n += 1
	web.ok(ctx, s.n)
}
