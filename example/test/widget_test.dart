import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_ultra_player_example/main.dart';

void main() {
  testWidgets('renders editor shell controls', (WidgetTester tester) async {
    await tester.pumpWidget(const TimelineEditorApp(autoLoad: false));

    expect(find.text('Meu vídeo'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Exportar'), findsOneWidget);
    expect(find.text('Dividir'), findsOneWidget);
    expect(find.text('Velocidade'), findsOneWidget);
    expect(find.text('Proporção'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
  });
}
