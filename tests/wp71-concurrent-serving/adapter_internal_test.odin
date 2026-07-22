package transport

import "core:testing"

@(test)
wp71_automatic_handler_capacity_is_bounded_and_explicit_values_are_exact :: proc(t: ^testing.T) {
	automatic := resolve_handler_concurrency(0)
	testing.expect(t, automatic >= AUTO_HANDLER_CONCURRENCY_MIN)
	testing.expect(t, automatic <= AUTO_HANDLER_CONCURRENCY_MAX)
	testing.expect_value(t, resolve_handler_concurrency(1), 1)
	testing.expect_value(t, resolve_handler_concurrency(4), 4)
	testing.expect_value(t, resolve_handler_concurrency(256), 256)
}
