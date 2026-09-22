#!/usr/bin/env python3
"""Looks at, and presses things in, the desktop tools/gnome/session.sh starts.

Every subcommand is one short conversation over the session bus, so a shell
script can interleave them with the application under test:

    desktop.py ready [--timeout S]      wait until the shell answers Eval
    desktop.py wait-name NAME           wait until NAME is owned on the bus
    desktop.py shot FILE                photograph the whole screen
    desktop.py state                    focus, windows, and any shell dialog
    desktop.py click LABEL              press every visible button so labelled
    desktop.py keys ctrl+shift+n        type a key combination
    desktop.py launch DESKTOP-ID [ACTION]
                                        start an application the way the dash
                                        does, or one of its desktop actions
    desktop.py portal [--interactive] [--timeout S]
                                        ask xdg-desktop-portal for a
                                        screenshot exactly as Snipper does
    desktop.py permissions              the portal's stored screenshot grants
    desktop.py grant APP yes|no         store one, as the dialog would
    desktop.py forget                   store none, as on a fresh install

Looking and pressing go through org.gnome.Shell.Eval, which only answers in
unsafe mode; the rig's extension turns that on. The screenshot portal is asked
through its public interface, never around it: that is the thing under test.

Needs python3-gi.
"""

import argparse
import json
import os
import random
import struct
import sys
import time

from gi.repository import Gio, GLib

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
STORE = "org.freedesktop.impl.portal.PermissionStore"
STORE_PATH = "/org/freedesktop/impl/portal/PermissionStore"
# The table and entry xdg-desktop-portal keeps screenshot grants under. An app
# id of "" is every unsandboxed application it cannot put a name to.
TABLE = "screenshot"
ENTRY = "screenshot"


def bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(dest, path, iface, method, args, reply, timeout_ms=10000):
    return (
        bus()
        .call_sync(
            dest,
            path,
            iface,
            method,
            args,
            GLib.VariantType(reply) if reply else None,
            Gio.DBusCallFlags.NONE,
            timeout_ms,
            None,
        )
        .unpack()
    )


def shell_eval(code):
    ok, result = call(
        "org.gnome.Shell",
        "/org/gnome/Shell",
        "org.gnome.Shell",
        "Eval",
        GLib.Variant("(s)", (code,)),
        "(bs)",
    )
    if not ok:
        raise RuntimeError("the shell refused to evaluate: %s" % (result or "no reason"))
    return json.loads(result) if result else None


# Resolves the namespaces the snippets use from inside Eval, whose scope is the
# shell's D-Bus module and may or may not have imported them.
_PRELUDE = """
const _gi = globalThis.imports?.gi;
const _Shell = typeof Shell !== 'undefined' ? Shell : _gi.Shell;
const _Clutter = typeof Clutter !== 'undefined' ? Clutter : _gi.Clutter;
const _GLib = typeof GLib !== 'undefined' ? GLib : _gi.GLib;
"""


def cmd_ready(args):
    deadline = time.monotonic() + args.timeout
    last = None
    while time.monotonic() < deadline:
        try:
            if shell_eval("global.context.unsafe_mode") is True:
                # The shell opens on the overview when there are no windows,
                # which is not what anyone sees after logging in to Ubuntu.
                shell_eval("Main.overview.hide(); true")
                return 0
        except (GLib.Error, RuntimeError, ValueError) as error:
            last = error
        time.sleep(0.5)
    print("the shell never answered: %s" % last, file=sys.stderr)
    # Which is almost always the rig's extension not running. The shell will
    # say why through an interface that needs no unsafe mode.
    uuid = "snipper-rig@alpinsuite.test"
    for method, reply in (("GetExtensionInfo", "(a{sv})"), ("GetExtensionErrors", "(as)")):
        try:
            (answer,) = call(
                "org.gnome.Shell",
                "/org/gnome/Shell",
                "org.gnome.Shell.Extensions",
                method,
                GLib.Variant("(s)", (uuid,)),
                reply,
            )
            print("%s: %s" % (method, answer), file=sys.stderr)
        except GLib.Error as error:
            print("%s failed: %s" % (method, error.message), file=sys.stderr)
    return 1


def cmd_wait_name(args):
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        (owned,) = call(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            GLib.Variant("(s)", (args.name,)),
            "(b)",
        )
        if owned:
            return 0
        time.sleep(0.2)
    return 1


def cmd_shot(args):
    path = os.path.abspath(args.file)
    ok, used = call(
        "org.gnome.Shell.Screenshot",
        "/org/gnome/Shell/Screenshot",
        "org.gnome.Shell.Screenshot",
        "Screenshot",
        GLib.Variant("(bbs)", (False, False, path)),
        "(bs)",
    )
    if not ok:
        print("the shell took no screenshot", file=sys.stderr)
        return 1
    print(used)
    return 0


STATE_JS = _PRELUDE + """
(() => {
  const tracker = _Shell.WindowTracker.get_default();
  const focus = tracker.focus_app;
  const windows = global.display.list_all_windows().map(w => ({
    title: w.get_title(),
    app: tracker.get_window_app(w)?.get_id() ?? null,
    wmClass: w.get_wm_class(),
    gtkAppId: w.get_gtk_application_id(),
    pid: w.get_pid(),
    focused: w.has_focus(),
    minimized: w.minimized,
    frame: (r => [r.x, r.y, r.width, r.height])(w.get_frame_rect()),
  }));
  const texts = [];
  const walk = actor => {
    if (!actor.visible) return;
    if (typeof actor.text === 'string' && actor.text.trim()) texts.push(actor.text);
    actor.get_children().forEach(walk);
  };
  walk(Main.layoutManager.modalDialogGroup);
  return {
    focusApp: focus ? focus.get_id() : null,
    overview: Main.overview.visible,
    modalCount: Main.modalCount,
    dialog: texts,
    windows,
  };
})()
"""


def cmd_state(args):
    print(json.dumps(shell_eval(STATE_JS)))
    return 0


CLICK_JS = """
((label) => {
  const hits = [];
  const walk = actor => {
    if (!actor.visible) return;
    if (actor.label === label && String(actor).includes('St.Button')) hits.push(actor);
    actor.get_children().forEach(walk);
  };
  walk(global.stage);
  hits.forEach(button => button.emit('clicked', 1));
  return hits.length;
})(%s)
"""


def cmd_click(args):
    pressed = shell_eval(CLICK_JS % json.dumps(args.label))
    print(pressed)
    return 0 if pressed else 1


KEYVALS = {
    "ctrl": 0xFFE3,
    "shift": 0xFFE1,
    "alt": 0xFFE9,
    "super": 0xFFEB,
    "return": 0xFF0D,
    "enter": 0xFF0D,
    "escape": 0xFF1B,
    "tab": 0xFF09,
    "space": 0x20,
}

KEYS_JS = _PRELUDE + """
((keyvals) => {
  const backend = _Clutter.get_default_backend
    ? _Clutter.get_default_backend()
    : global.stage.get_context().get_backend();
  if (!globalThis.__snipperRigKeyboard) {
    globalThis.__snipperRigKeyboard = backend.get_default_seat()
      .create_virtual_device(_Clutter.InputDeviceType.KEYBOARD_DEVICE);
  }
  const keyboard = globalThis.__snipperRigKeyboard;
  const now = () => _GLib.get_monotonic_time();
  keyvals.forEach(k => keyboard.notify_keyval(now(), k, _Clutter.KeyState.PRESSED));
  [...keyvals].reverse().forEach(k =>
    keyboard.notify_keyval(now(), k, _Clutter.KeyState.RELEASED));
  return keyvals.length;
})(%s)
"""


def cmd_keys(args):
    keyvals = []
    for name in args.combo.lower().split("+"):
        if name in KEYVALS:
            keyvals.append(KEYVALS[name])
        elif len(name) == 1:
            keyvals.append(ord(name))
        else:
            print("no keyval for %r" % name, file=sys.stderr)
            return 2
    shell_eval(KEYS_JS % json.dumps(keyvals))
    return 0


LAUNCH_JS = _PRELUDE + """
((id, action) => {
  const app = _Shell.AppSystem.get_default().lookup_app(id);
  if (!app) return false;
  if (action) app.launch_action(action, global.get_current_time(), -1);
  else app.launch(global.get_current_time(), -1, _Shell.AppLaunchGpu.APP_PREF);
  return true;
})(%s, %s)
"""


def cmd_launch(args):
    launched = shell_eval(LAUNCH_JS % (json.dumps(args.id), json.dumps(args.action)))
    if not launched:
        print("the shell knows no application %s" % args.id, file=sys.stderr)
        return 1
    return 0


def png_size(path):
    with open(path, "rb") as png:
        head = png.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def cmd_portal(args):
    """The request capture_channel.cc makes, made the same way."""
    connection = bus()
    sender = connection.get_unique_name()[1:].replace(".", "_")
    token = "rig%d" % random.randint(0, 2**31)
    handle = "%s/request/%s/%s" % (PORTAL_PATH, sender, token)
    loop = GLib.MainLoop()
    started = time.monotonic()
    outcome = {"interactive": args.interactive}
    subscription = []

    def elapsed():
        return round(time.monotonic() - started, 2)

    def on_response(_conn, _sender, _path, _iface, _signal, params):
        code, results = params.unpack()
        outcome["response"] = code
        outcome["answered_after"] = elapsed()
        outcome["results"] = {k: str(v) for k, v in results.items()}
        loop.quit()

    def subscribe(path):
        for sub in subscription:
            connection.signal_unsubscribe(sub)
        subscription[:] = [
            connection.signal_subscribe(
                PORTAL,
                "org.freedesktop.portal.Request",
                "Response",
                path,
                None,
                Gio.DBusSignalFlags.NONE,
                on_response,
            )
        ]

    def on_return(conn, result):
        try:
            (path,) = conn.call_finish(result).unpack()
        except GLib.Error as error:
            outcome["error"] = error.message
            loop.quit()
            return
        outcome["returned_after"] = elapsed()
        outcome["handle_matches_token"] = path == handle
        if path != handle:
            subscribe(path)

    def on_timeout():
        outcome.setdefault("response", "none")
        outcome["gave_up_after"] = elapsed()
        loop.quit()
        return False

    subscribe(handle)
    options = {
        "handle_token": GLib.Variant("s", token),
        "interactive": GLib.Variant("b", args.interactive),
    }
    connection.call(
        PORTAL,
        PORTAL_PATH,
        "org.freedesktop.portal.Screenshot",
        "Screenshot",
        GLib.Variant("(sa{sv})", ("", options)),
        GLib.VariantType("(o)"),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
        on_return,
    )
    GLib.timeout_add(int(args.timeout * 1000), on_timeout)
    loop.run()

    uri = outcome.get("results", {}).get("uri")
    if uri:
        path = Gio.File.new_for_uri(uri).get_path()
        outcome["file"] = path
        if path and os.path.exists(path):
            outcome["size"] = png_size(path)
            if args.keep:
                os.replace(path, args.keep)
                outcome["kept"] = args.keep
            else:
                os.remove(path)
    print(json.dumps(outcome))
    return 0 if outcome.get("response") == 0 else 1


def cmd_permissions(args):
    try:
        entries, _data = call(
            STORE, STORE_PATH, STORE, "Lookup", GLib.Variant("(ss)", (TABLE, ENTRY)), "(a{sas}v)"
        )
    except GLib.Error as error:
        # No table yet is the ordinary state of a fresh install.
        entries = {"error": error.message}
    print(json.dumps(entries))
    return 0


def cmd_grant(args):
    call(
        STORE,
        STORE_PATH,
        STORE,
        "SetPermission",
        GLib.Variant("(sbssas)", (TABLE, True, ENTRY, args.app, [args.value])),
        None,
    )
    return 0


def cmd_forget(args):
    try:
        call(STORE, STORE_PATH, STORE, "Delete", GLib.Variant("(ss)", (TABLE, ENTRY)), None)
    except GLib.Error:
        pass  # nothing stored is what was asked for
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("ready")
    p.add_argument("--timeout", type=float, default=60)
    p.set_defaults(run=cmd_ready)

    p = sub.add_parser("wait-name")
    p.add_argument("name")
    p.add_argument("--timeout", type=float, default=30)
    p.set_defaults(run=cmd_wait_name)

    p = sub.add_parser("shot")
    p.add_argument("file")
    p.set_defaults(run=cmd_shot)

    p = sub.add_parser("state")
    p.set_defaults(run=cmd_state)

    p = sub.add_parser("click")
    p.add_argument("label")
    p.set_defaults(run=cmd_click)

    p = sub.add_parser("keys")
    p.add_argument("combo")
    p.set_defaults(run=cmd_keys)

    p = sub.add_parser("launch")
    p.add_argument("id")
    p.add_argument("action", nargs="?", default=None)
    p.set_defaults(run=cmd_launch)

    p = sub.add_parser("portal")
    p.add_argument("--interactive", action="store_true")
    p.add_argument("--timeout", type=float, default=30)
    p.add_argument("--keep", help="move the portal's file here instead of deleting it")
    p.set_defaults(run=cmd_portal)

    p = sub.add_parser("permissions")
    p.set_defaults(run=cmd_permissions)

    p = sub.add_parser("grant")
    p.add_argument("app")
    p.add_argument("value", choices=["yes", "no"])
    p.set_defaults(run=cmd_grant)

    p = sub.add_parser("forget")
    p.set_defaults(run=cmd_forget)

    args = parser.parse_args()
    try:
        return args.run(args)
    except (GLib.Error, RuntimeError) as error:
        print("%s: %s" % (args.command, error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
