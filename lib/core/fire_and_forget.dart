import 'package:flutter/foundation.dart';

/// Starts [future] and does not wait for it, but still reports a failure.
///
/// `dart:async` already has `unawaited`, and it swallows errors completely —
/// which is right for work whose failure genuinely does not matter and wrong
/// for everything in this application. A preference that failed to save or a
/// probe that threw should reach the console rather than disappearing, even
/// though nothing is going to await it.
void fireAndForget(Future<void> future) {
  future.catchError((Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'snipper'),
    );
  });
}
