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
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: editorAccent,
                shape: BoxShape.circle,
              ),
            ),
            Positioned(
              top: 9,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: editorAccent,
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
