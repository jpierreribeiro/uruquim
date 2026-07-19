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

`bash build/check.sh` exits 0 on the pinned toolchain. WP3-specific results:

```
PASS=10 FAIL=0 SKIP=0                       (experiment prototypes, unchanged)
WP1 public API: check + compile contract    PASS
WP2 internal + public surface + probes      PASS
WP3 probe C1: web/testing compiles alone (neutral, core-only)   PASS
WP3 probe C2: web imports web/testing one-way                    PASS
WP3 machinery internal behavior (throwaway package, 7 tests)     PASS
WP3 public surface incl. C4 in-memory round trip (4 tests)       PASS
WP3 probe: Recorded_Response has no public headers field         PASS
WP3 probe C5: web/testing -> web back-edge is a compile cycle    PASS
Phase-1 anti-accretion contract: 32 + 2 = 34                     PASS
WP3 mutation checks: 8 forbidden states all rejected             PASS
```

Probes C1–C5 are the committed, executable ratification the amendment asked for
(planning/21 Part II). The exact diagnostics the gate pins:

- C5 back-edge: `Cyclic importation of 'web_testing'` (the machinery's declared
  package name; the facade's import alias is still `testing`).
- no-headers probe: `'res' of type 'Recorded_Response' has no field 'headers'`.

### Package-name note (deviation from the planning/21 sketch)

planning/21 sketched the machinery as `package testing`. On the pinned toolchain
a package literally named `testing` collides with `core:testing` at link time
(`Duplicate declaration of 'package testing' … A package name must be unique`),
because any application test binary links both. The machinery therefore declares
`package web_testing`, while the facade imports it with the alias `testing`
(`import testing "uruquim:web/testing"`). The directory is still `web/testing/`,
callers still write `testing.*` internally, and `web.test_request` is unchanged.
This is a naming correction forced by the compiler, not an architecture change.

## Review — hidden-cost audit (BINARY DELTA IS NON-ZERO)

Same minimal consumer, same source, same flags, rebuilt against the WP3 `web`:

| Binary | test_request? | bytes | delta vs baseline |
|---|---|---|---|
| baseline (pre-impl) | no | 42744 | — |
| after (post-impl) | no | **47976** | **+5232** |
| user (calls test_request) | yes | 395456 | +352712 |

Verified linkage facts (`nm`):

- `core:testing` appears in NEITHER non-test binary (0 symbols). The permanent
  ban holds — the machinery ships without the test runner.
- `recorder_capture` / `strings.clone_from_bytes` are DEAD-CODE-ELIMINATED in the
  unused-facade binary (0 symbols) and present in the using binary (2). The lazy
  design works: an app that never calls `test_request` links no capture path.
- No `@(init)` runs; `app()`/`bare()` allocate nothing; the internal tests prove
  the recorder is inactive before the first call.

**Cause of the +5232 bytes (fully explained, not unexplained).** The 15 new
symbols in the unused-facade binary are exactly the TEARDOWN path, reachable
because every `web.destroy(&app)` calls `web_testing.destroy` →
`recorder_destroy`, whose body references `delete` on the owned types even though
it early-returns for an inactive recorder:

```
web_testing::destroy
web_testing::recorder_destroy
runtime::delete_dynamic_array (for [dynamic]web_testing.Recorded)
runtime::delete_slice        (for []web_testing.Header)
runtime::delete_string
runtime::mem_free_with_size
mem::query_page_size_init, mem::PAGE_SIZE   (pulled by the free path)
```

This is intrinsic to the ratified lifetime (planning/21: the App OWNS the
test-support state and frees it at `destroy`). The delete instantiations are
linked by reachability, not by runtime use, so the runtime `if !active { return }`
guard cannot remove them. Reducing this to zero would require changing the
ownership/lifetime or moving packages — which the WP3 prompt forbids the agent
from doing unilaterally.

**Decision required (human).** Per the WP3 cost-review rule, a non-zero
unused-facade delta — even an explained one — is a human-review item. The gate
is marked `READY_WITH_BLOCKER`: everything technical is green, but WP3 is NOT
marked COMPLETE until a human accepts (or rejects) the +5232-byte teardown cost
that every application binary now carries. For comparison, the cost the WP2
arrangement eliminated was +41,592 bytes (`core:testing`); this cost is ~1/8 of
that and buys the App-owned, leak-checked recorder lifetime.

## Bridge exports (unsupported internals of package `web_testing`)

The facade calls the machinery across the package boundary, so a minimal set of
`web_testing` declarations is exported. These are UNSUPPORTED INTERNALS: not part
of the 34-symbol `web` surface, not documented for direct consumption. The set
is LOCKED exactly by `build/check_public_api.sh` (ledger 2d) so it cannot grow
silently. Exactly six:

| Bridge export | File | Why the facade needs it |
|---|---|---|
| `Request` | request_builder.odin | return of `build_request`; facade reads `.method`/`.path` |
| `build_request` | request_builder.odin | facade constructs the neutral inbound request |
| `Header` | recorder.odin | facade passes neutral response headers to the recorder |
| `Test_Transport` | test_transport.odin | the App owns one as its test-support state |
| `capture` | test_transport.odin | facade records the response into owned storage |
| `destroy` | test_transport.odin | `web.destroy` releases the transport |

Everything else in the machinery is `@(private)`: `Recorded`, `Recorder`,
`recorder_ensure`, `recorder_capture`, `recorder_destroy`.

## Mutation checks

`build/check_wp3_mutations.sh` (run by the gate) copies the package into a
throwaway tree, applies ONE forbidden mutation, and asserts the checker rejects
it with the expected message. All eight pass (state → rejected):

1. extra application-ledger symbol → rejected
2. extra test-support-ledger symbol → rejected
3. subdirectory other than web/testing → rejected
4. `core:testing` imported by the machinery → rejected
5. `uruquim:web` imported by the machinery → rejected
6. `@(init)` in the machinery → rejected
7. bridge export beyond the locked set → rejected
8. public `headers` field on `Recorded_Response` → rejected

## Lifetime / cleanup evidence

- Public (external consumer, `tests/wp3-public-surface`): two consecutive
  `test_request` results both remain readable after the second call; an App that
  never calls `test_request` constructs and destroys cleanly under the memory
  tracker.
- Internal (machinery, `tests/wp3-internal`): the recorder copies body and every
  header name/value out of the source buffer (mutating the source does not change
  the copy); a local `mem.Tracking_Allocator` shows `len(allocation_map) == 0`
  and `len(bad_free_array) == 0` after `destroy`, and a second `destroy` reports
  no bad free (freed exactly once, idempotent).

## Status

**READY_WITH_BLOCKER.** All technical completion criteria are met: gate exit 0;
prototypes PASS=10; WP1/WP2 green; 32 application + 2 test-support = 34; C1–C5
committed and green; `test_request` runs in-memory with no socket and no routing;
recorder copies body/headers and two responses survive until `destroy`; memory
tracker shows complete cleanup; no `core:testing`/test file in the shipped
package; no init/allocation when `test_request` is unused; docs match the code;
no WP4+ symbol entered.

The one open item is the measured, explained **+5232-byte** teardown cost in
application binaries that never use `test_request`. Per the WP3 prompt this
requires human acceptance before WP3 is COMPLETE. The agent does not weaken the
gate or mask the cost to reach COMPLETE on its own.
