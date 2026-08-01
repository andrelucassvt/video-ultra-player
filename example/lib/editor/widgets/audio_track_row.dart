import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

class AudioTrackRow extends StatelessWidget {
  const AudioTrackRow({
    super.key,
    required this.controller,
    required this.width,
  });

  final EditorController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final track = controller.audioTrack;
    if (track == null) {
      return SizedBox(
        width: width,
        child: OutlinedButton.icon(
          onPressed: controller.hasTimeline ? controller.addAudioTrack : null,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar audio'),
          style: OutlinedButton.styleFrom(
            foregroundColor: editorTextMuted,
            side: const BorderSide(color: editorLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }

    final left =
        track.offset.inMilliseconds /
        Duration.millisecondsPerSecond *
        controller.pixelsPerSecond;
    final blockWidth = math.max(220.0, width - left);

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned(
            left: left.clamp(0.0, width),
            top: 0,
            bottom: 0,
            width: blockWidth.clamp(0.0, width),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: editorAccent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: editorAccent.withValues(alpha: 0.58)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.graphic_eq, color: editorAccent, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.audioTrackName ?? 'Audio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: editorText),
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Slider(
                      value: track.volume,
                      min: 0,
                      max: 1,
                      onChanged: controller.setAudioVolumePreview,
                      onChangeEnd: controller.commitAudioVolume,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove audio',
                    onPressed: controller.removeAudioTrack,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
