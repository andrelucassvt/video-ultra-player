import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/timeline_ruler_painter.dart';

class TimelineRuler extends StatelessWidget {
  const TimelineRuler({
    super.key,
    required this.duration,
    required this.pixelsPerSecond,
    required this.width,
    required this.onSeek,
  });

  final Duration duration;
  final double pixelsPerSecond;
  final double width;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final textStyle =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: editorTextMuted, fontSize: 10) ??
        const TextStyle(fontSize: 10);

    return Semantics(
      label: 'Timeline ruler',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            onSeek(_positionFromDx(details.localPosition.dx)),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(width, 24),
            painter: TimelineRulerPainter(
              duration: duration,
              pixelsPerSecond: pixelsPerSecond,
              textStyle: textStyle,
            ),
          ),
        ),
      ),
    );
  }

  Duration _positionFromDx(double dx) {
    final seconds = dx / pixelsPerSecond;
    return Duration(
      milliseconds: (seconds * Duration.millisecondsPerSecond).round(),
    );
  }
}
