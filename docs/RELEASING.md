# Releasing

1. `tools/set_version.sh 0.2.0` — writes the version to `pubspec.yaml`,
   `lib/core/app_version.dart` and the AppStream metainfo. CI fails if the
   three disagree.
2. Move the `Unreleased` section of `CHANGELOG.md` under a `## [0.2.0] - <date>`
   heading. The release notes are cut from it.
3. Commit, then tag and push: `git tag v0.2.0 && git push origin main v0.2.0`.

The tag starts `.github/workflows/release.yml`, which refuses a tag that does
not match the pubspec, runs the tests, builds in an `ubuntu:22.04` container
(glibc 2.35, so the binary runs on Ubuntu 22.04+ and Debian 12+), and publishes
a GitHub Release carrying the `.deb`, a tarball of the bundle, the CycloneDX
SBOM, build-provenance attestations and a signed `SHA256SUMS`. A version with a
hyphen (`0.2.0-rc.1`) is marked a prerelease.

It stops there. The suite's APT repository,
[alpinsuite/apt](https://github.com/alpinsuite/apt), pulls the `.deb` from the
Releases page within the hour; `gh workflow run publish.yml -R alpinsuite/apt`
publishes it at once. Prereleases and drafts are never published to apt.

`SHA256SUMS` is signed with the `APT_GPG_PRIVATE_KEY` repository secret, the
same key that signs the APT repository. Without it the sums are published
unsigned, with a warning.

The repository has to be public for any of this to reach anyone: the APT
repository reads the Releases page anonymously, and attestations are not
available to private repositories on the free plan.
