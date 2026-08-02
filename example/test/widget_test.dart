import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_ultra_player_example/main.dart';

void main() {
  testWidgets('renders editor shell controls', (WidgetTester tester) async {
    await tester.pumpWidget(const TimelineEditorApp(autoLoad: false));

    // Top bar
    expect(find.text('Meu vídeo'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);

    // Toolbar: playback, ações, undo/redo, zoom e export
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('00:00 / 00:00'), findsOneWidget);
    expect(find.byIcon(Icons.call_split), findsOneWidget);
    expect(find.byIcon(Icons.speed), findsOneWidget);
    expect(find.byIcon(Icons.timelapse), findsOneWidget);
    expect(find.byIcon(Icons.aspect_ratio), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.redo), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);

    // Preview placeholder
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);

    // Lane headers da timeline
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byIcon(Icons.music_note_outlined), findsOneWidget);
  });

  testWidgets('toolbar actions start disabled without a timeline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TimelineEditorApp(autoLoad: false));

    for (final icon in [
      Icons.call_split,
      Icons.speed,
      Icons.timelapse,
      Icons.aspect_ratio,
      Icons.delete_outline,
      Icons.undo,
      Icons.redo,
    ]) {
      final button = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNull, reason: '$icon should be disabled');
    }
  });
}
