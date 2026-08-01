import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

class ClipTrimHandles extends StatefulWidget {
  const ClipTrimHandles({
    super.key,
    required this.controller,
    required this.state,
    required this.clip,
    required this.clipIndex,
    required this.clipStart,
    required this.duration,
    required this.pixelsPerSecond,
    this.onVisualWidthChange,
  });

  final EditorController controller;
  final TimelinePlayerState state;
  final TimelineClip clip;
  final int clipIndex;
  final Duration clipStart;
  final Duration duration;
  final double pixelsPerSecond;
  final void Function(double)? onVisualWidthChange;

  @override
  State<ClipTrimHandles> createState() => _ClipTrimHandlesState();
}

class _ClipTrimHandlesState extends State<ClipTrimHandles> {
  Duration? _draftStart;
  Duration? _draftEnd;

  Duration get _trimStart =>
      _draftStart ?? widget.clip.trimStart ?? Duration.zero;

  Duration get _trimEnd {
    return _draftEnd ??
        widget.clip.trimEnd ??
        ((widget.clip.trimStart ?? Duration.zero) + widget.duration);
  }

  @override
  void didUpdateWidget(covariant ClipTrimHandles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip != widget.clip ||
        oldWidget.duration != widget.duration ||
        oldWidget.clipIndex != widget.clipIndex) {
      _draftStart = null;
      _draftEnd = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final durationLabel = _formatSeconds(_trimEnd - _trimStart);

    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              durationLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ),
        ),
        if (widget.clip.type == MediaType.video) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _TrimHandle(
              icon: Icons.keyboard_arrow_left,
              onPanUpdate: (details) => _updateStart(details.delta.dx),
              onPanEnd: _commit,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _TrimHandle(
              icon: Icons.keyboard_arrow_right,
              onPanUpdate: (details) => _updateEnd(details.delta.dx),
              onPanEnd: _commit,
            ),
          ),
        ],
      ],
    );
  }

  void _notifyVisualWidth() {
    final seconds =
        (_trimEnd - _trimStart).inMilliseconds / Duration.millisecondsPerSecond;
    widget.onVisualWidthChange?.call(
      (seconds * widget.pixelsPerSecond).clamp(0.0, double.maxFinite),
    );
  }

  void _updateStart(double deltaPixels) {
    final delta = _durationFromPixels(deltaPixels);
    final minDuration = const Duration(milliseconds: 300);
    final maxStart = _trimEnd - minDuration;
    final next = _clampDuration(_trimStart + delta, Duration.zero, maxStart);
    setState(() => _draftStart = next);
    _notifyVisualWidth();
    widget.controller.previewSeek(widget.clipStart, widget.state);
  }

  void _updateEnd(double deltaPixels) {
    final delta = _durationFromPixels(deltaPixels);
    final minDuration = const Duration(milliseconds: 300);
    final currentSourceEnd =
        widget.clip.trimEnd ??
        (widget.clip.trimStart ?? Duration.zero) + widget.duration;
    final maxEnd = currentSourceEnd > _trimEnd ? currentSourceEnd : _trimEnd;
    final next = _clampDuration(
      _trimEnd + delta,
      _trimStart + minDuration,
      maxEnd,
    );
    setState(() => _draftEnd = next);
    _notifyVisualWidth();
    widget.controller.previewSeek(
      widget.clipStart + widget.duration,
      widget.state,
    );
  }

  void _commit() {
    widget.controller.trimClip(
      widget.clipIndex,
      trimStart: _trimStart,
      trimEnd: _trimEnd,
    );
  }

  Duration _durationFromPixels(double pixels) {
    return Duration(
      milliseconds: (pixels / widget.pixelsPerSecond * 1000).round(),
    );
  }

  Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({
    required this.icon,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final IconData icon;
  final GestureDragUpdateCallback onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: onPanUpdate,
      onHorizontalDragEnd: (_) => onPanEnd(),
      onHorizontalDragCancel: onPanEnd,
      child: Container(
        width: 24,
        decoration: BoxDecoration(
          color: editorAccent.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

String _formatSeconds(Duration duration) {
  final seconds = duration.inMilliseconds / Duration.millisecondsPerSecond;
  return '${seconds.toStringAsFixed(1)}s';
}
