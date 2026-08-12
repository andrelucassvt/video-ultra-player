import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('TimelineCompositionConfig', () {
    test('toJson serializes default values', () {
      final config = TimelineCompositionConfig();

      expect(config.toJson(), {
        'aspectRatio': 'original',
        'baseWidth': 1080,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
      });
    });

    test('toJson serializes custom values', () {
      final config = TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio9x16,
        baseWidth: 1440,
        hdrMode: TimelineHdrMode.toneMapToSdrUsingMediaCodec,
        preserveSourceQuality: true,
        enablePreview: false,
      );

      expect(config.toJson(), {
        'aspectRatio': 'ratio9x16',
        'baseWidth': 1440,
        'hdrMode': 'toneMapToSdrUsingMediaCodec',
        'preserveSourceQuality': true,
        'enablePreview': false,
      });
    });

    test('enablePreview defaults to true', () {
      final config = TimelineCompositionConfig();

      expect(config.enablePreview, isTrue);
    });

    test('throws ArgumentError for non-positive baseWidth', () {
      expect(
        () => TimelineCompositionConfig(baseWidth: 0),
        throwsArgumentError,
      );
    });
  });
}
