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

**None.** The vendored `.odin` files are byte-for-byte the upstream root
package.

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
