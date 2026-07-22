// WP68 — bounded structural preflight for canonical request JSON.
//
// The pinned standard decoder is still the authority that populates the
// caller's destination. This module supplies only the information it does not
// expose: a field stack and strict unknown-field detection. It deliberately
// does not implement a second JSON grammar. Syntax and string decoding remain
// owned by core:encoding/json.
package web
// uruquim:file application

import json "core:encoding/json"
import "core:mem"
import "core:reflect"
import "core:strconv"

@(private)
JSON_FIELD_PATH_MAX :: ERROR_NAME_ESCAPED_MAX

// JSON_NEST_DEPTH_MAX bounds structural nesting (arrays and objects) accepted
// from a request body. The pinned `core:encoding/json` validator and parser are
// both recursive-descent over this nesting and impose no depth limit of their
// own, so a small body — under the `max_body` size cap — that is nothing but
// deeply nested brackets can drive recursion until the worker thread's stack
// overflows and the whole process aborts. Real request payloads nest a handful
// of levels; this ceiling is far above any legitimate shape and only refuses
// the pathological one.
@(private)
JSON_NEST_DEPTH_MAX :: 128

@(private)
Json_Decode_Issue_Kind :: enum {
	None,
	Invalid_Json,
	Invalid_Field,
	Unknown_Field,
	Unsupported_Destination,
	Internal,
}

@(private)
Json_Field_Path :: struct {
	bytes: [JSON_FIELD_PATH_MAX]u8,
	len:   int,
}

@(private)
Json_Decode_Issue :: struct {
	kind: Json_Decode_Issue_Kind,
	path: Json_Field_Path,
}

@(private)
json_path_string :: proc(path: ^Json_Field_Path) -> string {
	return string(path.bytes[:path.len])
}

// json_path_push appends a decoded object key without splitting UTF-8. The
// wire renderer applies its own escaped-byte cap later, so both buffers remain
// fixed and attacker-controlled nesting cannot grow request memory.
@(private)
json_path_push :: proc(path: ^Json_Field_Path, field: string) -> int {
	old := path.len
	if old > 0 && path.len < len(path.bytes) {
		path.bytes[path.len] = '.'
		path.len += 1
	}

	i := 0
	for i < len(field) && path.len < len(path.bytes) {
		width := 1
		c := field[i]
		switch {
		case c >= 0xF0: width = 4
		case c >= 0xE0: width = 3
		case c >= 0xC0: width = 2
		}
		if i + width > len(field) || path.len + width > len(path.bytes) {
			break
		}
		copy(path.bytes[path.len:], transmute([]u8)field[i:i + width])
		path.len += width
		i += width
	}
	return old
}

@(private)
json_path_restore :: proc(path: ^Json_Field_Path, old: int) {
	path.len = old
}

@(private)
json_field_name :: proc(field: reflect.Struct_Field) -> string {
	tag := reflect.struct_tag_get(field.tag, "json")
	name := tag
	for i in 0 ..< len(tag) {
		if tag[i] == ',' {
			name = tag[:i]
			break
		}
	}
	if name == "" {
		return field.name
	}
	return name
}

// json_struct_field finds the same ordinary and flattened-using fields as the
// stdlib decoder. The first match wins, matching declaration order.
@(private)
json_struct_field :: proc(info: ^reflect.Type_Info, key: string) -> (field_type: ^reflect.Type_Info, found: bool) {
	for field in reflect.struct_fields_zipped(info.id) {
		if json_field_name(field) == key {
			return field.type, true
		}
	}
	for field in reflect.struct_fields_zipped(info.id) {
		if field.is_using && field.name == "_" {
			base := reflect.type_info_base(field.type)
			if _, ok := base.variant.(reflect.Type_Info_Struct); ok {
				if nested, nested_ok := json_struct_field(base, key); nested_ok {
					return nested, true
				}
			}
		}
	}
	return nil, false
}

@(private)
json_issue_at :: proc(kind: Json_Decode_Issue_Kind, path: ^Json_Field_Path) -> Json_Decode_Issue {
	return Json_Decode_Issue{kind = kind, path = path^}
}

@(private)
json_destination_is_unsupported :: proc(info: ^reflect.Type_Info) -> bool {
	if reflect.is_pointer(info) || reflect.is_multi_pointer(info) || reflect.is_soa_pointer(info) {
		return true
	}
	#partial switch _ in reflect.type_info_base(info).variant {
	case reflect.Type_Info_Procedure:
		return true
	}
	return false
}

@(private)
json_struct_known_check :: proc(
	object: json.Object,
	info: ^reflect.Type_Info,
	path: ^Json_Field_Path,
) -> Json_Decode_Issue {
	for field in reflect.struct_fields_zipped(info.id) {
		if field.is_using && field.name == "_" {
			base := reflect.type_info_base(field.type)
			if _, ok := base.variant.(reflect.Type_Info_Struct); ok {
				if issue := json_struct_known_check(object, base, path); issue.kind != .None {
					return issue
				}
			}
			continue
		}

		name := json_field_name(field)
		if child, present := object[name]; present {
			old := json_path_push(path, name)
			issue := json_shape_check(child, field.type, path)
			json_path_restore(path, old)
			if issue.kind != .None {
				return issue
			}
		}
	}
	return {}
}

@(private)
json_shape_check :: proc(value: json.Value, info: ^reflect.Type_Info, path: ^Json_Field_Path) -> Json_Decode_Issue {
	if info == nil {
		return json_issue_at(.Unsupported_Destination, path)
	}
	info := reflect.type_info_base(info)
	if json_destination_is_unsupported(info) {
		return json_issue_at(.Unsupported_Destination, path)
	}

	// The stdlib treats JSON null as the zero value for every destination. WP81
	// owns the distinct missing/null/value representation; WP68 preserves the
	// current decode contract until that decision is made.
	#partial switch _ in value {
	case json.Null:
		return {}
	}

	// The stdlib tries non-null union variants in declaration order. Mirror
	// that compatibility without exposing the union itself in the wire error;
	// this covers ordinary optional/Maybe shapes and json.Value.
	if union_info, ok := info.variant.(reflect.Type_Info_Union); ok {
		first_issue: Json_Decode_Issue
		for variant in union_info.variants {
			candidate_path := path^
			issue := json_shape_check(value, variant, &candidate_path)
			if issue.kind == .None {
				return {}
			}
			if first_issue.kind == .None {
				first_issue = issue
			}
		}
		if first_issue.kind != .None {
			return first_issue
		}
		return json_issue_at(.Unsupported_Destination, path)
	}

	#partial switch v in value {
	case json.Boolean:
		if _, ok := info.variant.(reflect.Type_Info_Boolean); ok {
			return {}
		}
		return json_issue_at(.Invalid_Field, path)

	case json.Integer:
		#partial switch _ in info.variant {
		case reflect.Type_Info_Integer, reflect.Type_Info_Float,
		     reflect.Type_Info_Complex, reflect.Type_Info_Quaternion,
		     reflect.Type_Info_Bit_Set:
			return {}
		}
		return json_issue_at(.Invalid_Field, path)

	case json.Float:
		#partial switch _ in info.variant {
		case reflect.Type_Info_Integer, reflect.Type_Info_Float,
		     reflect.Type_Info_Complex, reflect.Type_Info_Quaternion:
			return {}
		}
		return json_issue_at(.Invalid_Field, path)

	case json.String:
		text := string(v)
		#partial switch t in info.variant {
		case reflect.Type_Info_String, reflect.Type_Info_Rune:
			return {}
		case reflect.Type_Info_Enum:
			for name in t.names {
				if name == text {
					return {}
				}
			}
			return json_issue_at(.Invalid_Field, path)
		case reflect.Type_Info_Integer:
			_, ok := strconv.parse_i128(text)
			if ok {
				return {}
			}
			return json_issue_at(.Invalid_Field, path)
		case reflect.Type_Info_Float:
			_, ok := strconv.parse_f64(text)
			if ok {
				return {}
			}
			return json_issue_at(.Invalid_Field, path)
		}
		return json_issue_at(.Invalid_Field, path)

	case json.Array:
		elem: ^reflect.Type_Info
		capacity := -1
		#partial switch t in info.variant {
		case reflect.Type_Info_Slice:
			elem = t.elem
		case reflect.Type_Info_Dynamic_Array:
			elem = t.elem
		case reflect.Type_Info_Fixed_Capacity_Dynamic_Array:
			elem = t.elem
			capacity = t.capacity
		case reflect.Type_Info_Array:
			elem = t.elem
			capacity = t.count
		case reflect.Type_Info_Enumerated_Array:
			elem = t.elem
			capacity = t.count
		case:
			return json_issue_at(.Invalid_Field, path)
		}
		if capacity >= 0 && len(v) > capacity {
			return json_issue_at(.Invalid_Field, path)
		}
		for item in v {
			if issue := json_shape_check(item, elem, path); issue.kind != .None {
				return issue
			}
		}
		return {}

	case json.Object:
		#partial switch t in info.variant {
		case reflect.Type_Info_Struct:
			if .raw_union in t.flags {
				return json_issue_at(.Unsupported_Destination, path)
			}

			// Validate declared fields in declaration order, so two invalid
			// values cannot make the selected error depend on map iteration.
			if issue := json_struct_known_check(v, info, path); issue.kind != .None {
				return issue
			}

			// Select the lexicographically smallest unknown key. Map order is
			// deliberately not allowed to leak into the stable client result.
			unknown := ""
			for key in v {
				if _, known := json_struct_field(info, key); !known {
					if unknown == "" || key < unknown {
						unknown = key
					}
				}
			}
			if unknown != "" {
				old := json_path_push(path, unknown)
				issue := json_issue_at(.Unknown_Field, path)
				json_path_restore(path, old)
				return issue
			}
			return {}

		case reflect.Type_Info_Map:
			for key, child in v {
				old := json_path_push(path, key)
				issue := json_shape_check(child, t.value, path)
				json_path_restore(path, old)
				if issue.kind != .None {
					return issue
				}
			}
			return {}

		case:
			return json_issue_at(.Invalid_Field, path)
		}
	}

	return json_issue_at(.Unsupported_Destination, path)
}

// body_json_preflight parses with the standard library into a disposable
// arena, then compares that tree with the destination RTTI. The arena is
// destroyed before the real typed decode, so the caller never owns the
// preflight tree and every failure path has one obvious cleanup point.
@(private)
body_json_preflight :: proc(raw: []u8, info: ^reflect.Type_Info) -> Json_Decode_Issue {
	// Reject pathological structural nesting BEFORE the recursive-descent
	// validator and parser ever see the input: neither bounds its own depth, so
	// a body of nothing but `[` overflows the stack and aborts the process. This
	// pre-scan is a single allocation-free pass that counts bracket/brace depth
	// while skipping string contents, so a `[` inside a JSON string is never
	// miscounted. A body deeper than the ceiling is a malformed request.
	{
		depth := 0
		max_depth := 0
		in_string := false
		escaped := false
		for b in raw {
			if in_string {
				if escaped {
					escaped = false
				} else if b == '\\' {
					escaped = true
				} else if b == '"' {
					in_string = false
				}
				continue
			}
			switch b {
			case '"':
				in_string = true
			case '[', '{':
				depth += 1
				if depth > max_depth {
					max_depth = depth
				}
			case ']', '}':
				depth -= 1
			}
		}
		if max_depth > JSON_NEST_DEPTH_MAX {
			return Json_Decode_Issue{kind = .Invalid_Json}
		}
	}

	// The stdlib parser's partial-tree cleanup uses context.allocator on some
	// syntax-error paths. Validate allocation-free first, so malformed input
	// never creates a partial tree and cannot free through the wrong allocator.
	if !json.is_valid(raw, .JSON, true) {
		return Json_Decode_Issue{kind = .Invalid_Json}
	}

	temporary: mem.Dynamic_Arena
	mem.dynamic_arena_init(&temporary)
	defer mem.dynamic_arena_destroy(&temporary)
	temporary_allocator := mem.dynamic_arena_allocator(&temporary)

	parser := json.make_parser_from_bytes(
		raw,
		.JSON,
		true,
		temporary_allocator,
	)
	// Duplicate-key rejection is a parse-time error after syntax validation.
	// Keep the parser allocator implicit during that call as well, because the
	// pinned stdlib's error cleanup consults context.allocator for child values.
	previous_allocator := context.allocator
	context.allocator = temporary_allocator
	value, err := json.parse_value(&parser)
	context.allocator = previous_allocator
	if err != .None {
		#partial switch err {
		case .Out_Of_Memory, .Invalid_Allocator:
			return Json_Decode_Issue{kind = .Internal}
		case:
			return Json_Decode_Issue{kind = .Invalid_Json}
		}
	}
	if parser.curr_token.kind != .EOF {
		return Json_Decode_Issue{kind = .Invalid_Json}
	}

	path: Json_Field_Path
	issue := json_shape_check(value, info, &path)
	if issue.kind == .Invalid_Field && issue.path.len == 0 {
		issue.path.bytes[0] = '$'
		issue.path.len = 1
	}
	return issue
}

@(private)
body_unmarshal_error_is_internal :: proc(err: json.Unmarshal_Error) -> bool {
	switch e in err {
	case json.Error:
		return e == .Out_Of_Memory || e == .Invalid_Allocator
	case json.Unmarshal_Data_Error:
		return e != .Invalid_Data
	case json.Unsupported_Type_Error:
		return true
	}
	return true
}
