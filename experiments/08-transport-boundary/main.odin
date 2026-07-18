// Experiment 08 — transport-boundary
// Question: can a MINIMAL private contract connect (request view) -> dispatch
// -> (response sink) with a single commit, using a test transport, with no
// backend type or ABI on the public surface?
//
// THROWAWAY. Not imported by any product package.
package transport_boundary

import "core:fmt"

// ---- framework-native types (public surface would expose only these) ----
Request  :: struct { method: string, path: string, body: []byte }
Response :: struct { status: int, body: []byte, commit_count: int }

Dispatch :: proc(req: ^Request, res: ^Response)

// ---- minimal PRIVATE transport contract (shape intentionally not frozen) ----
// Only what the framework needs: serve(work -> dispatch -> commit), stop.
Transport :: struct {
	data:  rawptr,
	serve: proc(t: ^Transport, dispatch: Dispatch),
	stop:  proc(t: ^Transport),
}

// commit guard: exactly one commit per response.
commit :: proc(res: ^Response, status: int, body: []byte) -> bool {
	if res.commit_count > 0 {
		return false // double-commit rejected
	}
	res.status = status
	res.body = body
	res.commit_count = 1
	return true
}

// ---- test transport: feeds canned requests, captures responses. No sockets. ----
Test_Transport_Data :: struct {
	inbox:   []Request,
	outbox:  [dynamic]Response,
}

test_serve :: proc(t: ^Transport, dispatch: Dispatch) {
	d := cast(^Test_Transport_Data)t.data
	for &req in d.inbox {
		res: Response
		dispatch(&req, &res)
		append(&d.outbox, res)
	}
}
test_stop :: proc(t: ^Transport) { /* nothing to release in the stub */ }

make_test_transport :: proc(data: ^Test_Transport_Data) -> Transport {
	return Transport{ data = data, serve = test_serve, stop = test_stop }
}

// ---- a tiny dispatch: 200 for /ping, 404 otherwise; try a double-commit. ----
demo_dispatch :: proc(req: ^Request, res: ^Response) {
	if req.method == "GET" && req.path == "/ping" {
		commit(res, 200, transmute([]byte)string("pong"))
	} else {
		commit(res, 404, transmute([]byte)string(`{"error":{"code":"not_found"}}`))
	}
	// attempt an illegal second commit — must be rejected by the guard.
	ok2 := commit(res, 500, transmute([]byte)string("should-not-apply"))
	if ok2 { fmt.eprintln("BUG: double commit succeeded") }
}

main :: proc() {
	data := Test_Transport_Data{
		inbox = {
			Request{ method = "GET", path = "/ping" },
			Request{ method = "GET", path = "/nope" },
		},
	}
	t := make_test_transport(&data)
	t.serve(&t, demo_dispatch)
	defer { t.stop(&t); delete(data.outbox) }

	for res, i in data.outbox {
		fmt.printfln("resp[%d] status=%d commit=%d body=%s", i, res.status, res.commit_count, res.body)
	}
	// Public surface note: nothing above (no Transport, no Test_Transport_Data)
	// would appear in a handler signature. Handlers see only ^Context built
	// from ^Request/^Response.
}
