# Phase 1 — Normative Freeze Manifest (WP11)

This is the **permanent, normative record** of what Phase 1 froze, and the
evidence each frozen line rests on. It is not a status report and it is not
temporary: `build/check_phase1_freeze.sh` parses this file on every gate run
and fails the gate when a frozen claim loses its evidence.

What FREEZE means here — and what it does not:

- **Frozen** = the Phase-1 contracts below are protected by an executable
  gate. Changing any of them requires a spec amendment: editing this manifest
  and the snapshots under `build/` in the same reviewed change.
- Internals stay replaceable. The linear route table, the response driver,
  the recorder and the transport adapter are NOT frozen — only their
  observable contracts are.
- Freeze is **not** a release. No tag, no version, no stability promise
  beyond the gate itself. A semantic release stays a human decision.
- Phase 1 is accepted only when a human reviews and merges the WP11 PR and
  the merged commit passes the independent VPS verifier (`ops/ci/`).

## Status

Freeze state: CANDIDATE — gate-verified locally; human merge and the
post-merge VPS run on `main` are still pending, and only they complete the
acceptance.

An open blocker assigned to Phase 1 must be recorded in a planning document
with the marker token defined in `build/check_phase1_freeze.sh` §7; the gate
is red while one exists. None is recorded.

## Toolchain

| Item | Value |
| --- | --- |
| Odin release | `dev-2026-07a` (pin: `odin-version.txt`) |
| Commit | `819fdc7` |
| Verified by | `build/check.sh` (refuses any other compiler) |

## Frozen surface

The single source of truth for the frozen surface is the compiler:
`odin doc web` on the pinned toolchain, normalized by
`build/check_phase1_freeze.sh` (location comments stripped; nothing else
rewritten), compared byte-for-byte against:

- `build/phase1-public-signatures.txt` — all 34 declarations: exact
  argument lists, results, genericity, struct fields, enum members and
  backing types.
- `build/phase1-direct-dependencies.txt` — the direct imports of every
  shipped package, the vendored transitive dependency, and the example
  programs' imports.

Ledgers: **32 application symbols + 2 test-support symbols = 34**, disjoint.

Application types (7): `App`, `Context`, `Handler`, `Header_View`, `Method`,
`Request`, `Status`.

Application procedures (25): `app`, `bad_request`, `bare`, `body`, `created`,
`delete`, `destroy`, `forbidden`, `get`, `internal_error`, `json`,
`no_content`, `not_found`, `ok`, `patch`, `path`, `path_int`, `post`, `put`,
`query`, `query_int`, `query_int_or`, `serve`, `text`, `unauthorized`.

Test-support (2): `Recorded_Response`, `test_request`.

Frozen with the snapshot (because `odin doc` prints them inline):

- every public field: `App{private}`, `Context{request, private}`,
  `Header_View{private}`, `Request{method, path, query, headers, body}`,
  `Recorded_Response{status, body}`;
- enum backing types and exact members: `Method :: enum u8` with
  `UNKNOWN, GET, POST, PUT, PATCH, DELETE`; `Status :: enum int` with the
  ten ratified members `200, 201, 202, 204, 400, 401, 403, 404, 405, 500`;
- the canonical handler shape `Handler :: proc(ctx: ^Context)` (ADR-011);
- genericity: `body(ctx, dst: ^$T) -> bool`, `json(ctx, status, value: $T)`,
  `ok(ctx, value: $T)`, `created(ctx, value: $T)` — and nothing else generic;
- named results on the fallible extractors (`value, ok` / `value, found`)
  and the absence of `#optional_ok` everywhere (ADR-002, plus the three
  discard probes in `build/check.sh`);
- HTTP 413 stays a **private** value (`Status(413)` in `web/errors.odin`):
  the gate rejects any public `Status` member containing `413`.

## Evidence matrix

Every row below must point at evidence that exists and executes in
`build/check.sh`. The checker verifies each referenced path exists and each
`::identifier` occurs in the referenced file. A row may only say `PROVEN`;
anything else keeps the gate RED. "Covered by the general gate" is not
evidence and appears nowhere below.

<!-- evidence-matrix:begin -->

| Symbol | Ledger | Owner | Compile evidence | Behavior evidence | Docs evidence | Ownership | Dependencies | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `App` | application | WP1/WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_destroy_releases_the_table_exactly_once` <br> `tests/wp4-internal/wp4_internal_test.odin::wp4_an_app_with_no_routes_allocates_nothing` | `docs/ai-context.md` <br> `examples/01-hello-world/main.odin` | owns route table, pattern copies and lazy test-support state; by value; destroy once on the original value (ADR-001) | `uruquim:web/testing` (lazy recorder state type) | PROVEN |
| `Context` | application | WP1/WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_context_carries_the_request` | `tests/wp2-public-surface/probes/context_has_no_response.odin` (must not compile) <br> `tests/wp2-public-surface/contract_test.odin::wp2_context_carries_the_request` | `docs/ai-context.md` | borrows request views for one request; private slot reachable by contract, not barrier (ADR-008) | `core:mem` (private arena field) | PROVEN |
| `Handler` | application | WP1 | `tests/wp2-public-surface/contract_test.odin::wp2_handler_signature_is_unchanged` | `tests/wp4-public-surface/contract_test.odin::wp4_registered_route_is_reached_exactly_once` | `docs/ai-context.md` | borrows `^Context` for the call; returns nothing (ADR-011) | none beyond package | PROVEN |
| `Header_View` | application | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_request_exposes_the_ratified_fields` | `tests/wp2-internal/wp2_internal_test.odin::wp2_header_view_wraps_pairs_without_copying` <br> `tests/wp2-public-surface/probes/header_pair_not_exported.odin` (must not compile) | `docs/ai-context.md` | view over transport-owned pairs; valid during the request; no public lookup in Phase 1 | none beyond package | PROVEN |
| `Method` | application | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_method_members_are_uppercase` | `tests/wp2-internal/wp2_internal_test.odin::wp2_unsupported_method_tokens_convert_to_unknown` <br> `tests/wp8-internal/wp8_internal_test.odin::wp8_method_token_round_trip` | `docs/ai-context.md` <br> `docs/transport-conformance.md` | plain value enum u8; `.UNKNOWN` is a conversion result, never an HTTP decision | none beyond package | PROVEN |
| `Request` | application | WP2 | `tests/wp2-public-surface/contract_test.odin::wp2_request_exposes_the_ratified_fields` | `tests/wp2-internal/wp2_internal_test.odin::wp2_buffer_reuse_invalidates_retained_views` <br> `tests/wp2-internal/wp2_internal_test.odin::wp2_explicit_copy_survives_buffer_reuse` | `docs/ai-context.md` | every field is a view over transport-owned storage; copy explicitly to persist (G-05, ADR-007) | none beyond package | PROVEN |
| `Status` | application | WP6 | `tests/wp3-public-surface/contract_test.odin::wp3_recorded_response_exposes_status_and_body` | `tests/wp6-internal/wp6_internal_test.odin::wp6_json_preserves_an_arbitrary_status` <br> `tests/wp7-internal/wp7_internal_test.odin::wp7_body_too_large_reports_413` (413 stays private) | `docs/errors.md` <br> `docs/ai-context.md` | plain value enum int; ten public members only | none beyond package | PROVEN |
| `app` | application | WP1/WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_an_app_with_no_routes_allocates_nothing` <br> `tests/wp4-internal/wp4_internal_test.odin::wp4_app_commits_404_on_path_miss` | `docs/quick-start.md` <br> `examples/01-hello-world/main.odin` | returns App by value; allocates nothing until the first registration | none beyond package | PROVEN |
| `bad_request` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_error_helpers_produce_the_ratified_envelopes` | `docs/errors.md` <br> `examples/03-route-params/main.odin` | envelope rendered into request-local storage; single commit | `core:encoding/json` (message escaping) | PROVEN |
| `bare` | application | WP1/WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-public-surface/contract_test.odin::wp4_bare_dispatches_but_installs_no_defaults` <br> `tests/wp8-internal/wp8_internal_test.odin::wp8_bare_miss_is_uncommitted_until_the_driver_finalizes` | `docs/ai-context.md` | returns App by value; installs no default 404/405 policy | none beyond package | PROVEN |
| `body` | application | WP7 | `tests/wp7-public-surface/contract_test.odin::wp7_signature_is_the_canonical_destination_filling_shape` | `tests/wp7-internal/wp7_internal_test.odin::wp7_one_over_the_limit_is_too_large_before_parse_and_arena` <br> `tests/wp7-internal/wp7_internal_test.odin::wp7_second_bind_after_success_reports_and_500s` <br> `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops` | `docs/quick-start.md` <br> `examples/02-json-api/main.odin` | single consumer; decoded nested data lives in the request arena, released once at request end (ADR-006/ADR-012) | `core:encoding/json` (strict decode) <br> `core:mem` (arena) | PROVEN |
| `created` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_created_returns_201` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_created_is_byte_identical_to_json_created` | `docs/ai-context.md` <br> `examples/02-json-api/main.odin` | delegates to `json(.Created)`; body owned by the internal Response (ADR-014) | `core:encoding/json` (marshal) | PROVEN |
| `delete` | application | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_methods_are_isolated` <br> `tests/wp4-public-surface/contract_test.odin::wp4_every_verb_registers` | `docs/ai-context.md` <br> `examples/02-json-api/main.odin` | App clones the pattern; released by destroy | none beyond package | PROVEN |
| `destroy` | application | WP1/WP3/WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_destroy_releases_the_table_exactly_once` <br> `tests/wp3-internal/wp3_internal_test.odin::wp3_destroy_releases_everything_exactly_once` <br> `tests/wp3-public-surface/contract_test.odin::wp3_unused_test_support_is_a_noop_destroy` | `docs/quick-start.md` <br> `examples/01-hello-world/main.odin` | releases routes, patterns and recorder exactly once; second call is a safe no-op; call on the original value only | `uruquim:web/testing` (guarded teardown pointer) | PROVEN |
| `forbidden` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_error_helpers_produce_the_ratified_envelopes` | `docs/errors.md` | envelope in request-local storage; single commit | `core:encoding/json` (message escaping) | PROVEN |
| `get` | application | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_static_route_matches_and_runs_handler_once` <br> `tests/wp4-public-surface/contract_test.odin::wp4_registered_route_is_reached_exactly_once` | `docs/quick-start.md` <br> `examples/01-hello-world/main.odin` | App clones the pattern; released by destroy | none beyond package | PROVEN |
| `internal_error` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` <br> `tests/wp8-internal/wp8_internal_test.odin::wp8_uncommitted_response_is_finalized_to_500` | `docs/errors.md` | static envelope, no caller message; also the framework's terminal fallback | none beyond package | PROVEN |
| `json` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_json_carries_an_arbitrary_status` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_marshal_failure_is_logged_before_the_commit` <br> `tests/wp6-public-surface/contract_test.odin::wp6_unmarshalable_payload_yields_a_complete_500` | `docs/ai-context.md` | value payload marshalled into a Response-owned body, released by the driver teardown exactly once (ADR-014); marshal failure logs then commits a clean 500 | `core:encoding/json` (marshal) | PROVEN |
| `no_content` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_no_content_returns_204_and_an_empty_body` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_no_content_allocates_nothing` | `docs/ai-context.md` <br> `examples/02-json-api/main.odin` | allocates nothing; empty body, no Content-Type | none beyond package | PROVEN |
| `not_found` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_not_found_escapes_the_resource_name` | `docs/errors.md` <br> `examples/02-json-api/main.odin` | composes and escapes the resource name into request-local storage; distinct from the automatic route 404 | `core:encoding/json` (message escaping) | PROVEN |
| `ok` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_ok_returns_200_with_a_json_body` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_ok_is_byte_identical_to_json_ok` | `docs/quick-start.md` <br> `examples/02-json-api/main.odin` | delegates to `json(.OK)`; byte-identical output is behavior-tested, which is what licenses the shorthand (G-01) | `core:encoding/json` (marshal) | PROVEN |
| `patch` | application | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_methods_are_isolated` <br> `tests/wp4-public-surface/contract_test.odin::wp4_every_verb_registers` | `docs/ai-context.md` <br> `examples/02-json-api/main.odin` | App clones the pattern; released by destroy | none beyond package | PROVEN |
| `path` | application | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` | `tests/wp5-public-surface/contract_test.odin::wp5_path_with_an_unknown_name_is_empty_and_does_not_respond` <br> `tests/wp5-internal/wp5_internal_test.odin::wp5_path_value_is_a_view_over_the_request_path` | `docs/ai-context.md` <br> `examples/03-route-params/main.odin` | returns a view over the request path; valid during the request; never responds | none beyond package | PROVEN |
| `path_int` | application | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` <br> `tests/wp5-public-surface/probes/discard_path_int_ok.odin` (must not compile) | `tests/wp5-public-surface/contract_test.odin::wp5_path_int_failure_is_a_complete_400_over_the_public_surface` <br> `tests/wp5-internal/wp5_internal_test.odin::wp5_path_int_rejects_empty_text_and_overflow` | `docs/quick-start.md` <br> `examples/02-json-api/main.odin` | value copy plus ok; on failure commits the `invalid_path_parameter` 400 into request-local storage | none beyond package | PROVEN |
| `post` | application | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_methods_are_isolated` <br> `tests/wp4-public-surface/contract_test.odin::wp4_every_verb_registers` | `docs/ai-context.md` <br> `examples/02-json-api/main.odin` | App clones the pattern; released by destroy | none beyond package | PROVEN |
| `put` | application | WP4 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp4-internal/wp4_internal_test.odin::wp4_methods_are_isolated` <br> `tests/wp4-public-surface/contract_test.odin::wp4_every_verb_registers` | `docs/ai-context.md` <br> `examples/02-json-api/main.odin` | App clones the pattern; released by destroy | none beyond package | PROVEN |
| `query` | application | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` | `tests/wp5-internal/wp5_internal_test.odin::wp5_query_first_occurrence_wins` <br> `tests/wp5-internal/wp5_internal_test.odin::wp5_query_does_not_decode_anything` <br> `tests/wp5-public-surface/contract_test.odin::wp5_query_reads_the_public_request_query` | `docs/ai-context.md` <br> `examples/03-route-params/main.odin` | returns a view over the request query; valid during the request; never responds | none beyond package | PROVEN |
| `query_int` | application | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` <br> `tests/wp5-public-surface/probes/discard_query_int_ok.odin` (must not compile) | `tests/wp5-public-surface/contract_test.odin::wp5_query_int_missing_responds_400_over_the_public_surface` <br> `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_present_but_invalid_commits_the_integer_envelope` | `docs/ai-context.md` <br> `examples/03-route-params/main.odin` | value copy plus ok; absence and malformation both commit the `invalid_query_parameter` 400 | none beyond package | PROVEN |
| `query_int_or` | application | WP5 | `tests/wp5-public-surface/contract_test.odin::wp5_extractor_signatures_are_exact` <br> `tests/wp5-public-surface/probes/discard_query_int_or_ok.odin` (must not compile) | `tests/wp5-public-surface/contract_test.odin::wp5_query_int_or_uses_the_default_only_for_absence` <br> `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_or_never_substitutes_the_default_for_a_malformed_value` | `docs/ai-context.md` <br> `examples/03-route-params/main.odin` | value copy plus ok; default applies only when the key is absent; malformed is a 400 | none beyond package | PROVEN |
| `serve` | application | WP8 | `tests/wp7-public-surface/contract_test.odin::wp7_test_request_signature_is_unchanged` (serve signature pinned alongside) <br> `tests/wp9-public-surface/contract_test.odin::wp9_public_surface_is_unchanged` | `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops` <br> `tests/wp9-semantic/http_factory_test.odin::wp9_semantic_matrix_on_the_real_http_transport` <br> `tests/wp9-wire/wire_test.odin::wp9_raw_wire_corpus` | `docs/quick-start.md` <br> `examples/01-hello-world/main.odin` | blocks while serving; invalid port or bind failure is logged and returns; transport selection stays private (ADR-009) | `uruquim:web/internal/transport` (private boundary; the adapter alone names the vendored backend) | PROVEN |
| `text` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_text_returns_a_plain_body` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_text_copies_the_caller_buffer` | `docs/quick-start.md` <br> `examples/01-hello-world/main.odin` | copies the caller string into a Response-owned body; released by teardown exactly once | none beyond package | PROVEN |
| `unauthorized` | application | WP6 | `tests/wp1-public-api/contract_test.odin::wp1_public_api_surface_compiles` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_error_helpers_produce_the_ratified_envelopes` | `docs/errors.md` | envelope in request-local storage; single commit | `core:encoding/json` (message escaping) | PROVEN |
| `Recorded_Response` | test-support | WP3 | `tests/wp3-public-surface/contract_test.odin::wp3_recorded_response_exposes_status_and_body` <br> `tests/wp3-public-surface/probes/recorded_response_has_no_headers.odin` (must not compile) | `tests/wp3-public-surface/contract_test.odin::wp3_two_recorded_responses_survive_until_destroy` <br> `tests/wp6-public-surface/contract_test.odin::wp6_earlier_bodies_survive_later_requests` | `docs/ai-context.md` <br> `docs/quick-start.md` | `status` copied by value; `body` is a view over an App-owned copy, valid until `destroy(&app)`; no per-response cleanup | none beyond package | PROVEN |
| `test_request` | test-support | WP3 | `tests/wp7-public-surface/contract_test.odin::wp7_test_request_signature_is_unchanged` | `tests/wp3-public-surface/contract_test.odin::wp3_test_request_runs_in_memory_without_routing` <br> `tests/wp4-public-surface/contract_test.odin::wp4_registered_route_is_reached_exactly_once` <br> `tests/wp8-internal/wp8_internal_test.odin::wp8_test_request_finalizes_a_silent_handler_to_500` <br> `build/check_g11_teardown.sh` (zero teardown symbols when unused) | `docs/quick-start.md` <br> `docs/ai-context.md` | creates the recorder lazily on first call with `context.allocator`; every copy released by `destroy(&app)`; no socket (static import ban) | `uruquim:web/internal/transport` (shared driver pipeline) <br> `uruquim:web/testing` (recorder) | PROVEN |

<!-- evidence-matrix:end -->

## Frozen behavioral contracts

Each contract line cites the executable evidence that proves it. All of it
runs inside `env -u ODIN_ROOT URUQUIM_ODIN_BIN=… bash build/check.sh`.

### App lifecycle

- `app()` returns App **by value**; App is **non-copyable by contract** — a
  copy must never be destroyed independently (ADR-001, ratified by
  experiment 01; `tests/wp4-internal/wp4_internal_test.odin::wp4_destroy_releases_the_table_exactly_once`).
- `destroy` runs once on the original value; the second call is a safe
  no-op; routes, pattern copies and recorder are released **exactly once**
  (`tests/wp4-internal/wp4_internal_test.odin::wp4_destroy_releases_the_table_exactly_once`,
  `tests/wp3-internal/wp3_internal_test.odin::wp3_destroy_releases_everything_exactly_once`).
- `bare()` installs no default 404/405
  (`tests/wp4-public-surface/contract_test.odin::wp4_bare_dispatches_but_installs_no_defaults`,
  `tests/wp8-internal/wp8_internal_test.odin::wp8_bare_miss_is_uncommitted_until_the_driver_finalizes`).

### Routing (observable contract only — the linear table is internal and replaceable)

- Static routes and at most **one `:param`** per pattern; an unsupported
  pattern never matches and never contributes to `Allow`
  (`tests/wp4-public-surface/contract_test.odin::wp4_unsupported_pattern_never_routes`,
  `tests/wp4-internal/wp4_internal_test.odin::wp4_pattern_with_two_params_never_matches`).
- Static beats param in **both** registration orders
  (`tests/wp4-internal/wp4_internal_test.odin::wp4_static_beats_param_when_static_registered_first`,
  `tests/wp4-internal/wp4_internal_test.odin::wp4_static_beats_param_when_param_registered_first`).
- Per-method isolation; the matched handler runs exactly once
  (`tests/wp4-public-surface/contract_test.odin::wp4_methods_are_isolated_publicly`,
  `tests/wp4-public-surface/contract_test.odin::wp4_registered_route_is_reached_exactly_once`).
- Automatic 404 on `app()` path miss; automatic 405 with the header named
  exactly `Allow`, canonical order `GET, POST, PUT, PATCH, DELETE`, only
  registered methods, no duplicates
  (`tests/wp4-public-surface/contract_test.odin::wp4_app_returns_404_for_an_unknown_path`,
  `tests/wp4-internal/wp4_internal_test.odin::wp4_allow_is_the_first_header_with_the_exact_name`,
  `tests/wp4-internal/wp4_internal_test.odin::wp4_allow_uses_the_canonical_method_order`).
- An unknown method follows the same 404/405 policy and **never becomes
  501** (`tests/wp4-public-surface/contract_test.odin::wp4_unknown_method_follows_404_and_405_never_501`;
  raw-wire case 25 in `tests/support/transport_conformance/corpus.odin`).
- **No normalization**: trailing slashes, segment counts and encodings are
  matched literally
  (`tests/wp4-internal/wp4_internal_test.odin::wp4_trailing_slash_is_not_normalized`,
  `tests/wp4-internal/wp4_internal_test.odin::wp4_segment_count_must_match_exactly`).
- Registration conflicts are **not diagnosed** in Phase 1; precedence and
  registration order decide. Conflict diagnostics are Phase-3 router work.

### Request and lifetimes

- `Request` is `method, path, query, headers, body`; every non-enum field is
  a **view** over transport-owned storage, valid only during the request;
  persisting requires an explicit copy
  (`tests/wp2-internal/wp2_internal_test.odin::wp2_buffer_reuse_invalidates_retained_views`,
  `tests/wp2-internal/wp2_internal_test.odin::wp2_explicit_copy_survives_buffer_reuse`).
- No `^Context` and no view may be handed to background work (G-05,
  normative; encapsulation is by contract, not compiler barrier — the
  ratified fact is pinned by the probe
  `tests/wp2-public-surface/probes/internal_slot_is_reachable.odin`, which
  must keep compiling).
- `Header_View` exposes **no public lookup** in Phase 1
  (`tests/wp2-public-surface/probes/header_pair_not_exported.odin`).

### Extractors

- `path` returns a view `string` and never responds; unknown name yields
  empty (`tests/wp5-public-surface/contract_test.odin::wp5_path_with_an_unknown_name_is_empty_and_does_not_respond`).
- `query` returns `(value, found)`, a view, and never responds
  (`tests/wp5-public-surface/contract_test.odin::wp5_query_reads_the_public_request_query`).
- `path_int`, `query_int`, `query_int_or` return `(value, ok)` with **no
  `#optional_ok`** — dropping `ok` is a compile error (the three discard
  probes under `tests/wp5-public-surface/probes/`); on failure they commit
  the standardized 400 and continued handler code cannot replace it
  (`tests/wp5-public-surface/contract_test.odin::wp5_continued_handler_code_cannot_replace_the_400`).
- `query_int_or`'s default applies **only on absence**; a present, empty or
  malformed value is a 400
  (`tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_or_never_substitutes_the_default_for_a_malformed_value`,
  `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_or_treats_an_empty_value_as_malformed_not_absent`).
- Strict decimal integers only (`0x1f`, `1_000`, `+42`, `4.2`, spaces and
  overflow all rejected;
  `tests/wp5-internal/wp5_internal_test.odin::wp5_path_int_rejects_empty_text_and_overflow`).
- Names are case-sensitive; **no percent-decoding** anywhere; the **first**
  duplicate query key wins, with no multi-value promise
  (`tests/wp5-internal/wp5_internal_test.odin::wp5_query_is_case_sensitive`,
  `tests/wp5-internal/wp5_internal_test.odin::wp5_query_does_not_decode_anything`,
  `tests/wp5-internal/wp5_internal_test.odin::wp5_query_first_occurrence_wins`).

### Body binding

- One consumer per request: the **first** `body` call consumes the
  capability whether it succeeds or fails; a second call never reprocesses,
  never double-commits, and reports the framework error before a 500
  (`tests/wp7-internal/wp7_internal_test.odin::wp7_a_failed_first_bind_still_consumes_the_capability`,
  `tests/wp7-internal/wp7_internal_test.odin::wp7_second_bind_after_success_reports_and_500s`,
  `tests/wp7-internal/wp7_internal_test.odin::wp7_second_bind_never_double_commits`).
- Empty or invalid JSON → 400 `invalid_json`; strict JSON only (JSON5
  rejected) (`tests/wp7-internal/wp7_internal_test.odin::wp7_empty_body_is_invalid_json_and_makes_no_arena`,
  `tests/wp7-internal/wp7_internal_test.odin::wp7_json5_is_rejected`).
- Fixed 4 MiB limit, checked **before** parser and arena; exactly the limit
  passes, one byte over is the private 413 `body_too_large`
  (`tests/wp7-internal/wp7_internal_test.odin::wp7_exactly_the_limit_is_not_too_large`,
  `tests/wp7-internal/wp7_internal_test.odin::wp7_one_over_the_limit_is_too_large_before_parse_and_arena`,
  over the wire in `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops`).
- Decoded nested data lives in the request-local arena; released exactly
  once; a request that never binds creates no arena
  (`tests/wp7-internal/wp7_internal_test.odin::wp7_decoded_data_lives_in_the_request_arena`,
  `tests/wp7-internal/wp7_internal_test.odin::wp7_second_teardown_is_a_safe_no_op`,
  `tests/wp7-internal/wp7_internal_test.odin::wp7_a_request_that_never_binds_makes_no_arena`).
- Internal decode failure is logged, then a clean 500
  (`tests/wp7-internal/wp7_internal_test.odin::wp7_incompatible_destination_logs_and_500s`).

### Response

- The `Response` type and its commit state are **private**; `Context` has no
  public response field
  (`tests/wp2-public-surface/probes/context_has_no_response.odin`).
- **First commit wins**, atomically across status, headers and body
  (`tests/wp6-public-surface/contract_test.odin::wp6_the_first_response_wins`,
  `tests/wp2-internal/wp2_internal_test.odin::wp2_second_commit_is_rejected_and_changes_nothing`).
- `json`/`text` bodies are copied into (or rendered as) Response-owned
  allocations and released by the teardown exactly once, after the response
  was captured or written
  (`tests/wp6-internal/wp6_internal_test.odin::wp6_text_copies_the_caller_buffer`,
  `tests/wp6-internal/wp6_internal_test.odin::wp6_teardown_releases_exactly_once`,
  `tests/wp6-internal/wp6_internal_test.odin::wp6_response_owns_the_rendered_body`).
- Marshal failure is **logged before** the 500 commit and never leaves a
  partial body
  (`tests/wp6-internal/wp6_internal_test.odin::wp6_marshal_failure_is_logged_before_the_commit`,
  `tests/wp6-internal/wp6_internal_test.odin::wp6_marshal_failure_leaves_no_partial_body`).
- Payloads are **values**; a pointer payload is not part of the contract and
  observably follows the rejection path to a clean 500
  (`tests/wp6-internal/wp6_internal_test.odin::wp6_pointer_payload_follows_the_rejection_path`).
- Automatic headers: `application/json` for JSON and envelopes,
  `text/plain; charset=utf-8` for text; 405 keeps `Allow` first; 204 is
  empty with no Content-Type; Content-Length is written by the transport
  (`tests/wp6-internal/wp6_internal_test.odin::wp6_json_sets_the_exact_content_type`,
  `tests/wp6-internal/wp6_internal_test.odin::wp6_automatic_405_is_a_json_envelope_and_keeps_allow`,
  `tests/wp6-internal/wp6_internal_test.odin::wp6_no_content_is_empty_and_header_free`,
  `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops`).

### Errors — the ten Phase-1 codes

Envelope: `{"error":{"code":…,"message":…,"field":…}}`, `field` present
**only** for the two extractor codes and omitted entirely otherwise
(AMEND-2; `tests/wp6-internal/wp6_internal_test.odin::wp6_field_is_absent_not_empty`).
Content-Type is always `application/json`; every envelope re-parses under
the official strict `.JSON` parser in the tests; single commit throughout.

| Code | Status | Field | Ratified message | End-to-end evidence |
| --- | --- | --- | --- | --- |
| `invalid_path_parameter` | 400 | yes | `Path parameter '<name>' must be an integer` | `tests/wp5-public-surface/contract_test.odin::wp5_path_int_failure_is_a_complete_400_over_the_public_surface` |
| `invalid_query_parameter` | 400 | yes | `Query parameter '<name>' is required` / `… must be an integer` | `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_absent_commits_the_required_envelope` <br> `tests/wp5-internal/wp5_internal_test.odin::wp5_query_int_present_but_invalid_commits_the_integer_envelope` |
| `invalid_json` | 400 | no | `Request body must be valid JSON` | `tests/wp7-public-surface/contract_test.odin::wp7_body_handler_via_test_request_produces_invalid_json` |
| `body_too_large` | 413 (private status) | no | `Request body exceeds the 4 MiB limit` | `tests/wp7-internal/wp7_internal_test.odin::wp7_body_too_large_reports_413` <br> `tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops` |
| `bad_request` | 400 | no | caller message verbatim (escaped) | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` |
| `not_found` | 404 | no | `Resource '<r>' not found` (helper) / `Route not found` (automatic) | `tests/wp6-public-surface/contract_test.odin::wp6_automatic_404_carries_an_envelope` <br> `tests/wp6-internal/wp6_internal_test.odin::wp6_not_found_escapes_the_resource_name` |
| `method_not_allowed` | 405 | no | `Method not allowed` | `tests/wp6-public-surface/contract_test.odin::wp6_automatic_405_carries_an_envelope` |
| `unauthorized` | 401 | no | caller message verbatim (escaped) | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` |
| `forbidden` | 403 | no | caller message verbatim (escaped) | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` |
| `internal_error` | 500 | no | `Internal server error` | `tests/wp6-public-surface/contract_test.odin::wp6_error_helpers_are_observable_end_to_end` <br> `tests/wp8-internal/wp8_internal_test.odin::wp8_uncommitted_response_is_finalized_to_500` |

Protocol errors raised before an Inbound request exists (bad framing,
smuggling attempts, oversized reads at the transport) stay **outside** the
public envelope, per `docs/transport-conformance.md` and the wire corpus.

### Test-support

- Exactly two symbols; `Recorded_Response` is `status, body` and nothing
  else (`tests/wp3-public-surface/probes/recorded_response_has_no_headers.odin`).
- `body` stays valid, alongside every earlier response from the same App,
  until `destroy(&app)`; there is no public per-response cleanup
  (`tests/wp3-public-surface/contract_test.odin::wp3_two_recorded_responses_survive_until_destroy`,
  `tests/wp6-public-surface/contract_test.odin::wp6_earlier_bodies_survive_later_requests`).
- No socket anywhere on the path — a **static** property: the facade and
  machinery may not import `core:net`/`core:nbio`/`core:sys`
  (`build/check_public_api.sh`).
- The recorder is lazy: created on the first `test_request`, with
  `context.allocator`; an application that never calls `test_request` runs
  no initializer and links **zero** recorder-teardown symbols — asserted
  with `nm` on a real consumer binary, with a positive control and a
  mutation control (`build/check_g11_teardown.sh`).

### Transport (conceptual contract only — the private ABI is not frozen)

- The frozen shape is `accept → dispatch → commit → stop`; the backend never
  appears in a public signature (snapshot + `build/check_public_api.sh`).
- The body is limited during the read; the response is copied before
  cleanup; a handler that never responds is finalized by the driver to a
  logged 500 on **both** transports
  (`tests/wp8-internal/wp8_internal_test.odin::wp8_uncommitted_response_is_finalized_to_500`,
  `tests/wp8-internal/wp8_internal_test.odin::wp8_test_request_finalizes_a_silent_handler_to_500`).
- `stop` is basic and idempotent; after it the port no longer accepts
  (`tests/wp8-socket/socket_test.odin::wp8_real_server_serves_and_stops`).
- Semantic conformance: one shared 20-scenario matrix runs on **both** the
  in-memory and the real HTTP transport
  (`tests/wp9-semantic-internal/memory_factory_test.odin::wp9_semantic_matrix_on_the_memory_transport`,
  `tests/wp9-semantic/http_factory_test.odin::wp9_semantic_matrix_on_the_real_http_transport`).
- Defensive framing: the 25-case raw-wire corpus runs against the real
  adapter (`tests/wp9-wire/wire_test.odin::wp9_raw_wire_corpus`), covering
  smuggling-shaped inputs (Content-Length + Transfer-Encoding, duplicate and
  malformed Content-Length, chunked truncations), request desync, and DoS
  regressions fixed in WP9; `Expect: 100-continue` is refused with 417 and
  the connection closes (corpus case 24;
  `tests/support/transport_conformance/corpus.odin`).

## Dependency and vendor audit

Canonical inventory: `build/phase1-direct-dependencies.txt` (compared on
every gate run). Summary and policies, each enforced by a named gate:

- `web` imports exactly `core:encoding/json`, `core:mem`, `core:strings`
  plus its two internal packages. Nothing else may enter
  (`build/check_public_api.sh` §7; freeze gate §5).
- `web/testing` imports only `core:mem`, `core:strings`. It may not import
  `uruquim:web` (compile cycle, probe C5) nor any networking package
  (`build/check_public_api.sh`).
- `web/internal/transport` imports `core:mem`, `core:net`, `core:slice`,
  `core:strings` and — **only inside the adapter file** — the vendored
  backend (`build/check_public_api.sh`, adapter-only rule).
- Examples import exactly `uruquim:web`; no vendor, no internals
  (`build/check_examples.sh`; freeze gate §5).
- No backend type appears in any exported declaration (snapshot +
  `build/check_public_api.sh` §6).
- No `core:testing` in any shipped first-party package (freeze gate §5).
- No networking dependency on the `test_request` path (static import ban).

Vendored transitive dependency:

| Item | Value |
| --- | --- |
| Package | `vendor/odin-http` (`laytan/odin-http`, server root package) |
| Upstream commit | `112c49b5bcee31308a695cc3f05d156d314a61a6` (2026-04-11) |
| License | MIT — `vendor/odin-http/LICENSE` (Copyright 2023 Laytan Laats) |
| Vendored on | 2026-07-19, toolchain-verified on `819fdc7` |
| Local patches | Five, all WP9, all security-motivated, each marked `URUQUIM PATCH` in source and tabulated in `vendor/odin-http/VENDOR.md` |

Known and accepted: two vendored files carry upstream in-file `@(test)`
blocks (and their `core:testing` imports) — `vendor/odin-http/allocator.odin`
and `vendor/odin-http/http.odin`. They ship in the vendor tree, not in the
first-party packages; the linker's dead-code elimination keeps test code out
of application binaries (the G-11 `nm` evidence below and the WP11 cost
measurements record the observed symbol tables). Removing the blocks is
deliberately NOT done — the vendor policy is minimal, marked patches only.
Vendor update policy is routed to Phase 4.

## Guardrail audit (G-01 … G-11)

PENDING-EVIDENCE

## Risk register and open questions — dispositions

PENDING-EVIDENCE

## Limitations routed to future phases

PENDING-EVIDENCE

## Human acceptance conditions

1. A human reviews and merges the WP11 PR — the agent never merges.
2. The merged commit on `main` passes `ops/ci/run.sh` on the VPS
   (`URUQUIM_CI_BRANCH=main`), same toolchain, same PASS/FAIL counts.
3. Tag and release remain a separate, human decision; nothing in this
   manifest creates one.
