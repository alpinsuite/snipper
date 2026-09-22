#!/usr/bin/env bash
#
# What a real GNOME desktop does when Snipper asks it for the whole screen,
# case by case. Runs inside tools/gnome/session.sh:
#
#   SNIPPER_RELEASED=path/to/an/older/snipper \
#     bash tools/gnome/session.sh bash tools/gnome/investigate.sh
#
# Nothing here passes or fails. Each case prints what the portal answered,
# what the shell put on screen while it was deciding, and what the permission
# store says afterwards; the screenshots and every log land in $GNOME_OUT.
#
# The binaries come in through the environment, not the command line: every
# Snipper is stopped with `pkill -f` between cases, and a path on this
# script's own command line would stop the script.

set -uo pipefail
cd "$(dirname "$0")/../.."

BUILD="$(realpath "${SNIPPER_BUILD:-build/linux/x64/release/bundle/snipper}")"
RELEASED="${SNIPPER_RELEASED:+$(realpath "$SNIPPER_RELEASED")}"
OUT="$GNOME_OUT"
USER_RT="$GNOME_RIG_USER_RUNTIME_DIR"

d() { python3 tools/gnome/desktop.py "$@"; }

echo "=== versions"
dpkg-query -W -f='${Package} ${Version}\n' gnome-shell mutter-common \
  xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
  libglib2.0-0t64 2> /dev/null

# Runs a command in app-gnome-snipper-<n>.scope, which is what GNOME's
# launcher puts an application it starts in, and where xdg-desktop-portal
# reads an unsandboxed application's identity from. Everything else about the
# command's environment stays the rig's.
in_scope() {
  env XDG_RUNTIME_DIR="$USER_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RT/bus" \
    systemd-run --user --scope --quiet --unit="app-gnome-snipper-$RANDOM" \
    env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    "$@"
}

# Snipper's desktop entry, installed so the shell can launch it the way the
# dash does: through a wrapper that takes the same scope, so both halves of
# the desktop agree on who is asking — the shell by the window's entry, the
# portal by unit name. `entry <binary>` points it at one build or the other.
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
sleep 2

# Stops every Snipper, however it was started.
reap() {
  pkill -f "/snipper( |$)" 2> /dev/null
  sleep 1
  pkill -9 -f "/snipper( |$)" 2> /dev/null
  return 0
}

# Answers whatever the shell is still asking, so a case starts with nothing on
# screen. A dialog nobody answers stays up after the portal has given up on
# it, and the shell refuses to show another until it goes.
dismiss() {
  if d state | grep -q '"dialog": \["'; then
    d click Deny > /dev/null
    sleep 1
  fi
}

# Watches for <seconds>. Records the shell's state every second; the first
# time the shell shows a dialog, photographs it, and presses <label> if given.
watch() {
  local name="$1" seconds="$2" press="${3:-}" state seen=0 i
  for i in $(seq 1 "$seconds"); do
    sleep 1
    state="$(d state 2>&1)"
    echo "$state" >> "$OUT/$name-states.jsonl"
    if [[ "$state" == *'"dialog": ["'* ]] && (( seen == 0 )); then
      seen=1
      echo "  t+${i}s the shell asks: $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["dialog"][0])' "$state")"
      d shot "$OUT/$name-dialog.png" > /dev/null
      if [[ -n "$press" ]]; then
        sleep 1
        echo "  pressed $press: $(d click "$press" 2>&1)"
      fi
    fi
  done
  (( seen )) || echo "  the shell asked nothing in ${seconds}s"
}

summary() {
  python3 - "$(d state)" << 'EOF'
import json, sys
s = json.loads(sys.argv[1])
print("  focus:", s["focusApp"], "| dialogs:", s["modalCount"])
for w in s["windows"]:
    print("  window %r: app=%s class=%s gapplication=%s focused=%s" % (
        w["title"], w["app"], w["wmClass"], w["gtkAppId"], w["focused"]))
EOF
}

# Waits for a window called Snipper, and says whether it has the focus.
await_window() {
  local i
  for i in $(seq 1 30); do
    sleep 1
    if d state | grep -q '"title": "Snipper"'; then
      sleep 3
      return 0
    fi
  done
  echo "  no Snipper window after 30s"
  return 1
}

fresh() {
  reap
  dismiss
  d forget
}

echo
echo "=== A. a request the portal cannot put a name to"
fresh
d portal --timeout 20 > "$OUT/A.json" &
P=$!
watch A 5 Allow
wait "$P"
echo "  portal: $(cat "$OUT/A.json")"
echo "  stored: $(d permissions)"

echo
echo "=== B. a request as 'snipper', from the dash's scope, nothing focused"
fresh
in_scope python3 tools/gnome/desktop.py portal --timeout 20 > "$OUT/B.json" &
P=$!
watch B 5 Allow
wait "$P"
echo "  portal: $(cat "$OUT/B.json")"
echo "  stored: $(d permissions)"
summary

echo
echo "=== C. the same request, while this build's window has the focus"
fresh
d launch snipper.desktop
await_window
summary
d shot "$OUT/C-window.png" > /dev/null
in_scope python3 tools/gnome/desktop.py portal --timeout 20 > "$OUT/C.json" &
P=$!
watch C 6 Allow
wait "$P"
echo "  portal: $(cat "$OUT/C.json")"
echo "  stored: $(d permissions)"
reap

if [[ -n "$RELEASED" ]]; then
  echo
  echo "=== D. Snipper 0.1.0 from the dash, then Ctrl+Shift+N"
  fresh
  entry "$RELEASED"
  d launch snipper.desktop
  await_window
  summary
  d keys ctrl+shift+n
  watch D 12 Allow
  d shot "$OUT/D-end.png" > /dev/null
  summary
  echo "  stored: $(d permissions)"

  echo
  echo "=== E. Snipper 0.1.0's 'Capture the Whole Screen' from the launcher"
  fresh
  d launch snipper.desktop full
  watch E 12 Allow
  d shot "$OUT/E-end.png" > /dev/null
  summary
  echo "  still running: $(pgrep -f "$RELEASED" > /dev/null && echo yes || echo no)"
  entry "$BUILD"
fi

echo
echo "=== F. this build from the dash, then Ctrl+Shift+N"
fresh
d launch snipper.desktop
await_window
summary
d keys ctrl+shift+n
watch F 12 Allow
d shot "$OUT/F-end.png" > /dev/null
summary
echo "  stored: $(d permissions)"

echo
echo "=== G. this build's 'Capture the Whole Screen', permission stored"
fresh
d grant snipper yes
d launch snipper.desktop full
watch G 12
d shot "$OUT/G-end.png" > /dev/null
summary
reap

echo
echo "=== the portal's account of it"
grep -E "Handle Screenshot|permission|access dialog|Calling Screenshot" "$OUT/portal.log" | tail -40
exit 0
