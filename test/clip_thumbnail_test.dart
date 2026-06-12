import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('ClipThumbnail.fromMap', () {
    test('produces ClipThumbnail with correct path and time', () {
      final thumb = ClipThumbnail.fromMap({'path': '/tmp/a.jpg', 'timeMs': 1000});

      expect(thumb.path, '/tmp/a.jpg');
      expect(thumb.time, const Duration(milliseconds: 1000));
    });

    test('timeMs of zero produces Duration.zero', () {
      final thumb = ClipThumbnail.fromMap({'path': '/tmp/b.jpg', 'timeMs': 0});

      expect(thumb.path, '/tmp/b.jpg');
      expect(thumb.time, Duration.zero);
    });

    test('large timeMs converts correctly', () {
      final thumb = ClipThumbnail.fromMap({'path': '/tmp/c.jpg', 'timeMs': 5500});

      expect(thumb.time, const Duration(milliseconds: 5500));
    });

    test('fromMap with missing path throws', () {
      expect(
        () => ClipThumbnail.fromMap({'timeMs': 1000}),
        throwsA(anyOf(isA<TypeError>(), isA<Error>())),
      );
    });

    test('fromMap with missing timeMs throws', () {
      expect(
        () => ClipThumbnail.fromMap({'path': '/tmp/a.jpg'}),
        throwsA(anyOf(isA<TypeError>(), isA<Error>())),
      );
    });
  });
}
