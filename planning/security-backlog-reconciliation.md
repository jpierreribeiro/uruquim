# Security-backlog reconciliation (Hardening H-1)

**Status: LIVE GATE.** Reconciles the 14 findings of the 2026-07-22
`/claude-security` scan (against the Phase-6 freeze `e6554e5`) with the current
tree, and — the part that matters — names the **test that fails if each fix
regresses.** `build/check_security_backlog.sh` fails if a row loses its pinning
test.

---

## 0. Why this exists

The only record of the 14 findings was a session memory that predated three
phases of work and had drifted: it still described findings that Phase 6.5 and
Phase 7 (WP91, patches 21/16/17/18) had closed. A fix with no named test is a
fix that can regress in silence — the exact failure mode the Closure was called
to end, applied to security. So this WP does not re-scan; it **pins**. All 14
are fixed in the current tree; the work was writing the four tests that were
missing and recording the two that cannot be pinned at the public surface, with
the reason.

**No re-scan** (owner's decision): the guarantee is this gate going red when a
fix loses its test, not a fresh sweep.

---

## 1. The reconciliation

`✅` = fixed and pinned by a named test · `◑` = fixed, pinned indirectly, reason
stated (no clean public injection path).

<!-- h1-findings: 14 -->

| # | Finding | Fixed at | Pinning test |
|---|---|---|---|
| **F1** | JSON nesting depth stack-overflow | `web/json_decode.odin:28` (`JSON_NEST_DEPTH_MAX :: 128`), enforced `:421` | ✅ `wp68_over_deep_nesting_is_refused_before_parsing` — `tests/wp67-json-boundary/decoder/contract_test.odin` |
| **F2** | chunked trailer vs `assert(!h.readonly)` | `vendor/odin-http/body.odin:354` (clears `readonly` around the trailer parse) — patch 15 | ✅ `wp9_raw_wire_corpus` — corpus case "chunked body with a trailer field is accepted" (`tests/support/transport_conformance/corpus.odin`) |
| **F3** | negative / overflow chunk-size | `vendor/odin-http/body.odin:264` (`if !ok \|\| size < 0`) — patch 14 | ✅ `wp9_raw_wire_corpus` — corpus case "negative chunk size is rejected" |
| **F4** | `X-Forwarded-For` believed leftmost (spoof) | `web/client_address.odin:163-184` (right-to-left walk, ADR-037) | ✅ `wp48i_a_spoofed_leftmost_is_ignored_behind_a_trusted_proxy` — `tests/wp48-internal/wp48_internal_test.odin` (sends `forged, real-client, real-proxy`, asserts the forged leftmost is never returned); end-to-end twin `c06_the_forwarded_client_address_is_believed_only_from_a_trusted_hop` |
| **F5** | static response skips `secure_headers` | `web/static.odin:209-216` (WP91 flattened chain) | ✅ `wp91_secure_headers_cover_a_static_response` — `tests/wp91-commit-security/static_chain_test.odin` |
| **F6** | static mount bypasses global `use()` | `web/static.odin:209-216` (same chain) | ✅ `wp91_global_middleware_runs_for_a_static_file` + `wp91_an_auth_refusal_blocks_a_static_file` |
| **F7** | intermediate-directory symlink escape | `web/static.odin:344-353` (per-segment `os.lstat` loop) | ✅ **NEW: `wp61_a_symlink_in_an_intermediate_segment_is_refused`** — `tests/wp61-public-surface/contract_test.odin` (creates a real symlink at an intermediate segment and at the final component; both refused) |
| **F8** | JSON preflight builds full parse tree (OOM) | `web/json_decode.odin:434-436` (disposable `dynamic_arena` + `defer …_destroy`) | ◑ **no dedicated leak test** — the depth cap (F1) bounds the tree, and the test runner's leak checker over the `tests/wp67-json-boundary` preflight suite would surface an arena-cleanup regression. A direct RSS assertion belongs to the C-04-style soak, not to a unit test; recorded rather than faked. |
| **F9** | unhandled `accept()` error panics | `vendor/odin-http/server.odin:873-891` (tolerate + re-arm + failure limit) — patch 21 | ✅ `c03_a_healthy_client_survives_an_rst_flood` — `tests/c03-fault-campaign/rst_flood_test.odin` (a sustained RST flood is the accept-error generator) |
| **F10** | Content-Length u64 overflow → smuggling | `vendor/odin-http/body.odin:156-176` (rejects >19 significant digits) | ✅ `wp9_raw_wire_corpus` — corpus cases "overflowing Content-Length…" and "signed and overflowing Content-Length is rejected" |
| **F11** | preflight accepts out-of-range int, decoder truncates | `web/json_decode.odin:37` (`json_int_fits`), enforced `:256` | ✅ `wp68_out_of_range_integer_is_an_invalid_field` — `tests/wp67-json-boundary/decoder/contract_test.odin` (`{"count":999999}` into a `u8` is refused, not truncated to 63) |
| **F12** | bare CR unescaped in header / cookie | `vendor/odin-http/http.odin:408-424` (`write_escaped_newlines`, the `'\r'` case) | ◑ **no public injection path** — the sink escapes a lone `\r`, but no public API lets an application put a CR into a response header: request-side CR is rejected upstream at `request_id_acceptable` (`tests/wp23-internal`, pinned), and the framework builds its own response headers. The fix is defense-in-depth at the serialization sink; a test would need a private sink call, which the two-instance rule discourages. Recorded with the inbound pin that guards the reachable half. |
| **F13** | multipart boundary via unanchored substring | `web/multipart.odin:183` (`multipart_boundary`, true MIME-parameter parse) | ✅ **NEW: `wp63_a_decoy_boundary_in_a_quoted_parameter_is_not_used`** — `tests/wp63-public-surface/contract_test.odin` (a decoy `boundary=evil` inside a quoted value with the real `boundary=good` after; body framed with the real one, so a substring parser would find no parts) |
| **F14** | tab-prefixed obs-fold not rejected | `vendor/odin-http/http.odin:177` (`line[0] != ' ' && line[0] != '\t'`) — patch 18 | ✅ `wp9_raw_wire_corpus` — corpus case "tab obs-fold header continuation is rejected" |

**All 14 fixed. 12 pinned by a named test; 2 (F8, F12) fixed with the pin
recorded as indirect and the reason stated.**

---

## 2. What H-1 added

Two tests, both through the ordinary request path so a regression is caught
where a user would meet it:

- **F7** — `tests/wp61-public-surface`: a symlink at an intermediate segment
  (and at the final component) is refused. The static suite previously exercised
  only textual traversal and the final-component check; the `lstat` loop over
  intermediate segments was unpinned.
- **F13** — `tests/wp63-public-surface`: a decoy `boundary=` inside a quoted
  parameter is not used. The `multipart_boundary` MIME-parameter parser was
  referenced only by its own source.

---

## 3. The two honest gaps, and why they are not "TODO tests"

- **F8** is a memory-shape property. A unit test asserting "no OOM" is a soak,
  not an assertion, and C-04 already owns the soak instrument; the depth cap
  (F1, pinned) is what makes the tree finite in the first place.
- **F12** has no reachable trigger from the public API. Pinning a fix to a defect
  no public path can reach would mean calling a private sink, which the WP2
  two-instance rule exists to discourage. The reachable half — inbound CR — is
  rejected and pinned at `tests/wp23-internal`.

Both are recorded here rather than left as silent "we think it's fine", which is
the whole point of the reconciliation.
