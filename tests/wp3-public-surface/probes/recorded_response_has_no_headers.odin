// NEGATIVE COMPILE PROBE — MUST FAIL TO COMPILE.
//
// `Recorded_Response` exposes exactly `status` and `body` in Phase 1. It has NO
// public `headers` field: the recorder copies response headers internally for
// the future WP4 tests, but Phase 1 ratifies no public abstraction for reading
// response headers. Naming `res.headers` must fail.
//
// Expected diagnostic: 'res' of type 'Recorded_Response' has no field 'headers'
package wp3_probe_recorded_headers

import web "uruquim:web"

probe :: proc(res: web.Recorded_Response) {
	_ = res.headers
}
