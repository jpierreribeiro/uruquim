# WP1 Gate — Compiling Public API Skeleton

Status: **IN PROGRESS.** Toolchain `dev-2026-07a` / commit `819fdc7`.

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

Recorded in the GATE section below.

## GATE

Recorded on completion.
