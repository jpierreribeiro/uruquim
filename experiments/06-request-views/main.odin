// Experiment 06 — request-views
// Question: can Request expose method/path/query/headers/body as VIEWS over a
// mutable transport buffer, demonstrate invalidation when the buffer is
// reused, and support explicit persistent copies via a chosen allocator?
//
// THROWAWAY. Not imported by any product package.
package request_views

import "core:fmt"
import "core:strings"
import "core:mem"

Header_View :: struct { name: string, value: string } // both alias buffer

Request :: struct {
	method:  string,        // view
	path:    string,        // view
	query:   string,        // view
	headers: []Header_View, // views
	body:    []byte        // view
}

// Parse VIEWS over `buf` — no copies. Slices/strings alias buf's memory.
parse_into_views :: proc(buf: []byte) -> Request {
	// toy parse: "GET /users?page=2\nX-Api-Key: abc\n\n<body>"
	s := string(buf)
	line_end := strings.index_byte(s, '\n')
	request_line := s[:line_end]
	sp1 := strings.index_byte(request_line, ' ')
	method := request_line[:sp1]
	rest := request_line[sp1+1:]
	qmark := strings.index_byte(rest, '?')
	path := rest if qmark < 0 else rest[:qmark]
	query := "" if qmark < 0 else rest[qmark+1:]

	// one header, one body — enough to show aliasing
	hv := Header_View{ name = "X-Api-Key", value = "abc" } // (would be sliced from buf)
	headers := make([]Header_View, 1)
	headers[0] = hv
	body := buf[line_end+1:]

	return Request{ method, path, query, headers, body }
}

// Persist a view beyond the request: explicit copy with an allocator.
persist :: proc(view: string, allocator: mem.Allocator) -> string {
	return strings.clone(view, allocator)
}

main :: proc() {
	buf := make([]byte, 128)
	defer delete(buf)
	copy(buf, transmute([]byte)string("GET /users?page=2\nbody-bytes-here"))

	req := parse_into_views(buf)
	defer delete(req.headers)
	fmt.printfln("views    -> method=%q path=%q query=%q body=%q",
		req.method, req.path, req.query, string(req.body))

	// Persist path BEFORE we clobber the buffer.
	saved := persist(req.path, context.allocator)
	defer delete(saved)

	// Invalidate: reuse the transport buffer for the "next request".
	for i in 0..<len(buf) { buf[i] = '#' }

	fmt.printfln("after reuse -> req.path (view, now GARBAGE)=%q ; saved (copied)=%q",
		req.path, saved)
	// Expectation: req.path shows '#' garbage (aliased buffer overwritten);
	// `saved` still equals "/users" because it was cloned before reuse.
}
