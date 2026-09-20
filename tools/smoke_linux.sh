#!/usr/bin/env bash
#
# Runs the built application on a real X server the way a person would, and
# leaves screenshots behind for a person to look at.
#
#   xvfb-run -a -s "-screen 0 1400x900x24 -noreset" bash tools/smoke_linux.sh
#
# Three things, in order of how much they prove:
#
#   1. It opens. A window maps, at the size asked for, with something drawn in
#      it. Until this existed the Linux build had never been started at all —
#      only its capture channel had, from a test that draws no interface.
#   2. `--full --clipboard` exits 0. That is a whole capture, through the real
#      application on a real X server: the process only exits 0 when an image
#      reached the clipboard.
#   3. `--region` opens the overlay, a dragged rectangle becomes a snip, and
#      the window comes back the size it was. That is the flow the application
#      exists for, and the one place a mistake strands the window frameless and
#      the size of the desktop.
#
# What it cannot do is judge how any of it looks, which is why the screenshots
# are kept.
#
# Needs imagemagick, x11-utils, x11-apps and xdotool.

set -euo pipefail
cd "$(dirname "$0")/.."

BINARY="${1:-build/linux/x64/release/bundle/snipper}"
OUT="${SMOKE_OUT:-build/smoke}"
rm -rf "$OUT"
mkdir -p "$OUT"

# Settings of its own, so every run starts from the defaults and nothing is
# left in the runner's home.
export XDG_DATA_HOME="$PWD/$OUT/xdg-data"
export XDG_CONFIG_HOME="$PWD/$OUT/xdg-config"

# Something on the root window, so a capture of it is not a rectangle of black
# and "the screenshot arrived" can be told from "the screenshot is empty".
xsetroot -solid "#1d5b7a"

APP=""
fail() {
  echo "::error::$1"
  xwd -root -silent | convert xwd:- "$OUT/failure.png" 2> /dev/null || true
  xwininfo -root -tree > "$OUT/windows.txt" 2> /dev/null || true
  echo "--- stderr"; cat "$OUT/stderr.log" 2> /dev/null || true
  [[ -n "$APP" ]] && kill "$APP" 2> /dev/null
  exit 1
}

# The geometry of the application's own window, or empty while it has none.
window() {
  xwininfo -root -tree 2> /dev/null \
    | sed -n 's/.*"Snipper[^"]*": ([^)]*) *\([0-9]*x[0-9]*+[0-9-]*+[0-9-]*\) .*/\1/p' \
    | head -1
}

# Waits for the window to report a size matching $1, a grep pattern.
await_window() {
  local want="$1" seconds="$2" geometry
  for _ in $(seq 1 "$seconds"); do
    sleep 1
    [[ -n "$APP" ]] && ! kill -0 "$APP" 2> /dev/null && return 1
    geometry="$(window)"
    if [[ "$geometry" == $want ]]; then
      echo "$geometry"
      return 0
    fi
  done
  return 1
}

start() {
  "$BINARY" "$@" > "$OUT/stdout.log" 2> "$OUT/stderr.log" &
  APP=$!
}

# Flutter's own way of saying something threw. GTK's chatter about a missing
# accessibility bus or DRI3 in a container is not that, and is left alone.
check_log() {
  if grep -E "Unhandled Exception|EXCEPTION CAUGHT BY|\[ERROR:flutter" "$OUT/stderr.log"; then
    fail "$1"
  fi
}

# --- 1. it opens -------------------------------------------------------------

start
GEOMETRY="$(await_window '1080x720*' 30)" || fail "no window 30 seconds after starting"
echo "window: $GEOMETRY"
sleep 4
xwd -root -silent | convert xwd:- "$OUT/1-window.png"

COLOURS="$(convert "$OUT/1-window.png" -format '%k' info:)"
echo "the screenshot has $COLOURS distinct colours"
(( COLOURS >= 50 )) || fail "the window mapped and drew nothing"
check_log "the application reported an error while starting"

kill "$APP" 2> /dev/null || true
wait "$APP" 2> /dev/null || true
APP=""

# --- 2. a capture from the command line --------------------------------------

# No window is ever shown, and the process exits 0 only once an image is on the
# clipboard. Whether it survives the process needs a clipboard manager, which
# is not this test's business; that it got there is.
start --full --clipboard
STATUS=0
for _ in $(seq 1 40); do
  sleep 1
  if ! kill -0 "$APP" 2> /dev/null; then
    wait "$APP" && STATUS=0 || STATUS=$?
    break
  fi
  STATUS="timeout"
done
[[ "$STATUS" == "0" ]] || fail "snipper --full --clipboard exited $STATUS"
check_log "the command-line capture reported an error"
APP=""
echo "--full --clipboard: captured and exited cleanly"

# --- 3. the region overlay ---------------------------------------------------

start --region
# The overlay is this same window, resized to the whole screen and stripped of
# its frame. It has to get there before anything is dragged over it.
await_window '1400x900*' 40 > /dev/null || fail "the region overlay never covered the screen"
sleep 3
xwd -root -silent | convert xwd:- "$OUT/2-overlay.png"

xdotool mousemove 300 250
xdotool mousedown 1
for x in 420 600 780 900; do
  xdotool mousemove "$x" $(( 250 + (x - 300) / 2 ))
  sleep 0.2
done
xdotool mouseup 1

# The snip opens in the editor, which means the window is given back at the
# size it had. A window left at 1400x900 and frameless is the failure this
# whole flow is written to avoid.
EDITOR="$(await_window '1080x720*' 30)" \
  || fail "the window was not given back after the selection"
sleep 3
xwd -root -silent | convert xwd:- "$OUT/3-editor.png"
xwininfo -root -tree > "$OUT/windows.txt"
check_log "the region capture reported an error"

# The snip is a piece of a desktop that was one flat blue, and the editor is
# now showing it. Looked for in the middle of the window rather than anywhere
# on the screen, because the root is that same blue and is visible around the
# window — a check that passed on the wallpaper would prove nothing.
IFS='x+' read -r W H X Y <<< "$EDITOR"
convert "$OUT/3-editor.png" \
  -crop "300x200+$(( X + W / 2 - 150 ))+$(( Y + H / 2 - 100 ))" +repage \
  "$OUT/4-canvas.png"
BLUE="$(convert "$OUT/4-canvas.png" -fuzz 12% -transparent '#1d5b7a' \
  -format '%[fx:int(100*(1-mean.a))]' info:)"
echo "the middle of the editor is $BLUE% the colour that was captured"
(( BLUE >= 25 )) || fail "the editor is not showing what was captured"

kill "$APP" 2> /dev/null || true
wait "$APP" 2> /dev/null || true
echo "the region flow works, and the window came back"
echo ok
