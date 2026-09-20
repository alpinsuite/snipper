#!/usr/bin/env bash
#
# Runs the Wayland capture path against tools/fake_portal.py.
#
#   dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24 -noreset" \
#     bash tools/portal_test_linux.sh
#
# The session bus is private to this run, which is what lets the fake own the
# portal's name. SNIPPER_CAPTURE=portal is what sends an X11 process down the
# portal path. See integration_test/linux_portal_test.dart for what is checked
# inside the application; this script checks the two things only the outside
# can see — what the application asked the portal for, and that it cleaned up.
#
# Needs python3-dbus, python3-gi, imagemagick and a Flutter Linux toolchain.

set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'kill "${PORTAL:-}" 2> /dev/null || true' EXIT

# The "screenshot": one flat colour at a size no monitor has, so a test that
# accidentally read the X root instead could not pass.
convert -size 320x200 xc:'#c0392b' "$WORK/fixture.png"

python3 tools/fake_portal.py "$WORK/fixture.png" "$WORK" &
PORTAL=$!
for _ in $(seq 1 50); do
  [[ -f "$WORK/ready" ]] && break
  kill -0 "$PORTAL" 2> /dev/null || { echo "::error::the fake portal did not start"; exit 1; }
  sleep 0.2
done
[[ -f "$WORK/ready" ]] || { echo "::error::the fake portal never took its bus name"; exit 1; }

SNIPPER_CAPTURE=portal GDK_BACKEND=x11 \
  flutter test integration_test/linux_portal_test.dart -d linux

echo "--- what the application asked for"
cat "$WORK/requests.jsonl"

python3 - "$WORK/requests.jsonl" <<'PY'
import json, sys
calls = [json.loads(line) for line in open(sys.argv[1])]
# The eighth call finds no portal, so the fake never sees it.
assert len(calls) == 7, "expected 7 requests, saw %d" % len(calls)
assert all(c["has_token"] for c in calls), "a request went out without a handle_token"
# Whole-screen captures must not open the desktop's interface; regions must.
expected = [False, True, True, True, True, True, False]
got = [c["interactive"] for c in calls]
assert got == expected, "interactive flags: expected %s, got %s" % (expected, got)
print("requests are what they should be")
PY

# The portal writes a file per capture, into the user's Pictures folder on a
# real desktop. The application was handed five and has to have deleted five.
LEFT="$(find "$WORK" -name 'shot-*.png' | wc -l)"
if [[ "$LEFT" != "0" ]]; then
  echo "::error::$LEFT screenshot file(s) were left behind"
  ls -la "$WORK"
  exit 1
fi
[[ -f "$WORK/vanished" ]] || { echo "::error::the fake never left the bus, so the missing-portal case did not run"; exit 1; }
echo "every file the portal wrote was deleted; ok"
