import 'capture_request.dart';

/// What the command line asked for, if anything.
///
/// This is the whole global-hotkey story on Linux. A client there cannot
/// register a system-wide binding — X11 needs an extra library and Wayland
/// refuses outright — so instead the desktop environment's own shortcut editor
/// is pointed at `snipper --region`, which is what Flameshot tells its users to
/// do and the only arrangement that works under both.
///
/// Parsing is a plain value function so it can be tested without launching
/// anything, which matters more here than usual: a switch that silently does
/// the wrong thing is a screenshot somebody did not get.
class StartupRequest {
  const StartupRequest({
    required this.mode,
    this.copyAndExit = false,
    this.useConfiguredDelay = true,
  });

  final CaptureMode mode;

  /// Take the shot, put it on the clipboard, and quit without ever showing a
  /// window. For binding to a key when the editor is not wanted.
  final bool copyAndExit;

  /// Whether the delay set in the interface applies. A capture asked for from
  /// the command line usually should wait if that is what was configured —
  /// the point of the delay is to get this application out of the way, and it
  /// is just as in the way when launched from a shortcut.
  final bool useConfiguredDelay;

  @override
  String toString() =>
      'StartupRequest(${mode.name}${copyAndExit ? ', copy and exit' : ''})';
}

/// The result of reading the command line.
class StartupOptions {
  const StartupOptions({
    this.request,
    this.showHelp = false,
    this.errors = const <String>[],
  });

  /// The capture to take before showing anything, or null for an ordinary
  /// launch.
  final StartupRequest? request;

  final bool showHelp;

  /// Switches that were not understood. Reported rather than ignored: a
  /// mistyped flag that silently starts the ordinary window looks exactly like
  /// the shortcut not being bound at all.
  final List<String> errors;

  bool get isPlainLaunch => request == null && !showHelp && errors.isEmpty;

  static const String usage = '''
snipper — screen capture and annotation

  snipper                 open the window
  snipper --region        freeze the screen and drag out a region
  snipper --full          capture the whole screen
  snipper --clipboard     with either of the above: copy and quit, no window
  snipper --no-delay      ignore the delay set in the interface
  snipper --help          this

Bind --region to a desktop-environment shortcut to get a global hotkey on
Linux, where an application cannot register one for itself.''';

  /// Reads the switches. Anything that is not a switch is ignored — a file
  /// manager may pass a path, and this application does not open files.
  static StartupOptions parse(List<String> args) {
    CaptureMode? mode;
    var copyAndExit = false;
    var delay = true;
    var help = false;
    final errors = <String>[];

    for (final arg in args) {
      if (!arg.startsWith('-')) continue;
      switch (arg) {
        case '--region':
        case '-r':
          mode = CaptureMode.region;
        case '--full':
        case '--fullscreen':
        case '-f':
          mode = CaptureMode.fullScreen;
        case '--clipboard':
        case '-c':
          copyAndExit = true;
        case '--no-delay':
          delay = false;
        case '--help':
        case '-h':
          help = true;
        default:
          errors.add(arg);
      }
    }

    if (help || errors.isNotEmpty) {
      return StartupOptions(showHelp: true, errors: errors);
    }
    if (mode == null) {
      // --clipboard on its own says what to do with a capture without asking
      // for one. Rather than guess, say so.
      if (copyAndExit) {
        return const StartupOptions(
          showHelp: true,
          errors: <String>['--clipboard needs --region or --full'],
        );
      }
      return const StartupOptions();
    }

    return StartupOptions(
      request: StartupRequest(
        mode: mode,
        copyAndExit: copyAndExit,
        useConfiguredDelay: delay,
      ),
    );
  }
}
