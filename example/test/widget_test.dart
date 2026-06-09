import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_ultra_player_example/main.dart';

void main() {
  testWidgets('renders timeline demo controls', (WidgetTester tester) async {
    await tester.pumpWidget(const TimelineDemoApp(autoLoad: false));

    expect(find.text('Native Timeline Player'), findsOneWidget);
    expect(find.text('Load timeline'), findsOneWidget);
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
  });
}
