# 01 — Toolchain and Repository Baseline

Status: **UPDATED AFTER C-1 EXECUTION.** This document preserves the initial
authoring condition and records the toolchain that is now available locally.

## Pinned toolchain (authority for Phase 1)

| Field | Value |
|---|---|
| Release | `dev-2026-07a` |
| Commit | `819fdc7` |
| Release date | 2026-07-10 |
| Target artifact | local distribution corresponding to pinned commit |
| Intended install prefix | `/tmp/uruquim-odin-toolchain` (isolated, no global config change) |

The pinned toolchain is the **only practical authority** for Phase 1. Official
documentation informs; the pinned compiler and stdlib decide any divergence.
An upgrade requires an explicit proposal and a full re-run of every experiment
and suite. It must not be updated silently.

References:
- Release: https://github.com/odin-lang/Odin/releases/tag/dev-2026-07a
- JSON: https://pkg.odin-lang.org/core/encoding/json/
- nbio: https://pkg.odin-lang.org/core/nbio/

## Current execution baseline: compiler AVAILABLE

The installed distribution at `/home/jp/.local/opt/Odin` was copied in full to
`/tmp/uruquim-odin-toolchain` so the compiler resolves its matching `base`,
`core`, and `vendor` trees from the isolated prefix.

```text
odin version dev-2026-07-nightly:819fdc7
OS:      Linux Mint 22.1, Linux 6.8.0-86-generic
CPU:     Intel(R) Core(TM) i7-8665U CPU @ 1.90GHz
RAM:     23845 MiB
Backend: LLVM 20.1.8
SHA-256: 6fea037515fee6c4e681a67fe86818998241f15abbadd8df67899d9f0ff32b12
```

The commit matches the pin. The binary's literal version label is
`dev-2026-07-nightly`, not `dev-2026-07a`; this difference is retained in the
evidence. See `planning/10-c1-execution-evidence.md`.

`core:net`, `core:nbio`, and `core:encoding/json` are present in the isolated
distribution.

## Historical authoring condition: compiler was unavailable

The pinned toolchain **could not be installed** in the authoring environment.
This is a recorded baseline condition, **not evidence against the viability of
the proposed APIs** (per the plan's assumptions).

Evidence captured:

```text
$ which odin          → (empty; not installed)
$ odin version        → (command not found)

$ curl -sSL https://github.com/odin-lang/Odin/releases/download/\
        dev-2026-07a/odin-linux-amd64-dev-2026-07a.zip
HTTP 403, size 195         # body was a JSON policy-denial, not a zip

$ curl -sS $HTTPS_PROXY/__agentproxy/status
  → noProxy allowlist contains registry.npmjs.org, jsr.io, pypi.org,
    files.pythonhosted.org, index.crates.io, proxy.golang.org — but NOT
    github.com / objects.githubusercontent.com
```

Interpretation: the session's egress policy does not allow GitHub. Per proxy
policy, a 403 is an organization denial that must be **reported, not routed
around**. No mirror, apt, or snap route exists:

- `apt-cache show odin` returns a package `odin 2.0.5-5build4`, which is an
  **unrelated homonymous program**, not the Odin language compiler. It was
  deliberately NOT installed — using it would be misleading.
- `snap`: not present.
- No `odin` executable exists anywhere on disk.

### Historical consequence for the initial audit

Prototype code was initially authored without compilation. C-1 has now run the
suite; the historical `NOT_EXECUTED` state is superseded by the first-run
evidence (`5 PASS / 4 FAIL`).

- No canonical signature is marked `READY_FOR_GATE` on compile evidence.
- Every experiment result is recorded as `NOT_EXECUTED — pending compile on
  pinned toolchain`, with hypothesis and expected outcome stated.
- A verification runner (`experiments/run_checks.sh`) is provided so the exact
  same experiments produce real evidence wherever the pinned toolchain is
  reachable.
- The Spec Gate (`07-spec-gate-phase-1.md`) treats compile-ratification as an
  explicit **blocker** with an owner and a deadline before WP1.

This keeps the deliverable honest: the intellectual work (audit, scope,
ADRs, risk, gate design) is complete and independent of the compiler; the
signature *ratification* is pending and clearly flagged.

## Commands used with the isolated toolchain

Recorded now so the runner and WP0 are unambiguous:

```bash
# selected execution PATH
export PATH="/tmp/uruquim-odin-toolchain:/usr/bin:/bin"

odin version                 # prints dev-2026-07-nightly:819fdc7
odin report                  # environment / backend record

odin check <dir> -collection:uruquim=<root>     # type-check without codegen
odin build  <dir> -collection:uruquim=<root>    # produce binary
odin test   <dir> -collection:uruquim=<root>    # run *_test.odin
```

Standard-library presence in the installed tree:

| Package | Expectation |
|---|---|
| `core:net` | present |
| `core:nbio` | present |
| `core:encoding/json` | present |
| `core:testing` | present (`@(test)`, `testing.T`, `expect`) |
| `core:mem` | present (allocators, arenas) |
| `core:net/http` | **expected ABSENT** — this is the whole reason for the transport boundary |
| `laytan/odin-http` | third-party, vendored only for the bootstrap adapter; not imported by transport-free prototypes |

## Repository baseline

Current execution workspace:

| Field | Value |
|---|---|
| Working dir | `/home/jp/Desktop/uruquim-odin` |
| Platform | Linux Mint 22.1, Linux x86_64 |
| Git metadata | local `.git` directory is empty; `git status` reports “not a git repository” |

The following table is retained as the historical authoring environment
reported by the original audit; it is not the current workspace:

| Field | Value |
|---|---|
| Working dir | `/home/user/uruquim` |
| Platform | Linux x86_64, Ubuntu 24.04.4 LTS |
| Branch | `claude/framework-api-productivity-xttqgl` |
| HEAD | `4a609c8` (freeze discipline) |

Git history present (5 commits, from `b42b8fa` initial to `4a609c8`). The plan
noted a possibly empty local `.git`; in fact history is intact, so no metadata
needed reconstruction. Nothing was artificially reconstructed either way.

Normative files (`README.md`, `knowledge-base/**`, `docs/**`) are **unchanged**
by this audit. All new content lives under `planning/` and `experiments/`.
