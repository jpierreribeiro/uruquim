#!/usr/bin/env bash
# WP10 — the documentation parity gate.
#
# Documentation drifts silently: the code changes, the prose does not, and both
# keep looking green. This gate makes drift a build failure.
#
# THE INVENTORY IS READ FROM `build/check_public_api.sh`, never re-typed here
# (WP10 D2). A second hand-maintained list would diverge from the package while
# both files still passed their own checks — precisely the failure this exists
# to prevent.
#
# It reads only; it never edits a document.
set -euo pipefail

URUQUIM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URUQUIM_DOCS="$URUQUIM_ROOT/docs"

fail() {
  echo "DOCS-FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# The canonical ledgers, extracted from the API checker itself.
# ---------------------------------------------------------------------------
URUQUIM_APP_SYMBOLS="$(sed -n '/^URUQUIM_EXPECTED_EXPORTS="/,/"$/p' \
  "$URUQUIM_ROOT/build/check_public_api.sh" | sed '1s/.*="//' | sed '$s/"$//')"
URUQUIM_TS_SYMBOLS="$(sed -n '/^URUQUIM_EXPECTED_TESTSUPPORT_EXPORTS="/,/"$/p' \
  "$URUQUIM_ROOT/build/check_public_api.sh" | sed '1s/.*="//' | sed '$s/"$//')"

URUQUIM_APP_COUNT="$(grep -c . <<<"$URUQUIM_APP_SYMBOLS")"
URUQUIM_TS_COUNT="$(grep -c . <<<"$URUQUIM_TS_SYMBOLS")"
test "$URUQUIM_APP_COUNT" -eq 32 ||
  fail "the canonical application ledger is $URUQUIM_APP_COUNT, not 32; docs parity cannot be trusted"
test "$URUQUIM_TS_COUNT" -eq 2 ||
  fail "the canonical test-support ledger is $URUQUIM_TS_COUNT, not 2"

# ---------------------------------------------------------------------------
# ACTIVE documents: the ones a person or agent is meant to copy from today.
#
# `cookbook.md`, `middleware.md` and `memory-model.md` are whole-file
# placeholders for later phases; they must SAY so at the top, and are not
# scanned as active.
# ---------------------------------------------------------------------------
URUQUIM_ACTIVE_DOCS=(
  "$URUQUIM_DOCS/ai-context.md"
  "$URUQUIM_DOCS/canonical-patterns.md"
  "$URUQUIM_DOCS/quick-start.md"
  "$URUQUIM_DOCS/errors.md"
  "$URUQUIM_ROOT/README.md"
)
URUQUIM_PLACEHOLDER_DOCS=(
  "$URUQUIM_DOCS/cookbook.md"
  "$URUQUIM_DOCS/middleware.md"
  "$URUQUIM_DOCS/memory-model.md"
)

for URUQUIM_DOC in "${URUQUIM_ACTIVE_DOCS[@]}"; do
  test -f "$URUQUIM_DOC" || fail "active document $URUQUIM_DOC is missing"
done

for URUQUIM_DOC in "${URUQUIM_PLACEHOLDER_DOCS[@]}"; do
  test -f "$URUQUIM_DOC" || continue
  head -n 8 "$URUQUIM_DOC" | grep -qiE 'placeholder|phase [2-4]|future' ||
    fail "$(basename "$URUQUIM_DOC") is a later-phase placeholder but does not say so in its first lines (AMEND-4)"
done

# ---------------------------------------------------------------------------
# 1. Every Odin block in an active document is CLASSIFIED (WP10 D1).
#
# The marker sits on the line immediately above the fence. Exactly four kinds
# are accepted; anything else is unclassified and fails.
# ---------------------------------------------------------------------------
uruquim_check_classification() { # file
  local file="$1"
  awk -v FILE="$file" '
    /^<!-- (compile|fragment|phase|pseudocode):/ { marker = NR; next }
    /^```odin$/ {
      if (marker != NR - 1) {
        printf "%s:%d: unclassified odin block\n", FILE, NR
        bad = 1
      }
      next
    }
    END { exit bad }
  ' "$file" || fail "an Odin block in $(basename "$file") has no classification marker (WP10 D1)"
}

for URUQUIM_DOC in "${URUQUIM_ACTIVE_DOCS[@]}"; do
  uruquim_check_classification "$URUQUIM_DOC"
done
echo "docs: every Odin block in an active document is classified"

# 1b. A `compile:` marker must name a file that exists, and a `fragment:`
#     marker must name a fixture that exists. A marker pointing at nothing is
#     worse than no marker: it claims coverage it does not have.
while IFS= read -r URUQUIM_TARGET; do
  test -f "$URUQUIM_ROOT/$URUQUIM_TARGET" ||
    fail "a doc block claims 'compile: $URUQUIM_TARGET' but that file does not exist"
done < <(grep -rhoE '<!-- compile: [^ ]+ -->' "${URUQUIM_ACTIVE_DOCS[@]}" |
  sed -E 's/<!-- compile: (.*) -->/\1/' | LC_ALL=C sort -u)

URUQUIM_FIXTURES="$URUQUIM_ROOT/tests/wp10-doc-fixtures"
while IFS= read -r URUQUIM_FRAGMENT; do
  test -d "$URUQUIM_FIXTURES" ||
    fail "a doc block claims 'fragment: $URUQUIM_FRAGMENT' but tests/wp10-doc-fixtures/ does not exist"
  grep -rqE "fragment: $URUQUIM_FRAGMENT\b" "$URUQUIM_FIXTURES" ||
    fail "the Phase-1 fragment '$URUQUIM_FRAGMENT' has no compilable fixture in tests/wp10-doc-fixtures/"
done < <(grep -rhoE '<!-- fragment: [^ ]+ -->' "${URUQUIM_ACTIVE_DOCS[@]}" |
  sed -E 's/<!-- fragment: (.*) -->/\1/' | LC_ALL=C sort -u)
echo "docs: every compile/fragment marker resolves to a real file or fixture"

# ---------------------------------------------------------------------------
# 2. Parity: the active reference names all 32 application symbols.
#
# `docs/ai-context.md` is the compact reference an agent is given. A symbol
# missing from it is a symbol an agent will not know exists.
# ---------------------------------------------------------------------------
URUQUIM_AI="$URUQUIM_DOCS/ai-context.md"
URUQUIM_AI_ACTIVE="$(awk '/^## Appendix — future phases/{exit} {print}' "$URUQUIM_AI")"
test -n "$URUQUIM_AI_ACTIVE" || fail "docs/ai-context.md has no active section"

while IFS= read -r URUQUIM_SYMBOL; do
  test -n "$URUQUIM_SYMBOL" || continue
  grep -qE "\bweb\.${URUQUIM_SYMBOL}\b|\b${URUQUIM_SYMBOL}\b" <<<"$URUQUIM_AI_ACTIVE" ||
    fail "public symbol '$URUQUIM_SYMBOL' is missing from the active reference in docs/ai-context.md"
done <<<"$URUQUIM_APP_SYMBOLS"
echo "docs: all $URUQUIM_APP_COUNT application symbols appear in the active reference"

# 2b. The two test-support symbols live in their OWN section, so the ledgers
#     cannot be quietly merged into one number.
grep -qE '^## Testing' <<<"$URUQUIM_AI_ACTIVE" ||
  fail "docs/ai-context.md has no separate Testing section for the test-support ledger"
while IFS= read -r URUQUIM_SYMBOL; do
  test -n "$URUQUIM_SYMBOL" || continue
  grep -qE "\b${URUQUIM_SYMBOL}\b" <<<"$URUQUIM_AI_ACTIVE" ||
    fail "test-support symbol '$URUQUIM_SYMBOL' is missing from docs/ai-context.md"
done <<<"$URUQUIM_TS_SYMBOLS"

# 2c. The documented counts must be the real ones.
grep -qE '\b32\b' <<<"$URUQUIM_AI_ACTIVE" ||
  fail "docs/ai-context.md does not state the 32-symbol application ledger"
grep -qE '\b34\b' <<<"$URUQUIM_AI_ACTIVE" ||
  fail "docs/ai-context.md does not state the 34-symbol union"

# ---------------------------------------------------------------------------
# 3. Method and Status members in the docs match the package.
# ---------------------------------------------------------------------------
URUQUIM_METHODS="$(awk '/^Method :: enum u8 \{/{f=1;next} /^\}/{f=0} f' \
  "$URUQUIM_ROOT/web/request.odin" | sed -E 's:^[[:space:]]*([A-Z_]+),.*:\1:' | grep -E '^[A-Z_]+$')"
while IFS= read -r URUQUIM_MEMBER; do
  grep -qE "\.${URUQUIM_MEMBER}\b" <<<"$URUQUIM_AI_ACTIVE" ||
    fail "Method member '.$URUQUIM_MEMBER' is missing from docs/ai-context.md"
done <<<"$URUQUIM_METHODS"

URUQUIM_STATUSES="$(awk '/^Status :: enum int \{/{f=1;next} /^\}/{f=0} f' \
  "$URUQUIM_ROOT/web/respond.odin" | sed -E 's:^[[:space:]]*([A-Za-z_]+)[[:space:]]*=.*:\1:' |
  grep -E '^[A-Za-z_]+$')"
while IFS= read -r URUQUIM_MEMBER; do
  grep -qE "\.${URUQUIM_MEMBER}\b" <<<"$URUQUIM_AI_ACTIVE" ||
    fail "Status member '.$URUQUIM_MEMBER' is missing from docs/ai-context.md"
done <<<"$URUQUIM_STATUSES"
echo "docs: Method and Status members match the package"

# ---------------------------------------------------------------------------
# 4. No future-phase API inside an ACTIVE section (AMEND-4).
#
# The scan stops at the appendix in ai-context, and at the first future-marked
# heading elsewhere, so a clearly-labelled future section may name them.
# ---------------------------------------------------------------------------
uruquim_active_prose() { # file
  # Drop blocks marked as future or pseudocode, and everything from the future
  # appendix onward.
  awk '
    /^## Appendix — future phases/ { exit }
    /^<!-- (phase|pseudocode):/ { skip = 1; next }
    /^```/ { if (skip && ++fences == 2) { skip = 0; fences = 0 } ; next }
    { if (!skip) print }
  ' "$1"
}

for URUQUIM_DOC in "${URUQUIM_ACTIVE_DOCS[@]}"; do
  URUQUIM_PROSE="$(uruquim_active_prose "$URUQUIM_DOC")"
  # Lines that explicitly name a later phase are allowed to mention the symbol.
  URUQUIM_PROSE="$(grep -viE 'phase [2-4]|future|unavailable|not in phase 1|later phase' <<<"$URUQUIM_PROSE" || true)"
  for URUQUIM_FUTURE in 'web\.use\b' 'web\.next\b' 'web\.router\b' 'web\.group\b' \
    'web\.mount\b' 'web\.header\(' 'web\.bearer_token\b' 'web\.state\b' \
    'web\.app_with_state\b' 'web\.serve_with\b' 'web\.serve_transport\b' \
    'web\.body_limit\b' 'web\.bytes\b' 'web\.redirect\b' 'web\.conflict\b'; do
    if grep -nE "$URUQUIM_FUTURE" <<<"$URUQUIM_PROSE"; then
      fail "$(basename "$URUQUIM_DOC") names future API /$URUQUIM_FUTURE/ in an ACTIVE section (AMEND-4)"
    fi
  done
done
echo "docs: no future-phase API appears in an active section"

# ---------------------------------------------------------------------------
# 5. Canonical call-site rules, everywhere in the active docs.
# ---------------------------------------------------------------------------
for URUQUIM_DOC in "${URUQUIM_ACTIVE_DOCS[@]}"; do
  # Every rule here is scoped to CODE BLOCKS, never prose. The documents must be
  # able to NAME a forbidden form in order to forbid it — "do not write
  # `or_else { }`" is guidance, not a violation.
  URUQUIM_CODE_ONLY="$(awk '/^```odin$/{inb=1;next} /^```$/{inb=0;next} inb' "$URUQUIM_DOC" |
    sed -E 's://.*$::')"
  if grep -nE 'or_else[[:space:]]*\{' <<<"$URUQUIM_CODE_ONLY"; then
    fail "$(basename "$URUQUIM_DOC") shows an 'or_else { ... }' block in code, which is not valid Odin"
  fi
  if grep -nE 'web\.(ok|created|json)\([^,)]+,[[:space:]]*&' <<<"$URUQUIM_CODE_ONLY"; then
    fail "$(basename "$URUQUIM_DOC") shows a POINTER payload; Phase-1 payloads are values (ADR-003)"
  fi
  # Comments are stripped above, so a comment that teaches ".GET, never .Get"
  # is not itself a violation.
  if grep -nE '\.(Get|Post|Put|Patch|Delete)\b' <<<"$URUQUIM_CODE_ONLY"; then
    fail "$(basename "$URUQUIM_DOC") uses a mixed-case Method member in code; they are UPPERCASE (.GET)"
  fi
done
echo "docs: canonical call-site rules hold in every active document"

# ---------------------------------------------------------------------------
# 6. No stale status claim survives (the WP10 repair list).
#
# Each of these was TRUE at some earlier work package and is FALSE now. Leaving
# one in place is worse than saying nothing: it tells a reader a working feature
# does not work.
# ---------------------------------------------------------------------------
for URUQUIM_DOC in "${URUQUIM_ACTIVE_DOCS[@]}"; do
  URUQUIM_BODY="$(cat "$URUQUIM_DOC")"
  for URUQUIM_STALE in \
    'serve.*(binds no port|does not bind|returns immediately without binding)' \
    '(responders|response helpers?).*(are|remain|still).*(inert|stubs?)' \
    'web\.body.*(is|remains|still).*(a )?(WP7 )?stub' \
    'body binding.*(does not work|is not implemented)' \
    'not a functional (HTTP )?server' \
    '(404|405).*(bodies are|body is) EMPTY' \
    '(returns|yields|is) the zero status' \
    'WP1 and WP2 are complete' \
    'production.ready'; do
    if grep -niE "$URUQUIM_STALE" <<<"$URUQUIM_BODY"; then
      fail "$(basename "$URUQUIM_DOC") contains a STALE claim matching /$URUQUIM_STALE/ (WP10 D4)"
    fi
  done
done
echo "docs: no stale pre-WP10 status claim remains"

# 6b. The delivered/future split must be present, not implied (AMEND-3).
grep -qiE 'phase 2' "$URUQUIM_AI" ||
  fail "docs/ai-context.md does not name the Phase-2 boundary (AMEND-3)"
grep -qiE '4 MiB' "$URUQUIM_AI" ||
  fail "docs/ai-context.md does not state the fixed 4 MiB body cap (AMEND-3)"

# 6c. The Quick Start must be real, not the WP10 placeholder.
grep -qiE '^> Placeholder' "$URUQUIM_DOCS/quick-start.md" &&
  fail "docs/quick-start.md is still the placeholder (WP10 must replace it)"
grep -qE 'web\.serve\(&app, 8080\)' "$URUQUIM_DOCS/quick-start.md" ||
  fail "docs/quick-start.md does not show a runnable server"

# 6d. The Quick Start teaches no internals.
for URUQUIM_INTERNAL in 'allocator' 'odin-http' 'radix' 'arena' 'Advanced API' \
  'middleware cursor' 'transport adapter'; do
  if grep -niE "^[^>]*\b$URUQUIM_INTERNAL\b" "$URUQUIM_DOCS/quick-start.md" |
    grep -viE 'internal|replaceable|behind|note'; then
    fail "docs/quick-start.md teaches an internal concept matching /$URUQUIM_INTERNAL/"
  fi
done
echo "docs: the Quick Start is real and teaches no internals"

# ---------------------------------------------------------------------------
# 7. No GitHub Actions workflow (owner decision; the gate is local/VPS).
# ---------------------------------------------------------------------------
if test -d "$URUQUIM_ROOT/.github/workflows"; then
  fail ".github/workflows exists; GitHub Actions is not a mandatory gate for this project"
fi

echo "PASS: documentation parity (ledgers $URUQUIM_APP_COUNT + $URUQUIM_TS_COUNT = $((URUQUIM_APP_COUNT + URUQUIM_TS_COUNT)))"
