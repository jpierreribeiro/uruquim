# Build baseline

WP0 pins the Phase-1 compiler in `odin-version.txt` and exposes one local/CI
entry point:

```bash
env URUQUIM_ODIN_BIN=/tmp/uruquim-odin-toolchain/odin bash build/check.sh
```

`build/check.sh` is verification-only. It checks commit `819fdc7`, confirms
the required standard-library packages, syntax-checks the shell runners, and
runs all nine disposable prototypes with the repository collection mapping.
It does not download a compiler or modify sources.

`build/check_test.sh` verifies both the accepted compiler path and rejection
of a divergent compiler. `.githooks/pre-push` runs the same gate before every
push. `ops/ci/` repeats it from a clean archive on the project VPS; no GitHub
Actions access is required.

WP0 deliberately does not create or check `web/`: the compiling public package
belongs to WP1. Once WP1 creates it, this entry point is extended spec-first to
check that package and its compile-contract tests.
