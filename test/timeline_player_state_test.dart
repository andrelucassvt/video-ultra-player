import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('TimelinePlayerState history flags', () {
    test('fromMap reads canUndo and canRedo', () {
      final state = TimelinePlayerState.fromMap({
        'globalPosition': 0,
        'clipIndex': 0,
        'localPosition': 0,
        'isPlaying': false,
        'totalDuration': 1000,
        'canUndo': true,
        'canRedo': true,
      });

      expect(state.canUndo, isTrue);
      expect(state.canRedo, isTrue);
    });

    test('fromMap defaults missing history flags to false', () {
      final state = TimelinePlayerState.fromMap({
        'globalPosition': 0,
        'clipIndex': 0,
        'localPosition': 0,
        'isPlaying': false,
        'totalDuration': 1000,
      });

      expect(state.canUndo, isFalse);
      expect(state.canRedo, isFalse);
    });

    test('copyWith updates history flags', () {
      final state = const TimelinePlayerState.initial().copyWith(
        canUndo: true,
        canRedo: true,
      );

      expect(state.canUndo, isTrue);
      expect(state.canRedo, isTrue);
    });
  });
}
