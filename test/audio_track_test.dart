import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('AudioTrack.toJson', () {
    test('includes required fields path, offsetMs, volume', () {
      const track = AudioTrack(path: '/music/bg.mp3');
      final json = track.toJson();
      expect(json['path'], '/music/bg.mp3');
      expect(json['offsetMs'], 0);
      expect(json['volume'], 1.0);
    });

    test('omits optional fields when null', () {
      const track = AudioTrack(path: '/music/bg.mp3');
      final json = track.toJson();
      expect(json.containsKey('trimStartMs'), isFalse);
      expect(json.containsKey('trimEndMs'), isFalse);
      expect(json.containsKey('fadeInMs'), isFalse);
      expect(json.containsKey('fadeOutMs'), isFalse);
    });

    test('includes trimStartMs and trimEndMs when set', () {
      const track = AudioTrack(
        path: '/music/bg.mp3',
        trimStart: Duration(milliseconds: 500),
        trimEnd: Duration(seconds: 5),
      );
      final json = track.toJson();
      expect(json['trimStartMs'], 500);
      expect(json['trimEndMs'], 5000);
    });

    test('includes fadeInMs and fadeOutMs when set', () {
      const track = AudioTrack(
        path: '/music/bg.mp3',
        fadeIn: Duration(milliseconds: 300),
        fadeOut: Duration(milliseconds: 600),
      );
      final json = track.toJson();
      expect(json['fadeInMs'], 300);
      expect(json['fadeOutMs'], 600);
    });

    test('encodes non-zero offset correctly', () {
      const track = AudioTrack(
        path: '/music/bg.mp3',
        offset: Duration(seconds: 2),
      );
      expect(track.toJson()['offsetMs'], 2000);
    });

    test('encodes volume correctly', () {
      const track = AudioTrack(path: '/music/bg.mp3', volume: 0.5);
      expect(track.toJson()['volume'], 0.5);
    });
  });

  group('AudioTrack defaults', () {
    test('default offsetMs is 0 (Duration.zero)', () {
      const track = AudioTrack(path: '/music/bg.mp3');
      expect(track.offset, Duration.zero);
      expect(track.toJson()['offsetMs'], 0);
    });

    test('default volume is 1.0', () {
      const track = AudioTrack(path: '/music/bg.mp3');
      expect(track.volume, 1.0);
    });
  });

  group('AudioTrack constructor validation', () {
    test('assert throws when volume < 0.0', () {
      expect(
        // ignore: prefer_const_constructors — must be non-const so assert runs
        () => AudioTrack(path: '/music/bg.mp3', volume: -0.1),
        throwsAssertionError,
      );
    });

    test('assert throws when volume > 1.0', () {
      expect(
        () => AudioTrack(path: '/music/bg.mp3', volume: 1.1),
        throwsAssertionError,
      );
    });

    test('boundary volume 0.0 is accepted', () {
      const track = AudioTrack(path: '/music/bg.mp3', volume: 0.0);
      expect(track.volume, 0.0);
    });

    test('boundary volume 1.0 is accepted', () {
      const track = AudioTrack(path: '/music/bg.mp3', volume: 1.0);
      expect(track.volume, 1.0);
    });
  });

  group('AudioTrack.copyWith', () {
    test('copies with new path', () {
      const original = AudioTrack(path: '/old.mp3');
      final copy = original.copyWith(path: '/new.mp3');
      expect(copy.path, '/new.mp3');
      expect(copy.volume, 1.0);
      expect(copy.offset, Duration.zero);
    });

    test('copies with new offset', () {
      const original = AudioTrack(path: '/music/bg.mp3');
      final copy = original.copyWith(offset: const Duration(seconds: 3));
      expect(copy.offset, const Duration(seconds: 3));
      expect(copy.path, '/music/bg.mp3');
    });

    test('copies with new volume', () {
      const original = AudioTrack(path: '/music/bg.mp3');
      final copy = original.copyWith(volume: 0.75);
      expect(copy.volume, 0.75);
    });

    test('preserves existing values when not specified', () {
      const original = AudioTrack(
        path: '/music/bg.mp3',
        offset: Duration(seconds: 1),
        volume: 0.8,
        trimStart: Duration(milliseconds: 200),
        trimEnd: Duration(seconds: 4),
        fadeIn: Duration(milliseconds: 300),
        fadeOut: Duration(milliseconds: 500),
      );
      final copy = original.copyWith(path: '/other.mp3');
      expect(copy.offset, const Duration(seconds: 1));
      expect(copy.volume, 0.8);
      expect(copy.trimStart, const Duration(milliseconds: 200));
      expect(copy.trimEnd, const Duration(seconds: 4));
      expect(copy.fadeIn, const Duration(milliseconds: 300));
      expect(copy.fadeOut, const Duration(milliseconds: 500));
    });
  });

  group('AudioTrack equality', () {
    test('equal tracks are equal', () {
      const a = AudioTrack(path: '/music/bg.mp3', volume: 0.5);
      const b = AudioTrack(path: '/music/bg.mp3', volume: 0.5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when path differs', () {
      const a = AudioTrack(path: '/a.mp3');
      const b = AudioTrack(path: '/b.mp3');
      expect(a, isNot(b));
    });

    test('not equal when volume differs', () {
      const a = AudioTrack(path: '/a.mp3', volume: 0.5);
      const b = AudioTrack(path: '/a.mp3', volume: 0.8);
      expect(a, isNot(b));
    });
  });
}
