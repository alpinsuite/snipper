/// The application version, shown in the About dialog.
///
/// Kept in step with `pubspec.yaml` by `tools/set_version.sh`. Reading it from
/// the pubspec at runtime would mean shipping the pubspec, so it is a constant
/// the release process rewrites instead.
const String appVersion = '0.1.1';
