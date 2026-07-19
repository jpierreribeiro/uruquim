# Phase 1 — Freeze Manifest

**Status: FROZEN pending human acceptance.** The contracts below are protected
by `build/check_phase1_freeze.sh`, which runs as the last step of
`build/check.sh`. Acceptance itself is a human act; see §12.

This is the normative record of what Phase 1 froze. It is not a report and not a
changelog: it is the document a future contributor is measured against when they
propose changing the public surface. The freeze gate reads this file on every
run and resolves every evidence citation in it against the working tree, so it
cannot rot quietly into an unverifiable claim.

## What "frozen" means

Freezing is a narrow claim, and the narrowness is the point:

* the Phase-1 contracts listed here are protected by an executable gate;
* changing one requires a spec amendment, not a snapshot refresh;
* internals stay replaceable — the linear route table, the request arena, the
  vendored backend and the transport boundary are all implementation and may be
  rewritten as long as the observable contract below is unchanged;
* a semantic version, a tag and a release remain human decisions and are
  explicitly NOT granted by this document.

Freezing is **not** a claim that the framework is production-ready, that the API
is stable forever, or that anything absent from this document works. §10 lists
what Phase 1 knowingly does not do.

### How evidence is cited

Every claim below cites evidence as `path/to/file::identifier`. The gate splits
each citation, checks that the file exists, and checks that the identifier
occurs in it. A renamed test or a deleted fixture therefore fails the gate
rather than silently degrading into a claim nobody can check.

---

## 1. Toolchain and base commit

| Field | Value |
|---|---|
| Odin toolchain | `dev-2026-07-nightly:819fdc7` (pinned, `odin-version.txt`) |
| Base | `origin/main` @ `3962a48` — WP10 merged (PR #20) |
| Gate command | `env -u ODIN_ROOT URUQUIM_ODIN_BIN=<odin> bash build/check.sh` |
| Gate result | `PASS=10 FAIL=0 SKIP=0` |
| Frozen ledgers | 32 application + 2 test-support = 34 exported |
| Signature snapshot | `build/phase1-public-signatures.txt` (34 lines) |
| Dependency snapshot | `build/phase1-direct-dependencies.txt` (15 lines) |

The compiler is the source of truth for the surface. The snapshots are generated
by `odin doc web -collection:uruquim=. -short` (procedures) and `odin doc web`
(expanded type bodies), normalized only by removing the unstable
`/* file!offset */` position markers. Names, argument lists, results, genericity,
field names, enum members and enum backing types are preserved verbatim, because
those are the contract.

---

## 2. Frozen application ledger — 32 symbols

**Types (7):** `App`, `Context`, `Handler`, `Header_View`, `Method`, `Request`,
`Status`.

**Procedures (25):** `app`, `bad_request`, `bare`, `body`, `created`, `delete`,
`destroy`, `forbidden`, `get`, `internal_error`, `json`, `no_content`,
`not_found`, `ok`, `patch`, `path`, `path_int`, `post`, `put`, `query`,
`query_int`, `query_int_or`, `serve`, `text`, `unauthorized`.

## 3. Frozen test-support ledger — 2 symbols

`Recorded_Response`, `test_request`.

These are a separate ledger by `planning/public-api-guardrails.md` G-11: public,
documented and behavior-tested exactly like the application surface, but counted
apart from the frozen 32 and required to cost nothing in applications that never
call `test_request` (§9, G-11).

## 4. Frozen types — fields, backing types, members

Reproduced verbatim from the compiler; `build/check_phase1_freeze.sh` asserts
each of these as a named expectation, in addition to diffing the whole snapshot.
The named assertions are redundant on purpose: if someone regenerates the
snapshot to make a change "pass", the named assertions still fail, because they
encode the decision rather than the current state.

```
App               :: struct {private: App_Internal}
Context           :: struct {request: Request, private: Context_Internal}
Handler           :: proc(ctx: ^Context)
Header_View       :: struct {private: Header_View_Internal}
Method            :: enum u8 {UNKNOWN, GET, POST, PUT, PATCH, DELETE}
Request           :: struct {method: Method, path: string, query: string, headers: Header_View, body: []u8}
Status            :: enum int {OK = 200, Created = 201, Accepted = 202, No_Content = 204,
                               Bad_Request = 400, Unauthorized = 401, Forbidden = 403,
                               Not_Found = 404, Method_Not_Allowed = 405,
                               Internal_Server_Error = 500}
Recorded_Response :: struct {status: Status, body: string}
```

Frozen alongside the shapes:

* `Method` is backed by `u8` and has exactly six members, with `UNKNOWN` as the
  zero value. Evidence: `tests/wp2-public-surface/contract_test.odin::wp2_method_members_are_uppercase`.
* `Status` is backed by `int`, the member values ARE the HTTP codes, and there
  are exactly ten. **There is no public 413.** The 4 MiB body cap is real and
  emits 413 on the wire, but it is a private HTTP behavior of the transport and
  adding a `Status` member for it is a gate failure. Evidence:
  `build/check_public_api.sh::public 413 Status member`.
* `Handler` is the only handler shape. There is no second form, no error-returning
  variant and no context-plus-state variant. Evidence:
  `tests/wp2-public-surface/contract_test.odin::wp2_handler_signature_is_unchanged`.
* `Context` exposes `request` and nothing else. There is no public `response`,
  no `params`, no `route`, no `user_data`, no `locals`. Evidence:
  `tests/wp2-public-surface/probes/context_has_no_response.odin::web.Context`.
* `Header_View` is opaque and carries **no public lookup**. Phase 1 ships no
  `web.header` and no `web.bearer_token`. Evidence:
  `tests/wp2-public-surface/probes/header_view_internal_not_exported.odin::Header_View_Internal`.
* No exported procedure carries `#optional_ok`. Dropping `ok` from a
  value-producing extractor is a compile error (ADR-002). Evidence:
  `tests/wp5-public-surface/probes/discard_path_int_ok.odin::path_int`.
* Genericity is contract: `body` is destination-filling (`dst: ^$T -> bool`);
  `json`, `ok` and `created` take their payload **by value** (`$T`). A pointer
  payload is not part of the contract. Evidence:
  `tests/wp7-public-surface/contract_test.odin::wp7_signature_is_the_canonical_destination_filling_shape`.

---

## 5. Evidence matrix — 34 symbols

Every row was produced by reading the cited file. `Compile` proves the shape
compiles at a call site; `Behavior` proves what it does at run time; `Docs`
points at the canonical teaching material. A signature without behavior evidence
would not be frozen — all 34 have both.

Ledger key: **A** = application, **T** = test-support.

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `App` | A | WP1/WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_an_app_with_no_routes_allocates_nothing` | `docs/ai-context.md::App` | owns route table + cloned patterns; by value, destroyed once |
| `Context` | A | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_context_carries_the_request` | `tests/wp2-internal/wp2_internal_test.odin::wp2_context_carries_an_uncommitted_response` | `docs/quick-start.md::Context` | holds private response + arena; no public response |
| `Handler` | A | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_handler_signature_is_unchanged` | `tests/wp4-public-surface/contract_test.odin::wp4_registered_route_is_reached_exactly_once` | `docs/ai-context.md::Handler` | plain proc value, returns nothing |
| `Header_View` | A | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_request_exposes_the_ratified_fields` | `tests/wp2-internal/wp2_internal_test.odin::wp2_header_view_wraps_pairs_without_copying` | `docs/canonical-patterns.md::Header_View` | non-owning alias; no copy, no lookup |
| `Method` | A | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_method_members_are_uppercase` | `tests/wp2-internal/wp2_internal_test.odin::wp2_unsupported_method_tokens_convert_to_unknown` | `docs/ai-context.md::Method` | value enum, no allocation |
| `Request` | A | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_request_exposes_the_ratified_fields` | `tests/wp2-internal/wp2_internal_test.odin::wp2_buffer_reuse_invalidates_retained_views` | `docs/canonical-patterns.md::lifetime` | all fields are views into transport memory |
| `Status` | A | WP6 | `tests/wp9-public-surface/contract_test.odin::wp9_public_surface_is_unchanged` | `tests/wp6-internal/wp6_internal_test.odin::wp6_json_preserves_an_arbitrary_status` | `docs/ai-context.md::Status` | value enum backed by the HTTP code |
| `app` | A | WP1/WP4 | `tests/wp9-public-surface/contract_test.odin::wp9_public_surface_is_unchanged` | `tests/wp4-public-surface/contract_test.odin::wp4_app_returns_404_for_an_unknown_path` | `examples/01-hello-world/main.odin::web.app` | returns owned App by value; installs default 404/405 |
| `bad_request` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_error_helpers_produce_the_ratified_envelopes` | `docs/errors.md::bad_request` | response owns the envelope body |
| `bare` | A | WP1/WP4 | `tests/wp9-public-surface/contract_test.odin::wp9_added_no_transport_surface` | `tests/wp4-internal/wp4_internal_test.odin::wp4_bare_injects_no_404` | `docs/errors.md::bare` | as `app`, but installs no default policy |
| `body` | A | WP7 | `tests/wp7-public-surface/contract_test.odin::wp7_signature_is_the_canonical_destination_filling_shape` | `tests/wp7-internal/wp7_internal_test.odin::wp7_decoded_data_lives_in_the_request_arena` | `docs/quick-start.md::web.body` | fills caller dst; nested data in the request arena |
| `created` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_created_is_byte_identical_to_json_created` | `examples/02-json-api/main.odin::web.created` | delegates to `json`; response owns the body |
| `delete` | A | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-public-surface/contract_test.odin::wp4_every_verb_registers` | `docs/canonical-patterns.md::web.delete` | App clones the pattern |
| `destroy` | A | WP3/WP4 | `tests/wp9-public-surface/contract_test.odin::wp9_public_surface_is_unchanged` | `tests/wp4-internal/wp4_internal_test.odin::wp4_destroy_releases_the_table_exactly_once` | `examples/01-hello-world/main.odin::web.destroy` | frees table, patterns, recorder; exactly once |
| `forbidden` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` | `docs/errors.md::forbidden` | response owns the envelope |
| `get` | A | WP4 | `tests/wp9-public-surface/contract_test.odin::wp9_public_surface_is_unchanged` | `tests/wp4-internal/wp4_internal_test.odin::wp4_static_route_matches_and_runs_handler_once` | `examples/01-hello-world/main.odin::web.get` | clones pattern into App storage |
| `internal_error` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp8-internal/wp8_internal_test.odin::wp8_uncommitted_response_is_finalized_to_500` | `docs/errors.md::internal_error` | static envelope, allocates nothing |
| `json` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_marshal_failure_leaves_no_partial_body` | `docs/canonical-patterns.md::web.json` | response OWNS the marshalled buffer |
| `no_content` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_no_content_is_empty_and_header_free` | `examples/02-json-api/main.odin::web.no_content` | allocates nothing |
| `not_found` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_not_found_escapes_the_resource_name` | `docs/errors.md::not_found` | composes and owns the envelope body |
| `ok` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_ok_is_byte_identical_to_json_ok` | `examples/03-route-params/main.odin::web.ok` | delegates to `json`; response owns the body |
| `patch` | A | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_allow_uses_the_canonical_method_order` | `examples/02-json-api/main.odin::web.patch` | clones pattern |
| `path` | A | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` | `tests/wp5-internal/wp5_internal_test.odin::wp5_path_value_is_a_view_over_the_request_path` | `examples/03-route-params/main.odin::web.path` | returns a VIEW; never responds |
| `path_int` | A | WP5 | `tests/wp5-public-surface/probes/discard_path_int_ok.odin::path_int` | `tests/wp5-internal/wp5_internal_test.odin::wp5_path_int_failure_commits_the_exact_envelope` | `docs/errors.md::invalid_path_parameter` | commits 400 on failure; no allocation on success |
| `post` | A | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops` | `examples/02-json-api/main.odin::web.post` | clones pattern |
| `put` | A | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-public-surface/contract_test.odin::wp4_methods_are_isolated_publicly` | `examples/02-json-api/main.odin::web.put` | clones pattern |
| `query` | A | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` | `tests/wp5-internal/wp5_internal_test.odin::wp5_query_does_not_decode_anything` | `examples/03-route-params/main.odin::web.query` | returns a VIEW; no decoding; never responds |
| `query_int` | A | WP5 | `tests/wp5-public-surface/probes/discard_query_int_ok.odin::query_int` | `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_present_but_invalid_commits_the_integer_envelope` | `docs/errors.md::invalid_query_parameter` | commits 400 on failure |
| `query_int_or` | A | WP5 | `tests/wp5-public-surface/probes/discard_query_int_or_ok.odin::query_int_or` | `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_or_never_substitutes_the_default_for_a_malformed_value` | `examples/03-route-params/main.odin::web.query_int_or` | default ONLY on absence; 400 on malformed |
| `serve` | A | WP8 | `tests/wp9-public-surface/contract_test.odin::wp9_added_no_transport_surface` | `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops` | `docs/quick-start.md::web.serve` | blocking; per-request arena torn down by the driver |
| `text` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-internal/wp6_internal_test.odin::wp6_text_copies_the_caller_buffer` | `examples/01-hello-world/main.odin::web.text` | COPIES the caller's string into response-owned memory |
| `unauthorized` | A | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` | `docs/errors.md::unauthorized` | response owns the envelope |
| `Recorded_Response` | T | WP3 | `tests/wp3-public-surface/probes/recorded_response_has_no_headers.odin::Recorded_Response` | `tests/wp3-public-surface/contract_test.odin::wp3_two_recorded_responses_survive_until_destroy` | `docs/canonical-patterns.md::Recorded_Response` | `body` is an App-owned copy, valid until `destroy` |
| `test_request` | T | WP3, amended WP14 | `tests/wp7-public-surface/contract_test.odin::wp7_test_request_signature_is_pinned` | `tests/wp14-public-surface/contract_test.odin::wp14_a_json_body_reaches_the_handler` | `docs/quick-start.md::web.test_request` | lazily allocates recorder state; results owned until `destroy`; `body` is borrowed for the call only |

### Evidence asymmetries recorded honestly

These are not gaps in the freeze — every symbol above has real behavior
evidence — but the audit found four places where coverage is thinner than the
surrounding rows, and a freeze manifest that hid them would be worth less:

1. **`Header_View` has no *public* behavior evidence, by design.** There is no
   public API to exercise: the type is opaque and Phase 1 ships no lookup. Its
   behavioral assertions run from inside `package web`. The "no public lookup"
   property is proven negatively, by compile probe.
2. **`Status` is proven on the wire for 6 of its 10 members** (200, 201, 204,
   400, 404, 405, via `tests/support/transport_conformance/semantic.odin::expect_status`).
   `Accepted` (202), `Unauthorized` (401) and `Forbidden` (403) are observed only
   as enum values in in-memory tests, never as an integer on a socket.
3. **`created`'s byte-identity test is weaker than `ok`'s.** `ok` is compared to
   `json` on status, body *and* header count; `created` is compared on body and
   status only. The delegation claim is proven for the body; header parity rests
   on `tests/wp6-public-surface/contract_test.odin::wp6_created_returns_201`.
4. **`unauthorized` and `forbidden` are proven in memory only.** Neither appears
   in the WP9 semantic matrix or the wire corpus, so neither has crossed a real
   socket in the suite.

These are recorded as accepted limitations (§10), not deferred obligations. None
of them changes a frozen signature or a frozen behavior; closing them adds test
coverage, which a later phase may do without a spec amendment.

---

## 6. Frozen behavioral contracts

### App lifecycle

`app()` returns `App` **by value** and stores no pointer to the pre-return local
(ADR-001, ratified by `experiments/01-api-shape/README.md::ADR-001`). The caller
keeps that value, passes `&app` to every mutating operation, and calls `destroy`
on that same value exactly once. **App is non-copyable by contract**: a copy must
never be destroyed independently. `bare()` is `app()` without the default 404/405
policy. Routes and recorder state are released exactly once.

Evidence: `tests/wp4-internal/wp4_internal_test.odin::wp4_destroy_releases_the_table_exactly_once`,
`tests/wp4-internal/wp4_internal_test.odin::wp4_bare_injects_no_405`,
`tests/wp3-internal/wp3_internal_test.odin::wp3_destroy_releases_everything_exactly_once`.

### Routing

Observable and frozen: static routes; at most one `:param` per pattern; static
wins over param; per-method isolation; the handler runs exactly once; 404 for an
unknown path; 405 with an exact `Allow` header for a known path under another
method; an unknown method never becomes 501; **no normalization of any kind** —
`/users` and `/users/` are different paths and stay that way; route conflicts are
not diagnosed in Phase 1.

**The linear table itself is NOT frozen.** It is an interim structure and Phase 3
may replace it with a compact per-method tree, as long as everything in the
previous paragraph stays true.

Evidence: `tests/wp4-internal/wp4_internal_test.odin::wp4_static_route_matches_and_runs_handler_once`,
`tests/wp4-internal/wp4_internal_test.odin::wp4_allow_uses_the_canonical_method_order`,
`tests/wp4-public-surface/contract_test.odin::wp4_methods_are_isolated_publicly`.

### Request and lifetimes

`Request` carries `method`, `path`, `query`, `headers`, `body`. **Every string
and slice on it is a view over transport-owned storage and is valid only for the
duration of the request.** Persisting any of them requires an explicit copy. No
`Context` and no view derived from it may be handed to background work.

Evidence: `tests/wp2-internal/wp2_internal_test.odin::wp2_buffer_reuse_invalidates_retained_views`,
`tests/wp2-internal/wp2_internal_test.odin::wp2_explicit_copy_survives_buffer_reuse`,
`docs/canonical-patterns.md::copy-to-persist`.

### Extractors

`path` and `query` return views. Value-producing extractors return `(value, ok)`
and deliberately omit `#optional_ok`, so dropping `ok` is a compile error.
`query_int_or` substitutes its default **only on absence** — a malformed value is
still a 400, never the default. Malformed input always commits 400. Integer
parsing is strict decimal. Names are case-sensitive. Nothing is percent-decoded
and `+` is not a space. For a duplicated query key the first occurrence wins;
this is the minimum rule and is **not** a promise of multi-value support.

Evidence: `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_or_treats_an_empty_value_as_malformed_not_absent`,
`tests/wp5-internal/wp5_internal_test.odin::wp5_query_does_not_decode_anything`,
`tests/wp5-internal/wp5_internal_test.odin::wp5_path_int_rejects_empty_text_and_overflow`.

### Body binding

There is a **single consumer**: the first `web.body` call consumes the capability,
and a second call does not reprocess. An empty or invalid body is a 400. The
limit is a **fixed 4 MiB**, not configurable; over the limit is 413, and the cap
is checked **before** the arena is created and before the parser runs. JSON is
decoded in the toolchain's strict mode. Nested decoded data lives in the
request-local arena and is cleaned up exactly once. An internal failure logs and
becomes a 500.

Evidence: `tests/wp7-internal/wp7_internal_test.odin::wp7_one_over_the_limit_is_too_large_before_parse_and_arena`,
`tests/wp7-internal/wp7_internal_test.odin::wp7_a_successful_first_bind_consumes_the_capability`,
`tests/wp7-internal/wp7_internal_test.odin::wp7_decoded_data_is_independent_of_the_raw_buffer`.

### Response

`Response` and its `committed` flag are **private**; there is no public response
object and no `ctx.response`. **First commit wins.** JSON and text bodies are
copied or owned by the response and released by `response_destroy`, which the
driver calls *after* the response has been captured or written. A marshal failure
is recorded before the 500 and **never leaves a partial body**. Payloads are taken
by value; a pointer payload is not part of the contract. Automatic headers are
correct and a 204 carries an empty body with no content headers.

Evidence: `tests/wp6-internal/wp6_internal_test.odin::wp6_marshal_failure_leaves_no_partial_body`,
`tests/wp6-internal/wp6_internal_test.odin::wp6_response_owns_the_rendered_body`,
`tests/wp6-internal/wp6_internal_test.odin::wp6_no_content_is_empty_and_header_free`.

### Errors — the ten Phase-1 codes

`invalid_path_parameter`, `invalid_query_parameter`, `invalid_json`,
`body_too_large`, `bad_request`, `not_found`, `method_not_allowed`,
`unauthorized`, `forbidden`, `internal_error`.

The envelope is always `{"error": {"code": ..., "message": ..., "field": ...}}`
with **`field` omitted entirely** when the error is not bound to an input field
(AMEND-2); only the two extractor errors carry one. Status, ratified message,
field presence, `Content-Type` and single-commit are all frozen. Protocol errors
detected before Inbound are a separate concern and never wear this envelope.

Evidence: `tests/wp6-internal/wp6_internal_test.odin::wp6_error_helpers_produce_the_ratified_envelopes`,
`docs/errors.md::body_too_large`, `docs/errors.md::method_not_allowed`.

### Test-support

Exactly two public symbols. `Recorded_Response` carries **only** `status` and
`body`; there is no headers field. A recorded body stays valid until
`destroy(&app)`, and responses recorded earlier stay valid when later ones are
recorded. There is no public cleanup call, no socket and no port anywhere on the
path. The recorder registers **lazily**, so an application that never calls
`test_request` links zero `web/testing` symbols.

Evidence: `tests/wp3-public-surface/contract_test.odin::wp3_two_recorded_responses_survive_until_destroy`,
`tests/wp3-public-surface/contract_test.odin::wp3_unused_test_support_is_a_noop_destroy`,
`build/check_g11_teardown.sh::URUQUIM_G11_PATTERN`.

### Transport

Only the **conceptual** contract is frozen: `accept → dispatch → commit → stop`.
The private ABI between `web` and `web/internal/transport` is explicitly NOT
frozen and may be redesigned.

Frozen: the backend never appears in a public signature; the body is limited
during reading, not after; the response is copied before cleanup; a handler that
commits nothing is finalized to 500; `stop` is basic and idempotent; the semantic
conformance matrix and the raw-wire corpus hold on both transports; framing is
defensive; `Expect: 100-continue` is rejected rather than auto-answered (WP9);
and no request-smuggling vector succeeds in the covered cases.

Evidence: `tests/wp9-semantic/http_factory_test.odin::wp9_semantic_matrix_on_the_real_http_transport`,
`tests/wp9-wire/wire_test.odin::wp9_raw_wire_corpus`,
`tests/wp8-internal/wp8_internal_test.odin::wp8_uncommitted_response_is_finalized_to_500`,
`docs/transport-conformance.md::100-continue`.

---

## 7. Dependency inventory

Snapshot: `build/phase1-direct-dependencies.txt` (15 direct imports, diffed on
every gate run).

| Package | Direct imports |
|---|---|
| `web` | `core:mem`, `core:strings`, `core:encoding/json`, `uruquim:web/testing`, `uruquim:web/internal/transport` |
| `web/testing` | `core:mem`, `core:strings` |
| `web/internal/transport` | `core:mem`, `core:net`, `core:slice`, `core:strings`, `uruquim:vendor/odin-http` |
| `examples/01..03` | `uruquim:web` only |

**Third-party.** Exactly one vendored dependency:

| Field | Value |
|---|---|
| Package | `laytan/odin-http` (root server package only) |
| Commit | `112c49b5bcee31308a695cc3f05d156d314a61a6` |
| License | MIT, Copyright (c) 2023 Laytan Laats (`vendor/odin-http/LICENSE`) |
| Owner | `web/internal/transport` — nothing else imports it |
| Record | `vendor/odin-http/VENDOR.md::Provenance` |

**Verified structural properties** (asserted by `build/check_phase1_freeze.sh`,
independently of the snapshot):

* no backend type appears in any exported signature;
* no example imports the vendor directly;
* `web/testing` does not import `web` — the back-edge is a compile cycle;
* `web/internal/transport` does not import `web` — the boundary is one-way;
* no package that ships inside application binaries imports `core:testing`;
* `web/testing` imports no networking package, so `test_request` reaches no socket;
* every dependency has a named owner and a license.

**Observed dynamic libraries** (`ldd`, all five cost fixtures, identical):
`linux-vdso.so.1`, `libm.so.6`, `libc.so.6`, `ld-linux-x86-64.so.2`. WP11 adds
none.

---

## 8. Ownership and lifetimes

| Data | Owner | Valid until |
|---|---|---|
| `App` value | the caller | `destroy(&app)`, exactly once, on the original value |
| Route patterns | `App` (cloned on registration) | `destroy` |
| `Request` fields | the transport | end of the request |
| `path`/`query` results | the transport (views) | end of the request |
| Decoded `body` nested data | the request arena | request teardown |
| Rendered response body | the internal `Response` | `response_destroy`, after capture/write |
| `Recorded_Response.body` | `App` (copied out) | `destroy(&app)` |

The single rule an application must remember: **anything reachable from
`ctx.request` is a view; copy it to keep it.**

---

## 9. Guardrail audit — G-01..G-11

Definitions in `planning/public-api-guardrails.md`. Ten of the eleven are backed
by executable enforcement; G-02 is not, and that is stated rather than smoothed
over.

| # | Guardrail | Result | Evidence |
|---|---|---|---|
| G-01 | One operation, one name | **PASS** | `build/check_public_api.sh::URUQUIM_EXPECTED_EXPORTS` — two-way `comm` diff of the extracted inventory; no synonym pair exists. `ok`/`created` are sanctioned exact delegations, proven by `tests/wp6-internal/wp6_internal_test.odin::wp6_ok_is_byte_identical_to_json_ok` |
| G-02 | Framework types stop at the HTTP boundary | **PASS (review-enforced only)** | `docs/canonical-patterns.md::boundary`. Structurally, `body` fills a caller-owned plain struct: `tests/wp7-internal/wp7_internal_test.odin::wp7_binds_nested_strings_and_slices`. **No gate asserts that a domain package is free of `uruquim:web`** — see the caveat below |
| G-03 | `Context` is not an extension bag | **PASS** | `build/check_public_api.sh::user_data` bans `user_data`/`locals`/`values`, `map[string]any`, `any` and `rawptr` in exported declarations; shape locked to `request` + `private`. Probe: `tests/wp2-public-surface/probes/context_has_no_response.odin::web.Context` |
| G-04 | Response side effects singular and visible | **PASS** | `tests/wp2-internal/wp2_internal_test.odin::wp2_second_commit_is_rejected_and_changes_nothing`; `tests/wp6-public-surface/contract_test.odin::wp6_the_first_response_wins`; `tests/wp5-public-surface/contract_test.odin::wp5_continued_handler_code_cannot_replace_the_400` |
| G-05 | Request views never escape implicitly | **PASS** | `tests/wp2-internal/wp2_internal_test.odin::wp2_buffer_reuse_invalidates_retained_views` and `::wp2_explicit_copy_survives_buffer_reuse`; `tests/wp6-internal/wp6_internal_test.odin::wp6_text_copies_the_caller_buffer` |
| G-06 | Backend stays private | **PASS** | `build/check_public_api.sh::URUQUIM_BACKEND_USERS` requires exactly ONE backend importer, inside `web/internal/transport/` (the adapter, derived rather than named — WP16), and bans `odin-http`/`nbio`/`laytan` in `web/` and `examples/`; `tests/wp9-public-surface/contract_test.odin::wp9_added_no_transport_surface` |
| G-07 | Optionals do not enlarge core | **PASS** | `build/check_public_api.sh::serve_with` — hard rejection loop over `use`, `router`, `group`, `mount`, `next`, `header`, `bearer_token`, `serve_with`, `recovery`, `Response`, `Transport` and more |
| G-08 | Defaults claimed only when delivered | **PASS** | `build/check_docs.sh::production.ready` — stale-claim blacklist; the 4 MiB cap is real and tested: `tests/wp7-internal/wp7_internal_test.odin::wp7_exactly_the_limit_is_not_too_large` |
| G-09 | Public growth carries evidence | **PASS** | Satisfied by §5 of this manifest plus `build/phase1-public-signatures.txt` and `build/phase1-direct-dependencies.txt`; enforced by `build/check_phase1_freeze.sh::evidence` |
| G-10 | No linter/analyzer as a product | **PASS** | Enforcement is compile probes, behavior tests and static repository assertions only — `build/check_public_api.sh::static repository assertions`. No CLI, generator or analyzer exists in the tree |
| G-11 | Test-support ledger and cost separated | **PASS** | `build/check_g11_teardown.sh::URUQUIM_G11_PATTERN` with a positive control and a static-edge mutation. Executed: never-tests → **0** `web/testing` symbols; does-test → **11**; mutation → 4, correctly rejected |

**No guardrail is deferred.** Every Phase-1 obligation is met in Phase 1; the
deferrals recorded in §11 are features that do not belong to Phase 1 at all.

### G-02 caveat, recorded rather than smoothed over

G-02 is the only guardrail whose PASS rests on documentation and reviewer
discipline instead of an executable check. Nothing in the repository asserts that
an application's domain package is free of `uruquim:web`; all three examples are
single-file `package main` programs, so they neither demonstrate nor violate the
boundary. G-10 explicitly sanctions review as an enforcement mode, so this is not
a broken promise — but a reader cannot tell "enforced" from "unenforced" here.
**Forwarded to Phase 2: add a multi-package example plus a gate asserting the
domain package does not import `uruquim:web`.** This does not block the freeze:
it constrains no frozen signature and no frozen behavior.

### Risk and open-question triage

All 19 risks, 20 open questions, 14 ADRs and 11 research items were classified.
**No open blocker is assigned to Phase 1.** Highlights:

* Resolved in Phase 1 with executed evidence: R-01, R-04, R-05, R-06, R-07,
  R-08, R-09, R-10, R-12, R-14, R-15, R-17; ADR-001, -002, -006, -007, -008,
  -009, -011, -012, -014.
* Accepted limitations: R-02 (pinned beta backend, confined to one file),
  R-13/ADR-003 (value-only payloads).
* Deferred: R-03 → 5; R-16 → 3; R-18 → 3/4; R-19/ADR-013 → 4; ADR-005
  (middleware) → 2; ADR-004 (typed state) → 3; ADR-010 (Advanced API) →
  post-Phase-1. ADR-005, -010 and -013 are **PROPOSED, not accepted**, and are
  recorded as such.
* R-11 ("freeze discipline violated") named WP11 itself as its own mitigation:
  the freeze must be computed from executed runner output only. This manifest
  and the two committed snapshots are that output; R-11 closes with this
  work.

---

## 10. Accepted limitations

Shipped as-is, documented, not blocking:

* No header lookup. `Header_View` is opaque; `web.header` and `web.bearer_token`
  are Phase 2.
* No path normalization: trailing slashes, dot segments and percent-encoding are
  all significant and untouched.
* No percent-decoding or `+`-as-space in query values.
* Duplicate query keys: first wins; no multi-value access.
* Body limit fixed at 4 MiB, not configurable.
* No configurable timeouts. `stop` is basic and idempotent, not a graceful
  drain.
* Route conflicts are not diagnosed.
* One `:param` per pattern; no wildcards.
* The four evidence asymmetries in §5.
* `serve` is a bootstrap server. It is not a hardened production front end and
  this document makes no such claim.

## 11. Forwarded to later phases

Implemented by nobody in Phase 1; recorded so that their absence is deliberate
rather than forgotten:

| Item | Phase |
|---|---|
| Middleware (`use`, `next`), route groups, `mount` | 2 |
| Header accessors, `bearer_token`, typed state | 2 |
| Radix/compact router, conflict diagnostics, normalization policy | 3 |
| Request buffer retention and pooling | 3 |
| Trusted proxies, robust shutdown, configurable timeouts | 4 |
| `core:net/http` migration, streaming, WebSocket, uploads, static files | 5 / future |
| OpenAPI generation | future |

Confirmed absent from the public surface: middleware, groups, radix, wildcard,
typed state, `user_data`, `locals`, dynamic context map, header accessor,
configurable body limit, configurable timeouts, recovery, uploads, static files,
OpenAPI, WebSocket, streaming, public transport injection, public `Response`, a
second handler shape, and aliases. The freeze gate rejects any exported symbol
carrying Phase-2+ vocabulary.

## 12. Conditions of human acceptance

The freeze becomes effective only when all of the following hold:

1. `build/check.sh` is green at `PASS=10 FAIL=0 SKIP=0` on a clean checkout.
2. The ledgers read 32 + 2 = 34 and the snapshot diff is empty.
3. The independent VPS verifier reproduces both, from a clean archive, on the
   exact public commit, with the same pinned toolchain.
4. A human reviews and merges the WP11 pull request.
5. A human confirms one further verifier run on the merged commit on `main`.

Tag, semantic version and release are **not** granted by this document and
remain the owner's decision. No agent may merge, tag or publish.


---

## Amendment 1 — WP14: `test_request` carries an optional body

**Date:** 2026-07-19. **Authority:** owner, ADR-021 (as amended).
**Ledger effect: none.** 32 application + 2 test-support = 34, unchanged.

Phase 1 froze `test_request` at method + path. The consequence, unnoticed until
the post-Phase-1 audit measured it, was that a handler calling `web.body` could
never reach its success path in memory — it always saw `invalid_json`. The
framework's own tests reached it only by copying `web/*.odin` into a throwaway
package, which an application cannot do.

The frozen line changes from:

```
test-support	proc	test_request :: proc(a: ^App, method: Method, path: string) -> Recorded_Response
```

to:

```
test-support	proc	test_request :: proc(a: ^App, method: Method, path: string, body: string = "") -> Recorded_Response
```

**No symbol is added or removed.** The default keeps every existing call site
compiling and behaving exactly as before, which the gate asserts directly
(`tests/wp14-public-surface/contract_test.odin::wp14_the_three_argument_form_is_unchanged`).

**Why a default parameter and not a procedure group.** A group over `@(private)`
members renders in `odin doc` as member names only, so the snapshot would have
pinned this symbol's *name* while leaving its parameters free to change —
measured, and now rejected outright by `build/check_phase1_freeze.sh`. A default
parameter keeps the entire signature inside the frozen record.

**This is the amendment path working, not a breach of it.** Freezing never meant
"never changes"; it meant "changes only with evidence and a recorded amendment".
The gate's named assertions still hold — a snapshot cannot be refreshed to
launder a change, because they encode the decision rather than the current
state.

### One consequence worth recording

The 4 MiB cap is now reachable in memory, and it returns **413** — which has no
member in the public `Status` enum, because Phase 1 deliberately kept it private
(§4). So `Recorded_Response.status` can hold a value that is not a valid
`Status`, and testing the cap requires an integer comparison:

```odin
testing.expect_value(t, int(res.status), 413)
```

That is the frozen design meeting the new capability rather than a defect, but a
user will meet it the first time they test the cap, so it is pinned by
`tests/wp14-public-surface/contract_test.odin::wp14_the_body_cap_holds_on_the_memory_transport`.


---

## Amendment 2 — WP14: `test_request` carries an optional query string

**Date:** 2026-07-19. **Authority:** owner, ADR-021 (scope as accepted).
**Ledger effect: none.** 32 application + 2 test-support = 34, unchanged.

`web.query`, `web.query_int` and `web.query_int_or` are frozen Phase-1 symbols,
and none of them could be exercised through `test_request`: the facade filled
`Inbound.path` and left `Inbound.query` empty, so every lookup missed. Three
frozen public procedures were untestable without opening a socket.

The frozen line becomes:

```
test-support	proc	test_request :: proc(a: ^App, method: Method, path: string, body: string = "", query: string = "") -> Recorded_Response
```

`query` is a second fully visible default parameter, for the reason in
Amendment 1: both defaults appear in `odin doc`, so the entire callable contract
stays inside the frozen record. Query-only calls read
`web.test_request(&app, .GET, "/search", query = "q=hello")`; the named-argument
form was verified to compile on the pinned toolchain before the signature was
frozen.

**Query is carried separately from the path**, exactly as the real adapter does
it — the transport splits the request target before the core sees it, so a `?`
inside `path` is not a query string here either. Pinned by
`tests/wp14-query/contract_test.odin::wp14_query_is_not_part_of_the_route_path`.

### What is deliberately NOT in this amendment

**Request headers.** Phase 1 exports no header accessor, so a `headers`
parameter would be **write-only** — settable, and readable by nothing. It moves
to **WP19**, alongside `web.header` and `web.bearer_token`, so it arrives with a
test that can assert something. `Header_Pair` is not exported and no test-only
header type is introduced.

**Response-header recording.** `Recorded_Response` still carries only `status`
and `body`. That decision belongs to Phase 4, where CORS and cookies create the
first real need.

## Amendment 3 — WP17: middleware (`use`, `next`) joins the application ledger

**Date:** 2026-07-19. **Authority:** owner — the approved Phase-2 ledger
(`planning/phase-2-spec.md` §9.2, PR #30 review) assigns `use` and `next` to
WP17 under ADR-005 and ADR-019, both settled.
**Ledger effect: application 32 → 34.** 34 application + 2 test-support = 36.
The Phase-1 core of 32 symbols is unchanged: no frozen signature moved, no
field was added to a public type, and `odin doc` renders the two new rows and
nothing else (the snapshot diff at this amendment was exactly two added
lines).

The two recorded lines:

```
application	proc	next :: proc(ctx: ^Context)
application	proc	use :: proc(a: ^App, middleware: Handler)
```

There is NO `Middleware` type (D-12.1: a distinct proc type converts implicitly
in both directions on the pinned toolchain — no call-site cost, no protection
either). Chains are flattened at registration into an App-owned pool and routes
store index pairs, never `[]Handler` (spec §2.2, WP12 P8). Post-`next`
behaviour is specified and tested (ADR-022 = B1). App-level middleware observe
404/405 misses, in `bare()` too (ADR-023). `use()` after any registration or
after the first dispatch rejects the application fail-closed with the
owner-approved diagnostic (ADR-019; the diagnostic additionally names the count
of already-registered routes and the first unprotectable pattern, composed
through a fixed buffer — no `core:fmt`).

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `use` | A | WP17 | `tests/wp17-public-surface/contract_test.odin::wp17_use_and_next_signatures_are_pinned` | `tests/wp17-public-surface/contract_test.odin::wp17_mis_ordered_auth_program_does_not_serve_the_protected_route` | `docs/middleware.md::web.use` | App owns the global list and chain pool; lazy; freed once by `destroy` |
| `next` | A | WP17 | `tests/wp17-public-surface/contract_test.odin::wp17_use_and_next_signatures_are_pinned` | `tests/wp17-internal/wp17_internal_test.odin::wp17_second_next_is_a_silent_noop_and_the_handler_runs_once` | `docs/middleware.md::web.next` | reads the per-request cursor; allocates nothing; never rewinds |

One consequence recorded honestly: the §11 forwarded-items table still lists
middleware as "forwarded to Phase 2" — that stays true as a statement about
Phase 1. This amendment is the record that Phase 2 (WP17) delivered it.
