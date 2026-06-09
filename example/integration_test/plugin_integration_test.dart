import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timeline state map conversion', (WidgetTester tester) async {
    final state = TimelinePlayerState.fromMap({
      'globalPosition': 100,
      'clipIndex': 0,
      'localPosition': 100,
      'isPlaying': false,
      'totalDuration': 5000,
    });

    expect(state.globalPosition, const Duration(milliseconds: 100));
    expect(state.totalDuration, const Duration(milliseconds: 5000));
  });
}
