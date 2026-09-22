# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-09-22

### Fixed

- **Full-screen capture on GNOME under Wayland** — Ubuntu 24.04's default
  session — failed every time with "The desktop declined to take a
  screenshot". GNOME asks once before an application may capture the whole
  screen by itself, and GNOME Shell puts that question only on behalf of the
  focused window. Snipper stepped out of the way first, so nobody was ever
  asked. The first full-screen capture now keeps Snipper's window in front
  while GNOME asks **Allow Snipper to Take Screenshots?**; after Allow the
  capture is taken with the window out of the way, and GNOME does not ask
  again. After Deny, Snipper says so, and gives the command that makes GNOME
  ask again — GNOME's settings have no switch for it.
- **GNOME now knows Snipper's window is Snipper's.** It was tracked as an
  anonymous window, with no icon in the dock and nothing to ask a permission
  on behalf of: the window's application ID matched no launcher entry.
- **A capture started from the launcher or a keyboard shortcut says why it
  failed.** `snipper --full` exited quietly when the desktop refused, which
  looked exactly like the shortcut doing nothing; the window now opens on the
  reason. With `--clipboard` the reason is printed and the exit status is 1.

### Added

- **A real GNOME desktop in CI.** Every change runs GNOME Shell 46 headless with
  the portals Ubuntu 24.04 ships, and takes a full-screen capture from the
  dash, from the launcher's action, from a terminal and from a keyboard
  shortcut, answering GNOME's question for real — including Deny, and the way
  back. The released 0.1.0 is put through the first of those beforehand, and
  the job fails unless 0.1.0 does.

## [0.1.0] - 2026-09-20

First version. Everything below is new.

### Added

- **Capture a region or the whole screen.** A region is chosen over a frozen
  picture of the desktop, so nothing moves while it is being picked out — in
  Snipper's own overlay on Windows, and in the desktop's screenshot interface
  on Linux, for the reason under *Screen capture on Linux* below. There is an
  optional delay, for catching something that only appears while another
  application has the pointer.
- **Annotate before it goes anywhere.** The capture opens in an editor rather
  than a file: draw on it, mark up what matters, then copy it to the clipboard
  or save it.
- **Capture from anywhere, with a keyboard shortcut.** `snipper --region` and
  `snipper --full` take a capture and open it; adding `--clipboard` copies it
  and quits without ever showing a window, which is the shape a desktop
  shortcut wants. Both are offered as actions on the launcher entry, because a
  client cannot register a system-wide hotkey under Wayland and the desktop's
  own shortcut editor has to be pointed at one of these instead.
- **Screen capture on Linux.** A full-screen capture is read straight off the
  X server where there is one, and asked of the desktop under Wayland, where an
  application is not allowed to read the screen itself.

  **A region is always selected by the desktop**, through
  `xdg-desktop-portal`, on both display servers: its own screenshot interface
  opens, and what you choose comes back already cropped and ready to mark up.
  Closing that interface cancels quietly, and a desktop with no portal
  installed says so and names the package. Drawing our own selection over the
  screen is what the Windows build does, and it was tried here first — it
  needs the window resized out from under the Flutter engine, which then never
  draws the overlay and ends the process on the first click. That happened on
  about half of all runs, so the desktop does the selecting instead.

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

- **Region capture has not been run against a real desktop portal.** Every
  push starts the application on a real X server, presses the shortcut three
  times and checks that what the portal returned is what the editor opened
  — but the portal answering is `tools/fake_portal.py`, which follows the
  specification through every reply it allows: on time, before the call
  returns, from a request path of its own choosing, a cancel, a refusal, and
  no portal at all. It also checks that the file the portal wrote is deleted
  afterwards. What no test here can show is that GNOME and KDE answer the way
  the specification says they do. Full-screen capture **is** checked against a
  real X server, pixel for pixel.

  If a capture fails on your desktop, the message says which part refused, and
  [an issue](https://github.com/alpinsuite/snipper/issues) with it in is the
  most useful thing you can send.
- **x86-64 Linux only.** There is no 32-bit and no ARM package, and nothing is
  published for Windows yet, though it builds and runs there.
