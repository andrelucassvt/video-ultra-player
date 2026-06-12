import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

class EditorTopBar extends StatelessWidget {
  const EditorTopBar({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Reset',
            onPressed: controller.loading ? null : controller.reset,
            icon: const Icon(Icons.close),
          ),
          const Spacer(),
          PopupMenuButton<_TimelineSourceAction>(
            tooltip: 'Timeline source',
            enabled: !controller.loading && !controller.exporting,
            color: editorSurfaceHigh,
            onSelected: (action) {
              switch (action) {
                case _TimelineSourceAction.sample:
                  controller.loadSample();
                case _TimelineSourceAction.gallery:
                  controller.pickVideos();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TimelineSourceAction.sample,
                child: Text('Sample'),
              ),
              PopupMenuItem(
                value: _TimelineSourceAction.gallery,
                child: Text('Clips'),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 2),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<int>(
            tooltip: 'Resolution',
            enabled: !controller.loading && !controller.exporting,
            color: editorSurfaceHigh,
            onSelected: controller.setBaseWidth,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 720, child: Text('720p')),
              PopupMenuItem(value: 1080, child: Text('1080p')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                controller.resolutionLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          _ExportButton(controller: controller),
        ],
      ),
    );
  }
}

enum _TimelineSourceAction { sample, gallery }

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
        final label = controller.exporting ? '$percent%' : 'Exportar';
        return TextButton.icon(
          onPressed:
              controller.loading ||
                  controller.exporting ||
                  !controller.hasTimeline
              ? null
              : controller.export,
          icon: controller.exporting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: editorAccent,
                  ),
                )
              : const Icon(Icons.upload, size: 18),
          label: Text(label),
        );
      },
    );
  }
}
