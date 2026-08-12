import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/src/models/timeline_caption.dart';

void main() {
  group('TimelineCaptionWord', () {
    test('toMap serializes text, startMs and endMs', () {
      final word = TimelineCaptionWord(
        text: 'Olá',
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 400),
      );

      expect(word.toMap(), {
        'text': 'Olá',
        'startMs': 100,
        'endMs': 400,
      });
    });

    test('rejects end <= start with ArgumentError', () {
      expect(
        () => TimelineCaptionWord(
          text: 'x',
          start: const Duration(seconds: 1),
          end: const Duration(milliseconds: 900)),
        throwsArgumentError,
      );
      expect(
        () => TimelineCaptionWord(
          text: 'x',
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 1)),
        throwsArgumentError,
      );
    });
  });

  group('TimelineCaptionCue', () {
    final word = TimelineCaptionWord(
      text: 'Olá',
      start: const Duration(milliseconds: 100),
      end: const Duration(milliseconds: 400),
    );

    test('toMap serializes text, startMs, endMs and the words list', () {
      final cue = TimelineCaptionCue(
        text: 'Olá mundo',
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 3),
        words: [word],
      );

      expect(cue.toMap(), {
        'text': 'Olá mundo',
        'startMs': 1000,
        'endMs': 3000,
        'words': [
          {'text': 'Olá', 'startMs': 100, 'endMs': 400},
        ],
      });
    });

    test('serializes words as an empty list when none are provided', () {
      final cue = TimelineCaptionCue(
        text: 'oi',
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
      );

      final map = cue.toMap();
      expect(map.containsKey('words'), isTrue);
      expect(map['words'], isA<List<dynamic>>());
      expect(map['words'], isEmpty);
    });

    test('rejects end <= start with ArgumentError', () {
      expect(
        () => TimelineCaptionCue(
          text: 'x',
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(
        () => TimelineCaptionCue(
          text: 'x',
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 1)),
        throwsArgumentError,
      );
    });

    test('supports copyWith and value equality', () {
      final cue = TimelineCaptionCue(
        text: 'oi',
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
      );
      final same = TimelineCaptionCue(
        text: 'oi',
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
      );
      final copy = cue.copyWith(text: 'tchau');

      expect(cue, same);
      expect(cue.hashCode, same.hashCode);
      expect(copy.text, 'tchau');
      expect(copy.start, cue.start);
      expect(copy.words, isEmpty);
    });
  });

  group('TimelineCaptionStyle', () {
    test('toMap serializes all style fields', () {
      const style = TimelineCaptionStyle(
        color: 0xFFFFFFFF,
        fontSize: 0.06,
        positionY: 0.9,
        uppercase: true,
        karaoke: true,
        strokeWidth: 2.5,
        backgroundOpacity: 0.5,
        highlightColor: 0xFFFFD700,
      );

      expect(style.toMap(), {
        'color': 0xFFFFFFFF,
        'fontSize': 0.06,
        'positionY': 0.9,
        'uppercase': true,
        'karaoke': true,
        'strokeWidth': 2.5,
        'backgroundOpacity': 0.5,
        'highlightColor': 0xFFFFD700,
      });
    });

    test('applies default values', () {
      const style = TimelineCaptionStyle();

      expect(style.color, 0xFFFFFFFF);
      expect(style.fontSize, 0.055);
      expect(style.positionY, 0.85);
      expect(style.uppercase, isFalse);
      expect(style.karaoke, isFalse);
      expect(style.strokeWidth, 0.0);
      expect(style.backgroundOpacity, 0.0);
      expect(style.highlightColor, 0xFFFFD700);
    });

    test('supports copyWith and value equality', () {
      const style = TimelineCaptionStyle(fontSize: 0.07);
      const same = TimelineCaptionStyle(fontSize: 0.07);
      final copy = style.copyWith(karaoke: true);

      expect(style, same);
      expect(style.hashCode, same.hashCode);
      expect(copy.karaoke, isTrue);
      expect(copy.fontSize, 0.07);
      expect(copy.color, style.color);
    });
  });
}
