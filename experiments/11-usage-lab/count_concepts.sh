#!/usr/bin/env bash
# The usage-laboratory instrument, PRESERVED.
#
# Phase 2 recorded "14 concepts" and "23 concepts" but did not keep the programs
# or the counting rule, so the WP38 re-run had to RECONSTRUCT both — and could
# not reproduce 23 exactly (see planning/phase-3-freeze.md §7). Storing the
# instrument is the fix: the next freeze re-runs rather than reconstructs.
#
# THE RULE: a concept is a distinct `web.` identifier the program NAMES, with
# comments stripped first. Comments are stripped because a program that says
# "this deliberately does not use web.route" would otherwise be charged for the
# sentence — which is how the first WP38 run over-counted by two.
#
# It is a proxy, and the freeze says so: it counts vocabulary, not difficulty.
# Two symbols a reader already knows cost less than one that surprises them.
set -euo pipefail
test $# -ge 1 || { echo "usage: count_concepts.sh <program-dir>..." >&2; exit 2; }
for dir in "$@"; do
  count="$(sed -E 's://.*$::' "$dir"/*.odin | grep -oE 'web\.[a-zA-Z_]+' | LC_ALL=C sort -u | grep -c . || true)"
  printf '%s\t%s\n' "$count" "$dir"
done
