# WP3 Gate — In-memory Test Transport

Status: **READY — LOCAL PASS, pending human ratification.** Toolchain
`dev-2026-07-nightly:819fdc7` (release `dev-2026-07a`). Worktree branch
`opus/wp3-test-transport`, base `origin/main` at `b6f7e36` (descendant of
`2943d3e`, PR #5 merged). Surface checkpoint: **32 application + 2 test-support
= 34 exported union**.

WP3 adds the public in-memory test-support facade `web.test_request` /
`web.Recorded_Response` (package `web`) and its machinery (package `testing`,
`web/testing/`), following planning/21 (HUMAN-ACCEPTED spec amendment) and
planning/15 G-11. The dependency is strictly one-way: `web` imports
`web/testing`; the machinery imports neither `uruquim:web` nor `core:testing`.

---

## SPEC

### What WP3 is

WP3 lets later work packages drive dispatch and read the response WITHOUT
binding a socket:

```odin
app := web.app()
defer web.destroy(&app)

res := web.test_request(&app, .GET, "/users/42")   // in-memory, no sockets
// res.status : web.Status   (copied by value)
// res.body   : string       (view over a copy the App owns until destroy)
```

Its claims are exactly:

1. `web.test_request(a: ^App, method: Method, path: string) -> Recorded_Response`
   exists in package `web`, compiles for an external consumer, and RUNS with no
   socket, port, or network syscall on its path;
2. `Recorded_Response` exposes exactly `status` and `body` — no `headers`,
   `committed`, allocator or transport field;
3. the recorder COPIES status/body/headers into storage owned by the App's lazy
   test-support state, so a returned `Recorded_Response` survives the request
   buffer and remains readable — across consecutive calls — until
   `web.destroy(&app)`, which frees every copy exactly once;
4. an application that never calls `test_request` allocates no recorder, runs no
   `@(init)`, and pays no measurable binary cost (see Review);
5. the machinery is neutral: it names no `web` type, and the back-edge
   `web/testing -> web` is a compile-time import cycle.

### What WP3 explicitly is NOT

**WP3 ships no router.** The private `dispatch` stub commits nothing, so
`test_request` returns the uncommitted response: the ZERO status and an EMPTY
body. There is deliberately no fabricated 200 and no echoed path — producing one
would be a fake the WP3 prompt forbids. WP4 fills in `dispatch` and proves real
routed status/body through this same `web.test_request`.

| Deliberately absent in WP3 | Owning WP |
|---|---|
| route table, dispatch behavior, 404, 405 + `Allow` | WP4 |
| extractor parsing and standardized failure responses | WP5 |
| JSON marshal, error envelope, wiring responders onto the commit guard | WP6 |
| body binding, request arena, 4 MiB cap | WP7 |
| sockets, transport adapter, HTTP parsing | WP8 |
| transport conformance suite, header normalization | WP9 |
| a public way to read response headers / a `headers` field on Recorded_Response | later |

### Surface ledger after WP3

```
Application API:   32   (unchanged, frozen)
Test-support API:   2   (Recorded_Response, test_request)
Exported union:    34
```

### Files

Facade (package `web`):

- `web/test_support.odin` — `Recorded_Response`, `test_request`, and the private
  `web`-side conversions (`method_token`, `response_headers_neutral`).

Machinery (package `testing`, `web/testing/`):

- `web/testing/request_builder.odin` — neutral `Request` + `build_request`.
- `web/testing/recorder.odin` — owned copies (`Header`, private `Recorded`,
  private `Recorder`) and cleanup.
- `web/testing/test_transport.odin` — `Test_Transport` (the App-owned in-memory
  transport), `capture`, `destroy`.

Wired into `web/app.odin` (App owns a `testing.Test_Transport`; `destroy` frees
it) and `web/routing.odin` (private `dispatch` stub, no routing yet).

### Dependency direction (ratified)

```
web (facade)  ->  web/testing (machinery)  ->  neutral records + core:
```

`web/testing` MUST NOT import `uruquim:web` (cycle) nor `core:testing`. The
facade converts `App`, `Method` and the captured `Response` across the boundary;
the machinery names no `web` type. Verified as probes C1–C5.

---

## RED (TESTS-FIRST, preserved)

The TESTS-FIRST commit raised `build/check_public_api.sh` to the dual-ledger
contract, added `build/check.sh` steps for probes C1/C2/C4/C5 and the machinery
+ public-surface tests, and added the test/probe files — all BEFORE any
production file existed. Captured on `819fdc7`:

RED 1 — the full gate stops at the first WP3 step (machinery absent):

```
--- WP3 probe C1: web/testing machinery compiles alone (neutral, core-only) ---
ERROR: `.../odin check` takes a package/directory as its first argument.
The file '.../web/testing' was not found.
GATE EXIT=1
```

RED 2 — the dual-ledger checker (run standalone):

```
FAIL: web/testing/ is missing; WP3 has not created the test machinery
API EXIT=1
```

RED 3 — the external public-surface test cannot compile, because the two ratified
symbols do not exist yet:

```
tests/wp3-public-surface/contract_test.odin(32:5) Error:
  'Recorded_Response' is not declared by 'web'
SURFACE EXIT=1
```

The RED commit is preserved and is not rewritten after GREEN.

---

## Minimal binary baseline (measured BEFORE implementation)

A minimal consumer that imports `uruquim:web`, constructs and destroys an App,
and never calls `test_request`:

```odin
package minapp
import web "uruquim:web"
main :: proc() {
	app := web.app()
	defer web.destroy(&app)
	_ = app
}
```

Command (pinned toolchain, `ODIN_ROOT`/`PATH` set to the pinned distribution):

```
odin build minapp -collection:uruquim=<worktree> -out:minapp_baseline -o:minimal
```

| Field | Value |
|---|---|
| Toolchain | `dev-2026-07-nightly:819fdc7` |
| Base commit | `origin/main` `b6f7e36` |
| Optimization | `-o:minimal` |
| Baseline size | **42744 bytes** |

The after-measurement and delta are recorded in the Review section (filled at
GREEN).

---

## GREEN

_(filled by the implementation/gate commit)_

## Review — hidden-cost audit

_(filled by the implementation/gate commit)_

## Bridge exports (unsupported internals of package `testing`)

_(filled by the implementation/gate commit)_

## Mutation checks

_(filled by the implementation/gate commit)_

## Status

_(filled by the implementation/gate commit)_
