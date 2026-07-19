# WP1 Gate — Compiling Public API Skeleton

Status: **COMPLETE — LOCAL PASS.** Toolchain `dev-2026-07a` / commit `819fdc7`.

## SPEC

### What WP1 is

WP1 creates a **compiling public API skeleton** of the approved Phase-1
surface. Its single claim is nominal: the exact Phase-1 names and signatures
can coexist and compile as one `web` package on the pinned Odin toolchain, and
they are reachable from an external package through the `uruquim` collection.

### What WP1 explicitly is not

**WP1 adds no HTTP behavior.** It is not a functional server. Every procedure
body is an inert stub. WP1 implements none of the following, each of which
belongs to a later work package:

| Deliberately absent in WP1 | Owning WP |
|---|---|
| request/response model, views, commit state | WP2 |
| in-memory test transport, `test_request` | WP3 |
| route registration table, dispatch, 404, 405 + `Allow` | WP4 |
| extractor parsing and standardized failure responses | WP5 |
| JSON marshal, error envelope, codes, error rendering | WP6 |
| body binding, request arena, 4 MiB cap | WP7 |
| sockets, transport boundary, `odin-http` adapter | WP8 |
| transport conformance suite | WP9 |
| examples and documentation parity | WP10 |

WP1 also does not design the private typed error-report path (ADR-011); that
implementation belongs to its own future work package.

### Symbol map

Phase column: the phase that owns the symbol. Status column: `RATIFIED
(shape)` means a compiling prototype already demonstrated the shape before
WP1; `NOMINAL (WP1)` means WP1 is the first compiling evidence of the exact
public name and signature. **No symbol is behaviourally frozen by WP1** — the
freeze discipline requires a behavior test from the owning WP
(`knowledge-base/03-development-phases.md`, "Freeze discipline").

| Symbol | Spec section | Experiment evidence | Phase | Status after WP1 |
|---|---|---|---|---|
| `App` | 01 §Application; ADR-001 | exp-01 | 1 | RATIFIED (shape) |
| `Context` | 01 §Context Model (default, non-parametric) | exp-01, exp-09 | 1 | NOMINAL (WP1) |
| `Handler` | 01 §Handlers; ADR-011 | exp-01, exp-10 | 1 | RATIFIED (shape) |
| `Status` | 01 §Response helpers (`json(ctx, status, …)`) | exp-02 | 1 | NOMINAL (WP1) |
| `app` | 01 §Application; ADR-001 | exp-01 | 1 | RATIFIED (shape) |
| `bare` | 01 §Application | none (listed provisional in 03) | 1 | NOMINAL (WP1) |
| `destroy` | 01 §Application; ADR-001 | exp-01 | 1 | RATIFIED (shape) |
| `get` | 01 §Routing | exp-01 | 1 | RATIFIED (shape) |
| `post` | 01 §Routing | exp-01 | 1 | RATIFIED (shape) |
| `put` | 01 §Routing | none | 1 | NOMINAL (WP1) |
| `patch` | 01 §Routing | none | 1 | NOMINAL (WP1) |
| `delete` | 01 §Routing | none | 1 | NOMINAL (WP1) |
| `path` | 01 §Extractors (path family) | none | 1 | NOMINAL (WP1) |
| `path_int` | 01 §Canonical Extractor Control Flow; ADR-002 | exp-04 | 1 | RATIFIED (shape) |
| `query` | 01 §Canonical query extractor family | none | 1 | NOMINAL (WP1) |
| `query_int` | 01 §Canonical query extractor family; ADR-002 | exp-04 | 1 | RATIFIED (shape) |
| `query_int_or` | 01 §Canonical query extractor family | none | 1 | NOMINAL (WP1) |
| `body` | 01 §Extractors (destination-filling); ADR-006 | exp-03 | 1 | RATIFIED (shape) |
| `json` | 01 §Response helpers; ADR-003 | exp-02 | 1 | RATIFIED (shape) |
| `ok` | 01 §Response helpers (exact shorthand) | exp-02 | 1 | RATIFIED (shape) |
| `created` | 01 §Response helpers (exact shorthand) | exp-02 | 1 | RATIFIED (shape) |
| `text` | 01 §Response helpers | none | 1 | NOMINAL (WP1) |
| `no_content` | 01 §Response helpers | none | 1 | NOMINAL (WP1) |
| `bad_request` | 01 §Response helpers; §Standardized Error Responses | none | 1 | NOMINAL (WP1) |
| `unauthorized` | 01 §Response helpers; §Standardized Error Responses | none | 1 | NOMINAL (WP1) |
| `forbidden` | 01 §Response helpers; §Standardized Error Responses | none | 1 | NOMINAL (WP1) |
| `not_found` | 01 §Response helpers; §Standardized Error Responses | none | 1 | NOMINAL (WP1) |
| `internal_error` | 01 §Response helpers; §Standardized Error Responses | none | 1 | NOMINAL (WP1) |
| `serve` | 01 §Serving | exp-01 | 1 | NOMINAL (WP1) |

Total exported surface: **4 types + 25 procedures = 29 symbols.**

### Two exports outside the target vocabulary list

The WP1 prompt's target vocabulary lists names, not the types those names
require. Two exported types are structurally unavoidable and are recorded here
so the inventory stays honest:

- **`App`** — the declared return type of `app()` and `bare()` and the
  pointee of every `^App` parameter. `web.app()` cannot exist without it.
  Ratified by exp-01 and named in `knowledge-base/01-architecture-spec.md`
  §Application.
- **`Status`** — the second parameter of the ratified `json(ctx, status,
  value)` and `text(ctx, status, s)` signatures. `docs/ai-context.md` already
  uses `web.json(ctx, .Accepted, payload)` and `web.text(ctx, .OK, "pong")`
  as Phase-1 forms, so the enum is required for those documented calls to
  compile. Its members are restricted to the statuses the Phase-1 public
  documentation and the Phase-1 default-policy contract actually name.

Neither is a new concept, an alias, or a second way to perform a canonical
task. No other type is exported.

### Deliberate non-exports

`Request`, `Response`, `Params`, `Route_Info`, `Method`, `Error_Code`, the
error envelope type, and `Transport` are **not** exported by WP1. They belong
to WP2/WP4/WP6/WP8. `Context_Internal` and `App_Internal` exist but are
`@(private)`; a compiler probe confirms an external package cannot name them.

### File placement note

`web/errors.odin` carries the five error-response helpers
(`bad_request`/`unauthorized`/`forbidden`/`not_found`/`internal_error`) and
`web/respond.odin` carries the success responders plus `Status`. The
architecture spec's reference tree lists "errors" under `respond.odin` and
"error envelope + codes" under `errors.odin`; WP1 owns no envelope or code
list (WP6 does), so grouping the error responders in `errors.odin` keeps both
files meaningful and leaves `errors.odin` as the natural home for the WP6
envelope. This is a file-organization choice only: **no exported name,
signature, or semantic differs either way**, and WP6 may move them without a
public API change.

### Guardrails applied (planning/15)

- **G-01 — one public name per operation.** The inventory contains no alias,
  spelling variant, or convenience family. `ok`/`created` are the sole
  delegations and are exact fixed-status one-liners over `json`, which
  planning/15 G-01 permits explicitly.
- **G-02 — framework types stop at the HTTP boundary.** `^Context` appears
  only on handler and extractor signatures. WP1 ships no domain code and adds
  no framework type to any.
- **G-03 — Context is not an extension bag.** `Context` exposes one field of a
  private type. No `user_data`, `locals`, `values`, `map[string]any`,
  `map[any]any`, `any`, or public `rawptr` exists anywhere in `web/`.
- **G-06 — transport names stay behind the boundary.** `web/` imports nothing
  and mentions no backend name. The static scan is scoped to `web/` and, when
  it exists, `examples/`; it never scans `knowledge-base/`, `planning/`, or
  `docs/`, so internal architecture documentation is not flagged.
- **G-09 — public growth carries evidence in the same change.** Each symbol
  above carries its owning phase, spec clause, non-synonym argument, and
  compiling evidence on `819fdc7`. Behavior tests are explicitly deferred to
  the owning WP and no symbol is advertised as shipped.

### Compiler evidence gathered before implementation

Signature probes were run in a scratch directory outside the repository, on
`dev-2026-07-nightly:819fdc7`. Two results shaped the implementation:

1. `odin check web` on a non-`main` package requires `-no-entry-point`;
   without it the compiler reports `Undefined entry point procedure 'main'`.
   The gate therefore passes that flag.
2. A test package named `c` collides with `core:c`
   (`Duplicate declaration of 'package c'`). The contract package is named
   `wp1_public_api`.

No proposed signature was refuted.

## TESTS FIRST

The contract was written and run **before** `web/` existed.

- `tests/wp1-public-api/contract_test.odin` — an external consumer package
  that imports `uruquim:web` and references every Phase-1 symbol by exact
  public name, in both canonical extractor shapes and with by-value response
  payloads. It never executes a stub.
- `build/check_public_api.sh` — static repository assertions: exact file set,
  exact exported-symbol inventory, later-phase symbol rejection, dynamic/
  untyped storage rejection, canonical handler shape, transport-leak scan, and
  dependency policy.
- `build/check.sh` — extended, as `build/README.md` anticipated, to run the
  package check, the compile contract, and the static assertions after the
  disposable suite.

### RED evidence (no `web/` package present)

```text
$ ls web
ls: cannot access 'web': No such file or directory

$ odin check /tmp/uruquim-opus-wp1/web -collection:uruquim=/tmp/uruquim-opus-wp1 -no-entry-point
ERROR: `/tmp/uruquim-odin-toolchain/odin check` takes a package/directory as its first argument.
The file '/tmp/uruquim-opus-wp1/web' was not found.
exit=1

$ odin test /tmp/uruquim-opus-wp1/tests/wp1-public-api -collection:uruquim=/tmp/uruquim-opus-wp1
/tmp/uruquim-opus-wp1/tests/wp1-public-api/contract_test.odin(14:1) Syntax Error: Path does not exist: uruquim:web
	import web "uruquim:web"
	^

$ bash build/check_public_api.sh
FAIL: web/ does not exist; WP1 has not created the public package
exit=1

$ URUQUIM_ODIN_BIN=/tmp/uruquim-odin-toolchain/odin bash build/check.sh
...
PASS=10 FAIL=0 SKIP=0
--- WP1 public API package (odin check) ---
ERROR: ... The file '/tmp/uruquim-opus-wp1/web' was not found.
gate exit=1
```

The disposable suite already reported `PASS=10 FAIL=0 SKIP=0` in the same run,
so the RED state was caused only by the missing WP1 package.

### GREEN evidence

```text
$ URUQUIM_ODIN_BIN=/tmp/uruquim-odin-toolchain/odin bash build/check.sh
toolchain version: dev-2026-07-nightly:819fdc7
toolchain commit: 819fdc7
...
PASS=10 FAIL=0 SKIP=0
--- WP1 public API package (odin check) ---
--- WP1 public API compile contract (odin test) ---
Finished 1 test in 217.355µs. The test was successful.
--- WP1 public API anti-accretion contract ---
public API contract: web/ file set matches WP1
public API contract: exported surface is exactly 29 Phase-1 symbols
public API contract: no later-phase symbol, dynamic storage, or backend leak
PASS: WP1 public API anti-accretion contract
gate exit=0

$ URUQUIM_ODIN_BIN=/tmp/uruquim-odin-toolchain/odin bash build/check_test.sh
PASS: WP0 toolchain and repository baseline
```

### The assertions were proven to bite

A checker that never fails proves nothing, so each assertion was driven to RED
by a temporary local edit that was reverted immediately (`git status` clean
afterwards; no probe file remains):

| Injected violation | Assertion result |
|---|---|
| extra export `respond` | `FAIL: web/ exports symbols outside the ratified Phase-1 surface` |
| Phase-2 export `use` | `FAIL: web/ exports symbols outside the ratified Phase-1 surface` |
| `user_data: map[string]any` on `Context` | `FAIL: web/ declares an untyped request-local storage field` |
| `serve(..., t: ^Transport)` | `FAIL: transport-shaped name matching /\bTransport\b/ appears in an exported declaration` |
| `import http "shared:odin-http"` | `FAIL: backend identifier matching /odin[-_]http/ reached the public package or examples` |
| extra file `web/middleware.odin` | `FAIL: web/ file set does not match the WP1 contract` |
| `Handler :: proc(ctx) -> Handler_Error` | `FAIL: web/ uses a forbidden construct matching /Handler_Error/` |

Two false positives were found and fixed while building the checker, both of
which planning/15's false-positive rules require avoiding:

1. the comment in `web/context.odin` that *prohibits* `map[string]any` was
   reported as `map[string]any`. The scans now read code, not comments.
2. the HTTP status `Internal_Server_Error` was reported as a `Server`
   transport leak. The transport-type patterns are now word-bounded.

## REVIEW

Audit of the diff against `planning/15-public-api-anti-accretion-guardrails.md`.

**Exact exported-symbol inventory (29).** Types: `App`, `Context`, `Handler`,
`Status`. Procedures: `app`, `bare`, `destroy`; `get`, `post`, `put`, `patch`,
`delete`; `path`, `path_int`, `query`, `query_int`, `query_int_or`, `body`;
`json`, `ok`, `created`, `text`, `no_content`; `bad_request`, `unauthorized`,
`forbidden`, `not_found`, `internal_error`; `serve`. Machine-enforced by
`build/check_public_api.sh`, which fails on any addition or removal.

**No synonyms.** There is one name per operation. `ok` and `created` are the
only delegations; each is a single-line exact fixed-status call to `json` with
no extra behavior, which G-01 permits by name. No `respond`, `bind`,
`parse_body`, `decode_json`, `send`, or `write` exists. No second handler
shape exists.

**Context has no dynamic/untyped storage.** `Context` has exactly one field,
`private`, of the package-private type `Context_Internal`. A compiler probe
confirms an external package cannot name that type
(`'Context_Internal' is not exported by 'web'`). `any`, `rawptr`,
`map[string]any`, `map[any]any`, `user_data`, `locals`, and `values` appear
nowhere in `web/` — not even privately.

**No transport/backend type is public.** `web/` imports nothing at all. No
exported declaration mentions `Transport`, `Socket`, `TCP`, `Connection`,
`Server`, `net.`, or `http.`. `serve` takes `(^App, int)` and no transport
handle. The single mention of the future official `core:net/http` package is a
comment in `web/serve.odin` explaining why transport selection is internal —
which G-06 explicitly protects as non-leakage.

**No framework type was added to domain code.** WP1 ships no domain code.
`^Context` appears only on handler and extractor signatures. In the compile
contract, `User` and `Create_User` are plain application structs that do not
reference any `web` type.

**No request/response lifetime or commit behavior is falsely promised.**
`Context` deliberately does **not** declare `request`, `response`, `params`,
or `route`; declaring them would advertise a view-lifetime and single-commit
contract that WP2 owns. No stub sets a status, writes a body, or touches a
commit flag. `path_int`, `query_int`, and `query_int_or` return `ok = false`
without writing a response, which is honest — a WP1 handler that follows the
canonical `if !ok { return }` form simply returns. `query_int_or` notably does
**not** return `default_value`: WP1 cannot distinguish "absent" from
"malformed", and returning the default would claim the absence semantics that
WP5 owns. Every file states which work package delivers its behavior.

**No Phase-2+ surface exists.** `use`, `next`, `router`, `group`, `mount`,
`state`, `app_with_state`, `header`, `bearer_token`, `serve_with`,
`serve_transport`, `app_init`, `test_request`, `redirect`, `conflict`,
`bytes`, `logger`, `recovery`, `request_id`, and `cors` are all absent and are
individually rejected by the contract. `web/` has no subdirectories, so no
`internal/`, `middleware/`, or `testing/` package started early.

**No unrelated file was modified.** Changes are confined to: the new `web/`
package, the new compile contract, the new static contract, the two build
files that had to learn about them (`build/check.sh`, `build/README.md` — the
latter had explicitly reserved this extension for WP1), the three status/
documentation surfaces required by the cross-phase parity invariant
(`README.md`, `docs/ai-context.md`, `docs/canonical-patterns.md`), and this
gate record. `knowledge-base/**` is untouched. `experiments/**`,
`ops/**`, `build/check_test.sh`, and the pre-push hook are untouched.

## DOCUMENTATION

- `README.md`, `docs/ai-context.md`, and `docs/canonical-patterns.md` now
  state that WP1 delivered a **compiling public API skeleton, never a
  functional server**, and that `web.serve` returns immediately.
- **Nominally compiler-ratified by WP1** — first compiling evidence of the
  exact public name and signature: `Context`, `Status`, `bare`, `put`,
  `patch`, `delete`, `path`, `query`, `query_int_or`, `text`, `no_content`,
  `bad_request`, `unauthorized`, `forbidden`, `not_found`, `internal_error`,
  `serve`. This closes the "PROVISIONAL UNTIL WP1/OWNER WP" column of
  `knowledge-base/03-development-phases.md` for its *nominal* half only.
  **No symbol is behaviourally frozen**: the freeze discipline additionally
  requires a behavior test from the owning work package, and WP1 has none.
- One documented clarification was required and added to `docs/ai-context.md`:
  the status argument of `json`/`text` has type `web.Status` and is always
  written as an inferred enum member, never a bare integer. This is a
  clarification of an already-ratified signature, not a new decision — the
  documented Phase-1 calls `web.json(ctx, .Accepted, payload)` and
  `web.text(ctx, .OK, "pong")` already required the type to exist.
- **No PROPOSED SPEC AMENDMENT is needed.** No governing clause was
  contradicted by the compiler, and no normative form changed. The canonical
  patterns are unchanged; they are simply now compiled against real code.

## GATE

| Requirement | Result |
|---|---|
| pinned-toolchain command (`build/check.sh` via the tracked pre-push hook) | PASS, `toolchain commit: 819fdc7` |
| `build/check_test.sh` | `PASS: WP0 toolchain and repository baseline` |
| WP1 compile contract (`odin test tests/wp1-public-api`) | PASS, 1 test |
| WP1 anti-accretion contract | `PASS: WP1 public API anti-accretion contract` |
| disposable suite baseline | `PASS=10 FAIL=0 SKIP=0` — unchanged |
| `git diff --check` | clean |
| untracked binaries or temporary probes | none; `git status` clean |
| WP2 started? | **No.** No `web/request.odin`, `web/response.odin`, or `web/headers.odin` exists, and `Context` has no request/response field. |

Status: **COMPLETE.**

## GATE

Recorded on completion.
