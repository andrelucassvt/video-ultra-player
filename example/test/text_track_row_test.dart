import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/text_track_row.dart';

import 'test_fakes.dart';

void main() {
  late FakeTimelinePlayer player;
  late EditorController controller;

  setUp(() async {
    player = FakeTimelinePlayer();
    controller = EditorController(player: player);
    await controller.replaceTimeline(
      const [TimelineClip(path: '/tmp/a.mp4', type: MediaType.video)],
      source: 'test',
    );
  });

  tearDown(() async {
    controller.dispose();
    await player.close();
  });

  Future<void> pumpRow(
    WidgetTester tester,
    EditorController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: editorTheme,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 40,
            child: TextTrackRow(
              controller: controller,
              state: const TimelinePlayerState.initial(),
              width: 400,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('empty state shows add button', (WidgetTester tester) async {
    await pumpRow(tester, controller);

    expect(find.text('Adicionar texto'), findsOneWidget);

    await tester.tap(find.text('Adicionar texto'));
    await tester.pumpAndSettle();

    expect(player.calls, contains('addTextOverlay:text_0'));
    expect(controller.textOverlays, hasLength(1));
    expect(controller.hasSelectedTextOverlay, isTrue);
  });

  testWidgets('renders one block per overlay and tap selects it', (
    WidgetTester tester,
  ) async {
    await controller.addTextOverlay();
    await controller.commitTextOverlay(
      controller.textOverlays.single.copyWith(
        text: 'Primeiro',
        start: const Duration(milliseconds: 500),
        end: const Duration(seconds: 3),
      ),
    );
    await controller.addTextOverlay();
    await controller.commitTextOverlay(
      controller.textOverlays.last.copyWith(
        text: 'Segundo',
        start: const Duration(seconds: 4),
        end: const Duration(seconds: 6),
      ),
    );

    await pumpRow(tester, controller);

    expect(find.byType(TextTrackRow), findsOneWidget);
    expect(find.text('Primeiro'), findsOneWidget);
    expect(find.text('Segundo'), findsOneWidget);

    await tester.tap(find.text('Primeiro'));
    await tester.pumpAndSettle();

    expect(controller.selectedTextOverlayId, controller.textOverlays.first.id);
  });
}
