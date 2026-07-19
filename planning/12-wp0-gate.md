# WP0 Gate — Toolchain and Repository Baseline

Status: **COMPLETE — LOCAL PASS / REAL VPS PASS** — 2026-07-18.

## SPEC

- Pinned authority: Odin `dev-2026-07a`, commit `819fdc7`.
- Repository collection: `uruquim=<workspace-root>`.
- The gate rejects any compiler with a different commit.
- The tracked pre-push hook is mandatory and provider-independent.
- A clean VPS verifier repeats the same pushed commit without GitHub Actions.
- WP0 does not create `web/`; production starts only in WP1.

Official Linux amd64 asset:

```text
odin-linux-amd64-dev-2026-07a.tar.gz
sha256: 32a7678abc66f1af7353abb5b0b5da47d94b7e663f6d250df29bc9117e864c10
```

## TESTS FIRST

The original baseline test first failed because the pin was absent. After the
GitHub Actions constraint changed, the expanded test first failed as required:

```text
FAIL: pre-push hook is missing or not executable
exit=1
```

The current test verifies the pin/digest, real compiler, divergent-compiler
rejection, isolation from an inherited `ODIN_ROOT`, executable hook, absence
of an active GitHub Actions workflow, VPS script syntax, collection mapping,
and the full prototype result.

## MINIMAL IMPLEMENTATION

- `odin-version.txt` — release, commit, asset, digest.
- `build/check.sh` — single verification entry point.
- `.githooks/pre-push` + `build/install-hooks.sh` — mandatory local gate.
- `ops/ci/run.sh` — fetch public branch, archive one clean commit, verify it,
  and atomically record status/logs.
- `ops/ci/install-odin.sh` — SHA/commit-verified VPS toolchain installer.
- systemd oneshot/timer — repeat every five minutes as unprivileged user.
- `ops/ci/status.sh` — human-readable latest status; no dashboard or secret.

## EVIDENCE

Local hook integration:

```text
PASS: WP0 toolchain and repository baseline
PASS=10 FAIL=0 SKIP=0
```

Clean-clone VPS simulation used a temporary bare remote and a fresh Git
archive, not the workspace:

```text
commit=f5c4784580c777e8f834c43e41424f78124c10b9
branch=codex/phase-1-bootstrap
result=pass
duration_seconds=12
PASS=10 FAIL=0 SKIP=0
```

The exp-02 `Unsupported_Type` log is expected negative pointer evidence.

## REVIEW

- GitHub Actions is not required or referenced as a completion criterion.
- The local hook and VPS execute the same script; policy cannot drift.
- The VPS uses a dedicated mirror + fresh archive, so untracked files cannot
  make a commit pass.
- The public repository requires no stored GitHub credential.
- Status writes are atomic; a failing commit is retried and remains visible.
- The service runs without root and exposes no port.
- A previously observed truncated compiler download proves the SHA check is
  mandatory; extraction never occurs before digest verification.
- The checker resolves the compiler path and forces `ODIN_ROOT` to that same
  verified distribution. A deliberately invalid inherited `ODIN_ROOT` is a
  passing regression test, so another standard-library tree cannot silently
  contaminate the gate.
- The first real service run exposed missing host `clang`; the second exposed
  an implicit `/` working directory. Both failures were preserved, then fixed
  by documenting/checking the linker prerequisite and compiling from the
  extracted writable archive.

## GATE

- Local gate: **PASS**.
- Clean-clone verifier mechanism: **PASS**.
- Real VPS: **PASS** on Ubuntu 26.04 x86_64.

```text
commit=4ae2d1cbbb4c6f2775bf19f78248185d35116270
branch=codex/phase-1-bootstrap
result=pass
duration_seconds=12
PASS=10 FAIL=0 SKIP=0
timer=enabled,active
```

WP0 is COMPLETE. ADR-011 is closed and the Phase-1 Spec Gate is READY. WP1 may
start only as a new work package following its mandatory
SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE cycle.
