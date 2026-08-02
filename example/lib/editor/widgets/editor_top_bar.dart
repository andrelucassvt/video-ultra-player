import 'package:flutter/material.dart';
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
                  controller.pickMedia();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TimelineSourceAction.sample,
                child: Text('Sample'),
              ),
              PopupMenuItem(
                value: _TimelineSourceAction.gallery,
                child: Text('Galeria'),
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
        ],
      ),
    );
  }
}

enum _TimelineSourceAction { sample, gallery }
