import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/aspect_ratio_sheet.dart';
import 'package:video_ultra_player_example/editor/widgets/speed_sheet.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    required this.state,
  });

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  Widget build(BuildContext context) {
    final hasTimeline = controller.hasTimeline && controller.clips.isNotEmpty;
    final canSplit =
        hasTimeline &&
        state.localPosition > Duration.zero &&
        state.clipIndex >= 0 &&
        state.clipIndex < controller.clips.length;
    final canEditSelected = hasTimeline && controller.hasSelectedClip;
    final canRemove = canEditSelected && controller.clips.length > 1;
    final canUndo = state.canUndo && controller.canUndo;
    final canRedo = state.canRedo && controller.canRedo;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: editorBackground,
        border: Border(bottom: BorderSide(color: editorLine)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _PlayButton(controller: controller, state: state),
            const SizedBox(width: 10),
            Text(
              '${_formatDuration(state.globalPosition)} / '
              '${_formatDuration(controller.timelineDuration(state))}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 18),
            IconButton(
              tooltip: 'Dividir',
              onPressed: canSplit ? () => controller.split(state) : null,
              icon: const Icon(Icons.call_split, size: 20),
            ),
            IconButton(
              tooltip: 'Velocidade',
              onPressed: canEditSelected
                  ? () => showSpeedSheet(context, controller)
                  : null,
              icon: const Icon(Icons.speed, size: 20),
            ),
            IconButton(
              tooltip: 'Proporção',
              onPressed: hasTimeline
                  ? () => showAspectRatioSheet(context, controller)
                  : null,
              icon: const Icon(Icons.aspect_ratio, size: 20),
            ),
            IconButton(
              tooltip: 'Excluir',
              onPressed: canRemove ? controller.removeSelected : null,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
            const SizedBox(width: 18),
            IconButton(
              tooltip: 'Undo',
              onPressed: canUndo ? controller.undo : null,
              icon: const Icon(Icons.undo, size: 20),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: canRedo ? controller.redo : null,
              icon: const Icon(Icons.redo, size: 20),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: () => controller.setPixelsPerSecond(
                controller.pixelsPerSecond - 10,
              ),
              icon: const Icon(Icons.remove, size: 18),
            ),
            SizedBox(
              width: 96,
              child: Slider(
                value: controller.pixelsPerSecond,
                min: controller.minPixelsPerSecond,
                max: controller.maxPixelsPerSecond,
                onChanged: controller.setPixelsPerSecond,
              ),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () => controller.setPixelsPerSecond(
                controller.pixelsPerSecond + 10,
              ),
              icon: const Icon(Icons.add, size: 18),
            ),
            const SizedBox(width: 8),
            _ExportButton(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.controller, required this.state});

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: controller.hasTimeline ? editorAccent : editorLine,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: controller.hasTimeline
            ? () => controller.playOrPause(state)
            : null,
        child: SizedBox.square(
          dimension: 36,
          child: Icon(
            state.isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TimelineExportProgress>(
      stream: controller.exportProgressStream,
      initialData: const TimelineExportProgress.idle(),
      builder: (context, snapshot) {
        final progress = snapshot.data ?? const TimelineExportProgress.idle();
        final percent = (progress.progress * 100).round();
        final enabled =
            !controller.loading &&
            !controller.exporting &&
            controller.hasTimeline;

        return TextButton.icon(
          onPressed: enabled ? controller.export : null,
          icon: controller.exporting
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: editorAccent,
                  ),
                )
              : const Icon(Icons.upload, size: 18),
          label: Text(controller.exporting ? '$percent%' : 'Exportar'),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
