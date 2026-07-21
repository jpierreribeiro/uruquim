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
| `web/internal/transport` | `core:mem`, `core:net`, `core:slice`, `core:strings`, `core:time`, `uruquim:vendor/odin-http` |
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

## Amendment 4 — WP18: route organisation (`Router`, `router`, `mount`)

**Date:** 2026-07-19. **Authority:** owner — the approved Phase-2 ledger
(`planning/phase-2-spec.md` §9.2) assigns the three names to WP18 under
ADR-024 (ACCEPTED) and ADR-025 (ACCEPTED as option B).
**Ledger effect: application 34 → 37.** 37 application + 2 test-support = 39.
The snapshot diff at this amendment was exactly three added lines; no
existing row changed a byte.

The three recorded lines:

```
application	proc	mount :: proc(a: ^App, prefix: string, r: ^Router)
application	proc	router :: proc() -> Router
application	type	Router :: struct {using app: App}
```

**The §9.2 guard note, resolved.** The plan projected `use`, `destroy` and the
five verbs becoming procedure groups so Router variants add zero names; the
freeze gate rejects a group over `@(private)` members (unfreezable, ADR-021 as
amended), and exporting the members would have grown the ledger far past the
approved 44. The shape chosen instead: `Router` embeds an `App` with `using`
(subtype polymorphism), so `^Router` converts to `^App` implicitly at every
existing call site — zero new names beyond the approved three, zero procedure
groups, and the five verb signatures plus `use`/`destroy` stay byte-identical
(ADR-025 B's constraint holds literally). Compile-probed on the pinned
toolchain before implementation: all seven call sites accept `^Router`
unchanged; `^App` where `^Router` is expected is a compile error, so `mount`
stays Router-only; `odin doc` renders the using-field fully, so the snapshot
pins it. No `web.group` exists and none ever will (ADR-024, G-01).

Fail-closed rules carried by the mechanism (ADR-019 family, all tested):
`use` after a route applies inside a Router; mounting a poisoned Router
poisons the receiving App; `mount` counts as a registration; `mount` closes
the Router (late registration or a second mount fails closed); an invalid
prefix — one that does not begin with `/`, or ends with `/` — rejects the
App with a diagnostic naming the prefix, composed through a fixed buffer,
never `core:fmt`.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `Router` | A | WP18 | `tests/wp18-public-surface/contract_test.odin::wp18_public_signatures_are_pinned` | `tests/wp18-internal/wp18_internal_test.odin::wp18_app_and_router_each_release_their_own_storage_exactly_once` | `docs/canonical-patterns.md::Router` | embeds App via `using`; own storage, destroyed exactly once, never copied |
| `router` | A | WP18 | `tests/wp18-public-surface/contract_test.odin::wp18_public_signatures_are_pinned` | `tests/wp18-internal/wp18_internal_test.odin::wp18_an_unmounted_router_leaks_nothing` | `docs/canonical-patterns.md::web.router` | returns Router by value; allocates nothing; no default responses |
| `mount` | A | WP18 | `tests/wp18-public-surface/contract_test.odin::wp18_public_signatures_are_pinned` | `tests/wp18-internal/wp18_internal_test.odin::wp18_nested_routers_outer_use_before_inner_use_before_handler` | `docs/canonical-patterns.md::web.mount` | COPIES into the App; closes the router; counts as a registration |

## Amendment 5 — WP19: request header lookup (`header`, `bearer_token`)

**Date:** 2026-07-19. **Authority:** owner — the approved Phase-2 ledger
(`planning/phase-2-spec.md` §9.2) assigns both names to WP19 ("plan WP19, no
new decision"); the behaviour contract is `planning/phase-2-plan.md` §WP19.
**Ledger effect: application 37 → 39.** 39 application + 2 test-support = 41.
The snapshot diff for this amendment was exactly two added application lines.

The two recorded lines:

```
application	proc	bearer_token :: proc(ctx: ^Context) -> (value: string, ok: bool)
application	proc	header :: proc(ctx: ^Context, name: string) -> (value: string, ok: bool)
```

Both are PURE lookups — no response side effect (the documented asymmetry with
the extractors: an absent header is routinely not an error), nothing logged
(values are attacker-controlled; the WP6 `core:log`/`core:fmt` ban holds), no
allocation, `(value, ok)` with no `#optional_ok` (ADR-002). Names compare
case-insensitively with ASCII folding; duplicates: first occurrence wins (the
WP5 D4 rule); an empty value is present. `header` reads the EFFECTIVE request
header: the private ADR-027 overlay first, then what arrived — WP19 ships the
read path, WP23 the writer. `bearer_token` parses RFC 6750 strictly (scheme
case-insensitive, exactly one space, non-empty token, no whitespace tolerance)
and returns the token verbatim, never trimmed or normalised. Returned values
are VIEWS invalidated at request end — the WP2 view test is ported. **Audit
A-8 is resolved**: the per-request header materialisation the transport has
performed since WP8 is now read by these two procedures.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `header` | A | WP19 | `tests/wp19-public-surface/contract_test.odin::wp19_public_signatures_are_pinned` | `tests/wp19-internal/wp19_internal_test.odin::wp19_header_value_is_a_view_invalidated_by_buffer_reuse` | `docs/canonical-patterns.md::web.header` | returns a view over transport memory; overlay consulted first; allocates nothing |
| `bearer_token` | A | WP19 | `tests/wp19-public-surface/contract_test.odin::wp19_public_signatures_are_pinned` | `tests/wp19-internal/wp19_internal_test.odin::wp19_bearer_rejects_every_malformed_shape` | `docs/canonical-patterns.md::web.bearer_token` | strict RFC 6750 parse; token verbatim, never normalised; allocates nothing |

## Amendment 6 — WP19: `test_request` carries optional request headers

**Date:** 2026-07-19. **Authority:** owner, ADR-021 (scope as accepted) and
spec §9.3, which pre-authorised exactly this mechanism.
**Ledger effect: none.** Test-support stays 2 — the §9.3 contingency (a new
public type forcing the number up) was NOT needed.

The frozen line becomes:

```
test-support	proc	test_request :: proc(a: ^App, method: Method, path: string, body: string = "", query: string = "", headers: []string = nil) -> Recorded_Response
```

`headers` is the THIRD fully visible default parameter, on Amendment 1/2's
exact terms: the whole callable contract stays inside the frozen record and
every earlier call shape compiles unchanged (pinned by the amended
`tests/wp7-public-surface/contract_test.odin::wp7_test_request_signature_is_pinned`).

**Representation choice, presented.** Each element is one header line,
`"Name: value"` — split at the FIRST colon, optional whitespace trimmed around
the value (RFC 9110 field parsing, i.e. exactly what a socket delivers to the
core), inner colons kept, a colon-less element is a name with an empty value.
Considered and rejected: a public pair type (grows a ledger — needs owner
approval, and §9.3 said avoid if expressible); alternating name/value strings
(silently truncatable on an odd count, teaches nothing about wire form). The
header lines travel the SHARED driver pipeline as neutral pairs, so nothing
downstream can tell the two transports apart (R-10).

## Amendment 7 — WP20: the typed framework-error observer

**Date:** 2026-07-19. **Authority:** owner — ADR-026 (ACCEPTED, option A) and
the approved Phase-2 ledger (`planning/phase-2-spec.md` §6, §9.2).
**Ledger effect: application 39 → 42.** 42 application + 2 test-support = 44.
The snapshot diff for this amendment was exactly three added lines.

The three recorded lines:

```
application	proc	observe :: proc(a: ^App, observer: proc(event: Framework_Event))
application	type	Framework_Error :: enum {None, Response_Marshal_Failed, Body_Decode_Failed, Body_Consumed_Twice, No_Response_Committed, Invalid_Serve_Port, Serve_Listen_Failed, Use_After_Route}
application	type	Framework_Event :: struct {kind: Framework_Error, method: Method, route: string, status: Status, payload_type: typeid}
```

`Framework_Error` is the pre-existing private closed enum made public
unchanged. It carries **eight** members, not the seven §6.1 listed: WP17
ratified `Use_After_Route` after that section was written, and the spec's own
rule is that the enum "grows only when a work package ratifies a new member" —
so the eighth member is recorded here rather than silently absorbed.

**The redaction constraint is enforced by the gate, not by convention**
(§6.2, HARD). `build/check_public_api.sh` now asserts, on every run: the
event's field set is exactly the ratified five; **no field whose type mentions
`string` may be named anything but `route`** (so `path: string`,
`message: string` or `headers: []string` each fail the build); `observe` keeps
its exact signature; and the number of `framework_report` call sites equals
the number of observer emissions, so a future failure cannot be reported
without being observable. All four assertions were verified to FAIL against a
deliberate mutation before being trusted.

Two properties are stronger than the specification anticipated, and are
recorded as such rather than restated loosely:

* §6.3 says an observer that attempts to respond is stopped by the
  single-commit guard. With the accepted signature an observer receives the
  **event by value and nothing else** — no `^Context` — so responding is
  impossible **by type**; the guard is never reached because there is nothing
  to write through.
* `status` is read **after** the framework commits its answer, so it is the
  status actually sent rather than a prediction. Failures outside a request
  (the `serve` path) carry `method = .UNKNOWN`, `route = ""` and the zero
  `Status`: the event declines to invent values it cannot supply.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `observe` | A | WP20 | `tests/wp20-public-surface/contract_test.odin::wp20_public_signatures_are_pinned` | `tests/wp20-internal/wp20_internal_test.odin::wp20_last_observer_wins` | `docs/ai-context.md::observe` | one procedure pointer on the App; last wins; owns no storage |
| `Framework_Event` | A | WP20 | `tests/wp20-public-surface/contract_test.odin::wp20_public_signatures_are_pinned` | `tests/wp20-internal/wp20_internal_test.odin::wp20_the_event_survives_the_request_by_value` | `docs/ai-context.md::Framework_Event` | passed by value; `route` is an App-owned pattern valid until `destroy` |
| `Framework_Error` | A | WP20 | `tests/wp20-public-surface/contract_test.odin::wp20_public_signatures_are_pinned` | `tests/wp20-internal/wp20_internal_test.odin::wp20_marshal_failure_is_observed_once` | `docs/ai-context.md::Framework_Error` | closed enum, value type; grows only by ratification |

## Amendment 8 — WP22: the `logger` middleware

**Date:** 2026-07-20. **Authority:** owner — the approved Phase-2 ledger
(`planning/phase-2-spec.md` §9.2, row `logger`) and `planning/phase-2-plan.md`
WP22, which the spec records as carrying **no new decision**.
**Ledger effect: application 42 → 43.** 43 application + 2 test-support = 45.
The snapshot diff for this amendment was exactly one added line.

The recorded line:

```
application	proc	logger :: proc(ctx: ^Context)
```

`logger` is a `Handler` value, not a constructor and not a configurable object.
That is the whole shape: there is no `logger_with(...)`, no level, no sink and
no format argument, because every one of those would be a second public name
for an operation that already has one (G-01) and would freeze a configuration
contract Phase 4 owns.

**It is OPT-IN.** `web.app()` does not install it. G-08 forbids inventing a
default, and the phases document makes only recovery default-on; an application
that never writes `web.use(&app, web.logger)` logs nothing and links none of
this code.

**What the line may contain is frozen with the symbol**, because for this
component the OUTPUT is the contract. Method, registered route pattern, and
committed status — nothing else. Never the raw path, the query string, a header
name or value, a body byte, or a captured parameter value. The route field
carries the same low-cardinality identity rule §6.2 imposes on
`Framework_Event`, and for the same reason: on a miss there is no pattern, so
the field is `-` and does **not** fall back to the path.

Three properties are recorded because they are the ones a later change would
silently break:

* **Truncation is observable.** The line is composed in a fixed stack buffer
  bounded by `LOGGER_LINE_MAX`. A route field that does not fit is cut on an
  escape-unit boundary and marked `...[truncated]`, and the status still
  follows the mark. Growing the buffer would defeat the fixed buffer and
  re-import the per-request allocation it exists to avoid; dropping the line
  would make the logger lie by omission about traffic it saw. Both are excluded
  by tests, and a positive control asserts an ordinary pattern is **not**
  marked.
* **The status is read, never predicted.** The line is written after `next`
  returns (ADR-022 B1 is what makes that legal to promise). When the chain
  committed nothing, the field is `-`: the driver's 500 finalization happens
  after dispatch returns — after this middleware's frame is gone — so the
  logger did not see it, and says so rather than inventing it. That failure is
  reported through the WP20 observer, which is the channel that does see it.
* **It costs nothing when unused.** No import at all: not `core:log` (WP6
  measured ~37 KiB added to every application, referenced or not), not
  `core:fmt`. An application that never names `web.logger` links **zero**
  logger symbols, proven with `nm` against a positive control in
  `build/check_wp22_controls.sh` (control 7). What is NOT claimed, because it
  is not testable here: byte-identity of the binary. The pinned toolchain does
  not build reproducibly — five builds of an identical tree produced five
  distinct binaries — so byte-identity fails for a tree compared against
  itself. Recorded as a plan amendment rather than quietly downgraded.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `logger` | A | WP22 | `tests/wp22-public-surface/contract_test.odin::wp22_public_signature_is_pinned` | `tests/wp22-public-surface/contract_test.odin::wp22_public_never_emits_query_header_or_body` | `docs/middleware.md::web.logger` | a `Handler` value; composes into a fixed STACK buffer no response can alias; owns no storage; consults the commit guard through `logger_status` before reading response state |

## Amendment 9 — WP23: the `request_id` middleware and its trust policy

**Date:** 2026-07-20. **Authority:** owner — ADR-027 (ACCEPTED, option A) and
the approved Phase-2 ledger (`planning/phase-2-spec.md` §9.2).
**Ledger effect: application 43 → 44.** 44 application + 2 test-support = 46.
The snapshot diff for this amendment was exactly one added line.

The recorded line:

```
application	proc	request_id :: proc(ctx: ^Context)
```

**+1, not +2.** ADR-027 closed the `request_id_value` accessor contingency: the
effective ID is read through `web.header(ctx, "X-Request-Id")`, the one
canonical name for reading a request header (G-01). The cost of that choice is
declared rather than discovered — WP19 already documents `header` as returning
the **effective** request header, and this is the work package that makes the
word load-bearing.

**The trust policy is the deliverable, and it is frozen with the symbol.** A
client-supplied `X-Request-Id` is honoured **only** if it matches charset
`[A-Za-z0-9._-]` and length 1..64. Everything else — too long, empty, a space,
a semicolon, a control byte, non-ASCII, and above all CR or LF — causes the
value to be **discarded** and a fresh ID generated. Discarded is absolute: the
rejected bytes are never echoed, never written to the overlay, never logged,
and never reachable by a handler. There is no sanitising pass, because a
repaired attacker value is still an attacker value.

**The attack this closes** is CR/LF response-header injection. The charset
makes it impossible by construction rather than by a sanitiser that must be
remembered at every write site; the suites send `\r\n` anyway, because a
construction argument is a claim until something asserts it.

Four properties are recorded because a later change would break them silently:

* **The ID is NOT unguessable, and is never authentication.** Generation is a
  per-process seed (mixed from two ASLR-derived addresses — no import, see
  below) plus a monotonic counter: enough to be unique, deliberately not enough
  to be unpredictable. `core:crypto` is not imported, partly because a request
  ID must not be mistaken for a secret.
* **No dependency was added.** `web`'s direct-import set stays at the five
  pinned in `build/phase1-direct-dependencies.txt`. A cycle counter
  (`base:intrinsics`) or a clock (`core:time`) would each have grown it for a
  value that is explicitly not a secret.
* **The header is APPENDED, never seeded first.** WP4 ratified `Allow` first
  and `Content-Type` second for a 405, and a merged WP17 test pins both by
  index; seeding at slot 0 would have renumbered them. `RESPONSE_HEADER_MAX`
  grows 2 → 3.
* **It is attached where response headers are BUILT**, not by the middleware's
  unwind code, which is what puts it on a 404, a 405 **and** the driver's
  standardized 500. WP22 measured that the driver finalizes a missing response
  after the chain has unwound — a middleware stamping on the way out would miss
  exactly the response an operator most needs to correlate.

**The counter is not atomic**, and that is a stated assumption: one server per
process (audit R-10) with a single-threaded event loop. Phase 4 owns
concurrency and owns this line with it.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `request_id` | A | WP23 | `tests/wp23-public-surface/contract_test.odin::wp23_public_signature_is_pinned` | `tests/wp23-public-surface/contract_test.odin::wp23_public_crlf_is_never_echoed` | `docs/middleware.md::web.request_id` | a `Handler` value; the effective ID is copied into fixed request-local storage on the Context, viewed by the committed response and by the overlay; owns no allocation |

## Amendment 10 — WP34: route identity (`route`)

**Date:** 2026-07-20. **Authority:** the **ADR-029 delegation**
(`planning/adrs.md` §ADR-029, and the resolution table at
`planning/phase-3-plan.md` §2b, which records WP34 as *"Approved: +1 symbol"*).
This is the **first Phase-3 amendment**, and the first one whose authority is a
delegation rather than a direct owner decision — recorded here in those words,
because an amendment that cannot say who authorised it is not evidence.
**Ledger effect: application 44 → 45.** 45 application + 2 test-support = 47.
The snapshot diff for this amendment was exactly one added line; no existing
row changed a byte.

The recorded line:

```
application	proc	route :: proc(ctx: ^Context) -> string
```

**What it returns is the whole contract: the REGISTERED PATTERN, never the
request path.** `/users/:id`, not `/users/42`. This is C-2's constraint — the
OpenTelemetry `http.route` convention requires route identity to be
**low-cardinality** — and it is the reason the symbol earns its place: an
application that wanted the path already had `ctx.request.path`. What it could
not obtain was the identity that is safe to key a metric, a log field or a span
name on. A path-valued answer would create one time series per user id, and put
a user identifier into a dashboard nobody meant to put it in.

**The redaction rule is a GATE ASSERTION, not a convention.**
`build/check_public_api.sh` §8b pins the accessor's shape, requires its body to
be exactly `return ctx.private.route`, and — the assertion that actually does
the work — requires **every** write to that slot to be the matched entry's
`pattern`. A behavioural test can only check the routes someone thought to
write; this checks the assignment where the decision is made. It is the sibling
of the §8 assertion that keeps `Framework_Event` free of request-derived
strings, and the two exist together because one procedure returning the pattern
while another quietly returned the path is exactly how a redaction rule rots.

**Why the name is `route` and not `route_pattern`, `matched_route` or
`route_name` (G-01).** The framework already calls this value `route`: it is
the `route` field of `Framework_Event`, read from the same slot and carrying
the same string. A second name would mean an application reading
`web.route(ctx)` and an observer reading `event.route` had to be told they are
the same thing. `tests/wp34-public-surface` asserts they are, so a future
divergence is a red test rather than a documentation problem.

**No route means `""`,** and that is the answer rather than an error: on a 404
there is no route, and on a 405 no entry was selected for that method, so
naming the other method's pattern would name a route that did not run. A field
the framework cannot supply is left unpopulated rather than guessed (§6.2).

**Lifetime — the one exception, already on the books.** The result is a view
over **App-owned** storage, the pattern cloned at registration, and is valid
until `destroy`. It is therefore the only value reachable from a `^Context`
that is **not** request-scoped, and it is the same exception the Phase-2
lifetime ledger already records for `Framework_Event.route` — the same string,
now reachable by a second route. G-05 is unchanged for everything else.

**OQ-18 is closed by this amendment.** It recorded a stable route identity for
observability as internal and FUTURE. WP20 made the value visible to an
observer; WP34 makes it visible to the application that owns the request, under
the same redaction rule.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `route` | A | WP34 | `tests/wp34-public-surface/contract_test.odin::wp34_the_route_signature_is_pinned` | `tests/wp34-public-surface/contract_test.odin::wp34_a_parametric_route_reports_the_pattern_and_never_the_path` | `docs/ai-context.md::web.route` | App owns the pattern (cloned at registration, freed once by `destroy`); the result is a borrowed view valid until `destroy`, the single documented exception to request-scoped views; allocates nothing |

## Amendment 11 — WP37: typed application state (`app_with_state`, `state`)

**Date:** 2026-07-20. **Authority:** the **ADR-029 delegation**
(`planning/phase-3-plan.md` §2b: *"WP37 implements ADR-004 only"*), over
**ADR-004** (ACCEPTED, option A, with AMEND-1) and **ADR-028** (ACCEPTED,
option 1).
**Ledger effect: application 45 → 47.** 47 application + 2 test-support = 49.
The snapshot diff for this amendment was exactly two added lines; no existing
row changed a byte.

The two recorded lines:

```
application	proc	app_with_state :: proc(state: ^$T) -> App
application	proc	state :: proc(ctx: ^Context, $T: typeid) -> ^T
```

**Two symbols and not one**, because construction and access are different
operations with different failure modes: one rejects nil at boot, the other
asserts type identity per call.

**WHAT IS FROZEN IS THE SHAPE OF THE CALL SITE.** `web.state(ctx, App_State)`
carries no generic noise, and no handler signature acquires a type parameter.
That is precisely what ADR-004 chose option A for: option B — a parametric
`App(S)`/`Context(S)` — would have put a type argument on every handler in
every program. The declared price is a runtime assert instead of a compile
error, and it is paid where it can be seen: `state` asserts registration and
then EXACT `typeid` equality before the cast. There is no subtyping walk and no
"close enough"; casting a `^Config` to a `^Database` because both are pointers
is the defect the `typeid` exists to make impossible.

**A nil state rejects the application (AMEND-1),** through the ADR-019 poison
mechanism rather than a new one. An App that accepted nil would abort inside
the first request instead — the same failure, discovered later, in front of a
client.

**The `rawptr` is private and that is the whole basis on which G-03 permits
it.** Neither exported signature carries an untyped pointer: `app_with_state`
takes `^$T`, `state` returns `^T`. This is the narrowing
`build/check_public_api.sh` anticipated by name in the comment beside the ban.
Enforcing it exposed a hole in the check itself, closed in the same change: the
exported-declaration extractor treated any declaration line not ending in `{`
as complete, so a MULTI-LINE exported signature was never scanned at all. It
now follows a signature to its closing parenthesis, and stops at a procedure's
opening brace — a body is implementation, a signature is surface, which is what
G-03 always said in words.

**NO BACK-POINTER TO THE APP.** The driver copies the pointer and the `typeid`
onto the Context at the start of the request, exactly as it copies the WP20
observer. `Context_Internal` still holds no `^App` — the WP4 D3 decision stands
— and both transports get the state through one line on the shared pipeline
(R-10).

**ADR-028 IS THE OTHER HALF OF THIS AMENDMENT, and it ships nothing.**
Request-scoped typed state **does not exist and is not scheduled**. C-6 found
that Go's `context.WithValue` and Rust's `http::Extensions` exist for
type-erased, dynamically-keyed state crossing library boundaries — which
Uruquim does not have — and concluded that this SUPPORTS G-03. The honest
consequence is recorded rather than softened: the canonical auth pattern's
revalidation cost (WP24) stands until an ADR decides otherwise, and
`build/check_examples.sh` rejects a comment that schedules its removal.

**Lifetime, stated plainly because no assert can enforce it:** the pointed-to
value must outlive the App. The framework owns nothing here — `destroy` has
nothing to release, because it allocated nothing — and a pointer to a local in
a procedure that has returned is dangling with the type still right and the
memory still mapped. `examples/07-app-state` teaches the rule as LAYOUT: the
state and the App are both locals of `main`.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `app_with_state` | A | WP37 | `tests/wp37-public-surface/contract_test.odin::wp37_the_state_signatures_are_pinned` | `tests/wp37-public-surface/contract_test.odin::wp37_a_nil_state_rejects_the_application` | `docs/ai-context.md::web.app_with_state` | stores the CALLER's pointer and a `typeid`; owns nothing and allocates nothing; the caller owns the value and must outlive the App; `destroy` releases nothing here |
| `state` | A | WP37 | `tests/wp37-public-surface/contract_test.odin::wp37_the_requested_type_decides_the_result_type` | `tests/wp37-public-surface/contract_test.odin::wp37_a_handler_mutates_the_original_value` | `docs/ai-context.md::web.state` | returns the caller's own pointer, typed; asserts registration and exact `typeid` before the cast; borrows, owns nothing, allocates nothing |

## Amendment 12 — WP36: configurable limits (`Limits`, `DEFAULT_LIMITS`, `limits`)

**Date:** 2026-07-20. **Authority:** the **ADR-029 delegation**
(`planning/phase-3-plan.md` §2b: *"Approved: options struct + package default
constant; boot-derived immutable runtime"*).
**Ledger effect: application 47 → 50.** 50 application + 2 test-support = 52.
The snapshot diff for this amendment was exactly three added lines; no existing
row changed a byte.

The three recorded lines:

```
application	const	DEFAULT_LIMITS :: Limits{max_body = BODY_LIMIT, max_request_line = REQUEST_LINE_LIMIT, max_headers = HEADER_BLOCK_LIMIT}
application	proc	limits :: proc(a: ^App, l: Limits)
application	type	Limits :: struct {max_body: int, max_request_line: int, max_headers: int}
```

**THIS IS THE LEAST REVERSIBLE CHANGE IN PHASE 3 and the struct's size is the
whole defence.** A public options type is a promise per FIELD: once an
application writes `max_body`, removing or renaming that field breaks its build,
and *tightening a default* breaks its traffic without breaking its build — which
is worse. Adding a field later is cheap. Three fields ship, each because
something downstream already enforces it.

**THE DEFAULTS ARE THE SHIPPED VALUES, NOT NEW OPINIONS.** 4 MiB is the cap
Phase 1 fixed; 8000 is the vendored backend's own default for both text budgets.
An application that never mentions limits therefore behaves exactly as it did
before this amendment — the property that makes shipping the type safe. The
freeze snapshot records `DEFAULT_LIMITS` by the NAMES of its constants, so
`build/check_public_api.sh` additionally pins all three numbers; without that,
a default could change with the snapshot unmoved.

**IT ATTACHES TO THE APP, NOT TO `serve`, AND R-10 IS THE REASON.**
`test_request` never calls `serve`. A cap living on `serve` would make an
in-memory test answer 200 where a socket answers 413 — on exactly the boundary
a test suite exists to prove. The limits travel with the application, the shared
driver copies them onto every request beside the observer and the state, and
`serve` DERIVES the backend's options from them at boot. No `Limits` value
crosses the transport boundary: the adapter receives resolved integers, because
a public `web` type there would be the back-edge ADR-009 forbids.

**THE CONCURRENCY DECISION, recorded here because this is where the snapshot is
taken.** `limits` after the first dispatch **REJECTS** the application through
the existing poison mechanism. The snapshot model **sits beside ADR-019 and
ADR-023 and does not replace them**: `use()` after the first dispatch is still
refused for its own reason, and a test asserts that it still is. Nothing shipped
became weaker. Order relative to *routes* is deliberately unconstrained — a
limit protects every route equally, so there is no ordering hazard of the kind
ADR-019 exists for, and rejecting a safe program for resembling an unsafe one
would be a worse error than the one it prevented.

**A ZERO FIELD IS REJECTED.** `Limits{max_body = 1024}` leaves two fields at
zero, and the struct has no unset state to tell a forgotten field from a
deliberate one. Guessing would mean an application silently running on a mix of
its own values and the framework's. Start from `DEFAULT_LIMITS`.

**READ AND WRITE TIMEOUTS ARE NOT HERE, AND THAT IS A FINDING.** The plan named
them and set a stop rule, which this work package hit. The vendored server has
**no read or write deadline to configure**: `Server_Opts` carries
`limit_request_line` and `limit_headers` and nothing temporal, its only
`nbio.timeout_poly` uses are a fixed close delay and a one-second date tick, and
the request read in `vendor/odin-http/scanner.odin` still carries an unfinished-
work comment saying a timeout is wanted there. Real deadlines are
surgery inside the vendored event loop, not a field. Shipping without those
fields is the reversible arm: adding a field later is an amendment, while
shipping one that silently does nothing would be a lie with a version number on
it. **No document may claim Uruquim has configurable timeouts.**

**THE DERIVATION WAS MEASURED, as the plan required, and the measurement does
not distinguish the shapes on cost.** Consumer built at `-o:speed`, one POST
route binding a JSON body:

| Shape | Binary | Δ vs baseline | Request-path branches added | Allocations |
|---|---|---|---|---|
| `origin/main` (fixed 4 MiB constant) | 744,744 B | — | — | 0 |
| **Boot-resolved budget on the Context** (shipped) | 745,216 B | +472 B | **0** — a constant comparison became a field comparison | 0 |
| Configuration re-derived per request | 745,216 B | +472 B | 3 | 0 |

**Byte-identical**, so the amendment's reasoning is not vindicated by size and
this amendment says so. What separates the shapes is the branch count and the
semantics behind it: a per-request derivation can *discover a contradiction
under load*, which is the failure the boot-time validation exists to move to
boot. The evidence supports the choice on the second ground and is silent on the
first.

**ONE DECISION EMERGED DURING IMPLEMENTATION and is recorded rather than
smoothed over: a ZERO budget on the read path resolves to the default.** The
first cut compared directly against `ctx.private.limits.max_body`, which turned
every hand-built `Context` — every internal test suite that constructs one
without the driver — into an application that answers 413 to every body. That is
not failing closed; it is broken. The public contract is unchanged: `web.limits`
still REFUSES a partially-filled `Limits`, so an application can never choose a
zero, and the only way one arrives is a framework-internal omission. The public
API refuses ambiguity; the read path is defensive. `check_public_api.sh` §8c
still requires every constructor to set `DEFAULT_LIMITS`, now as defence in
depth rather than as the only thing standing between a slip and a dead
application — and `check_wp36_controls.sh` control 4 is a PAIR that pins both
halves: with a forgetful constructor the application must still serve (positive),
and with the safety net also removed it must not (negative).

**FINDING-C is discharged in this change.** The capacity ledger's row —
*"request body: 4 MiB, fixed, not configurable until Phase 3"* — is amended in
`planning/phase-2-freeze.md`, and the claim ledger gains a row for the new
promise with its own negative control.

**Freezing this exposed a hole in the freeze gate itself, closed in the same
change.** The signature extractor read procedures, procedure groups and types —
**never constants**. An exported constant is a public symbol whose VALUE is the
contract, so `DEFAULT_LIMITS` would have been invisible to the snapshot and its
value changeable with the frozen inventory unmoved. It is the same class of hole
the proc-group branch was written for. Constants are now extracted from the
FULL `odin doc` view, because the short view renders a struct constant as
`Limits{...}` and elides exactly the values that are the promise.

Evidence rows, same schema as §5:

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `Limits` | A | WP36 | `tests/wp36-public-surface/contract_test.odin::wp36_the_limits_surface_is_pinned` | `tests/wp36-public-surface/contract_test.odin::wp36_a_lowered_body_cap_is_enforced_exactly` | `docs/ai-context.md::web.Limits` | a plain value of three ints; owns nothing, allocates nothing; copied onto the App and onto each request |
| `DEFAULT_LIMITS` | A | WP36 | `tests/wp36-public-surface/contract_test.odin::wp36_the_defaults_are_the_values_already_shipped` | `tests/wp36-public-surface/contract_test.odin::wp36_an_application_that_never_configures_anything_still_works` | `docs/ai-context.md::web.DEFAULT_LIMITS` | a compile-time constant; unassignable, so no library can change another's defaults |
| `limits` | A | WP36 | `tests/wp36-public-surface/contract_test.odin::wp36_the_limits_surface_is_pinned` | `tests/wp36-public-surface/contract_test.odin::wp36_limits_after_the_first_dispatch_rejects_the_application` | `docs/ai-context.md::web.limits` | stores three ints on the App; validates at the call so the request path only compares; rejects fail-closed after the first dispatch |

## Amendment 13 — WP46: the request deadline joins `Limits`

**Date: 2026-07-21. Authority: the ADR-029 delegation, over ADR-031 (ACCEPTED,
as amended).**
**Ledger effect: NONE. 50 application + 2 test-support = 52, unchanged.**
No symbol is added. `Limits` gains a FIELD and `DEFAULT_LIMITS` gains the value
for it, which is a signature amendment rather than a ledger one — and it is
recorded here for exactly that reason: the snapshot diff was two changed lines,
and a changed line in a frozen signature needs the same ceremony as a new one.

The two amended rows:

```
application	const	DEFAULT_LIMITS :: Limits{..., max_request_time = REQUEST_TIME_LIMIT}
application	type	Limits :: struct {..., max_request_time: i64}
```

**WHY A FIELD RATHER THAN A NEW SYMBOL.** WP36 established the shape and its
cost: a public options struct is a promise per field. Adding a field is the
cheap direction of that asymmetry, and it keeps one answer to "how do I bound
this server" rather than two.

**WHAT IT BOUNDS, precisely, because the name could be read three ways.**
`max_request_time` is how long ONE request may take to **arrive** — first byte
to last. It is a REQUEST deadline, not an idle timeout: an idle timer is reset
by every byte, so a client trickling one byte per second resets it forever, and
that client is exactly the attack. It does **not** bound a handler; a slow
handler is the application's own time, and killing its connection would turn a
slow page into a broken one.

**THE TYPE IS `i64` NANOSECONDS RATHER THAN `time.Duration`**, and that is
FINDING-B rather than taste: `package web` may not import `core:time`, because
an application would then link a clock merely because the framework can
configure one. The neutral transport boundary carries a plain integer and the
adapter converts on the side where a clock is already linked.

**THIS IS THE FIRST DEFAULT THAT CHANGES BEHAVIOUR FOR AN APPLICATION THAT NEVER
MENTIONS LIMITS.** Every previous default restated what already shipped. This
one closes a connection that would previously have been held open forever. It is
a security fix rather than a tuning knob, and it is called out here because
WP36's own rule says tightening a default breaks traffic without breaking a
build — a rule this deliberately accepts rather than evades.

**THE NUMBER IS JUDGEMENT AND IS RECORDED AS SUCH** (the C-5 honesty rule).
Thirty seconds: no specification sets it, and the sources that discuss slowloris
name the technique and no figure. It is far longer than any legitimate client
needs to send a request over a working network — a large upload is bounded by
`max_body`, not by this — and far shorter than the "forever" that shipped
before.

**ZERO MEANS NO DEADLINE, and validation permits it** where the byte budgets
refuse zero. An operator must be able to ask for the previous behaviour
explicitly, and asking explicitly is the difference between a deliberate choice
and a forgotten field.

**ONE NEW DIRECT DEPENDENCY, and the gate made it deliberate.**
`web/internal/transport` now imports `core:time`. That is the FINDING-B line
being honoured rather than crossed: the clock lives on the transport side, where
`core:nbio` and the vendored server already link one, and **`package web` still
imports no clock** — which is why `max_request_time` is an `i64` and not a
`time.Duration`. The dependency snapshot and this manifest were updated
together, which is what the freeze gate refuses to let happen separately.

**Evidence.** `tests/wp41-fault` — the same laboratory that demonstrated the
hole. Its `phase_truncated_hold` and `phase_trickle` still assert the old
behaviour against a server with **no** deadline configured, and two new phases
assert the connection is closed when one **is**. The positive control runs
first: a deadline that also refused valid traffic would pass the new assertions
while breaking the server.

| Symbol | L | Owner | Compile evidence | Behavior evidence | Docs | Ownership |
|---|---|---|---|---|---|---|
| `Limits.max_request_time` | A | WP46 | `build/phase1-public-signatures.txt` (the frozen row) | `tests/wp41-fault/fault_test.odin::phase_deadline_ends_a_held_connection` | `docs/ai-context.md::web.Limits` | a plain `i64` on a value type; owns nothing; converted to a duration at the transport boundary |
