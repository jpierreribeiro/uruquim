#!/usr/bin/env bash
set -euo pipefail

URUQUIM_CI_REPO_URL="${URUQUIM_CI_REPO_URL:-https://github.com/jpierreribeiro/uruquim.git}"
URUQUIM_CI_BRANCH="${URUQUIM_CI_BRANCH:-codex/phase-1-bootstrap}"
URUQUIM_CI_ROOT="${URUQUIM_CI_ROOT:-/opt/uruquim-ci}"
URUQUIM_CI_STATE_DIR="${URUQUIM_CI_STATE_DIR:-/var/lib/uruquim-ci}"
URUQUIM_ODIN_BIN="${URUQUIM_ODIN_BIN:-/opt/uruquim-odin/odin}"
URUQUIM_CI_MIRROR="$URUQUIM_CI_ROOT/mirror.git"
URUQUIM_CI_STATUS="$URUQUIM_CI_STATE_DIR/status"
URUQUIM_CI_LOG="$URUQUIM_CI_STATE_DIR/latest.log"

mkdir -p "$URUQUIM_CI_ROOT" "$URUQUIM_CI_STATE_DIR"

if test ! -d "$URUQUIM_CI_MIRROR"; then
  git clone --mirror "$URUQUIM_CI_REPO_URL" "$URUQUIM_CI_MIRROR"
fi

git --git-dir="$URUQUIM_CI_MIRROR" fetch --prune "$URUQUIM_CI_REPO_URL" \
  "+refs/heads/$URUQUIM_CI_BRANCH:refs/heads/$URUQUIM_CI_BRANCH"

URUQUIM_CI_COMMIT="$(git --git-dir="$URUQUIM_CI_MIRROR" \
  rev-parse "refs/heads/$URUQUIM_CI_BRANCH")"
URUQUIM_CI_LAST_COMMIT="$(sed -n 's/^commit=//p' "$URUQUIM_CI_STATUS" 2>/dev/null || true)"
URUQUIM_CI_LAST_RESULT="$(sed -n 's/^result=//p' "$URUQUIM_CI_STATUS" 2>/dev/null || true)"

if test "$URUQUIM_CI_COMMIT" = "$URUQUIM_CI_LAST_COMMIT" && \
   test "$URUQUIM_CI_LAST_RESULT" = "pass"; then
  echo "Already verified: $URUQUIM_CI_COMMIT"
  exit 0
fi

URUQUIM_CI_WORK="$(mktemp -d /tmp/uruquim-ci.XXXXXX)"
cleanup() {
  rm -rf -- "$URUQUIM_CI_WORK"
}
trap cleanup EXIT

git --git-dir="$URUQUIM_CI_MIRROR" archive "$URUQUIM_CI_COMMIT" |
  tar -x -C "$URUQUIM_CI_WORK"

URUQUIM_CI_STARTED="$(date +%s)"
set +e
env URUQUIM_ODIN_BIN="$URUQUIM_ODIN_BIN" \
  bash "$URUQUIM_CI_WORK/build/check.sh" 2>&1 | tee "$URUQUIM_CI_LOG"
URUQUIM_CI_EXIT="${PIPESTATUS[0]}"
set -e
URUQUIM_CI_FINISHED="$(date +%s)"
URUQUIM_CI_DURATION="$((URUQUIM_CI_FINISHED - URUQUIM_CI_STARTED))"

if test "$URUQUIM_CI_EXIT" -eq 0; then
  URUQUIM_CI_RESULT=pass
else
  URUQUIM_CI_RESULT=fail
fi

URUQUIM_CI_STATUS_TMP="$(mktemp "$URUQUIM_CI_STATE_DIR/.status.XXXXXX")"
{
  printf 'commit=%s\n' "$URUQUIM_CI_COMMIT"
  printf 'branch=%s\n' "$URUQUIM_CI_BRANCH"
  printf 'result=%s\n' "$URUQUIM_CI_RESULT"
  printf 'checked_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'duration_seconds=%s\n' "$URUQUIM_CI_DURATION"
} >"$URUQUIM_CI_STATUS_TMP"
mv "$URUQUIM_CI_STATUS_TMP" "$URUQUIM_CI_STATUS"

echo "Verification $URUQUIM_CI_RESULT: $URUQUIM_CI_COMMIT"
exit "$URUQUIM_CI_EXIT"
