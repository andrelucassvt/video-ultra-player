import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('TimelineTextOverlay.toJson', () {
    test('includes all fields with correct channel keys', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hello\nWorld',
        start: Duration(milliseconds: 500),
        end: Duration(seconds: 3),
        x: 0.25,
        y: 0.75,
        rotationDegrees: 15,
        fontSize: 0.08,
        color: 0xFFFF0000,
        fontFamily: 'Avenir',
        fontPath: '/fonts/custom.otf',
        backgroundColor: 0x80000000,
        opacity: 0.5,
        textAlign: TimelineTextAlign.right,
      );
      final json = overlay.toJson();
      expect(json['id'], 'text-1');
      expect(json['text'], 'Hello\nWorld');
      expect(json['startMs'], 500);
      expect(json['endMs'], 3000);
      expect(json['x'], 0.25);
      expect(json['y'], 0.75);
      expect(json['rotationDegrees'], 15);
      expect(json['fontSize'], 0.08);
      expect(json['color'], 0xFFFF0000);
      expect(json['fontFamily'], 'Avenir');
      expect(json['fontPath'], '/fonts/custom.otf');
      expect(json['backgroundColor'], 0x80000000);
      expect(json['opacity'], 0.5);
      expect(json['textAlign'], 'right');
    });

    test('omits fontFamily and fontPath when null', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      final json = overlay.toJson();
      expect(json.containsKey('fontFamily'), isFalse);
      expect(json.containsKey('fontPath'), isFalse);
    });

    test('serializes textAlign as name string', () {
      const overlay = TimelineTextOverlay(
        id: 't',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
        textAlign: TimelineTextAlign.left,
      );
      expect(overlay.toJson()['textAlign'], 'left');
    });
  });

  group('TimelineTextOverlay defaults', () {
    test('default rotationDegrees is 0', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(overlay.rotationDegrees, 0);
      expect(overlay.toJson()['rotationDegrees'], 0);
    });

    test('default color is opaque white', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(overlay.color, 0xFFFFFFFF);
    });

    test('default backgroundColor is transparent', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(overlay.backgroundColor, 0x00000000);
    });

    test('default opacity is 1.0', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(overlay.opacity, 1.0);
      expect(overlay.toJson()['opacity'], 1.0);
    });

    test('default textAlign is center', () {
      const overlay = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(overlay.textAlign, TimelineTextAlign.center);
      expect(overlay.toJson()['textAlign'], 'center');
    });
  });

  group('TimelineTextOverlay constructor validation', () {
    test('assert throws when x < 0', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: -0.1,
          y: 0.5,
          fontSize: 0.1,
        ),
        throwsAssertionError,
      );
    });

    test('assert throws when x > 1', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: 1.1,
          y: 0.5,
          fontSize: 0.1,
        ),
        throwsAssertionError,
      );
    });

    test('assert throws when y outside [0, 1]', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: 0.5,
          y: 1.1,
          fontSize: 0.1,
        ),
        throwsAssertionError,
      );
    });

    test('assert throws when fontSize <= 0', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: 0.5,
          y: 0.5,
          fontSize: 0.0,
        ),
        throwsAssertionError,
      );
    });

    test('assert throws when fontSize > 1', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: 0.5,
          y: 0.5,
          fontSize: 1.1,
        ),
        throwsAssertionError,
      );
    });

    test('assert throws when opacity < 0', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: 0.5,
          y: 0.5,
          fontSize: 0.1,
          opacity: -0.1,
        ),
        throwsAssertionError,
      );
    });

    test('assert throws when opacity > 1', () {
      expect(
        () => TimelineTextOverlay(
          id: 't',
          text: 'Hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
          x: 0.5,
          y: 0.5,
          fontSize: 0.1,
          opacity: 1.1,
        ),
        throwsAssertionError,
      );
    });

    test('boundary x 0.0 and x 1.0 are accepted', () {
      const overlay = TimelineTextOverlay(
        id: 't',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 1.0,
        y: 0.0,
        fontSize: 1.0,
      );
      expect(overlay.x, 1.0);
      expect(overlay.y, 0.0);
      expect(overlay.fontSize, 1.0);
    });

    test('boundary opacity 0.0 and 1.0 are accepted', () {
      const overlay = TimelineTextOverlay(
        id: 't',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
        opacity: 0.0,
      );
      expect(overlay.opacity, 0.0);
    });
  });

  group('TimelineTextOverlay.copyWith', () {
    test('replaces provided fields and preserves others', () {
      const original = TimelineTextOverlay(
        id: 'text-1',
        text: 'Original',
        start: Duration(milliseconds: 500),
        end: Duration(seconds: 3),
        x: 0.25,
        y: 0.75,
        rotationDegrees: 15,
        fontSize: 0.08,
        color: 0xFFFF0000,
        fontFamily: 'Avenir',
        fontPath: '/fonts/custom.otf',
        backgroundColor: 0x80000000,
        opacity: 0.5,
        textAlign: TimelineTextAlign.right,
      );
      final copy = original.copyWith(
        text: 'Updated',
        x: 0.9,
        opacity: 1.0,
        textAlign: TimelineTextAlign.left,
      );
      expect(copy.id, 'text-1');
      expect(copy.text, 'Updated');
      expect(copy.start, const Duration(milliseconds: 500));
      expect(copy.end, const Duration(seconds: 3));
      expect(copy.x, 0.9);
      expect(copy.y, 0.75);
      expect(copy.rotationDegrees, 15);
      expect(copy.fontSize, 0.08);
      expect(copy.color, 0xFFFF0000);
      expect(copy.fontFamily, 'Avenir');
      expect(copy.fontPath, '/fonts/custom.otf');
      expect(copy.backgroundColor, 0x80000000);
      expect(copy.opacity, 1.0);
      expect(copy.textAlign, TimelineTextAlign.left);
    });
  });

  group('TimelineTextOverlay equality', () {
    test('equal overlays are equal', () {
      const a = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      const b = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('not equal when id differs', () {
      const a = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      const b = TimelineTextOverlay(
        id: 'text-2',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(a, isNot(b));
    });

    test('not equal when text differs', () {
      const a = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      const b = TimelineTextOverlay(
        id: 'text-1',
        text: 'Bye',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(a, isNot(b));
    });

    test('not equal when start differs', () {
      const a = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      const b = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration(milliseconds: 100),
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
      );
      expect(a, isNot(b));
    });

    test('not equal when fontFamily differs', () {
      const a = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
        fontFamily: 'Avenir',
      );
      const b = TimelineTextOverlay(
        id: 'text-1',
        text: 'Hi',
        start: Duration.zero,
        end: Duration(seconds: 1),
        x: 0.5,
        y: 0.5,
        fontSize: 0.1,
        fontFamily: 'Helvetica',
      );
      expect(a, isNot(b));
    });
  });
}
