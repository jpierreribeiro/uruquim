// WP9 — THE TEST-ONLY TRANSPORT FACTORY.
//
// This package is the shared conformance harness. It is TEST-ONLY: it lives
// under `tests/`, it imports `core:testing`, and nothing in `web/`,
// `web/testing/`, `web/internal/transport/` or `vendor/` may import it. That
// placement is WP9 D1 — the plan originally proposed `web/testing/`, which G-11
// refutes because that package ships inside every application binary.
//
// `Transport_Factory` is deliberately MINIMAL: start, exchange, stop, destroy.
// It is the smallest shape that lets one matrix drive both the in-memory
// transport and a real HTTP server, and it is not a public API — no `web`
// symbol references it and it never joins the 34-symbol surface.
package transport_conformance

// Header is a neutral name/value pair as seen by a test.
Header :: struct {
	name:  string,
	value: string,
}

// Exchange_Request is what a semantic scenario asks a transport to perform.
//
// `method` is the on-the-wire TOKEN ("GET", "PROPFIND", ...) so the matrix can
// express methods the public `web.Method` enum deliberately does not name.
Exchange_Request :: struct {
	method:  string,
	path:    string,
	query:   string,
	headers: []Header,
	body:    []u8,
}

// Exchange_Response is what a transport reports back. `closed` says the
// connection was closed by the server, which only a real socket transport can
// observe; the in-memory transport leaves it false and no semantic scenario
// asserts on it.
Exchange_Response :: struct {
	status:  int,
	headers: []Header,
	body:    string,
	closed:  bool,
	ok:      bool,
}

// Transport_Factory is the test-only interface both backends implement.
//
// `start` makes the transport ready to serve the routes an individual scenario
// registered; `exchange` performs one request/response; `stop` ends serving and
// joins whatever the transport owns; `destroy` releases the rest. A factory may
// implement these very differently — one binds a socket, the other does not —
// but the MATRIX and the expected results are shared, which is the entire point
// (R-10: a test transport that lies would otherwise go unnoticed).
Transport_Factory :: struct {
	name:     string,
	user:     rawptr,
	start:    proc(user: rawptr) -> bool,
	exchange: proc(user: rawptr, req: Exchange_Request) -> Exchange_Response,
	stop:     proc(user: rawptr),
	destroy:  proc(user: rawptr),
}

// header_value finds a response header by case-insensitive name, because the
// two transports are not required to agree on header CASE — only on names being
// lowercase at the CORE boundary (WP9 D8) and on values being preserved.
header_value :: proc(headers: []Header, name: string) -> (value: string, found: bool) {
	for header in headers {
		if equal_ascii_fold(header.name, name) {
			return header.value, true
		}
	}
	return "", false
}

// equal_ascii_fold compares two ASCII strings ignoring case. It exists so the
// harness never depends on a particular header casing.
equal_ascii_fold :: proc(a: string, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		x := a[i]
		y := b[i]
		if x >= 'A' && x <= 'Z' {
			x += 32
		}
		if y >= 'A' && y <= 'Z' {
			y += 32
		}
		if x != y {
			return false
		}
	}
	return true
}
