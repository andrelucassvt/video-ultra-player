import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

class PreviewArea extends StatelessWidget {
  const PreviewArea({super.key, required this.controller, required this.state});

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = controller.previewAspectRatio;
        Widget preview = Builder(
          builder: (textureContext) {
            return GestureDetector(
              onPanUpdate: controller.textureId == null
                  ? null
                  : (details) {
                      final renderBox =
                          textureContext.findRenderObject() as RenderBox?;
                      if (renderBox == null || !renderBox.hasSize) {
                        return;
                      }

                      final local = renderBox.globalToLocal(
                        details.globalPosition,
                      );
                      final x =
                          ((local.dx / renderBox.size.width) * 2 - 1)
                              .clamp(-1.0, 1.0)
                              .toDouble();
                      final y =
                          ((local.dy / renderBox.size.height) * 2 - 1)
                              .clamp(-1.0, 1.0)
                              .toDouble();
                      controller.setClipAlignment(state.clipIndex, x, y);
                    },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: editorLine),
                ),
                child: ClipRect(
                  child: controller.textureId == null
                      ? _PreviewPlaceholder(loading: controller.loading)
                      : Texture(textureId: controller.textureId!),
                ),
              ),
            );
          },
        );

        if (ratio != null) {
          preview = AspectRatio(aspectRatio: ratio, child: preview);
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth,
              maxHeight: constraints.maxHeight,
            ),
            child: preview,
          ),
        );
      },
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Icon(
        Icons.video_library_outlined,
        color: Colors.white.withValues(alpha: 0.55),
        size: 48,
      ),
    );
  }
}
