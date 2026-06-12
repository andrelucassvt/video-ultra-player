import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/editor_screen.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

void main() {
  runApp(const TimelineEditorApp());
}

class TimelineEditorApp extends StatelessWidget {
  const TimelineEditorApp({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: editorTheme,
      home: EditorScreen(autoLoad: autoLoad),
    );
  }
}
