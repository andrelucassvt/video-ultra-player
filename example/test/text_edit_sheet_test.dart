import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/text_edit_sheet.dart';

import 'test_fakes.dart';

void main() {
  late FakeTimelinePlayer player;
  late EditorController controller;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('text_sheet_test_');
    final file = File('${tempDir.path}/a.mp4');
    await file.writeAsBytes(<int>[1, 2, 3]);
    player = FakeTimelinePlayer();
    controller = EditorController(player: player);
    await controller.replaceTimeline([
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

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: editorTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTextEditSheet(
                context,
                controller,
                const TimelinePlayerState.initial(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sheet renders content field, swatches, sliders and delete button',
    (WidgetTester tester) async {
      await pumpSheet(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Texto'), findsWidgets);
      expect(find.byType(Slider), findsNWidgets(3));
      expect(find.byType(SegmentedButton<TimelineTextAlign>), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('Excluir texto'), findsOneWidget);
    },
  );

  testWidgets('submitting edited content commits the new text', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'Novo conteúdo');
    await tester.ensureVisible(find.text('Concluir'));
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();

    expect(player.calls, contains('updateTextOverlay:text_0'));
    expect(player.overlays.single.text, 'Novo conteúdo');
  });

  testWidgets('delete button removes the overlay', (WidgetTester tester) async {
    await pumpSheet(tester);

    await tester.ensureVisible(find.text('Excluir texto'));
    await tester.tap(find.text('Excluir texto'));
    await tester.pumpAndSettle();

    expect(player.calls, contains('removeTextOverlay:text_0'));
    expect(player.overlays, isEmpty);
    expect(controller.hasSelectedTextOverlay, isFalse);
  });
}
