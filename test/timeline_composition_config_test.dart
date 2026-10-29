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

    test('custom accepts even dimensions and serializes them', () {
      final config = TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.custom,
        customWidth: 1080,
        customHeight: 1350,
      );

      expect(config.toJson(), {
        'aspectRatio': 'custom',
        'baseWidth': 1080,
        'hdrMode': 'keepHdr',
        'preserveSourceQuality': false,
        'enablePreview': true,
        'customWidth': 1080,
        'customHeight': 1350,
      });
    });

    test('custom rejects missing, odd and out-of-range dimensions', () {
      TimelineCompositionConfig custom({int? width, int? height}) =>
          TimelineCompositionConfig(
            aspectRatio: OutputAspectRatio.custom,
            customWidth: width,
            customHeight: height,
          );

      expect(() => custom(), throwsArgumentError);
      expect(() => custom(width: 1080), throwsArgumentError);
      expect(() => custom(height: 1350), throwsArgumentError);
      expect(() => custom(width: 1081, height: 1350), throwsArgumentError);
      expect(() => custom(width: 1080, height: 1351), throwsArgumentError);
      expect(() => custom(width: 14, height: 1350), throwsArgumentError);
      expect(() => custom(width: 1080, height: 4098), throwsArgumentError);
      expect(custom(width: 16, height: 4096).customHeight, 4096);
    });

    test('custom dimensions are ignored by other aspect ratios', () {
      final config = TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.ratio9x16,
        customWidth: 1081,
      );

      expect(config.customWidth, isNull);
      expect(config.toJson().containsKey('customWidth'), isFalse);
    });

    test('frameRate accepts 1 to 60 and is omitted when null', () {
      for (final fps in [1, 30, 60]) {
        expect(TimelineCompositionConfig(frameRate: fps).frameRate, fps);
      }
      for (final fps in [0, 61, -24]) {
        expect(
          () => TimelineCompositionConfig(frameRate: fps),
          throwsArgumentError,
        );
      }
      expect(
        TimelineCompositionConfig().toJson().containsKey('frameRate'),
        isFalse,
      );
      expect(
        TimelineCompositionConfig(frameRate: 24).toJson()['frameRate'],
        24,
      );
    });

    test('copyWith keeps and updates custom size and frameRate', () {
      final config = TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.custom,
        customWidth: 1080,
        customHeight: 1350,
        frameRate: 24,
      );

      final kept = config.copyWith(baseWidth: 720);
      expect(kept.customWidth, 1080);
      expect(kept.customHeight, 1350);
      expect(kept.frameRate, 24);

      final updated = config.copyWith(customHeight: 1920, frameRate: 60);
      expect(updated.customWidth, 1080);
      expect(updated.customHeight, 1920);
      expect(updated.frameRate, 60);
    });

    test('equality distinguishes frameRate and custom size', () {
      final base = TimelineCompositionConfig(
        aspectRatio: OutputAspectRatio.custom,
        customWidth: 1080,
        customHeight: 1350,
        frameRate: 30,
      );

      expect(base, base.copyWith());
      expect(base.hashCode, base.copyWith().hashCode);
      expect(base == base.copyWith(frameRate: 24), isFalse);
      expect(base.hashCode == base.copyWith(frameRate: 24).hashCode, isFalse);
      expect(base == base.copyWith(customHeight: 1352), isFalse);
      expect(
        base.hashCode == base.copyWith(customHeight: 1352).hashCode,
        isFalse,
      );
    });
  });
}
