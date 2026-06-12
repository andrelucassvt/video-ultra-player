import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('EditHistoryState.fromMap', () {
    test('reads canUndo and canRedo flags', () {
      final state = EditHistoryState.fromMap({
        'canUndo': true,
        'canRedo': false,
      });

      expect(state.canUndo, isTrue);
      expect(state.canRedo, isFalse);
    });

    test('defaults missing flags to false', () {
      final state = EditHistoryState.fromMap({});

      expect(state.canUndo, isFalse);
      expect(state.canRedo, isFalse);
    });
  });
}
