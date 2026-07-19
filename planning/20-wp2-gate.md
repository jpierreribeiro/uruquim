# WP2 Gate — Framework Request/Response Model

Status: **COMPLETE — LOCAL PASS.** Toolchain `dev-2026-07a` / commit
`819fdc7`. Base `origin/main` at `687d045` (pre-WP2 normative amendment
merged). Surface checkpoint: **exactly 32 symbols**.

## SPEC

### What WP2 is

WP2 delivers the **framework-owned request/response model**: the public
`Request` view and its `Method` and `Header_View` vocabulary, and the
package-internal `Response` with its single-commit guard.

Its claims are exactly three:

1. a `Request` can carry method, path, query, headers and body as **views**
   over transport-owned storage, and those views are invalidated — silently —
   when that storage is reused;
2. an **explicit copy** with a chosen allocator is what makes request data
   survive, and it is the only thing that does;
3. a response can be committed **at most once**, and the second attempt changes
   nothing — provable by reading the stored status.

### What WP2 explicitly is not

**WP2 is not a functional server, and is not closer to being one than WP1
was.** There is no dispatch, no transport, and no way for an HTTP request to
reach a handler. `web.serve` still returns immediately. The model exists;
nothing fills it in yet.

| Deliberately absent in WP2 | Owning WP |
|---|---|
| in-memory test transport, `test_request` | WP3 |
| route table, dispatch, 404, 405 + `Allow` | WP4 |
| extractor parsing and standardized failure responses | WP5 |
| JSON marshal, error envelope, wiring `web.json`/`web.ok` onto the commit guard | WP6 |
| body binding, request arena (ADR-007), 4 MiB cap | WP7 |
| sockets, transport adapter, HTTP parsing, method token extraction | WP8 |
| transport conformance suite, header normalization | WP9 |
| `web.header` / header lookup, `bearer_token` | Phase 2 |
| `Params`, `Route_Info`, `ctx.params`, `ctx.route` | WP4 |
| `HEAD` / `OPTIONS` contracts | deferred until specified and tested |
| full allocator/lifetime audit, `docs/memory-model.md` | **Phase 4** |

### Symbol map — exactly three new public symbols (29 → 32)

| Symbol | Spec section | Evidence | Phase | Status after WP2 |
|---|---|---|---|---|
| `Method` | 01 §Request/Response ownership; planning/18 Part I | planning/18 item 7; WP2 conversion tests | 1 | RATIFIED (behavior) |
| `Header_View` | 01 §Request/Response ownership; planning/18 Part I | planning/18 items 9–11; WP2 probes | 1 | RATIFIED (shape) |
| `Request` | 01 §Request/Response ownership | exp-06; WP2 invalidation/copy tests | 1 | RATIFIED (behavior) |

Package-private, and named here so their absence from the public inventory is
deliberate rather than accidental: `Header_View_Internal`, `Header_Pair`,
`Response`, `response_commit`, `method_from_token`, `header_view_from_pairs`.

`Header_View` is documented as **encapsulated by contract**, never as "opaque":
Odin does not offer opacity, and claiming it would be false.

### Normative view rule (planning/15 G-05)

> Request-derived strings, slices, headers, query values and body are
> **temporary views** over storage owned by the transport for the duration of
> one request. They are valid only during that request.
>
> To keep any of it, **copy it explicitly with an appropriate allocator**.
> Background work receives owned application data — never a `Request`, never a
> view, and never a `^Context`.

The failure mode is silent. A retained view keeps its length and keeps
pointing at live memory; it simply reads different bytes once the buffer is
reused. `web/wp2_internal_test.odin` pins this: after reuse, a path view that
read `"/users"` reads `"######"`, while a `strings.clone` of the same view
still reads `"/users"`.

### Response commit — scope of the guarantee (ADR-008, as amended)

The guard ensures the **supported `web.*` response paths** do not overwrite a
response that was already produced. It is **not a security boundary**:
application and framework share one program, `@(private)` hides a
declaration's *name* rather than the reachability of fields through a public
field, and per-field privacy is a syntax error in Odin. Code that deliberately
assigns to internal fields bypasses the guard, and that is accepted.

**No opaque handle, side table, or other indirection was built**, in either
direction — that approach is REJECTED as useless complexity (planning/18 P-3).
`tests/wp2-public-surface/probes/internal_slot_is_reachable.odin` is a
POSITIVE probe: it asserts that `r.headers.private.pairs` still compiles from
outside the package, so the documentation can never drift into claiming a
barrier the language does not provide.

### Unknown method — strict limit

A token outside the Phase-1 set converts to `.UNKNOWN`. **That is the entire
behavior.** WP2 does not reject unknown methods at the transport, and does not
decide any HTTP status: the transport must not decide responses, or the
decision would be duplicated into every adapter.

HTTP methods are extensible and case-sensitive (RFC 9110 §9.1, which also
distinguishes 501 "not implemented" from 405 "not allowed on this route"), and
the IANA HTTP Method Registry contains methods such as `PROPFIND`. Treating
every method outside the enum as malformed would therefore be incorrect. With
the ratified minimum set, `"HEAD"` converts to `.UNKNOWN` — correct, and
already ratified.

- <https://datatracker.ietf.org/doc/html/rfc9110#section-9.1>
- <https://www.iana.org/assignments/http-methods/http-methods.xhtml>

### HTTP status — precise limit

WP2 implements **no** automatic 404, 405 or 501. It stores a status in the
internal `Response` for one reason only: it is what makes "the second commit
did not replace the first" observable. `build/check_public_api.sh` §8f fails
the gate if `404`, `405`, `501`, `Not_Found` or `Method_Not_Allowed` appears in
the code of the WP2 model files.

### The allocator audit remains Phase 4 — declared gap, not an oversight

`docs/memory-model.md` is **untouched by WP2** and remains the Phase-4
placeholder (decision recorded in planning/18, P-7, option (a)).

WP2 states a *rule* — copy to persist — and pins it with tests. It does **not**
perform the allocator and lifetime audit: the internal allocation classes
(app-, router-, request-lifetime, scratch), the ADR-007 request arena, and the
Advanced API allocator configuration are Phase-4 work, and WP7 owns the request
arena itself. WP2 allocates nothing: `header_view_from_pairs` copies nothing,
`response_commit` copies nothing, and the only allocations in the WP2 tests are
made and freed by those tests.

The absence of content in `docs/memory-model.md` is therefore a **declared
gap**, recorded here so it cannot later be mistaken for something WP2 forgot.

### Pre-WP2 factual corrections — confirmed, not redone

The "unreachable from application code" claims in `web/app.odin` and
`web/context.odin` were corrected by the merged pre-WP2 normative PR (P-5/P-6).
WP2 **confirmed** them and did not touch them: `git grep "unreachable from
application code" -- web/` returns nothing, and both comments now state that
the types are encapsulated by contract, cannot be NAMED from outside, and are
not a safety guarantee.

### Freeze status

WP2 does not freeze the framework. `Method`, `Request` and `Header_View` now
have behavior tests, which is what the freeze discipline requires of the owning
work package (`knowledge-base/03-development-phases.md`). The internal
`Response` shape is explicitly unfrozen: WP6 adds rendering and WP7 the request
arena, and both may reshape it, since nothing internal is public API.

## TESTS FIRST — preserved RED evidence

Commit `6850a1c` raised `build/check_public_api.sh` to 32 and added every WP2
test and probe **before** the model existed. The checker was held to the same
discipline as the code, in a separate commit, exactly as planning/18 P-4
requires.

At `6850a1c` the gate failed, and failed for the intended reason:

```text
build/check_public_api.sh
  FAIL: web/ file set does not match the Phase-1 contract
        (expected headers.odin, request.odin, response.odin — absent)
  exit=1

odin check web
  web/wp2_internal_test.odin(42:46) Error: Undeclared name: Header_Pair
  web/wp2_internal_test.odin(42:62) Error: Undeclared name: Request
  web/wp2_internal_test.odin(231:26) Error: Undeclared name: method_from_token
  exit=1

odin test tests/wp2-public-surface
  contract_test.odin(27:5)  Error: 'web.Method' is not a type
  contract_test.odin(27:19) Error: Invalid type 'invalid type' for implicit
                                   selector expression '.GET'
  exit=1

build/check.sh
  GATE_EXIT=1
```

The negative probe is worth recording separately, because it shows why
`build/check.sh` matches the exact diagnostic instead of merely requiring a
non-zero exit. In the RED state the probe failed with

```text
'Header_Pair' is not declared by 'web'
```

and only in the GREEN state does it fail with the diagnostic the contract
actually means:

```text
'Header_Pair' is not exported by 'web'
```

"Absent" and "present but private" are different facts. A probe that accepted
any compile failure would have passed in both states and proved nothing.

## MINIMAL IMPLEMENTATION

Three files, as planned: `web/request.odin`, `web/response.odin`,
`web/headers.odin`. `web/context.odin` was extended only to bind the model to
the `Context` — `request` in public, response state in the private slot — and
no further.

Not implemented, deliberately: dispatch, route table, test transport, extractor
parsing, JSON marshal, error envelope, body binding, the 4 MiB cap, sockets,
transport adapter, and automatic status decisions. `odin-http` is not imported;
`web/` still imports only `core:`.

`response_commit` has **no public caller**. It is exercised only by the WP2
tests; wiring `web.json`/`web.ok` onto it is WP6.

## REVIEW — audited against the diff

| Item | Result |
|---|---|
| exported inventory is exactly 32 | PASS — 29 + `Method`, `Request`, `Header_View`; enforced in both directions |
| Context has no dynamic/untyped storage and no `response` field | PASS — checker §8d pins the exact field list; negative probe pins `ctx.response` |
| no public transport type; `Header_Pair` not exported | PASS — checker §6 and two negative probes |
| no view escapes without a documented explicit copy | PASS — WP2 adds no accessor at all; the only views are `Request`'s own fields, and copy-to-persist is documented and test-pinned |
| the commit guard is tested on the internal primitive | PASS — no responder call appears in `web/wp2_internal_test.odin` |
| no automatic 404/405/501 | PASS — checker §8f scans the model's code |
| no Phase-2+ surface | PASS — checker §3, extended with `Response`, `Header_Pair`, `Params`, `Route_Info`, `method_raw` |
| no unrelated file modified | PASS — every changed file is WP2's model, its tests, its gate, or the two mandated docs |
| `docs/memory-model.md` untouched | PASS — zero diff |
| WP3 not started | PASS — no `web/testing/`, no `test_request`, no transport |

## Findings

### 1. In-package tests cost every application 41,592 bytes — accepted, with a proposed follow-up

`Response`, `response_commit`, `method_from_token` and `Header_Pair` are
package-private, so testing them directly requires an `@(test)` procedure
compiled as part of `web`. Every route out of that was probed on `819fdc7` and
closed:

| Attempt | Result |
|---|---|
| test file without `#+private` | its declarations ARE exported by `web` (external package names one, exit 0) |
| `#+private` test file | privacy correct, tests still discovered — **chosen** |
| `@(test) proc()` without `core:testing` | rejected: "Testing procedures must have a signature type of proc(^testing.T)" |
| `when ODIN_TEST { import … }` | rejected: "Cannot use 'import' within a 'when' statement" |
| `#+build test` / `#+build ODIN_TEST` | rejected: build tags are platform-only |
| `#+build ignore` | excluded from `odin build` AND from `odin test` — "No tests to run" |
| external test package | cannot name package-private declarations |

The cost is specific to `core:testing`, not to `core:` imports generally, and
was measured against the real package with a minimal consumer application:

```text
core:strings   +248 bytes
core:mem       +552 bytes
core:testing   +41,592 bytes   (42,624 -> 84,216)
```

This conflicts with the "low hidden cost" mandate of
`knowledge-base/02-odin-idioms-guidelines.md`, and Odin's own `core:` ships no
`_test.odin` inside its packages. WP2 accepts it rather than changing ratified
architecture on its own authority, and contains it: the checker now requires
`#+private` on every test file under `web/` and forbids `core:testing` in any
production file, so the surface cannot leak through this door.

**PROPOSED FOLLOW-UP, for human decision — not applied here.** Move the
internal-only machinery to `web/internal/…`, exported from that internal
package and therefore still absent from `uruquim:web`'s public surface, and
test it from an external package. `core:testing` then leaves the shipped
package entirely. This is already the direction the plan takes: KB02 states
that internals live under `web/internal/`, WP3 introduces `web/testing/`, and
WP4 introduces `web/internal/dispatch/`. Doing it inside WP2 would have meant
contradicting WP2's ratified file list and relaxing the checker's
no-subdirectory rule, which is not this work package's call.

### 2. `web.delete` shadows the builtin `delete` inside the package

The ratified route-registration name `delete` shadows Odin's builtin `delete`
for all code inside package `web`; the compiler reports
`Cannot assign value 'buf' of type '[]u8' to '^App'`. In-package code must use
`delete_slice` / `delete_string`. Application code is unaffected — outside the
package, `delete` is the builtin, as the documented examples show. Recorded so
WP4 onward does not rediscover it as a mystery.

### 3. Two latent defects in the WP1 gate, fixed here

- `comm` compared C-sorted inventories under the ambient locale. Any added or
  lost symbol aborted with `comm: input is not in sorted order` instead of
  naming it. Fail-safe under `set -e`, but the diagnostic is the point of that
  section.
- A negative probe's compile output was captured by plain assignment under
  `set -e`, which aborted the run before the diagnostic could be matched.

### 4. The checker's export scan now understands `#+private`

Files whose first directive is `#+private` export nothing — verified on the
pinned toolchain — so they are excluded from the export inventory. This
narrows the scan to match the compiler; it never widens what may be exported.
The mutation tests below confirm the assertions still bite.

## GATE

Toolchain: `odin version dev-2026-07a:819fdc7`, run through the documented
command (`build/check.sh`, invoked by the tracked `.githooks/pre-push` hook).

```text
PASS=10 FAIL=0 SKIP=0                      (throwaway prototype baseline)
WP1 public API compile contract             1 test  — pass
WP2 request/response model, internal       11 tests — pass
WP2 public surface contract                 5 tests — pass
WP2 probes                                  4 probes — pass
public API contract: exported surface is exactly 32 Phase-1 symbols
PASS: Phase-1 public API anti-accretion contract (WP1 + WP2)
build/check.sh          exit 0
build/check_test.sh     exit 0
git diff --check        exit 0, no binaries, no untracked probes
```

The raised checker was mutation-tested to prove it is not vacuous. Each
mutation was applied to a scratch copy and reverted:

| Mutation | Caught by |
|---|---|
| drop `#+private` from the test file | test file would export its declarations |
| add a 33rd exported symbol | inventory names `Extra_Public` |
| export `Response` | inventory names `Response` |
| rename `.GET` to `.Get` | Method is not the ratified set |
| announce `pairs` publicly on `Header_View` | Header_View must expose only the private slot |
| add a public `response` field to `Context` | Context field list |
| return `.Not_Found` from the model | WP2 model decides an HTTP status |
| add a `header` lookup | exports outside the ratified surface |

**WP3 has not been started.**

Status: **COMPLETE — LOCAL PASS**, pending human review of the PR and of
finding 1.
