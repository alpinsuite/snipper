#!/usr/bin/env bash
#
# What a real GNOME desktop does when Snipper asks it for the whole screen,
# case by case. Runs inside tools/gnome/session.sh:
#
#   bash tools/gnome/session.sh bash tools/gnome/investigate.sh [binary]
#
# Nothing here passes or fails. Each case prints what the portal answered,
# what the shell put on screen while it was deciding, and what the permission
# store says afterwards; the screenshots and every log land in $GNOME_OUT.

set -uo pipefail
cd "$(dirname "$0")/../.."

BINARY="$PWD/${1:-build/linux/x64/release/bundle/snipper}"
OUT="$GNOME_OUT"
USER_RT="${GNOME_RIG_USER_RUNTIME_DIR:-}"
[[ -n "$USER_RT" ]] || USER_RT="/run/user/$(id -u)"

d() { python3 tools/gnome/desktop.py "$@"; }

echo "=== versions"
dpkg-query -W -f='${Package} ${Version}\n' gnome-shell mutter-common \
  xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
  libglib2.0-0t64 2> /dev/null
echo "=== which backend answers which portal"
for f in /usr/share/xdg-desktop-portal/*.conf /usr/share/xdg-desktop-portal/portals/*.portal; do
  echo "--- $f"
  cat "$f"
done
echo "=== the runner's own systemd, which the launcher's scopes need"
echo "this shell's cgroup: $(cat /proc/self/cgroup)"
env XDG_RUNTIME_DIR="$USER_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RT/bus" \
  systemctl --user is-system-running 2>&1

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
# the desktop agree on who is asking — the shell by process id, the portal by
# unit name.
LAUNCHER="$HOME/snipper-from-the-dash.sh"
cat > "$LAUNCHER" << EOF
#!/bin/bash
exec env XDG_RUNTIME_DIR="$USER_RT" DBUS_SESSION_BUS_ADDRESS="unix:path=$USER_RT/bus" \\
  systemd-run --user --scope --quiet --unit="app-gnome-snipper-\$\$" \\
  env XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \\
  "$BINARY" "\$@" >> "$OUT/snipper-launched.log" 2>&1
EOF
chmod +x "$LAUNCHER"
mkdir -p "$XDG_DATA_HOME/applications"
sed -e "s|^Exec=snipper|Exec=$LAUNCHER|" packaging/snipper.desktop \
  > "$XDG_DATA_HOME/applications/snipper.desktop"
sleep 2

# Stops every Snipper, however it was started.
reap() {
  pkill -f "$BINARY" 2> /dev/null
  sleep 1
  pkill -9 -f "$BINARY" 2> /dev/null
  return 0
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
      echo "  t+${i}s the shell shows: $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["dialog"])' "$state")"
      d shot "$OUT/$name-dialog.png" > /dev/null
      if [[ -n "$press" ]]; then
        echo "  pressed $press: $(d click "$press" 2>&1)"
      fi
    fi
  done
  (( seen )) || echo "  the shell showed no dialog in ${seconds}s"
}

summary() {
  python3 - "$1" << 'EOF'
import json, sys
s = json.loads(sys.argv[1])
print("  focus:", s["focusApp"], "| modal:", s["modalCount"], "| overview:", s["overview"])
for w in s["windows"]:
    print("  window: %r app=%s class=%s focused=%s frame=%s" % (
        w["title"], w["app"], w["wmClass"], w["focused"], w["frame"]))
EOF
}

echo
echo "=== A. a process the portal cannot name asks for the whole screen"
d forget
d portal --timeout 25 > "$OUT/A.json" &
P=$!
watch A 8 Allow
wait "$P"
echo "  portal: $(cat "$OUT/A.json")"
echo "  stored: $(d permissions)"

echo
echo "=== B. the same request, from the scope the dash starts applications in"
d forget
in_scope python3 tools/gnome/desktop.py portal --timeout 25 > "$OUT/B.json" &
P=$!
watch B 8 Allow
wait "$P"
echo "  portal: $(cat "$OUT/B.json")"
echo "  stored: $(d permissions)"

echo
echo "=== C. the launcher's 'Capture the Whole Screen', first time"
d forget
d launch snipper.desktop full
watch C 20 Allow
d shot "$OUT/C-end.png" > /dev/null
summary "$(d state)"
echo "  stored: $(d permissions)"
reap

echo
echo "=== D. Snipper open and focused, full screen from its own window, first time"
d forget
d launch snipper.desktop
for _ in $(seq 1 30); do
  sleep 1
  d state | grep -q '"title": "Snipper"' && break
done
sleep 3
d shot "$OUT/D-window.png" > /dev/null
summary "$(d state)"
d keys ctrl+shift+n
watch D 20 Allow
d shot "$OUT/D-end.png" > /dev/null
summary "$(d state)"
echo "  stored: $(d permissions)"
reap

echo
echo "=== E. the launcher's 'Capture the Whole Screen', permission already stored"
d forget
d grant snipper yes
d launch snipper.desktop full
watch E 15
d shot "$OUT/E-end.png" > /dev/null
summary "$(d state)"
reap

echo
echo "=== F. snipper --full from a terminal, first time"
d forget
"$BINARY" --full >> "$OUT/snipper-F.log" 2>&1 &
watch F 20 Allow
d shot "$OUT/F-end.png" > /dev/null
summary "$(d state)"
echo "  stored: $(d permissions)"
reap

echo
echo "=== G. snipper --full from a terminal, after the user said no"
d forget
d grant "" no
"$BINARY" --full >> "$OUT/snipper-G.log" 2>&1 &
G=$!
watch G 10
d shot "$OUT/G-end.png" > /dev/null
summary "$(d state)"
if kill -0 "$G" 2> /dev/null; then echo "  still running"; else wait "$G"; echo "  exited $?"; fi
reap

echo
echo "=== the portal's own account of it"
grep -iE "access|screenshot|permission|denied|fail|warn" "$OUT/portal.log" | tail -60
echo "=== the shell's"
grep -iE "access|screenshot|portal|error|denied" "$OUT/gnome-shell.log" | tail -40
exit 0
