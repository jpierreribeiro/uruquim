# 01 — Toolchain and Repository Baseline

Status: **RECORDED**. This document fixes the initial conditions of the
pre-implementation audit. It is descriptive, not normative.

## Pinned toolchain (authority for Phase 1)

| Field | Value |
|---|---|
| Release | `dev-2026-07a` |
| Commit | `819fdc7` |
| Release date | 2026-07-10 |
| Target artifact | `odin-linux-amd64-dev-2026-07a.zip` (official) |
| Intended install prefix | `/tmp/uruquim-odin-toolchain` (isolated, no global config change) |

The pinned toolchain is the **only practical authority** for Phase 1. Official
documentation informs; the pinned compiler and stdlib decide any divergence.
An upgrade requires an explicit proposal and a full re-run of every experiment
and suite. It must not be updated silently.

References:
- Release: https://github.com/odin-lang/Odin/releases/tag/dev-2026-07a
- JSON: https://pkg.odin-lang.org/core/encoding/json/
- nbio: https://pkg.odin-lang.org/core/nbio/

## Initial condition: compiler UNAVAILABLE in this environment

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

### Consequence for this audit (carried into the gate)

Prototype **code** is authored as planned and is a deliverable. But it **was
not compiled** here. Therefore:

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

## Commands that WILL be used once the toolchain is present

Recorded now so the runner and WP0 are unambiguous:

```bash
# install (isolated)
mkdir -p /tmp/uruquim-odin-toolchain
# unzip official artifact there; export PATH="/tmp/uruquim-odin-toolchain:$PATH"

odin version                 # must print dev-2026-07a (819fdc7)
odin report                  # environment / backend record

odin check <dir> -collection:uruquim=<root>     # type-check without codegen
odin build  <dir> -collection:uruquim=<root>    # produce binary
odin test   <dir> -collection:uruquim=<root>    # run *_test.odin
```

Standard-library presence to confirm by `odin check` on a probe import once
installed (expected, from documentation — to be verified, not assumed):

| Package | Expectation |
|---|---|
| `core:net` | present (Berkeley sockets) |
| `core:nbio` | present (per-thread event loops, tick-driven callbacks) |
| `core:encoding/json` | present (`marshal`, `unmarshal`, `unmarshal` generic `^$T`) |
| `core:testing` | present (`@(test)`, `testing.T`, `expect`) |
| `core:mem` | present (allocators, arenas) |
| `core:net/http` | **expected ABSENT** — this is the whole reason for the transport boundary |
| `laytan/odin-http` | third-party, vendored only for the bootstrap adapter; not imported by transport-free prototypes |

## Repository baseline

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
