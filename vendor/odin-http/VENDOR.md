# Vendored dependency — laytan/odin-http (server root package)

This directory is a **pristine, minimal snapshot** of the root server package of
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

**Five, all added by WP9 (transport conformance), all minimal and security-
motivated.** Each is marked in the source with a `URUQUIM PATCH` comment naming
the decision it implements, and each is covered by a raw-wire corpus case that
FAILED before the patch. There are no opportunistic edits.

Upstream is not at fault for most of these: the package is a general HTTP
server, while Uruquim commits to a deliberately stricter Phase-1 framing policy
(planning/phase-1-plan.md §WP9 D2–D7). Two of the five, however, are outright
crashes and would be bugs anywhere.

| # | File | Conceptual change | Why |
|---|---|---|---|
| 1 | `body.odin` (`_body_length`) | A `Content-Length` must be one or more ASCII digits and nothing else; a negative or non-decimal value is rejected. | **REMOTE DENIAL OF SERVICE.** `strconv.parse_int` accepts `-1` and stops at the first non-digit, so `Content-Length: -1` reached `scanner.max_token_size` and tripped `scanner.odin`'s `n >= 0` assertion, **killing the server process**. `2, 2` likewise parsed as `2` and silently accepted an ambiguous framing. |
| 2 | `body.odin` (`_body_chunked`) | A chunk not terminated by CRLF is rejected instead of asserted. | **REMOTE DENIAL OF SERVICE.** `assert(len(token) == 0)` treated malformed *input* as a programming error, so a chunked body missing its trailing CRLF **killed the server process**. |
| 3 | `request.odin` (`headers_validate`) | `Content-Length` + `Transfer-Encoding` is **rejected**, not repaired. | Upstream deleted the `Content-Length` and continued. That leaves the two ends of a proxy chain disagreeing about where the body ends — the request-smuggling vector RFC 9112 §6.1 calls an unrecoverable error. |
| 4 | `http.odin` (`header_parse`) | **Any** repeated `Content-Length` is rejected, even when the values are identical. | Upstream let an exact duplicate through and then merged it via the comma rule into `2, 2`, an ambiguous framing. WP9 D2 chooses refusal over normalization: it is simpler and safer. |
| 5 | `http.odin` (`Method`, `Requestline`, `requestline_parse`) | A valid but unrecognized method becomes `.Unknown` and its original token is preserved in `Requestline.method_raw`, instead of the server answering `501`. | WP9 D7: method semantics are the framework's decision. `PROPFIND` must reach the dispatcher and follow the ratified 404/405 policy; the transport must not invent a status before the core sees the request. |

Patch 5 also adds a tenth entry to `_method_strings` and makes `method_parse`
skip the new member, so the existing `for r in Method` lookup (which indexes
that array under `#no_bounds_check`) stays in bounds.

Every other line is byte-for-byte upstream.

To update to a newer upstream commit, re-apply the five patches above (they are
small and each is commented at its site) and re-run the WP9 raw-wire corpus,
which is what proves they are still needed and still sufficient.

A note on cost, for the record: importing this package links its one `@(init)`
procedure (`status.odin::status_strings_init`, which precomputes the HTTP
status-line strings) into any binary that transitively imports it, because Odin
roots `@(init)` procedures unconditionally. This is a toolchain trait, not a
socket/server symbol — an application that never calls `web.serve` still links
ZERO socket, listener, connection, or server-teardown symbols (measured with
`nm`; see the WP8 PR). Neutralizing that `@(init)` would trim it further but
would require modifying vendored source, which is deliberately avoided here.

## Updating

To move to a different upstream commit, re-copy the root `.odin` files, the
`LICENSE` and `mod.pkg` from a fresh checkout at the new commit, update the
table above, and re-run the full gate. Do not edit these files in place.
