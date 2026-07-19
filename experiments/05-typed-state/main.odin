// Experiment 05 — typed-state
// Question: compare (A) rawptr+typeid app state validated at the boundary vs
// (B) a type-closed accessor, across correct type, wrong type, nil, and state
// lifetime.
//
// THROWAWAY. Not imported by any product package.
package typed_state

import "core:fmt"

// ---------- Alternative A: rawptr + typeid, asserted accessor ----------
App_A :: struct {
	state_ptr:  rawptr,
	state_type: typeid,
}

Context_A :: struct { app: ^App_A }

app_with_state_A :: proc(app: ^App_A, state: ^$T) {
	app.state_ptr  = state
	app.state_type = T
}

state_A :: proc(ctx: ^Context_A, $T: typeid) -> ^T {
	assert(ctx.app.state_type == T,
		"web.state called with a type different from the registered App_State")
	return cast(^T)ctx.app.state_ptr
}

// ---------- Alternative B: parametric app, type-closed by construction ----
App_B :: struct($S: typeid) { state: ^S }
Context_B :: struct($S: typeid) { app: ^App_B(S) }

state_B :: proc(ctx: ^Context_B($S)) -> ^S { return ctx.app.state }

// ---------- shared demo types ----------
App_State :: struct { db_name: string, hits: int }
Other     :: struct { x: int }

main :: proc() {
	st := App_State{ db_name = "primary", hits = 0 }

	// A: correct type
	app_a: App_A
	app_with_state_A(&app_a, &st)
	ctx_a := Context_A{ app = &app_a }
	got_a := state_A(&ctx_a, App_State)
	got_a.hits += 1
	fmt.printfln("[A] correct -> db=%q hits=%d (lifetime: shared &st)", got_a.db_name, got_a.hits)
	fmt.printfln("[A] st.hits after handler = %d (mutation visible => same object)", st.hits)

	// A: wrong type -> assert fires (intended failure; uncomment to record).
	// _ = state_A(&ctx_a, Other)   // <- expected: assertion failure message

	// A: nil state -> accessor returns a ^App_State pointing at nil; deref is UB.
	// Documented: app_with_state must reject nil, OR state_A must check. See README.

	// B: correct by construction; wrong type cannot be expressed.
	app_b := App_B(App_State){ state = &st }
	ctx_b := Context_B(App_State){ app = &app_b }
	got_b := state_B(&ctx_b)
	fmt.printfln("[B] correct -> db=%q (wrong type is a COMPILE error, not runtime)", got_b.db_name)

	// The cost of B is visible in these type arguments at every call site:
	//   App_B(App_State), Context_B(App_State) — the "generic noise" the spec
	//   wants to keep out of ordinary handlers.
}
