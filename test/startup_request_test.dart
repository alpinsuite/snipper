import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/model/capture_request.dart';
import 'package:snipper/model/startup_request.dart';

void main() {
  test('no switches is an ordinary launch', () {
    expect(StartupOptions.parse(const <String>[]).isPlainLaunch, isTrue);
  });

  test('a path is ignored', () {
    // A file manager may hand over a path. This application does not open
    // files, and treating one as an error would make it unlaunchable from
    // there.
    final options = StartupOptions.parse(const <String>['/home/a/b.png']);
    expect(options.isPlainLaunch, isTrue);
  });

  group('capture modes', () {
    test('--region', () {
      expect(
        StartupOptions.parse(const <String>['--region']).request?.mode,
        CaptureMode.region,
      );
      expect(
        StartupOptions.parse(const <String>['-r']).request?.mode,
        CaptureMode.region,
      );
    });

    test('--full, however it is spelled', () {
      for (final flag in const <String>['--full', '--fullscreen', '-f']) {
        expect(
          StartupOptions.parse(<String>[flag]).request?.mode,
          CaptureMode.fullScreen,
          reason: flag,
        );
      }
    });

    test('the last mode named wins', () {
      final options = StartupOptions.parse(const <String>[
        '--region',
        '--full',
      ]);
      expect(options.request?.mode, CaptureMode.fullScreen);
    });
  });

  group('--clipboard', () {
    test('rides along with a mode', () {
      final options = StartupOptions.parse(const <String>[
        '--region',
        '--clipboard',
      ]);
      expect(options.request?.copyAndExit, isTrue);
      expect(options.request?.mode, CaptureMode.region);
    });

    test('on its own says so rather than guessing', () {
      // It says what to do with a capture without asking for one. Starting the
      // ordinary window would look exactly like the shortcut not being bound.
      final options = StartupOptions.parse(const <String>['--clipboard']);
      expect(options.request, isNull);
      expect(options.showHelp, isTrue);
      expect(options.errors, isNotEmpty);
    });
  });

  test('--no-delay turns off the configured wait', () {
    expect(
      StartupOptions.parse(const <String>[
        '--region',
      ]).request?.useConfiguredDelay,
      isTrue,
    );
    expect(
      StartupOptions.parse(const <String>[
        '--region',
        '--no-delay',
      ]).request?.useConfiguredDelay,
      isFalse,
    );
  });

  group('bad input', () {
    test('an unknown switch is reported, not ignored', () {
      // A mistyped flag that silently opens the window is indistinguishable
      // from the shortcut never having fired.
      final options = StartupOptions.parse(const <String>['--regoin']);
      expect(options.errors, <String>['--regoin']);
      expect(options.showHelp, isTrue);
      expect(options.request, isNull);
    });

    test('an unknown switch beats a good one', () {
      final options = StartupOptions.parse(const <String>[
        '--region',
        '--nonsense',
      ]);
      expect(options.request, isNull);
      expect(options.errors, <String>['--nonsense']);
    });

    test('--help asks for help and nothing else', () {
      final options = StartupOptions.parse(const <String>[
        '--region',
        '--help',
      ]);
      expect(options.showHelp, isTrue);
      expect(options.errors, isEmpty);
      expect(options.request, isNull);
    });
  });

  test('the usage text names every switch it accepts', () {
    for (final flag in const <String>[
      '--region',
      '--full',
      '--clipboard',
      '--no-delay',
      '--help',
    ]) {
      expect(StartupOptions.usage, contains(flag), reason: flag);
    }
  });
}
