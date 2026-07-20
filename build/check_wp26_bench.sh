#!/usr/bin/env bash
# WP26 baseline producer.
#
# This script is NOT part of the fast pre-push path, and the split is
# deliberate. `tests/wp26-bench` asserts that the instrument is sound and
# finishes in milliseconds, so `build/check.sh` runs it on every push. This
# script runs the repeated alternating sweep that a DERIVED tolerance requires,
# which takes roughly fifteen minutes — long enough that putting it in the
# mandatory gate would eventually get the gate switched off, and a gate nobody
# runs measures nothing at all.
#
# Run it by hand when the baseline must be re-derived: after a hardware change,
# after a toolchain bump, and before WP28 compares any route representation
# against another. Its output is recorded in `planning/phase-2-baseline.md`.
#
#   bash build/check_wp26_bench.sh > /tmp/wp26.txt
#
# It measures; it decides nothing. WP26's own scope line: "This work package
# produces numbers."
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "WP26 BENCH: ERROR: $*" >&2
  exit 1
}

# The compiler is resolved the same way `check.sh` resolves it, and the pin is
# verified here too. A baseline measured on an unpinned toolchain is a number
# about someone else's compiler.
if test -n "${URUQUIM_COMPILER:-}"; then
  URUQUIM_BENCH_COMPILER="$URUQUIM_COMPILER"
elif test -n "${URUQUIM_ODIN_BIN:-}"; then
  URUQUIM_BENCH_COMPILER="$URUQUIM_ODIN_BIN"
elif command -v odin >/dev/null 2>&1; then
  URUQUIM_BENCH_COMPILER="$(command -v odin)"
else
  fail "odin not found; set URUQUIM_COMPILER or install the pinned distribution"
fi
URUQUIM_BENCH_COMPILER="$(readlink -f "$URUQUIM_BENCH_COMPILER")" ||
  fail "cannot resolve compiler path"
URUQUIM_BENCH_DIR="$(cd "$(dirname "$URUQUIM_BENCH_COMPILER")" && pwd)"

URUQUIM_PIN="$(sed -n 's/^commit=//p' "$URUQUIM_ROOT/odin-version.txt")"
test -n "$URUQUIM_PIN" || fail "missing commit pin in odin-version.txt"
URUQUIM_VERSION="$(ODIN_ROOT="$URUQUIM_BENCH_DIR" "$URUQUIM_BENCH_COMPILER" version 2>&1)"
case "$URUQUIM_VERSION" in
  *"$URUQUIM_PIN"*) ;;
  *) fail "compiler mismatch: expected $URUQUIM_PIN, got: $URUQUIM_VERSION" ;;
esac

URUQUIM_TMP="$(mktemp -d -t uruquim-wp26-XXXXXXXX)"
trap 'rm -rf "$URUQUIM_TMP"' EXIT

# ---------------------------------------------------------------------------
# The environment, recorded. RG-1 requires hardware, build mode, protocol and
# affinity to sit BESIDE the numbers, because a distribution without them is
# not reproducible and therefore is not evidence.
# ---------------------------------------------------------------------------
echo "# environment"
echo "# odin        $URUQUIM_VERSION"
echo "# cpu         $(grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //')"
echo "# cores       $(nproc)"
echo "# memory      $(grep MemTotal /proc/meminfo | awk '{print $2" "$3}')"
echo "# kernel      $(uname -srm)"
echo "# build mode  debug (no -o:speed) — the mode the gate builds"
echo "# tier        in-process dispatch via web.test_request; no socket"
echo "# affinity    none pinned; the sweep alternates instead"

# ---------------------------------------------------------------------------
# Build, and record the build time. RG-1 lists build time among the things the
# methodology must record.
# ---------------------------------------------------------------------------
URUQUIM_T0="$(date +%s)"
env ODIN_ROOT="$URUQUIM_BENCH_DIR" PATH="$URUQUIM_BENCH_DIR:/usr/bin:/bin" \
  "$URUQUIM_BENCH_COMPILER" build "$URUQUIM_ROOT/tests/wp26-runner" \
  "-collection:uruquim=$URUQUIM_ROOT" -out:"$URUQUIM_TMP/wp26-runner" ||
  fail "the baseline runner did not build"
URUQUIM_T1="$(date +%s)"

echo "# build time  $((URUQUIM_T1 - URUQUIM_T0))s"
echo "# runner size $(stat -c%s "$URUQUIM_TMP/wp26-runner") bytes"
# Reported, never asserted: FINDING-A measured a ~100-byte binary-size noise
# floor on this toolchain, so a size threshold would fail randomly.
echo "#"

# ---------------------------------------------------------------------------
# The sweep.
# ---------------------------------------------------------------------------
"$URUQUIM_TMP/wp26-runner" | tee "$URUQUIM_TMP/out.txt" ||
  fail "the baseline runner exited non-zero; see the unverified-run report above"

# ---------------------------------------------------------------------------
# The two conditions that make the output a baseline rather than a log.
# ---------------------------------------------------------------------------

# 1. Semantic equivalence. The runner already exits non-zero on any unverified
#    run, but the string is checked here too: a benchmark whose candidates
#    disagree about the work being done measures error rate and calls it
#    performance, and RG-1's amendment makes that a gate condition rather than
#    advice.
if grep -q '^FAILED' "$URUQUIM_TMP/out.txt"; then
  fail "at least one run was not verified; no baseline is emitted"
fi

# 2. The tolerance must be DERIVED. Its absence means the sweep produced fewer
#    than two repetitions of something, and a tolerance from one observation is
#    a number chosen by taste wearing a measurement's clothes.
grep -q '^TOLERANCE_FLOOR_BP ' "$URUQUIM_TMP/out.txt" ||
  fail "no tolerance floor was derived"

echo "PASS: WP26 baseline produced, every run verified, tolerance derived from the machine"
