# WP2 Gate — Framework Request/Response Model

Status: **SPEC.** Toolchain `dev-2026-07a` / commit `819fdc7`. Base
`origin/main` at `687d045` (pre-WP2 normative amendment merged).

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
