import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/text_edit_sheet.dart';

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
            return LayoutBuilder(
              builder: (context, stackConstraints) {
                final textGhost = _buildTextGhost(
                  context,
                  stackConstraints.biggest,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      // The clip-alignment drag yields to the text ghost while
                      // a text overlay is selected.
                      onPanUpdate:
                          controller.textureId == null ||
                              controller.hasSelectedTextOverlay
                          ? null
                          : (details) {
                              final renderBox =
                                  textureContext.findRenderObject()
                                      as RenderBox?;
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
                      onTap: controller.hasSelectedTextOverlay
                          ? () => controller.selectTextOverlay(null)
                          : null,
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
                    ),
                    ?textGhost,
                  ],
                );
              },
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

  /// Draggable Flutter "ghost" of the selected text overlay.
  ///
  /// The ghost is a temporary approximation of the native render during the
  /// drag; only the final position is committed to the native compositor
  /// (commit-only, required by Android's immutable effects).
  Widget? _buildTextGhost(BuildContext context, Size size) {
    final overlay = controller.selectedTextOverlay;
    if (overlay == null) return null;

    final fontSize = overlay.fontSize * size.height;
    final foreground = Color(overlay.color);
    final background = overlay.backgroundColor >> 24 > 0
        ? Color(overlay.backgroundColor)
        : null;

    return Positioned(
      left: overlay.x * size.width,
      top: overlay.y * size.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: () => showTextEditSheet(context, controller, state),
          onPanUpdate: (details) {
            final renderBox = context.findRenderObject() as RenderBox?;
            if (renderBox == null || !renderBox.hasSize) {
              return;
            }
            final local = renderBox.globalToLocal(details.globalPosition);
            controller.updateSelectedTextOverlayPosition(
              (local.dx / renderBox.size.width).clamp(0.0, 1.0).toDouble(),
              (local.dy / renderBox.size.height).clamp(0.0, 1.0).toDouble(),
            );
          },
          onPanEnd: (_) => controller.commitSelectedTextOverlayPosition(),
          child: Container(
            decoration: background == null
                ? null
                : BoxDecoration(color: background),
            padding: EdgeInsets.all(fontSize * 0.1),
            child: Text(
              overlay.text,
              textAlign: switch (overlay.textAlign) {
                TimelineTextAlign.left => TextAlign.left,
                TimelineTextAlign.center => TextAlign.center,
                TimelineTextAlign.right => TextAlign.right,
              },
              style: TextStyle(
                color: foreground.withValues(alpha: 0.8),
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
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
        color: editorTextMuted.withValues(alpha: 0.7),
        size: 48,
      ),
    );
  }
}
