#!/usr/bin/env bash
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_EXPECTED_COMMIT="819fdc7"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test -f "$URUQUIM_ROOT/odin-version.txt" || fail "odin-version.txt is missing"
grep -qx "release=dev-2026-07a" "$URUQUIM_ROOT/odin-version.txt" ||
  fail "release pin is missing"
grep -qx "commit=$URUQUIM_EXPECTED_COMMIT" "$URUQUIM_ROOT/odin-version.txt" ||
  fail "commit pin is missing"
grep -qx "linux_amd64_sha256=32a7678abc66f1af7353abb5b0b5da47d94b7e663f6d250df29bc9117e864c10" \
  "$URUQUIM_ROOT/odin-version.txt" || fail "release digest pin is missing"

test -f "$URUQUIM_ROOT/build/check.sh" || fail "build/check.sh is missing"
test -x "$URUQUIM_ROOT/.githooks/pre-push" || fail "pre-push hook is missing or not executable"
test -f "$URUQUIM_ROOT/build/install-hooks.sh" || fail "hook installer is missing"
test ! -f "$URUQUIM_ROOT/.github/workflows/ci.yml" ||
  fail "GitHub Actions workflow must not be an active gate"

for URUQUIM_CI_FILE in run.sh status.sh install-odin.sh; do
  test -f "$URUQUIM_ROOT/ops/ci/$URUQUIM_CI_FILE" ||
    fail "missing VPS verifier file: ops/ci/$URUQUIM_CI_FILE"
  bash -n "$URUQUIM_ROOT/ops/ci/$URUQUIM_CI_FILE"
done
grep -Fq 'cd "$URUQUIM_CI_WORK"' "$URUQUIM_ROOT/ops/ci/run.sh" ||
  fail "VPS verifier does not compile from its clean writable archive"

URUQUIM_REAL_OUTPUT="$(URUQUIM_ODIN_BIN="${URUQUIM_ODIN_BIN:-}" \
  bash "$URUQUIM_ROOT/.githooks/pre-push")" ||
  fail "pre-push gate rejected the pinned toolchain"
grep -q "toolchain commit: $URUQUIM_EXPECTED_COMMIT" <<<"$URUQUIM_REAL_OUTPUT" ||
  fail "check output did not report the pinned commit"
grep -q "PASS=10 FAIL=0 SKIP=0" <<<"$URUQUIM_REAL_OUTPUT" ||
  fail "check output did not report all prototype passes"

if ! ODIN_ROOT=/tmp/uruquim-invalid-ambient-odin-root \
  URUQUIM_ODIN_BIN="${URUQUIM_ODIN_BIN:-/tmp/uruquim-odin-toolchain/odin}" \
  bash "$URUQUIM_ROOT/build/check.sh" >/dev/null 2>&1; then
  fail "build/check.sh did not sanitize ambient ODIN_ROOT"
fi

if URUQUIM_ODIN_BIN="/bin/echo" \
  bash "$URUQUIM_ROOT/build/check.sh" >/dev/null 2>&1; then
  fail "build/check.sh accepted a divergent compiler"
fi

echo "PASS: WP0 toolchain and repository baseline"
