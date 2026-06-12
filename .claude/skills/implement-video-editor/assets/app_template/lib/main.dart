import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/media/media_picker_screen.dart';

void main() {
  runApp(const VideoEditorApp());
}

/// Entry point for the timeline editor flow: the user lands on the media
/// picker, selects videos/images, then continues into the editor.
class VideoEditorApp extends StatelessWidget {
  const VideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: editorTheme,
      home: const MediaPickerScreen(),
    );
  }
}
