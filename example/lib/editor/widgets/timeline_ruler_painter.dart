import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

final class TimelineRulerPainter extends CustomPainter {
  const TimelineRulerPainter({
    required this.duration,
    required this.pixelsPerSecond,
    required this.textStyle,
  });

  final Duration duration;
  final double pixelsPerSecond;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = editorLine
      ..strokeWidth = 1
      ..isAntiAlias = true;
    final majorTickPaint = Paint()
      ..color = editorTextMuted
      ..strokeWidth = 1
      ..isAntiAlias = true;

    final seconds = duration.inMilliseconds <= 0
        ? 1
        : (duration.inMilliseconds / Duration.millisecondsPerSecond).ceil();
    const labelEvery = 5;

    for (var second = 0; second <= seconds; second++) {
      final x = second * pixelsPerSecond;
      if (x > size.width) break;

      final isMajor = second % labelEvery == 0;
      final tickHeight = isMajor ? 12.0 : 7.0;
      canvas.drawLine(
        Offset(x, size.height - tickHeight),
        Offset(x, size.height),
        isMajor ? majorTickPaint : tickPaint,
      );

      if (!isMajor) continue;
      final textPainter = TextPainter(
        text: TextSpan(text: _formatLabel(second), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x + 4, 0));
    }
  }

  @override
  bool shouldRepaint(TimelineRulerPainter oldDelegate) {
    return oldDelegate.duration != duration ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.textStyle != textStyle;
  }
}

String _formatLabel(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
