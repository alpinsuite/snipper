#!/usr/bin/env bash
#
# Sets the project version everywhere it appears.
#
#   tools/set_version.sh 1.2.3
#
# pubspec.yaml is the single source of truth. This script carries the value to
# the two other places it is written down: lib/core/app_version.dart, which the
# About dialog shows, and the AppStream metainfo. The Debian control file reads
# pubspec at build time, so it needs no editing.
#
# With no argument it prints the current version, which is what the release
# workflow uses to check that a tag matches.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

METAINFO="packaging/com.alpinsuite.snipper.metainfo.xml"

current_version() {
  sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' pubspec.yaml
}

if [[ $# -eq 0 ]]; then
  current_version
  exit 0
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "not a semantic version: $VERSION" >&2
  echo "expected MAJOR.MINOR.PATCH, optionally with a -prerelease suffix" >&2
  exit 2
fi

# The build number is monotonic across releases; bump it alongside the version
# so package managers never see it go backwards.
BUILD="$(sed -n 's/^version: *[0-9][^+ ]*+\([0-9]*\).*/\1/p' pubspec.yaml)"
BUILD="$(( ${BUILD:-0} + 1 ))"

sed -i "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
sed -i "s/^const String appVersion = '.*';/const String appVersion = '$VERSION';/" \
  lib/core/app_version.dart

# The newest release goes first in the metainfo. Added only if this version is
# not already there, so running the script twice changes nothing.
if ! grep -q "<release version=\"$VERSION\"" "$METAINFO"; then
  TODAY="$(date -u +%Y-%m-%d)"
  sed -i "s|^  <releases>|  <releases>\n    <release version=\"$VERSION\" date=\"$TODAY\">\n      <description>\n        <p>See the changelog for what changed in $VERSION.</p>\n      </description>\n    </release>|" \
    "$METAINFO"
fi

echo "version set to $VERSION+$BUILD"
echo "now move the Unreleased section of CHANGELOG.md under a [$VERSION] heading"
