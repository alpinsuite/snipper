/// Naming a screenshot.
///
/// A capture has no name of its own — nobody titles a screenshot before taking
/// it — so the tool has to suggest one, and the only information it has is
/// when. A timestamp is what every screenshot tool uses for exactly that
/// reason, and it sorts correctly in a file manager, which a friendlier name
/// would not.
abstract final class SaveNaming {
  /// The stem shown in the save dialog, without an extension.
  ///
  /// Sortable, second-resolution, and free of the characters Windows refuses in
  /// a filename — which rules out the colons an ISO-8601 time would use.
  static String stem(DateTime when) {
    final local = when.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = _two(local.month);
    final day = _two(local.day);
    final hour = _two(local.hour);
    final minute = _two(local.minute);
    final second = _two(local.second);
    return 'Snip $year-$month-$day $hour.$minute.$second';
  }

  /// [stem] with an extension.
  static String fileName(DateTime when, String extension) =>
      '${stem(when)}.$extension';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
