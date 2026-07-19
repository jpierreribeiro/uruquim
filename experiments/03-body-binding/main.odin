// Experiment 03 — body-binding
// Question: does `body(ctx, dst: ^$T) -> bool` work with core:encoding/json
// unmarshal, an explicitly substituted allocator, nested strings/slices, and
// empty / invalid / over-limit bodies (writing the error and returning false)?
//
// THROWAWAY. Not imported by any product package.
package body_binding

import "core:encoding/json"
import "core:fmt"
import "core:mem"

Error_Code :: enum { None, Invalid_Json, Body_Too_Large }

Context :: struct {
	raw_body:      []byte,
	body_limit:    int,
	last_error:    Error_Code,
	responded:     bool,
	// request-lifetime allocator the bound value should live in:
	req_allocator: mem.Allocator,
}

// destination-filling extractor. returns bool only.
body :: proc(ctx: ^Context, dst: ^$T) -> bool {
	if len(ctx.raw_body) > ctx.body_limit {
		ctx.last_error = .Body_Too_Large
		ctx.responded = true // real framework writes body_too_large envelope
		return false
	}
	// nested strings/slices in dst are allocated with the request allocator,
	// explicitly substituted (not context.allocator by default).
	err := json.unmarshal(ctx.raw_body, dst, allocator = ctx.req_allocator)
	if err != nil {
		ctx.last_error = .Invalid_Json
		ctx.responded = true // real framework writes invalid_json envelope
		return false
	}
	return true
}

Create_User :: struct {
	name:  string   `json:"name"`,
	email: string   `json:"email"`,
	tags:  []string `json:"tags"`,
}

run_case :: proc(label: string, raw: string, limit: int, req_alloc: mem.Allocator) {
	ctx := Context{
		raw_body      = transmute([]byte)raw,
		body_limit    = limit,
		req_allocator = req_alloc,
	}
	input: Create_User
	okv := body(&ctx, &input)
	fmt.printfln("%-18s ok=%v err=%v responded=%v name=%q tags=%v",
		label, okv, ctx.last_error, ctx.responded, input.name, input.tags)
}

main :: proc() {
	// A dedicated arena stands in for the request-lifetime allocator.
	arena_backing := make([]byte, 64 * 1024)
	defer delete(arena_backing)
	arena: mem.Arena
	mem.arena_init(&arena, arena_backing)
	req_alloc := mem.arena_allocator(&arena)

	run_case("valid+nested", `{"name":"Jean","email":"j@x.io","tags":["a","b"]}`, 1024, req_alloc)
	run_case("empty-body",   ``,                                                  1024, req_alloc)
	run_case("invalid-json", `{"name":`,                                          1024, req_alloc)
	run_case("over-limit",   `{"name":"way too long for the tiny limit here"}`,   8,    req_alloc)

	fmt.println("arena used bytes:", arena.offset) // shows bound data lives in req allocator
}
