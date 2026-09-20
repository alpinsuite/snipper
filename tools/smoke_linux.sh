#!/usr/bin/env bash
#
# Runs the built application on a real X server the way a person would, and
# leaves screenshots behind for a person to look at.
#
#   xvfb-run -a -s "-screen 0 1400x900x24 -noreset" bash tools/smoke_linux.sh
#
# Four things, in the order a person meets them:
#
#   1. It opens. A window maps, at the size asked for, with something drawn in
#      it. Until this existed the Linux build had never been started at all —
#      only its capture channel had, from a test that draws no interface.
#   2. Ctrl+N from that window runs the whole region flow: the overlay covers
#      the screen, a dragged rectangle becomes a snip, and the window comes
#      back the size it was with the capture in it. This is what the
#      application is for, and the one place a mistake strands the window
#      frameless and the size of the desktop.
#   3. `--full --clipboard` exits 0. That is a whole capture through the real
#      application: the process only exits 0 when an image reached the
#      clipboard.
#   4. `--region` does the same as 2, but from a cold start with no window ever
#      shown — the shape a desktop shortcut uses.
#
# Every part runs even when an earlier one fails, because which of them fail is
# the useful information; the script fails at the end if any did. What it
# cannot do is judge how any of it looks, which is why the screenshots are kept.
#
# Needs imagemagick, x11-utils, x11-apps, x11-xserver-utils and xdotool.

set -uo pipefail
cd "$(dirname "$0")/.."

BINARY="${1:-build/linux/x64/release/bundle/snipper}"
OUT="${SMOKE_OUT:-build/smoke}"
SCREEN="1400x900"
WINDOW="1080x720"
rm -rf "$OUT"
mkdir -p "$OUT"

# Settings of its own, so every run starts from the defaults and nothing is
# left in the runner's home.
export XDG_DATA_HOME="$PWD/$OUT/xdg-data"
export XDG_CONFIG_HOME="$PWD/$OUT/xdg-config"

# Something on the root window, so a capture of it is not a rectangle of black
# and "the screenshot arrived" can be told from "the screenshot is empty".
ROOT_COLOUR="#1d5b7a"
xsetroot -solid "$ROOT_COLOUR"

APP=""
PROBLEMS=()
note() { echo "::error::$1"; PROBLEMS+=("$1"); }

shot() { xwd -root -silent | convert xwd:- "$OUT/$1.png"; }

stop() {
  [[ -n "$APP" ]] && kill "$APP" 2> /dev/null
  [[ -n "$APP" ]] && wait "$APP" 2> /dev/null
  APP=""
  return 0
}

# start <label> [arguments...]
start() {
  local label="$1"; shift
  LOG="$OUT/stderr-$label.log"
  "$BINARY" "$@" > "$OUT/stdout-$label.log" 2> "$LOG" &
  APP=$!
}

# The geometry of the application's own window, or empty while it has none.
window() {
  xwininfo -root -tree 2> /dev/null \
    | sed -n 's/.*"Snipper[^"]*": ([^)]*) *\([0-9]*x[0-9]*+[0-9-]*+[0-9-]*\) .*/\1/p' \
    | head -1
}

# Waits for the window to report a size matching $1, a glob.
await_window() {
  local want="$1" seconds="$2" geometry
  for _ in $(seq 1 "$seconds"); do
    sleep 1
    if [[ -n "$APP" ]] && ! kill -0 "$APP" 2> /dev/null; then
      echo "" ; return 2
    fi
    geometry="$(window)"
    if [[ "$geometry" == $want ]]; then echo "$geometry"; return 0; fi
  done
  echo ""
  return 1
}

# Flutter's own way of saying something threw. GTK's chatter about a missing
# accessibility bus or DRI3 in a container is not that, and is left alone.
check_log() {
  if grep -qE "Unhandled Exception|EXCEPTION CAUGHT BY|\[ERROR:flutter" "$LOG"; then
    note "$1"
    grep -E "Unhandled Exception|EXCEPTION CAUGHT BY|\[ERROR:flutter" "$LOG" | head -5
  fi
}

# Drags a rectangle across the overlay.
drag() {
  xdotool mousemove 300 250
  xdotool mousedown 1
  local x
  for x in 420 600 780 900; do
    xdotool mousemove "$x" $(( 250 + (x - 300) / 2 ))
    sleep 0.2
  done
  xdotool mouseup 1
}

# The snip is a piece of a desktop that was one flat colour, and the editor is
# showing it. Looked for in the middle of the window rather than anywhere on
# the screen, because the root is that same colour and is visible around the
# window — a check that passed on the wallpaper would prove nothing.
editor_shows_capture() {
  local geometry="$1" name="$2" w h x y blue
  IFS='x+' read -r w h x y <<< "$geometry"
  convert "$OUT/$name.png" \
    -crop "300x200+$(( x + w / 2 - 150 ))+$(( y + h / 2 - 100 ))" +repage \
    "$OUT/$name-canvas.png"
  blue="$(convert "$OUT/$name-canvas.png" -fuzz 12% -transparent "$ROOT_COLOUR" \
    -format '%[fx:int(100*(1-mean.a))]' info:)"
  echo "  the middle of the editor is $blue% the colour that was captured"
  (( blue >= 25 ))
}

# --- 1. it opens -------------------------------------------------------------

echo "=== 1. it opens"
start window
GEOMETRY="$(await_window "$WINDOW*" 30)"
if [[ -z "$GEOMETRY" ]]; then
  note "no window 30 seconds after starting"
  shot 1-failed
else
  echo "  window: $GEOMETRY"
  sleep 4
  shot 1-window
  COLOURS="$(convert "$OUT/1-window.png" -format '%k' info:)"
  echo "  the screenshot has $COLOURS distinct colours"
  (( COLOURS >= 50 )) || note "the window mapped and drew nothing"
  check_log "the application reported an error while starting"
fi

# --- 2. the region flow, from the open window --------------------------------

echo "=== 2. Ctrl+N, drag, back"
if [[ -n "$GEOMETRY" ]]; then
  xdotool key ctrl+n
  if [[ -z "$(await_window "$SCREEN*" 40)" ]]; then
    note "Ctrl+N did not put the overlay over the screen"
    shot 2-failed
  else
    sleep 3
    shot 2-overlay
    drag
    BACK="$(await_window "$WINDOW*" 30)"
    if [[ -z "$BACK" ]]; then
      note "the window was not given back after the selection"
      shot 2-failed
    else
      sleep 3
      shot 2-editor
      editor_shows_capture "$BACK" 2-editor \
        || note "the editor is not showing what was captured"
    fi
  fi
  check_log "the region capture reported an error"
fi
stop

# --- 3. a capture from the command line --------------------------------------

echo "=== 3. --full --clipboard"
# No window is ever shown, and the process exits 0 only once an image is on the
# clipboard. Whether it survives the process needs a clipboard manager, which
# is not this test's business; that it got there is.
start clipboard --full --clipboard
STATUS="timeout"
for _ in $(seq 1 40); do
  sleep 1
  if ! kill -0 "$APP" 2> /dev/null; then
    wait "$APP"; STATUS=$?
    break
  fi
done
APP=""
[[ "$STATUS" == "0" ]] || note "snipper --full --clipboard exited $STATUS"
check_log "the command-line capture reported an error"

# --- 4. the region flow, from a cold start -----------------------------------

echo "=== 4. --region from cold"
start region --region
if [[ -z "$(await_window "$SCREEN*" 40)" ]]; then
  note "--region never put the overlay over the screen"
  shot 4-failed
else
  sleep 3
  shot 4-overlay
  drag
  BACK="$(await_window "$WINDOW*" 30)"
  if [[ -z "$BACK" ]]; then
    note "--region did not give the window back after the selection"
    shot 4-failed
  else
    sleep 3
    shot 4-editor
    editor_shows_capture "$BACK" 4-editor \
      || note "--region: the editor is not showing what was captured"
  fi
fi
check_log "--region reported an error"
xwininfo -root -tree > "$OUT/windows.txt"
stop

# --- what happened -----------------------------------------------------------

echo
if (( ${#PROBLEMS[@]} == 0 )); then
  echo "ok: it opens, captures from the window and from the command line"
  exit 0
fi
echo "${#PROBLEMS[@]} problem(s):"
printf '  %s\n' "${PROBLEMS[@]}"
exit 1
