import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/text_edit_sheet.dart';

class TextTrackRow extends StatelessWidget {
  const TextTrackRow({
    super.key,
    required this.controller,
    required this.state,
    required this.width,
  });

  final EditorController controller;
  final TimelinePlayerState state;
  final double width;

  @override
  Widget build(BuildContext context) {
    final overlays = controller.textOverlays;
    if (overlays.isEmpty) {
      return SizedBox(
        width: width,
        child: OutlinedButton.icon(
          onPressed: controller.hasTimeline ? controller.addTextOverlay : null,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar texto'),
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

    final totalMs = controller.timelineDuration(state).inMilliseconds;
    final pixelsPerMs =
        totalMs > 0 ? controller.pixelsPerSecond / 1000 : 0.0;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          for (final overlay in overlays)
            Positioned(
              left: (overlay.start.inMilliseconds * pixelsPerMs).clamp(
                0.0,
                width,
              ),
              top: 0,
              bottom: 0,
              width: ((overlay.end.inMilliseconds -
                          overlay.start.inMilliseconds) *
                      pixelsPerMs)
                  .clamp(0.0, width),
              child: GestureDetector(
                onTap: () {
                  controller.selectTextOverlay(overlay.id);
                  showTextEditSheet(context, controller, state);
                },
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: editorAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: overlay.id == controller.selectedTextOverlayId
                          ? editorAccent
                          : editorAccent.withValues(alpha: 0.4),
                      width: overlay.id == controller.selectedTextOverlayId
                          ? 2
                          : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.title, color: editorAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          overlay.text.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: editorText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
