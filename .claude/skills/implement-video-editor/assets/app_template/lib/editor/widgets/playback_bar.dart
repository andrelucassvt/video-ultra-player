import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

class PlaybackBar extends StatelessWidget {
  const PlaybackBar({super.key, required this.controller, required this.state});

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  Widget build(BuildContext context) {
    final canUndo = state.canUndo && controller.canUndo;
    final canRedo = state.canRedo && controller.canRedo;

    return Container(
      height: 44,
      color: editorBackground,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          IconButton(
            tooltip: state.isPlaying ? 'Pause' : 'Play',
            onPressed: controller.hasTimeline
                ? () => controller.playOrPause(state)
                : null,
            icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_formatDuration(state.globalPosition)} / '
              '${_formatDuration(controller.timelineDuration(state))}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: canUndo ? controller.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: canRedo ? controller.redo : null,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
