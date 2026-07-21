// WP67 internal RED contract: allocator/decoder failure must fail closed.
#+private
package web

import "core:mem"
import "core:testing"

Wp67_Allocated_Input :: struct {
	name: string   `json:"name"`,
	tags: []string `json:"tags"`,
}

@(test)
wp67_decoder_allocation_failure_must_not_return_success_with_zero_values :: proc(t: ^testing.T) {
	ctx: Context
	defer request_arena_destroy(&ctx)
	ctx.request.body = transmute([]u8)string(`{"name":"a\\nb","tags":["x","y"]}`)

	// The pinned stdlib currently returns err=nil and zeroes when allocations
	// fail. The framework must detect or avoid that path; a successful bind with
	// empty values is data corruption, not graceful degradation.
	context.allocator = mem.nil_allocator()
	dst: Wp67_Allocated_Input
	ok := body(&ctx, &dst)

	testing.expect(t, !ok, "allocation failure must fail the bind")
	testing.expect_value(t, ctx.private.response.status, Status.Internal_Server_Error)
	testing.expect_value(
		t,
		string(ctx.private.response.body),
		`{"error":{"code":"internal_error","message":"Internal server error"}}`,
	)
}
