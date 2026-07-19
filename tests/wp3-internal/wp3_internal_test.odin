// WP3 machinery (package `testing`) internal-behavior tests.
//
// This file declares `package testing` but does NOT live in `web/testing/`, and
// it must never be moved there: on the pinned toolchain an `@(test)` procedure
// is compiled as part of the package it tests, so a test file inside
// `web/testing/` would link `core:testing` into every application binary — the
// same hidden cost the WP2 arrangement exists to avoid. `build/check.sh`
// therefore assembles a THROWAWAY package: it copies the real sources from
// `web/testing/` plus this file into a `mktemp -d` directory, runs `odin test`
// there, and deletes it afterwards. The tests see the genuine machinery, and
// the shipped machinery ships no test code. `build/check_public_api.sh`
// permanently forbids `*_test.odin` and `core:testing` under `web/testing/`.
//
// These are the copy / lifetime / ownership tests the WP3 contract requires at the
// internal level, using NEUTRAL canned responses (there is no `web` type here,
// which is exactly what keeps the dependency one-way). The public callsite
// test in tests/wp3-public-surface/ proves form and the socket-free round trip.
#+private
package web_testing

import "core:mem"
import "core:slice"
import "core:testing"

// ---------------------------------------------------------------------------
// 1. The neutral request builder preserves method/path for the sync call.
// ---------------------------------------------------------------------------

@(test)
wp3_build_request_preserves_method_and_path :: proc(t: ^testing.T) {
	req := build_request("GET", "/users/42")
	testing.expect_value(t, req.method, "GET")
	testing.expect_value(t, req.path, "/users/42")

	req2 := build_request("POST", "/items")
	testing.expect_value(t, req2.method, "POST")
	testing.expect_value(t, req2.path, "/items")
}

// ---------------------------------------------------------------------------
// 2. The recorder OWNS its copy of the body: mutating/reusing the source buffer
//    after capture must not change what was recorded.
// ---------------------------------------------------------------------------

@(test)
wp3_recorder_copies_body_out_of_the_source_buffer :: proc(t: ^testing.T) {
	tt: Test_Transport
	defer destroy(&tt)

	buf := make([]u8, 5)
	defer delete(buf)
	copy(buf, transmute([]u8)string("hello"))

	_, body := capture(&tt, context.allocator, 200, buf, nil)
	testing.expect_value(t, body, "hello")

	// The transport reuses its request buffer; the recorded copy must not move.
	slice.fill(buf, '#')
	testing.expect_value(t, body, "hello")
}

// ---------------------------------------------------------------------------
// 3. The recorder OWNS its copy of every header name and value.
// ---------------------------------------------------------------------------

@(test)
wp3_recorder_copies_header_names_and_values :: proc(t: ^testing.T) {
	tt: Test_Transport
	defer destroy(&tt)

	headers := make([]Header, 1)
	defer delete(headers)
	name := make([]u8, 5)
	value := make([]u8, 8)
	defer delete(name)
	defer delete(value)
	copy(name, transmute([]u8)string("allow"))
	copy(value, transmute([]u8)string("GET, PUT"))
	headers[0] = Header{name = string(name), value = string(value)}

	capture(&tt, context.allocator, 405, nil, headers)

	// Reach into the private record: the stored headers must be owned copies.
	stored := tt.recorder.records[0].headers
	testing.expect_value(t, len(stored), 1)
	testing.expect_value(t, stored[0].name, "allow")
	testing.expect_value(t, stored[0].value, "GET, PUT")

	// Mutate the source; the stored copy is unaffected.
	slice.fill(name, '#')
	slice.fill(value, '#')
	testing.expect_value(t, stored[0].name, "allow")
	testing.expect_value(t, stored[0].value, "GET, PUT")
}

// ---------------------------------------------------------------------------
// 4. Two consecutive captures both stay readable until destroy.
// ---------------------------------------------------------------------------

@(test)
wp3_two_captures_both_remain_readable :: proc(t: ^testing.T) {
	tt: Test_Transport
	defer destroy(&tt)

	_, first := capture(&tt, context.allocator, 200, transmute([]u8)string("aaa"), nil)
	_, second := capture(&tt, context.allocator, 201, transmute([]u8)string("bb"), nil)

	// After the second call, the first is still intact: distinct owned storage.
	testing.expect_value(t, first, "aaa")
	testing.expect_value(t, second, "bb")
	testing.expect_value(t, tt.served, 2)
}

// ---------------------------------------------------------------------------
// 5. The state is lazy: an untouched transport has allocated nothing.
// ---------------------------------------------------------------------------

@(test)
wp3_state_is_unallocated_before_first_capture :: proc(t: ^testing.T) {
	tt: Test_Transport

	testing.expect(t, !tt.recorder.active, "a fresh transport must be inactive")
	testing.expect_value(t, len(tt.recorder.records), 0)
	testing.expect_value(t, tt.served, 0)

	// destroy on an untouched transport is a no-op (no bad free).
	destroy(&tt)
	testing.expect(t, !tt.recorder.active)
}

// ---------------------------------------------------------------------------
// 6. destroy releases every tracked allocation EXACTLY ONCE, with an explicit
//    allocator — and a second destroy is a safe no-op (no double free).
// ---------------------------------------------------------------------------

@(test)
wp3_destroy_releases_everything_exactly_once :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	al := mem.tracking_allocator(&track)

	tt: Test_Transport
	capture(&tt, al, 200, transmute([]u8)string("first"), nil)

	hdr := []Header{{name = "content-type", value = "application/json"}}
	capture(&tt, al, 201, transmute([]u8)string("second"), hdr)

	testing.expect(t, len(track.allocation_map) > 0, "captures must have allocated owned storage")

	destroy(&tt)

	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)

	// Idempotent: destroying again frees nothing and reports no bad free.
	destroy(&tt)
	testing.expect_value(t, len(track.bad_free_array), 0)
}

// ---------------------------------------------------------------------------
// 7. An empty (uncommitted) response is captured cleanly — the WP3 no-router
//    case. Status is copied verbatim; the body is an empty owned string.
// ---------------------------------------------------------------------------

@(test)
wp3_empty_response_captures_cleanly :: proc(t: ^testing.T) {
	tt: Test_Transport
	defer destroy(&tt)

	status, body := capture(&tt, context.allocator, 0, nil, nil)

	testing.expect_value(t, status, 0)
	testing.expect_value(t, body, "")
	testing.expect_value(t, tt.served, 1)
}
