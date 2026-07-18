// Experiment 07 — middleware-chain
// Question: measure both a pre-order chain and an onion (before/after next)
// chain over global/group/route/handler, with short-circuit and unwind; record
// how much state each needs and WHERE a response would commit. NO Phase-2
// decision is made here.
//
// THROWAWAY. Not imported by any product package.
package middleware_chain

import "core:fmt"

Context :: struct {
	handlers:      []Handler,
	index:         int,
	log:           [dynamic]string,
	aborted:       bool,
	committed:     bool,
}

Handler :: proc(ctx: ^Context)

// cursor-based next(): the mechanism shared by pre-order and onion.
next :: proc(ctx: ^Context) {
	if ctx.aborted { return }
	ctx.index += 1
	if ctx.index < len(ctx.handlers) {
		ctx.handlers[ctx.index](ctx)
	}
}

execute :: proc(ctx: ^Context) {
	ctx.index = -1
	next(ctx)
}

// ---- onion-style middleware: work before AND after next ----
mw_global :: proc(ctx: ^Context) {
	append(&ctx.log, "global:before")
	next(ctx)
	append(&ctx.log, "global:after")
}
mw_group :: proc(ctx: ^Context) {
	append(&ctx.log, "group:before")
	next(ctx)
	append(&ctx.log, "group:after")
}
mw_route_auth :: proc(ctx: ^Context) {
	append(&ctx.log, "route:auth")
	// short-circuit demo toggled by first log entry length parity:
	if len(ctx.log) == 999 { // never true here; flip to test abort
		ctx.aborted = true
		append(&ctx.log, "route:ABORT")
		return
	}
	next(ctx)
	append(&ctx.log, "route:after")
}
terminal :: proc(ctx: ^Context) {
	append(&ctx.log, "handler:commit")
	ctx.committed = true
	// no next(): terminal handlers end the chain.
}

// ---- pre-order-only variant: middleware that never runs code after next ----
pre_only :: proc(ctx: ^Context) {
	append(&ctx.log, "preorder:run")
	next(ctx)
	// nothing after — equivalent to "no onion"
}

main :: proc() {
	// onion chain, flattened at "registration" (here: a literal slice)
	onion := Context{
		handlers = {mw_global, mw_group, mw_route_auth, terminal},
	}
	execute(&onion)
	fmt.println("onion order   :", onion.log[:])
	fmt.println("onion commit  :", onion.committed, " (commit happens at handler; middleware 'after' runs post-commit)")
	delete(onion.log)

	// pre-order-only chain
	pre := Context{ handlers = {pre_only, pre_only, terminal} }
	execute(&pre)
	fmt.println("preorder order:", pre.log[:])
	delete(pre.log)

	// STATE COST recorded: per-request we need {handlers slice ptr+len, index,
	// aborted, committed}. That is 1 slice + 3 scalars. No per-middleware heap.
	fmt.println("per-request chain state = slice + index + aborted + committed (no per-hop alloc)")
}
