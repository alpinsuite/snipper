// Unsafe mode, and nothing else.
//
// It lets any client on the session bus call org.gnome.Shell.Eval and the
// shell's own screenshot API, which is how tools/gnome/desktop.py reads the
// dialogs the shell draws, presses their buttons, and photographs the screen.
// Never install this on a desktop somebody uses: unsafe mode is exactly as
// unsafe as it sounds.
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class SnipperRig extends Extension {
    enable() {
        global.context.unsafe_mode = true;
    }

    disable() {
        global.context.unsafe_mode = false;
    }
}
