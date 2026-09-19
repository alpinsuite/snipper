#!/usr/bin/env bash
#
# Fails when a user-visible string is written directly into the UI instead of
# going through AppLocalizations.
#
# Catching this at build time is much cheaper than auditing the whole interface
# the day a second language is added, which is the point of wiring up i18n
# before it is strictly needed.
#
# The check is deliberately narrow: it looks for string literals passed to the
# widgets that render text, and ignores everything a user cannot read.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Widgets whose first positional argument is displayed to the user.
PATTERN="(Text|SelectableText)\\(\\s*'[^']"

# Strings that are legitimately not translatable: separators and glyphs, which
# are punctuation rather than words. Format names — JPEG, PNG — are proper nouns
# and reach the interface as data on OutputFormat rather than as literals here,
# so they need no exception.
ALLOWED="^[[:punct:][:space:]]+\$"

FOUND=0
while IFS= read -r line; do
  literal="$(printf '%s' "$line" | sed -n "s/.*(\s*'\([^']*\)'.*/\1/p")"
  if [[ -n "$literal" ]] && printf '%s' "$literal" | grep -qE "$ALLOWED"; then
    continue
  fi
  # An interpolated literal is composed from already-translated pieces.
  if printf '%s' "$line" | grep -q '\${'; then
    continue
  fi
  echo "$line"
  FOUND=1
done < <(grep -rnE "$PATTERN" lib/ui lib/app.dart 2>/dev/null || true)

if [[ "$FOUND" == "1" ]]; then
  cat >&2 <<'MESSAGE'

error: user-visible text is hardcoded in the widgets listed above.

Add the string to lib/l10n/app_en.arb, run `flutter gen-l10n`, and read it
through `AppLocalizations.of(context)`.
MESSAGE
  exit 1
fi

echo "no hardcoded user-facing strings"
