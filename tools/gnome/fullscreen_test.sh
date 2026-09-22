#!/usr/bin/env bash
#
# Snipper capturing the whole screen on a real GNOME desktop, every way a
# person asks it to. Runs inside tools/gnome/session.sh:
#
#   bash tools/gnome/session.sh bash tools/gnome/fullscreen_test.sh
#
# GNOME asks the user once before an application may take a screenshot by
# itself, and GNOME Shell puts that question only on behalf of the focused
# window. Snipper 0.1.0 stepped out of the way first, so nobody was ever
# asked and every full-screen capture was refused. What this checks is what
# the user sees: the question, asked for Snipper by name, and then the capture
# in the editor — told apart by colour from a picture of Snipper itself,
# which is what asking in front takes and has to throw away.
#
# With SNIPPER_RELEASED set to an older binary, that binary goes first, through
# the same steps, so that a pass here is a pass against the failure people saw.
#
# The binaries come in through the environment, not the command line: every
# Snipper is stopped with `pkill -f` between cases, and a path on this
# script's own command line would stop the script.
#
# Needs imagemagick and gir1.2-gtk-3.0, besides what session.sh needs.

set -uo pipefail
cd "$(dirname "$0")/../.."

BUILD="$(realpath "${SNIPPER_BUILD:-build/linux/x64/release/bundle/snipper}")"
RELEASED="${SNIPPER_RELEASED:+$(realpath "$SNIPPER_RELEASED")}"
OUT="$GNOME_OUT"
USER_RT="$GNOME_RIG_USER_RUNTIME_DIR"
WALLPAPER="$GNOME_RIG_WALLPAPER"

PROBLEMS=()
note() { echo "::error::$1"; PROBLEMS+=("$1"); }
d() { python3 tools/gnome/desktop.py "$@"; }

# Runs a command in app-gnome-snipper-<n>.scope, which is what GNOME's
# launcher and its keyboard shortcuts put an application in, and where
# xdg-desktop-portal reads an unsandboxed application's identity from. The
# rest of the command's environment stays the session's.
in_scope() {
  env XDG_RUNTIME_DIR="$USER_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RT/bus" \
    systemd-run --user --scope --quiet --unit="app-gnome-snipper-$RANDOM" \
    env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    "$@"
}

# Snipper's own desktop entry, installed so the shell launches it as the dash
# does — by a wrapper that takes the same kind of scope. `entry <binary>`
# points it at one build or the other.
LAUNCHER="$HOME/snipper-from-the-dash.sh"
entry() {
  cat > "$LAUNCHER" << EOF
#!/bin/bash
exec env XDG_RUNTIME_DIR="$USER_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RT/bus" \\
  systemd-run --user --scope --quiet --unit="app-gnome-snipper-\$\$" \\
  env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \\
  "$1" "\$@" >> "$OUT/snipper-launched.log" 2>&1
EOF
  chmod +x "$LAUNCHER"
}
entry "$BUILD"
sed -e "s|^Exec=snipper|Exec=$LAUNCHER|" packaging/snipper.desktop \
  > "$XDG_DATA_HOME/applications/snipper.desktop"

reap() {
  pkill -f "/snipper( |$)" 2> /dev/null
  sleep 1
  pkill -9 -f "/snipper( |$)" 2> /dev/null
  return 0
}

# Every case starts from nothing: no Snipper, no question left on screen,
# nothing recorded. A question nobody answered stays up after the portal has
# given up on it, and the shell will not put up another until it goes.
fresh() {
  reap
  if d state | grep -q '"dialog": \["'; then
    d click Deny > /dev/null
    sleep 1
  fi
  d idle > /dev/null || note "the desktop would not settle before a case"
  d forget
}

stored() { d permissions; }

await_window() {
  local _
  for _ in $(seq 1 30); do
    sleep 1
    if d state | grep -q '"title": "Snipper"'; then
      sleep 3
      return 0
    fi
  done
  return 1
}

focus() {
  d state | python3 -c 'import json, sys; print(json.load(sys.stdin)["focusApp"])'
}

# Presses Ctrl+Shift+N, which only means anything to a focused Snipper.
full_screen_key() {
  [[ "$(focus)" == "snipper.desktop" ]] \
    || note "$1: Snipper's window does not have the focus ($(focus))"
  d keys ctrl+shift+n
}

# How many screenshots the portal has actually taken, as opposed to refused.
taken() { grep -c "Calling Screenshot with interactive=0" "$OUT/portal.log"; }

# Watches for <seconds>, answering the first question the shell puts with
# <button>. The question's title is left in ASKED, empty if there was none.
ASKED=""
watch() {
  local name="$1" seconds="$2" button="${3:-}" state i
  ASKED=""
  for i in $(seq 1 "$seconds"); do
    sleep 1
    state="$(d state 2>&1)"
    echo "$state" >> "$OUT/$name-states.jsonl"
    if [[ -z "$ASKED" && "$state" == *'"dialog": ["'* ]]; then
      ASKED="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["dialog"][0])' "$state")"
      echo "  t+${i}s the desktop asks: $ASKED"
      d shot "$OUT/$name-asked.png" > /dev/null
      if [[ -n "$button" ]]; then
        sleep 1
        d click "$button" > /dev/null || note "$name: no $button button to press"
      fi
    fi
  done
  [[ -n "$ASKED" ]] || echo "  the desktop asked nothing"
}

# How much of Snipper's window is the colour of the desktop it captured. The
# desktop is one flat colour and Snipper's own interface has none of it, so
# an editor showing a capture is mostly that colour — and one showing a
# capture with Snipper still in it, the picture taken while asking, is not.
shows_capture() {
  local name="$1" frame x y w h pct
  frame="$(d state | python3 -c '
import json, sys
found = [w["frame"] for w in json.load(sys.stdin)["windows"] if w["title"] == "Snipper"]
print(*found[0]) if found else print("")')"
  d shot "$OUT/$name.png" > /dev/null
  if [[ -z "$frame" ]]; then
    echo "  no Snipper window on screen"
    return 1
  fi
  read -r x y w h <<< "$frame"
  pct="$(convert "$OUT/$name.png" -crop "${w}x${h}+${x}+${y}" +repage \
    -fuzz 8% -transparent "$WALLPAPER" -format '%[fx:int(100*(1-mean.a))]' info:)"
  echo "  $pct% of Snipper's window is the captured desktop"
  (( pct >= 35 ))
}

# Somebody else's window, as on any desktop in use. When Snipper steps aside
# this is what gets the focus, and it is why GNOME refused 0.1.0 at once
# rather than after its 25-second wait.
python3 - << 'EOF' &
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
window = Gtk.Window(title="Another application")
window.set_default_size(320, 240)
window.connect("destroy", Gtk.main_quit)
window.show_all()
Gtk.main()
EOF
OTHER=$!
trap 'kill "$OTHER" 2> /dev/null' EXIT
sleep 3

echo "=== the desktop"
dpkg-query -W -f='  ${Package} ${Version}\n' gnome-shell xdg-desktop-portal \
  xdg-desktop-portal-gnome 2> /dev/null
echo "  GNOME's screenshot backend is version $(d property \
  org.freedesktop.impl.portal.desktop.gnome /org/freedesktop/portal/desktop \
  org.freedesktop.impl.portal.Screenshot version 2>&1)"

if [[ -n "$RELEASED" ]]; then
  echo
  echo "=== before: Snipper as released, from the dash, Ctrl+Shift+N"
  fresh
  entry "$RELEASED"
  d launch snipper.desktop
  await_window || echo "  no window"
  d keys ctrl+shift+n
  watch before 8 Allow
  d shot "$OUT/before.png" > /dev/null
  echo "  recorded: $(stored)"
  if [[ -z "$ASKED" ]]; then
    echo "  as reported: nobody was asked, and the capture was refused"
  fi
  entry "$BUILD"
fi

echo
echo "=== 1. from the dash, full screen from Snipper's window, the first time"
fresh
d launch snipper.desktop
await_window || note "1: Snipper opened no window"
BEFORE="$(taken)"
full_screen_key 1
watch 1 10 Allow
[[ "$ASKED" == "Allow Snipper to Take Screenshots?" ]] \
  || note "1: the desktop did not ask on Snipper's behalf (asked: '$ASKED')"
shows_capture 1-editor || note "1: the editor is not showing a capture of the desktop"
[[ "$(stored)" == *'"snipper": ["yes"]'* ]] \
  || note "1: the desktop recorded no yes for snipper: $(stored)"
# One screenshot while asking, thrown away, and one with Snipper aside.
echo "  the portal took $(( $(taken) - BEFORE )) screenshots"
(( $(taken) - BEFORE == 2 )) || note "1: expected two screenshots, one to ask and one to keep"

echo
echo "=== 2. and again, now that the desktop remembers"
BEFORE="$(taken)"
full_screen_key 2
watch 2 6
[[ -z "$ASKED" ]] || note "2: the desktop asked a second time"
(( $(taken) - BEFORE == 1 )) \
  || note "2: expected one screenshot, the portal took $(( $(taken) - BEFORE ))"
shows_capture 2-editor || note "2: the editor is not showing a capture of the desktop"

echo
echo "=== 3. the launcher's 'Capture the Whole Screen', the first time"
fresh
d launch snipper.desktop full
watch 3 12 Allow
[[ "$ASKED" == "Allow Snipper to Take Screenshots?" ]] \
  || note "3: the desktop did not ask on Snipper's behalf (asked: '$ASKED')"
shows_capture 3-editor || note "3: the editor is not showing a capture of the desktop"

echo
echo "=== 4. Deny, then the way back that Snipper spells out"
fresh
d launch snipper.desktop
await_window || note "4: Snipper opened no window"
full_screen_key 4
watch 4 8 Deny
[[ "$(stored)" == *'"snipper": ["no"]'* ]] \
  || note "4: the desktop recorded no refusal: $(stored)"
d shot "$OUT/4-refused.png" > /dev/null
# Exactly what LinuxCaptureService.forgetPermissionCommand prints.
gdbus call --session \
  --dest org.freedesktop.impl.portal.PermissionStore \
  --object-path /org/freedesktop/impl/portal/PermissionStore \
  --method org.freedesktop.impl.portal.PermissionStore.DeletePermission \
  screenshot screenshot "'snipper'" > /dev/null \
  || note "4: the command Snipper prints did not run"
[[ "$(stored)" != *'"snipper"'* ]] \
  || note "4: the command left the refusal in place: $(stored)"
full_screen_key 4-again
watch 4-again 10 Allow
[[ "$ASKED" == "Allow Snipper to Take Screenshots?" ]] \
  || note "4: after the command, the desktop did not ask again (asked: '$ASKED')"
shows_capture 4-editor || note "4: the editor is not showing a capture of the desktop"

echo
echo "=== 5. snipper --full from a terminal, the first time"
fresh
"$BUILD" --full >> "$OUT/snipper-terminal.log" 2>&1 &
watch 5 12 Allow
# From a terminal the portal cannot name the application, and asks about
# every unnamed one at once.
[[ "$ASKED" == "Allow Applications to Take Screenshots?" ]] \
  || note "5: the desktop did not ask (asked: '$ASKED')"
shows_capture 5-editor || note "5: the editor is not showing a capture of the desktop"

echo
echo "=== 6. snipper --full from a keyboard shortcut, the first time"
# What GNOME's shortcut settings do: the same scope as the dash, with no
# launcher in between to hand the window the focus.
fresh
in_scope "$BUILD" --full >> "$OUT/snipper-shortcut.log" 2>&1 &
watch 6 12 Allow
[[ "$ASKED" == "Allow Snipper to Take Screenshots?" ]] \
  || note "6: the desktop did not ask on Snipper's behalf (asked: '$ASKED')"
shows_capture 6-editor || note "6: the editor is not showing a capture of the desktop"
reap

echo
echo "=== what the portal saw"
grep -E "Handle Screenshot|permission|access dialog|Calling Screenshot" "$OUT/portal.log" | tail -40

echo
if (( ${#PROBLEMS[@]} == 0 )); then
  echo "ok: GNOME asked for Snipper by name, every way in, and the capture arrived"
  exit 0
fi
echo "${#PROBLEMS[@]} problem(s):"
printf '  %s\n' "${PROBLEMS[@]}"
exit 1
