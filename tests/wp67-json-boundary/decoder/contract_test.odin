// WP67 RED contract for request-decoder classification.
//
// This is an external consumer. It deliberately names only the existing
// `web.body` API; WP68 must change behaviour, not invent a test-only path.
package wp67_json_decoder

import json "core:encoding/json"
import "core:log"
import "core:strings"
import "core:testing"
import web "uruquim:web"

Address :: struct {
	number: int `json:"number"`,
}

Input :: struct {
	name:    string  `json:"name"`,
	age:     int     `json:"age"`,
	address: Address `json:"address"`,
}

Unsupported_Input :: struct {
	callback: proc() `json:"callback"`,
}

Log_Filter :: struct {
	inner: log.Logger,
}

filter_log :: proc(
	data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	f := (^Log_Filter)(data)
	if level == .Error && strings.contains(text, "uruquim:") {
		return
	}
	if f.inner.procedure != nil {
		f.inner.procedure(f.inner.data, level, text, options, location)
	}
}

filtered_logger :: proc(f: ^Log_Filter) -> log.Logger {
	f.inner = context.logger
	return log.Logger {
		procedure = filter_log,
		data = rawptr(f),
		lowest_level = .Debug,
		options = context.logger.options,
	}
}

bind_input :: proc(ctx: ^web.Context) {
	dst: Input
	if !web.body(ctx, &dst) {
		return
	}
	web.no_content(ctx)
}

bind_unsupported :: proc(ctx: ^web.Context) {
	dst: Unsupported_Input
	if !web.body(ctx, &dst) {
		return
	}
	web.no_content(ctx)
}

expect_error :: proc(
	t: ^testing.T,
	path, raw: string,
	status: web.Status,
	code: string,
	field: string = "",
	loc := #caller_location,
) {
	filter: Log_Filter
	context.logger = filtered_logger(&filter)
	a := web.app()
	defer web.destroy(&a)
	web.post(&a, "/input", bind_input)
	web.post(&a, "/unsupported", bind_unsupported)

	res := web.test_request(&a, .POST, path, raw)
	testing.expect_value(t, res.status, status, loc = loc)
	if len(res.body) == 0 {
		testing.expect(t, false, "the error response must carry an envelope", loc = loc)
		return
	}

	value, parse_err := json.parse_string(res.body, .JSON, false, context.allocator)
	testing.expect_value(t, parse_err, json.Error.None, loc = loc)
	if parse_err != .None {
		return
	}
	defer json.destroy_value(value, context.allocator)

	root := value.(json.Object) or_else nil
	testing.expect(t, root != nil, "the response must be a JSON object", loc = loc)
	if root == nil {
		return
	}
	inner := root["error"].(json.Object) or_else nil
	testing.expect(t, inner != nil, "the response must contain error object", loc = loc)
	if inner == nil {
		return
	}

	actual_code := string(inner["code"].(json.String) or_else "")
	testing.expect_value(t, actual_code, code, loc = loc)
	if field != "" {
		actual_field := string(inner["field"].(json.String) or_else "")
		testing.expect_value(t, actual_field, field, loc = loc)
	}

	// No request body or language type may be reflected into a client error.
	testing.expect(t, !strings.contains(res.body, "Unsupported_Type_Error"), loc = loc)
	testing.expect(t, !strings.contains(res.body, "contract_test.odin"), loc = loc)
	testing.expect(t, !strings.contains(res.body, "callback"), loc = loc)
	testing.expect(t, !strings.contains(res.body, "old"), loc = loc)
}

@(test)
wp67_malformed_json_is_a_client_syntax_error :: proc(t: ^testing.T) {
	expect_error(t, "/input", `{`, .Bad_Request, "invalid_json")
}

@(test)
wp67_wrong_scalar_type_is_an_invalid_field :: proc(t: ^testing.T) {
	expect_error(t, "/input", `{"age":"old"}`, .Bad_Request, "invalid_field", "age")
}

@(test)
wp67_nested_type_mismatch_carries_a_stable_path :: proc(t: ^testing.T) {
	expect_error(
		t,
		"/input",
		`{"address":{"number":"x"}}`,
		.Bad_Request,
		"invalid_field",
		"address.number",
	)
}

@(test)
wp67_unknown_field_is_rejected_by_the_canonical_strict_path :: proc(t: ^testing.T) {
	expect_error(t, "/input", `{"surprise":true}`, .Bad_Request, "unknown_field", "surprise")
}

@(test)
wp67_unsupported_destination_remains_an_internal_error :: proc(t: ^testing.T) {
	expect_error(
		t,
		"/unsupported",
		`{"callback":"x"}`,
		.Internal_Server_Error,
		"internal_error",
	)
}
