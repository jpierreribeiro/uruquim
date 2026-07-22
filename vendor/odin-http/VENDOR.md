# Vendored dependency — laytan/odin-http (server root package)

This directory is a **minimal snapshot** of the root server package of
`laytan/odin-http`, used by the Uruquim bootstrap transport adapter
(`web/internal/transport/`) and by nothing else. No application imports it.

## Provenance

| Field | Value |
|---|---|
| Upstream | https://github.com/laytan/odin-http |
| Commit | `112c49b5bcee31308a695cc3f05d156d314a61a6` |
| Commit subject | `openssl: update bundled libraries to openssl-3.6.2 (#108)`, 2026-04-11 |
| License | MIT (`LICENSE`, Copyright (c) 2023 Laytan Laats) |
| Vendored on | 2026-07-19 |
| Toolchain verified with | `dev-2026-07-nightly:819fdc7` |

The pinned commit's root package compiles offline with:

```
odin check vendor/odin-http -no-entry-point
```

## What is included (root server package only, ~102 KiB of source)

```
allocator.odin  body.odin     cookie.odin   handlers.odin  headers.odin
http.odin       mimes.odin    request.odin  response.odin  responses.odin
routing.odin    scanner.odin  server.odin   status.odin
LICENSE         mod.pkg
```

These are exactly the root-level `.odin` files of the upstream package, plus the
MIT `LICENSE` and the package manifest `mod.pkg`. The root package imports only
`core:` and `base:` packages (no OpenSSL, no HTTP client).

## What is deliberately OMITTED

The following upstream trees are **not** vendored, because the bootstrap server
does not need them and they would add weight, extra dependencies, or platform
binaries:

```
.git/          — version-control metadata
client/        — the HTTP client (server-only bootstrap)
openssl/       — bundled OpenSSL and its libraries
old_nbio/      — a superseded async backend
examples/      — sample programs
comparisons/   — benchmark comparisons
docs/          — generated documentation
.github/       — CI workflows
README.md, odinfmt.json, .editorconfig, .gitignore — repo tooling
```

## Local patches

**Twelve.** Five added by WP9 (transport conformance), one each by WP45, WP46
(ADR-031) and WP47, three by WP59's drain repair, and one by WP70's multi-lane
lifecycle repair. All are minimal and fix a security issue, an upstream defect,
a lifecycle defect or a capacity the server had no way to bound. Each is marked
in source with `URUQUIM PATCH`, recorded below, and covered by executable
evidence that failed before it. There are no opportunistic edits.

The classification is mixed. Some patches encode Uruquim's deliberately
stricter framing, capacity and shutdown policy; seven fix upstream lifecycle,
parsing or keep-alive defects. The distinction is recorded per row because it
decides whether a re-vendor carries a policy or expects a fix to disappear.

| # | File | Conceptual change | Why |
|---|---|---|---|
| 1 | `body.odin` (`_body_length`) | A `Content-Length` must be one or more ASCII digits and nothing else; a negative or non-decimal value is rejected. | **REMOTE DENIAL OF SERVICE.** `strconv.parse_int` accepts `-1` and stops at the first non-digit, so `Content-Length: -1` reached `scanner.max_token_size` and tripped `scanner.odin`'s `n >= 0` assertion, **killing the server process**. `2, 2` likewise parsed as `2` and silently accepted an ambiguous framing. |
| 2 | `body.odin` (`_body_chunked`) | A chunk not terminated by CRLF is rejected instead of asserted. | **REMOTE DENIAL OF SERVICE.** `assert(len(token) == 0)` treated malformed *input* as a programming error, so a chunked body missing its trailing CRLF **killed the server process**. |
| 3 | `request.odin` (`headers_validate`) | `Content-Length` + `Transfer-Encoding` is **rejected**, not repaired. | Upstream deleted the `Content-Length` and continued. That leaves the two ends of a proxy chain disagreeing about where the body ends — the request-smuggling vector RFC 9112 §6.1 calls an unrecoverable error. |
| 4 | `http.odin` (`header_parse`) | **Any** repeated `Content-Length` is rejected, even when the values are identical. | Upstream let an exact duplicate through and then merged it via the comma rule into `2, 2`, an ambiguous framing. WP9 D2 chooses refusal over normalization: it is simpler and safer. |
| 8 | `server.odin` (`Server_Opts`, `Server_Thread`, `on_accept`) | Bounded admission: `max_connections` and `reserved_connections`. A connection past `max - reserved` is closed at accept; refusals are counted and the TRANSITION is logged, not each event. | Without it, concurrent connections are bounded only by the OS descriptor limit, and reaching that limit is an `accept` failing for a reason the server did not choose. The reservation exists so a shutdown always has slots to work in (WP40). |
| 7 | `body.odin` (`_body_length`) | A request with NO `Content-Length` sets `_body_ok = true` on its success path, instead of leaving the `false` the procedure starts with. | **KEEP-ALIVE WAS BROKEN FOR EVERY GET.** `_body_ok = false` means "a body read failed" and `response_must_close` retires the connection on it — but a request with no body returned through the success path without setting it. Measured before the patch: two sequential requests on one socket, the first answered and the second met an orderly close, with **no `Connection: close` advertised**, so a client had no way to know it was paying a TCP handshake per request while HTTP/1.1 promised persistence. |
| 6 | `server.odin` (`Server_Opts`, `Connection`, `server_deadline_sweep`, `server_date_start`, `conn_handle_req`) and `response.odin` (`clean_request_loop`) | A configurable REQUEST READ DEADLINE: `request_read_timeout`. A per-thread periodic sweep closes any connection whose current request has taken longer than that to arrive. Zero disables it, which is upstream's behaviour. | **REMOTE RESOURCE EXHAUSTION (slowloris).** The upstream read has no deadline — `scanner.odin` carries an unfinished-work comment at the recv site asking for exactly this — so a client that sends a valid prefix and stops, or trickles one byte at a time, holds a connection open indefinitely. Demonstrated against this server by `tests/wp41-fault` before the patch existed (WP41), closed by it (WP46/ADR-031). |
| 5 | `http.odin` (`Method`, `Requestline`, `requestline_parse`) | A valid but unrecognized method becomes `.Unknown` and its original token is preserved in `Requestline.method_raw`, instead of the server answering `501`. | WP9 D7: method semantics are the framework's decision. `PROPFIND` must reach the dispatcher and follow the ratified 404/405 policy; the transport must not invent a status before the core sees the request. |
| 9 | `scanner.odin` (`Scanner.pending_recv`, `scanner_scan`, `scanner_on_read`) | Preserve the outstanding receive operation until it fires or is cancelled. **BRIDGE.** | The upstream scanner discarded the only handle by which `core:nbio` can cancel a pending receive. WP58 proved that an idle keep-alive connection then made safe teardown structurally impossible. |
| 10 | `server.odin` (`connection_close`) | Cancel the scanner's outstanding receive before freeing connection-owned state. **BRIDGE.** | Without cancellation, a later completion dereferenced a freed `Connection`: WP58 reproduced an endless drain followed by `free(): invalid pointer`. This is an upstream use-after-free. |
| 11 | `server.odin` (`Server_Opts`, shutdown loop) | Apply one absolute `max_drain_time` across shutdown waits and cancel remaining reads at expiry. **BRIDGE.** | A graceful-stop knob must bound the whole operation, not only one loop. The WP58 laboratory is the executable deadline evidence. |
| 12 | `server.odin` (`Server`, `Server_Thread`, `server_shutdown`, Date cache, refusal count) | Elect one shutdown owner; make the Date cache lane-owned; atomically aggregate refusals. **BRIDGE.** | WP69 reproduced a multi-lane stop walking state another caller had begun freeing. WP70's contention corpus also owns the shared-counter and lane-cache races. |

Patch 5 also adds a tenth entry to `_method_strings` and makes `method_parse`
skip the new member, so the existing `for r in Method` lookup (which indexes
that array under `#no_bounds_check`) stays in bounds.

Every other line is byte-for-byte upstream.

To update to a newer upstream commit, re-apply the twelve patches above (they are
small and each is commented at its site) and re-run the WP9 raw-wire corpus,
which is what proves they are still needed and still sufficient.

A note on cost, for the record: importing this package links its one `@(init)`
procedure (`status.odin::status_strings_init`, which precomputes the HTTP
status-line strings) into any binary that transitively imports it, because Odin
roots `@(init)` procedures unconditionally. This is a toolchain trait, not a
socket/server symbol — an application that never calls `web.serve` still links
ZERO socket, listener, connection, or server-teardown symbols (measured with
`nm`; see the WP8 PR). Neutralizing that `@(init)` would trim it further but
would require another patch; WP9's five patches are all security-motivated, and
this cost is not.

## Updating

To move to a different upstream commit: re-copy the root `.odin` files, the
`LICENSE` and `mod.pkg` from a fresh checkout at the new commit, re-apply the
twelve patches listed above, update the provenance table, and re-run the full
gate — including the WP9 raw-wire corpus, which is what proves the patches are
still necessary and still sufficient. Do not make unrelated edits to these
files.
