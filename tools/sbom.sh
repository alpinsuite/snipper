#!/usr/bin/env bash
# The Software Bill of Materials for this application.
#
# One CycloneDX JSON document, resolved from pubspec.lock and never from
# pubspec.yaml. The manifest records the version ranges that were asked for;
# the lockfile records the versions that were actually built. Only the second
# one describes the binary somebody is holding.
#
#   bash tools/sbom.sh           write build/sbom.cdx.json
#   bash tools/sbom.sh --check   verify an existing one is complete and current
#
# --check is the release gate. It fails when the SBOM is missing, when it is
# older than the lockfile, and when a package in the lockfile is absent from
# it. Those are the three ways a stale SBOM lies about what shipped.
#
# Generate it in the same CI job that produces the binary. An SBOM written on
# a developer machine describes that machine.
#
# Needs Node, for npx. CI has it; locally, Node 20 or newer.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${SBOM_OUT:-build/sbom.cdx.json}"
CDXGEN="@cyclonedx/cdxgen@${CDXGEN_MAJOR:-12}"

die() { echo "::error::$*" >&2; exit 1; }

[ -f pubspec.lock ] || die "pubspec.lock is missing - run 'flutter pub get' first."

# Every package name in the lockfile. Parsed rather than pulled from a YAML
# library because the shape is fixed and the alternative is a dependency in a
# script whose whole job is to account for dependencies.
lock_packages() {
  node -e '
    const fs = require("fs");
    const lines = fs.readFileSync("pubspec.lock", "utf8").split(/\r?\n/);
    const names = [];
    let inPackages = false;
    for (const line of lines) {
      if (/^packages:\s*$/.test(line)) { inPackages = true; continue; }
      if (inPackages && /^\S/.test(line)) break;
      const m = inPackages && line.match(/^  ([A-Za-z0-9_]+):\s*$/);
      if (m) names.push(m[1]);
    }
    process.stdout.write(names.join("\n"));
  '
}

case "${1:-generate}" in
  generate)
    mkdir -p "$(dirname "$OUT")"
    rm -f "$OUT"
    echo "generating $OUT from pubspec.lock"
    npx --yes "$CDXGEN" --type dart --output "$OUT" . >/dev/null
    [ -s "$OUT" ] || die "cdxgen produced no SBOM."
    node -e '
      const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const n = (s.components || []).length;
      if (!n) { console.error("::error::the SBOM lists no components."); process.exit(1); }
      console.log(`  ${s.bomFormat} ${s.specVersion}, ${n} components`);
    ' "$OUT"
    ;;

  --check|check)
    [ -f "$OUT" ] || die "$OUT is missing - run 'bash tools/sbom.sh'."
    [ "$OUT" -nt pubspec.lock ] || die "$OUT is older than pubspec.lock - regenerate it."
    lock_packages | node -e '
      const fs = require("fs");
      let want = "";
      process.stdin.on("data", d => want += d);
      process.stdin.on("end", () => {
        const out = process.argv[1];
        const sbom = JSON.parse(fs.readFileSync(out, "utf8"));
        const have = new Set((sbom.components || []).map(c => c.name));
        const missing = want.split("\n").filter(Boolean).filter(n => !have.has(n));
        if (missing.length) {
          console.error(`::error::${out} is missing ${missing.length} package(s) from pubspec.lock: ${missing.join(", ")}`);
          process.exit(1);
        }
        console.log(`  ${out} covers all ${have.size} components in the lockfile`);
      });
    ' "$OUT"
    ;;

  *)
    die "usage: sbom.sh [--check]"
    ;;
esac
