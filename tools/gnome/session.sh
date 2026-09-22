#!/usr/bin/env bash
#
# Runs a command inside a real GNOME desktop: GNOME Shell with no screen,
# drawing into a virtual monitor, and the portals an Ubuntu desktop runs —
# xdg-desktop-portal with its GNOME and GTK backends, and the permission store.
#
#   bash tools/gnome/session.sh <command> [arguments...]
#
# This exists because tools/fake_portal.py answers the way the specification
# says a portal does, and GNOME does not always: it asks the user for
# permission first, it asks through the shell, and the shell has rules of its
# own about who may ask. None of that can be learned from a fake.
#
# Everything is private to the run: its own session bus, its own runtime
# directory, and its own HOME, so the settings it writes and the permissions
# it grants never reach the desktop of whoever runs it. The command inherits
# WAYLAND_DISPLAY, DBUS_SESSION_BUS_ADDRESS and the rest, and
# tools/gnome/desktop.py is how it looks at the screen and presses things.
#
# Needs gnome-shell, xdg-desktop-portal, xdg-desktop-portal-gnome,
# xdg-desktop-portal-gtk, dbus, python3-gi and a software GL (libgl1-mesa-dri,
# libegl-mesa0). Logs go to $GNOME_OUT (default build/gnome).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export GNOME_OUT="${GNOME_OUT:-$PWD/build/gnome}"
mkdir -p "$GNOME_OUT"
GNOME_OUT="$(cd "$GNOME_OUT" && pwd)"

# A bus of our own first, then everything below runs on it.
if [[ -z "${GNOME_RIG_BUS:-}" ]]; then
  export GNOME_RIG_BUS=1
  exec dbus-run-session -- bash "$0" "$@"
fi

# The desktop's own home, so gsettings, dconf and the permission store write
# here and nowhere else.
export HOME="$GNOME_OUT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
rm -rf "$HOME"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
# Before the shell starts, so it watches the directory for desktop entries a
# test installs later.
mkdir -p "$XDG_DATA_HOME/applications"

# The runtime directory the real one would be, for the Wayland socket. The
# real one is remembered: a test that needs the user's systemd — to start a
# process the way the shell's launcher does — has to be able to reach it.
export GNOME_RIG_USER_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
XDG_RUNTIME_DIR="$(mktemp -d /tmp/gnome-rig.XXXXXX)"
export XDG_RUNTIME_DIR
chmod 700 "$XDG_RUNTIME_DIR"

# What an Ubuntu desktop session says about itself. xdg-desktop-portal reads
# XDG_CURRENT_DESKTOP to decide which backend answers which portal.
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
export XDG_SESSION_DESKTOP=ubuntu
unset DISPLAY WAYLAND_DISPLAY

# No GPU on a runner. Mesa's software rasteriser, asked for outright.
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do kill "$pid" 2> /dev/null; done
  wait 2> /dev/null
  rm -rf "$XDG_RUNTIME_DIR"
}
trap cleanup EXIT

# The rig's extension, which turns on unsafe mode: see extension/extension.js.
# Written before the shell starts, because enabled-extensions is read once.
UUID="snipper-rig@alpinsuite.test"
mkdir -p "$XDG_DATA_HOME/gnome-shell/extensions"
cp -r "$HERE/extension" "$XDG_DATA_HOME/gnome-shell/extensions/$UUID"
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "['$UUID']"
# The welcome tour is a modal dialog of its own, and it would be the first
# thing any screenshot showed.
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999'

gnome-shell --headless --virtual-monitor 1280x800 --no-x11 \
  > "$GNOME_OUT/gnome-shell.log" 2>&1 &
PIDS+=($!)

for _ in $(seq 1 150); do
  [[ -S "$XDG_RUNTIME_DIR/wayland-0" ]] && break
  sleep 0.2
done
if [[ ! -S "$XDG_RUNTIME_DIR/wayland-0" ]]; then
  echo "::error::GNOME Shell never opened a Wayland socket"
  tail -50 "$GNOME_OUT/gnome-shell.log"
  exit 1
fi
export WAYLAND_DISPLAY=wayland-0

# Anything the bus starts from now on — the permission store, dconf — sees
# the display and the session's identity, as it would under gnome-session.
dbus-update-activation-environment \
  WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
  XDG_SESSION_DESKTOP HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME \
  XDG_STATE_HOME LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER

if ! python3 "$HERE/desktop.py" ready --timeout 60; then
  echo "::error::GNOME Shell came up but the rig cannot talk to it"
  tail -50 "$GNOME_OUT/gnome-shell.log"
  exit 1
fi

# The portals, started by hand rather than by the bus so their logs can be
# kept and made verbose. The backends first: the frontend looks for them as
# it starts.
/usr/libexec/xdg-desktop-portal-gnome --verbose \
  > "$GNOME_OUT/portal-gnome.log" 2>&1 &
PIDS+=($!)
/usr/libexec/xdg-desktop-portal-gtk --verbose \
  > "$GNOME_OUT/portal-gtk.log" 2>&1 &
PIDS+=($!)
python3 "$HERE/desktop.py" wait-name org.freedesktop.impl.portal.desktop.gnome --timeout 30 \
  || echo "::warning::the GNOME portal backend never took its name"
python3 "$HERE/desktop.py" wait-name org.freedesktop.impl.portal.desktop.gtk --timeout 30 \
  || echo "::warning::the GTK portal backend never took its name"
/usr/libexec/xdg-desktop-portal --verbose > "$GNOME_OUT/portal.log" 2>&1 &
PIDS+=($!)
if ! python3 "$HERE/desktop.py" wait-name org.freedesktop.portal.Desktop --timeout 30; then
  echo "::error::xdg-desktop-portal never took its name"
  tail -50 "$GNOME_OUT/portal.log"
  exit 1
fi

# Every message on the bus, for reading afterwards. The conversation between
# the portal, its backends and the shell is the thing being studied.
dbus-monitor --session > "$GNOME_OUT/dbus.log" 2>&1 &
PIDS+=($!)

"$@"
status=$?
exit "$status"
