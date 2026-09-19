# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **A Debian package.** `packaging/build_deb.sh` builds
  `snipper_<version>_amd64.deb` with its dependencies computed from the binary,
  a launcher entry with capture actions, icons, a man page and AppStream
  metadata.
- **Continuous integration**, and a release workflow that publishes through the
  suite's APT repository at `apt.buache.systems`. It refuses to run while
  screen capture on Linux is still a placeholder.

### Changed

- `slate_ui` is taken from the `v0.9.0` tag of alpinsuite/ui-kit rather than
  from a sibling directory, so the build does not depend on what happens to be
  checked out next to it. A gitignored `pubspec_overrides.yaml` restores the
  sibling checkout for local work.
