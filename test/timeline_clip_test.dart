import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('TimelineClip trim fields', () {
    test('toJson omits trimStartMs and trimEndMs when null', () {
      const clip = TimelineClip(path: '/a.mp4', type: MediaType.video);
      final json = clip.toJson();
      expect(json.containsKey('trimStartMs'), isFalse);
      expect(json.containsKey('trimEndMs'), isFalse);
    });

    test('toJson serializes trimStart and trimEnd when provided', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 500),
        trimEnd: Duration(seconds: 3),
      );
      final json = clip.toJson();
      expect(json['trimStartMs'], 500);
      expect(json['trimEndMs'], 3000);
    });

    test('accepts null trimStart with non-null trimEnd', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimEnd: Duration(seconds: 5),
      );
      expect(clip.trimEnd, const Duration(seconds: 5));
      expect(clip.trimStart, isNull);
    });

    test('accepts null trimEnd with non-null trimStart', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(seconds: 1),
      );
      expect(clip.trimStart, const Duration(seconds: 1));
      expect(clip.trimEnd, isNull);
    });

    test('accepts both null (full source range)', () {
      const clip = TimelineClip(path: '/a.mp4', type: MediaType.video);
      expect(clip.trimStart, isNull);
      expect(clip.trimEnd, isNull);
    });

    test('trimStartMs is zero for Duration.zero trimStart', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration.zero,
      );
      expect(clip.toJson()['trimStartMs'], 0);
    });
  });

  group('TimelineClip.transitionToNext', () {
    test('toJson omits transitionToNext when null', () {
      const clip = TimelineClip(path: '/a.mp4', type: MediaType.video);
      final json = clip.toJson();
      expect(json.containsKey('transitionToNext'), isFalse);
    });

    test('toJson serializes crossfade transitionToNext', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        transitionToNext: ClipTransition(
          type: TransitionType.crossfade,
          duration: Duration(milliseconds: 500),
        ),
      );
      final json = clip.toJson();
      expect(json['transitionToNext'], <String, dynamic>{
        'type': 'crossfade',
        'durationMs': 500,
      });
    });

    test('toJson serializes none transition', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        transitionToNext: ClipTransition(
          type: TransitionType.none,
          duration: Duration.zero,
        ),
      );
      final json = clip.toJson();
      expect((json['transitionToNext'] as Map)['type'], 'none');
    });

    test('null transitionToNext means hard cut', () {
      const clip = TimelineClip(path: '/a.mp4', type: MediaType.video);
      expect(clip.transitionToNext, isNull);
    });
  });

  group('TimelineClip.copyWith', () {
    test('copies with new trim and transition fields', () {
      const original = TimelineClip(path: '/a.mp4', type: MediaType.video);
      final copy = original.copyWith(
        trimStart: const Duration(milliseconds: 100),
        trimEnd: const Duration(seconds: 4),
        transitionToNext: const ClipTransition(
          type: TransitionType.crossfade,
          duration: Duration(milliseconds: 300),
        ),
      );
      expect(copy.trimStart, const Duration(milliseconds: 100));
      expect(copy.trimEnd, const Duration(seconds: 4));
      expect(copy.transitionToNext?.type, TransitionType.crossfade);
      expect(copy.path, '/a.mp4');
    });

    test('preserves existing values when arguments are null', () {
      const original = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 200),
        trimEnd: Duration(seconds: 5),
      );
      final copy = original.copyWith(scale: 1.5);
      expect(copy.trimStart, const Duration(milliseconds: 200));
      expect(copy.trimEnd, const Duration(seconds: 5));
      expect(copy.scale, 1.5);
    });
  });

  group('TimelineClip equality', () {
    test('equal clips with matching trim and transition', () {
      const a = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 500),
        trimEnd: Duration(seconds: 3),
        transitionToNext: ClipTransition(
          type: TransitionType.crossfade,
          duration: Duration(milliseconds: 300),
        ),
      );
      const b = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 500),
        trimEnd: Duration(seconds: 3),
        transitionToNext: ClipTransition(
          type: TransitionType.crossfade,
          duration: Duration(milliseconds: 300),
        ),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when trimStart differs', () {
      const a = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 100),
      );
      const b = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimStart: Duration(milliseconds: 200),
      );
      expect(a, isNot(b));
    });

    test('not equal when transitionToNext differs', () {
      const a = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        transitionToNext: ClipTransition(
          type: TransitionType.crossfade,
          duration: Duration(milliseconds: 500),
        ),
      );
      const b = TimelineClip(path: '/a.mp4', type: MediaType.video);
      expect(a, isNot(b));
    });

    test('not equal when trimEnd differs', () {
      const a = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimEnd: Duration(seconds: 3),
      );
      const b = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        trimEnd: Duration(seconds: 5),
      );
      expect(a, isNot(b));
    });
  });

  group('TimelineClip existing fields remain compatible', () {
    test('toJson still includes path, type, durationMs, alignment, scale', () {
      const clip = TimelineClip(
        path: '/a.mp4',
        type: MediaType.video,
        duration: Duration(seconds: 2),
        alignment: Alignment.topLeft,
        scale: 1.25,
      );
      final json = clip.toJson();
      expect(json['path'], '/a.mp4');
      expect(json['type'], 'video');
      expect(json['durationMs'], 2000);
      expect(json['alignment'], <String, double>{'x': -1.0, 'y': -1.0});
      expect(json['scale'], 1.25);
    });
  });

  group('ClipTransition equality', () {
    test('equal transitions with same type and duration', () {
      const a = ClipTransition(
        type: TransitionType.crossfade,
        duration: Duration(milliseconds: 500),
      );
      const b = ClipTransition(
        type: TransitionType.crossfade,
        duration: Duration(milliseconds: 500),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when type differs', () {
      const a = ClipTransition(
        type: TransitionType.crossfade,
        duration: Duration(milliseconds: 300),
      );
      const b = ClipTransition(
        type: TransitionType.none,
        duration: Duration(milliseconds: 300),
      );
      expect(a, isNot(b));
    });
  });
}
