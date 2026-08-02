import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/widgets/preview_area.dart';

import 'test_fakes.dart';

void main() {
  late FakeTimelinePlayer player;
  late EditorController controller;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preview_area_test_');
    final file = File('${tempDir.path}/a.mp4');
    await file.writeAsBytes(<int>[1, 2, 3]);
    player = FakeTimelinePlayer();
    controller = EditorController(player: player);
    await controller.replaceTimeline(<TimelineClip>[
      TimelineClip(path: file.path, type: MediaType.video),
    ], source: 'test');
    await controller.addTextOverlay();
  });

  tearDown(() async {
    controller.dispose();
    await player.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpPreview(WidgetTester tester, {required Duration position}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: PreviewArea(
              controller: controller,
              state: TimelinePlayerState(
                globalPosition: position,
                clipIndex: 0,
                localPosition: position,
                isPlaying: false,
                totalDuration: const Duration(seconds: 5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('selectedText_whenIdle_doesNotDuplicateNativeText', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester, position: const Duration(seconds: 1));

    final ghost = tester.widget<Opacity>(
      find.byKey(const ValueKey('text-overlay-drag-visual')),
    );
    expect(ghost.opacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectedText_atEndOfWindow_hidesInteractionGhost', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester, position: const Duration(seconds: 3));

    expect(
      find.byKey(const ValueKey('text-overlay-drag-visual')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectedText_whileDragging_showsGhostUntilNativeCommit', (
    WidgetTester tester,
  ) async {
    await pumpPreview(tester, position: const Duration(seconds: 1));
    final ghostFinder = find.byKey(const ValueKey('text-overlay-drag-visual'));

    final gesture = await tester.startGesture(tester.getCenter(ghostFinder));
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();

    expect(tester.widget<Opacity>(ghostFinder).opacity, 1);

    await gesture.up();
    await tester.pump();

    expect(tester.widget<Opacity>(ghostFinder).opacity, 0);
    expect(player.calls, contains('updateTextOverlay:text_0'));
    expect(tester.takeException(), isNull);
  });
}
