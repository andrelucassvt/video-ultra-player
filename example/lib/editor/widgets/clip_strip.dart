import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/clip_trim_handles.dart';

class ClipStrip extends StatelessWidget {
  const ClipStrip({
    super.key,
    required this.controller,
    required this.state,
    required this.width,
  });

  final EditorController controller;
  final TimelinePlayerState state;
  final double width;

  @override
  Widget build(BuildContext context) {
    final clips = controller.clips;
    if (clips.isEmpty) {
      return SizedBox(width: width, child: const _EmptyClipStrip());
    }

    final durations = controller.resolvedClipDurations(state);
    final children = <Widget>[];

    for (var index = 0; index < clips.length; index++) {
      final clip = clips[index];
      final duration = durations[index];
      final clipWidth = (duration.inMilliseconds /
              Duration.millisecondsPerSecond *
              controller.pixelsPerSecond)
          .clamp(4.0, double.infinity);

      children.add(
        DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) {
            controller.moveClip(details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            final hovering = candidateData.isNotEmpty;
            return Padding(
              padding: EdgeInsets.only(
                right: index == clips.length - 1 ? 0 : 8,
              ),
              child: LongPressDraggable<int>(
                data: index,
                feedback: SizedBox(
                  width: clipWidth,
                  height: 58,
                  child: Material(
                    color: Colors.transparent,
                    child: _ClipTile(
                      controller: controller,
                      state: state,
                      clip: clip,
                      index: index,
                      duration: duration,
                      clipStart: controller.clipStart(index, state),
                      width: clipWidth,
                      selected: true,
                      hovering: false,
                      dragging: true,
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: _ClipTile(
                    controller: controller,
                    state: state,
                    clip: clip,
                    index: index,
                    duration: duration,
                    clipStart: controller.clipStart(index, state),
                    width: clipWidth,
                    selected: index == controller.selectedClipIndex,
                    hovering: hovering,
                    dragging: false,
                  ),
                ),
                child: _ClipTile(
                  controller: controller,
                  state: state,
                  clip: clip,
                  index: index,
                  duration: duration,
                  clipStart: controller.clipStart(index, state),
                  width: clipWidth,
                  selected: index == controller.selectedClipIndex,
                  hovering: hovering,
                  dragging: false,
                ),
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ClipTile extends StatefulWidget {
  const _ClipTile({
    required this.controller,
    required this.state,
    required this.clip,
    required this.index,
    required this.duration,
    required this.clipStart,
    required this.width,
    required this.selected,
    required this.hovering,
    required this.dragging,
  });

  final EditorController controller;
  final TimelinePlayerState state;
  final TimelineClip clip;
  final int index;
  final Duration duration;
  final Duration clipStart;
  final double width;
  final bool selected;
  final bool hovering;
  final bool dragging;

  @override
  State<_ClipTile> createState() => _ClipTileState();
}

class _ClipTileState extends State<_ClipTile> {
  double? _draftWidth;

  void _onVisualWidthChange(double width) {
    setState(() => _draftWidth = width);
  }

  @override
  void didUpdateWidget(covariant _ClipTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration || oldWidget.clip != widget.clip) {
      _draftWidth = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = _draftWidth ?? widget.width;
    final borderColor = widget.hovering
        ? Colors.white
        : widget.selected
        ? editorAccent
        : editorLine;

    return SizedBox(
      width: effectiveWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.controller.selectClip(widget.index),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: editorSurfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: widget.selected ? 2 : 1,
              ),
              boxShadow: widget.dragging
                  ? const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ClipThumbnailRail(
                    controller: widget.controller,
                    clip: widget.clip,
                    index: widget.index,
                    duration: widget.duration,
                    width: effectiveWidth,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.42),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 5,
                    child: Text(
                      '${widget.index + 1}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (widget.selected)
                    ClipTrimHandles(
                      controller: widget.controller,
                      state: widget.state,
                      clip: widget.clip,
                      clipIndex: widget.index,
                      clipStart: widget.clipStart,
                      duration: widget.duration,
                      pixelsPerSecond: widget.controller.pixelsPerSecond,
                      onVisualWidthChange: _onVisualWidthChange,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipThumbnailRail extends StatelessWidget {
  const _ClipThumbnailRail({
    required this.controller,
    required this.clip,
    required this.index,
    required this.duration,
    required this.width,
  });

  final EditorController controller;
  final TimelineClip clip;
  final int index;
  final Duration duration;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (clip.type == MediaType.image) {
      return Image.file(
        File(clip.path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const _ClipFallbackIcon(icon: Icons.image),
      );
    }

    return FutureBuilder<List<String>>(
      future: controller.thumbnailPathsForClip(index, duration, width: 120),
      builder: (context, snapshot) {
        final paths = snapshot.data ?? const <String>[];
        if (paths.isEmpty) {
          return const _ClipFallbackIcon(icon: Icons.movie_creation_outlined);
        }

        final thumbnailWidth = width / paths.length;
        return ClipRect(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final path in paths)
                SizedBox(
                  width: thumbnailWidth,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const _ClipFallbackIcon(icon: Icons.movie_outlined),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ClipFallbackIcon extends StatelessWidget {
  const _ClipFallbackIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: editorSurfaceHigh,
      child: Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.48),
          size: 20,
        ),
      ),
    );
  }
}

class _EmptyClipStrip extends StatelessWidget {
  const _EmptyClipStrip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: editorLine),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          'Load a sample or choose videos',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}
