// Experiment 02 — generic-json-response
// Question: can `json(ctx, status, value: $T)` serialize structs, pointers,
// slices and large values via core:encoding/json, and can `ok`/`created`
// delegate to `json` exactly once with a fixed status?
//
// THROWAWAY. Not imported by any product package.
package generic_json_response

import encoding_json "core:encoding/json"
import "core:fmt"

Status :: enum { OK = 200, Created = 201, Bad_Request = 400 }

Response_Capture :: struct {
	status:       Status,
	body:         []byte,
	commit_count: int, // must be exactly 1 per response
}

Context :: struct {
	res: Response_Capture,
}

// The single renderer. Uses `any` INTERNALLY only because json.marshal takes
// any — this is an encapsulated stdlib detail, never framework storage/API.
json :: proc(ctx: ^Context, status: Status, value: $T) {
	data, err := encoding_json.marshal(value, allocator = context.temp_allocator)
	if err != nil {
		// real framework: this becomes internal_error before commit; here we record.
		fmt.eprintln("[json] marshal error:", err)
		ctx.res.status = .Bad_Request
		ctx.res.commit_count += 1
		return
	}
	ctx.res.status = status
	ctx.res.body = data
	ctx.res.commit_count += 1
}

// Exact shorthands — must delegate to `json` exactly once, no extra behavior.
ok      :: proc(ctx: ^Context, value: $T) { json(ctx, .OK, value) }
created :: proc(ctx: ^Context, value: $T) { json(ctx, .Created, value) }

User :: struct {
	id:   int    `json:"id"`,
	name: string `json:"name"`,
}

Big :: struct {
	tags:   []string `json:"tags"`,
	scores: []int    `json:"scores"`,
	nested: []User    `json:"nested"`,
}

main :: proc() {
	ctx: Context

	// struct value
	ok(&ctx, User{id = 1, name = "Jean"})
	fmt.printfln("ok/User      -> status=%v commit=%d body=%s", ctx.res.status, ctx.res.commit_count, ctx.res.body)

	// pointer to struct
	u := User{id = 2, name = "Ana"}
	ctx.res.commit_count = 0
	created(&ctx, &u)
	fmt.printfln("created/^User -> status=%v commit=%d body=%s", ctx.res.status, ctx.res.commit_count, ctx.res.body)

	// slice / large value
	ctx.res.commit_count = 0
	big := Big{
		tags   = {"a", "b", "c"},
		scores = {10, 20, 30, 40},
		nested = {{id = 3, name = "x"}, {id = 4, name = "y"}},
	}
	json(&ctx, .OK, big)
	fmt.printfln("json/Big     -> status=%v commit=%d body=%s", ctx.res.status, ctx.res.commit_count, ctx.res.body)

	// A type the JSON marshaller rejects: raw pointer / proc value.
	// Recorded as an intentional-failure probe (see README).
	// bad := proc() {}
	// json(&ctx, .OK, bad)   // <- expected marshal error path
}
