# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-20

First version. Everything below is new.

### Added

- **Capture a region or the whole screen.** A region is dragged out over a
  frozen picture of the desktop, so nothing moves while it is being chosen.
  There is an optional delay, for capturing something that only appears while
  another application has the pointer.
- **Annotate before it goes anywhere.** The capture opens in an editor rather
  than a file: draw on it, mark up what matters, then copy it to the clipboard
  or save it.
- **Capture from anywhere, with a keyboard shortcut.** `snipper --region` and
  `snipper --full` take a capture and open it; adding `--clipboard` copies it
  and quits without ever showing a window, which is the shape a desktop
  shortcut wants. Both are offered as actions on the launcher entry, because a
  client cannot register a system-wide hotkey under Wayland and the desktop's
  own shortcut editor has to be pointed at one of these instead.
- **Screen capture on Linux.** Under X11 Snipper reads the root window and
  selects a region in its own overlay, exactly as on Windows. Under Wayland an
  application is allowed to do neither, so it asks the desktop through
  `xdg-desktop-portal`: a full-screen capture comes straight back, and a region
  is chosen in the desktop's own screenshot interface and then opens in the
  editor. Closing that interface cancels quietly. A desktop with no portal
  installed says so, and names the package.

  `SNIPPER_CAPTURE=portal` sends captures through the desktop even on an X
  server, for a Wayland session reached through XWayland, where the X root
  shows every native window black.
- **A Debian package**, published through the suite's APT repository at
  `apt.buache.systems`. Its dependencies are computed from the binary, and it
  carries a launcher entry with capture actions, icons, a man page and
  AppStream metadata. Built against glibc 2.35, so it runs on Ubuntu 22.04+ and
  Debian 12+.
- **Everything happens on the machine it runs on.** No account, no telemetry,
  and nothing on the network.

### Known limitations

- **Screen capture under Wayland has not been run on a real desktop.** It is
  exercised in CI against a stand-in for the portal that follows the
  specification through every answer it allows — on time, before the call
  returns, from a request path of its own choosing, a cancel, a refusal, and no
  portal at all — and the file the portal writes is checked to have been
  deleted afterwards. What no test here can show is that GNOME and KDE answer
  the way the specification says they do. **Under X11 the whole flow is tested
  against a real X server**, pixel for pixel, and the application is started,
  driven through a dragged selection and screenshotted on every push.

  If a capture fails on your desktop, the message says which part refused, and
  [an issue](https://github.com/alpinsuite/snipper/issues) with it in is the
  most useful thing you can send.
- **x86-64 Linux only.** There is no 32-bit and no ARM package, and nothing is
  published for Windows yet, though it builds and runs there.
