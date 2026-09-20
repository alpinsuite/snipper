#!/usr/bin/env python3
"""A stand-in for xdg-desktop-portal's Screenshot interface, for CI.

Snipper's Wayland path is a D-Bus conversation with the desktop, and a CI
container has no desktop. This owns `org.freedesktop.portal.Desktop` on a
private session bus and answers the way the specification says a portal does:

    Screenshot(parent_window: s, options: a{sv}) -> handle: o
    ... later, on that handle:
    org.freedesktop.portal.Request.Response(response: u, results: a{sv})

It is not a screenshot tool. The "screenshot" is a PNG given on the command
line, copied fresh for every request so the test can check that the
application deletes the file it was handed.

Each call gets the next behaviour from SCRIPT below, in order. The integration
test makes its calls in the same order; both sides are written down, and
`integration_test/linux_portal_test.dart` is the other one.

    python3 tools/fake_portal.py <fixture.png> <work-dir>

Every request is appended to <work-dir>/requests.jsonl, which CI reads
afterwards to check what the application actually asked for.

Needs python3-dbus and python3-gi.
"""

import json
import os
import shutil
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.freedesktop.portal.Desktop"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
SCREENSHOT = "org.freedesktop.portal.Screenshot"
REQUEST = "org.freedesktop.portal.Request"

# One entry per call, in the order the test makes them.
SCRIPT = [
    # The ordinary case: the method returns, and the answer follows.
    "ok",
    "ok",
    # The answer arrives *before* the method returns. The specification allows
    # it, which is why a client subscribes first, and it is the ordering that
    # frees memory twice if the client gets it wrong.
    "early",
    # A portal older than 0.9 chooses the request path itself instead of
    # deriving it from the caller's token, so the client has to follow it.
    "legacy-handle",
    # The user closed the desktop's dialog.
    "cancel",
    # The desktop said no.
    "refuse",
    # And after this one, the name is given up: the next call finds no portal
    # on the bus at all, which is a machine without xdg-desktop-portal.
    "ok-then-vanish",
]


class Request(dbus.service.Object):
    """The object a Response is emitted from. One per call."""

    @dbus.service.signal(REQUEST, signature="ua{sv}")
    def Response(self, response, results):  # noqa: N802 - the D-Bus name
        pass


class Portal(dbus.service.Object):
    def __init__(self, bus, name, fixture, work):
        super().__init__(bus, OBJECT_PATH)
        self._bus = bus
        self._name = name
        self._fixture = fixture
        self._work = work
        self._calls = 0
        self._requests = []

    @dbus.service.method(
        SCREENSHOT, in_signature="sa{sv}", out_signature="o", sender_keyword="sender"
    )
    def Screenshot(self, parent_window, options, sender=None):  # noqa: N802
        behaviour = SCRIPT[min(self._calls, len(SCRIPT) - 1)]
        self._calls += 1

        token = str(options.get("handle_token", ""))
        derived = "/org/freedesktop/portal/desktop/request/%s/%s" % (
            sender[1:].replace(".", "_"),
            token,
        )
        handle = derived
        if behaviour == "legacy-handle":
            handle = "/org/freedesktop/portal/desktop/request/legacy/r%d" % self._calls

        with open(os.path.join(self._work, "requests.jsonl"), "a") as log:
            log.write(
                json.dumps(
                    {
                        "call": self._calls,
                        "behaviour": behaviour,
                        "interactive": bool(options.get("interactive", False)),
                        "has_token": bool(token),
                        "handle": handle,
                    }
                )
                + "\n"
            )

        request = Request(self._bus, handle)
        self._requests.append(request)

        def answer():
            if behaviour == "cancel":
                request.Response(dbus.UInt32(1), {})
            elif behaviour == "refuse":
                request.Response(dbus.UInt32(2), {})
            else:
                shot = os.path.join(self._work, "shot-%d.png" % self._calls)
                shutil.copyfile(self._fixture, shot)
                request.Response(
                    dbus.UInt32(0), {"uri": dbus.String("file://" + shot)}
                )
            if behaviour == "ok-then-vanish":
                GLib.timeout_add(200, self._vanish)
            return False

        if behaviour == "early":
            answer()
        else:
            GLib.timeout_add(80, answer)
        return dbus.ObjectPath(handle)

    def _vanish(self):
        self._bus.release_name(BUS_NAME)
        with open(os.path.join(self._work, "vanished"), "w") as marker:
            marker.write("1\n")
        return False


def main():
    fixture, work = sys.argv[1], sys.argv[2]
    os.makedirs(work, exist_ok=True)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(BUS_NAME, bus, do_not_queue=True)
    Portal(bus, name, fixture, work)

    # Tells the caller the name is owned, so it does not start the test early.
    with open(os.path.join(work, "ready"), "w") as marker:
        marker.write("1\n")
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
