# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Screen capture on Linux.** Until now the Linux build opened and could not
  take a screenshot. Under X11 it reads the root window and selects a region in
  its own overlay, exactly as on Windows. Under Wayland an application is not
  allowed to do either, so Snipper asks the desktop through
  `xdg-desktop-portal`: a full-screen capture comes straight back, and a region
  is chosen in the desktop's own screenshot interface and then opens in the
  editor. Closing that interface cancels quietly. A desktop with no portal
  installed says so, and names the package.

  The X11 path is tested in CI against a real X server: the root window is
  painted a known colour and the screenshot is checked pixel for pixel. **The
  Wayland path has not been run on a real desktop yet.** It shares everything
  after the screenshot arrives with the X11 path, but the conversation with the
  portal itself is untested until somebody tries it under GNOME and KDE.
- **A Debian package.** `packaging/build_deb.sh` builds
  `snipper_<version>_amd64.deb` with its dependencies computed from the binary,
  a launcher entry with capture actions, icons, a man page and AppStream
  metadata.
- **Continuous integration**, and a release workflow that publishes through the
  suite's APT repository at `apt.buache.systems`.

### Changed

- `slate_ui` is taken from the `v0.9.0` tag of alpinsuite/ui-kit rather than
  from a sibling directory, so the build does not depend on what happens to be
  checked out next to it. A gitignored `pubspec_overrides.yaml` restores the
  sibling checkout for local work.
