import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('TimelineCompositionConfig', () {
    test('toJson serializes default values', () {
      final config = TimelineCompositionConfig();

      expect(config.toJson(), {
        'aspectRatio': 'original',
        'baseWidth': 1080,
      });
    });

    test('toJson serializes custom values', () {
      final config = TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio9x16,
        baseWidth: 1440,
      );

      expect(config.toJson(), {
        'aspectRatio': 'ratio9x16',
        'baseWidth': 1440,
      });
    });

    test('throws ArgumentError for non-positive baseWidth', () {
      expect(
        () => TimelineCompositionConfig(baseWidth: 0),
        throwsArgumentError,
      );
    });
  });
}
