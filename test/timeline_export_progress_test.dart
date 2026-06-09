import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  group('TimelineExportProgress', () {
    test('fromMap converts progress and state', () {
      final progress = TimelineExportProgress.fromMap({
        'progress': 0.42,
        'state': 'exporting',
      });

      expect(progress.progress, 0.42);
      expect(progress.state, TimelineExportState.exporting);
    });

    test('fromMap clamps progress to 0..1', () {
      final below = TimelineExportProgress.fromMap({
        'progress': -0.5,
        'state': 'exporting',
      });
      final above = TimelineExportProgress.fromMap({
        'progress': 1.5,
        'state': 'completed',
      });

      expect(below.progress, 0);
      expect(above.progress, 1);
    });

    test('fromMap maps unknown state to idle', () {
      final progress = TimelineExportProgress.fromMap({
        'progress': 0.5,
        'state': 'unknown',
      });

      expect(progress.state, TimelineExportState.idle);
    });
  });
}
