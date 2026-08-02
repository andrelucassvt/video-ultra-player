import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

class TimelinePlayhead extends StatelessWidget {
  const TimelinePlayhead({
    super.key,
    required this.height,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double height;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => onDragStart(),
      onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd(),
      onHorizontalDragCancel: onDragEnd,
      child: SizedBox(
        width: 28,
        height: height,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            const Icon(Icons.arrow_drop_down, size: 16, color: editorText),
            Positioned(
              top: 12,
              bottom: 0,
              child: Container(
                width: 1.5,
                decoration: BoxDecoration(
                  color: editorText,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
