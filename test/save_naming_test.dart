import 'package:flutter_test/flutter_test.dart';
import 'package:snipper/io/save_service.dart';
import 'package:snipper/ops/encode.dart';

void main() {
  group('the suggested name', () {
    test('sorts chronologically as text', () {
      final earlier = SaveNaming.stem(DateTime(2026, 8, 21, 9, 5, 3));
      final later = SaveNaming.stem(DateTime(2026, 8, 21, 11, 5, 3));
      // The whole reason for a timestamp rather than "Snip 1", "Snip 2": a
      // file manager sorting by name has to put them in the order they were
      // taken, which zero-padding is what buys.
      expect(earlier.compareTo(later), lessThan(0));
    });

    test('has no character Windows refuses in a filename', () {
      final name = SaveNaming.fileName(DateTime(2026, 8, 21, 14, 30, 9), 'png');
      // Colons in particular: an ISO-8601 time would be full of them, and
      // Windows would refuse every one of these files.
      expect(name, isNot(contains(':')));
      for (final forbidden in r'\/:*?"<>|'.split('')) {
        expect(name, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('pads every field to a fixed width', () {
      expect(
        SaveNaming.fileName(DateTime(2026, 1, 2, 3, 4, 5), 'png'),
        'Snip 2026-01-02 03.04.05.png',
      );
    });
  });

  group('the format follows the extension', () {
    test('png', () {
      expect(SnipFormat.forPath(r'C:\shots\a.png'), SnipFormat.png);
    });

    test('both spellings of jpeg', () {
      expect(SnipFormat.forPath('/home/a/b.jpg'), SnipFormat.jpeg);
      expect(SnipFormat.forPath('/home/a/b.jpeg'), SnipFormat.jpeg);
    });

    test('case does not matter', () {
      expect(SnipFormat.forPath('/home/a/B.JPG'), SnipFormat.jpeg);
    });

    test('anything unrecognised is a PNG', () {
      // Including no extension at all: a save dialog on Linux will happily
      // return a bare name, and a lossless default is the safe guess for a
      // screenshot.
      expect(SnipFormat.forPath('/home/a/screenshot'), SnipFormat.png);
      expect(SnipFormat.forPath('/home/a/b.tiff'), SnipFormat.png);
    });

    test('a dot in a folder name is not an extension', () {
      expect(SnipFormat.forPath('/home/a.b/c.jpg'), SnipFormat.jpeg);
    });
  });
}
