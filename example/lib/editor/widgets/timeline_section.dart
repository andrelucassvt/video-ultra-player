import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/audio_track_row.dart';
import 'package:video_ultra_player_example/editor/widgets/clip_strip.dart';
import 'package:video_ultra_player_example/editor/widgets/timeline_playhead.dart';
import 'package:video_ultra_player_example/editor/widgets/timeline_ruler.dart';

class TimelineSection extends StatefulWidget {
  const TimelineSection({
    super.key,
    required this.controller,
    required this.state,
  });

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  State<TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<TimelineSection> {
  final ScrollController _scrollController = ScrollController();
  Duration? _dragPosition;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timelineDuration = widget.controller.timelineDuration(widget.state);
    final position = _dragPosition ?? widget.state.globalPosition;

    return Container(
      height: 184,
      decoration: const BoxDecoration(
        color: editorSurface,
        border: Border(top: BorderSide(color: editorLine)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          _TimelineHeader(
            controller: widget.controller,
            state: widget.state,
            position: position,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pixelsPerSecond = widget.controller.pixelsPerSecond;
                final clipDurations = widget.controller.resolvedClipDurations(
                  widget.state,
                );
                // Each clip has a minimum visual width of 76px; clips can exceed
                // contentWidth after splits, which causes Row overflow. Ensure
                // contentWidth covers the clips' total visual width.
                final clipsVisualWidth = clipDurations.isEmpty
                    ? 0.0
                    : clipDurations.fold<double>(
                            0.0,
                            (sum, d) =>
                                sum +
                                math.max(
                                  76.0,
                                  d.inMilliseconds /
                                      Duration.millisecondsPerSecond *
                                      pixelsPerSecond,
                                ),
                          ) +
                          8.0 * (clipDurations.length - 1);
                final contentWidth = math.max(
                  constraints.maxWidth,
                  math.max(
                    timelineDuration.inMilliseconds /
                            Duration.millisecondsPerSecond *
                            pixelsPerSecond +
                        28,
                    clipsVisualWidth,
                  ),
                );
                final playheadX = _positionToPixels(
                  position,
                ).clamp(0.0, contentWidth);

                return SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          width: contentWidth,
                          child: TimelineRuler(
                            duration: timelineDuration,
                            pixelsPerSecond: widget.controller.pixelsPerSecond,
                            width: contentWidth,
                            onSeek: _seekFromRuler,
                          ),
                        ),
                        Positioned(
                          top: 30,
                          left: 0,
                          height: 58,
                          width: contentWidth,
                          child: ClipStrip(
                            controller: widget.controller,
                            state: widget.state,
                            width: contentWidth,
                          ),
                        ),
                        Positioned(
                          top: 98,
                          left: 0,
                          height: 38,
                          width: contentWidth,
                          child: AudioTrackRow(
                            controller: widget.controller,
                            width: contentWidth,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: playheadX - 14,
                          child: TimelinePlayhead(
                            height: 138,
                            onDragStart: _startPlayheadDrag,
                            onDragUpdate: _updatePlayheadDrag,
                            onDragEnd: _endPlayheadDrag,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _seekFromRuler(Duration position) {
    final next = widget.controller.clampTimelinePosition(
      position,
      widget.state,
    );
    setState(() => _dragPosition = next);
    unawaited(
      widget.controller.commitSeek(next, widget.state).whenComplete(() {
        if (mounted) {
          setState(() => _dragPosition = null);
        }
      }),
    );
  }

  void _startPlayheadDrag() {
    setState(() => _dragPosition = widget.state.globalPosition);
  }

  void _updatePlayheadDrag(double deltaPixels) {
    final current = _dragPosition ?? widget.state.globalPosition;
    final delta = Duration(
      milliseconds:
          (deltaPixels /
                  widget.controller.pixelsPerSecond *
                  Duration.millisecondsPerSecond)
              .round(),
    );
    final next = widget.controller.clampTimelinePosition(
      current + delta,
      widget.state,
    );
    setState(() => _dragPosition = next);
    widget.controller.previewSeek(next, widget.state);
  }

  void _endPlayheadDrag() {
    final next = _dragPosition;
    if (next == null) return;
    unawaited(
      widget.controller.commitSeek(next, widget.state).whenComplete(() {
        if (mounted) {
          setState(() => _dragPosition = null);
        }
      }),
    );
  }

  double _positionToPixels(Duration position) {
    return position.inMilliseconds /
        Duration.millisecondsPerSecond *
        widget.controller.pixelsPerSecond;
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.controller,
    required this.state,
    required this.position,
  });

  final EditorController controller;
  final TimelinePlayerState state;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Text(
            _formatDuration(position),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            ' / ${_formatDuration(controller.timelineDuration(state))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.zoom_out, size: 16),
            onPressed: () =>
                controller.setPixelsPerSecond(controller.pixelsPerSecond - 10),
          ),
          SizedBox(
            width: 96,
            child: Slider(
              value: controller.pixelsPerSecond,
              min: controller.minPixelsPerSecond,
              max: controller.maxPixelsPerSecond,
              onChanged: controller.setPixelsPerSecond,
            ),
          ),
          IconButton(
            icon: Icon(Icons.zoom_in, size: 16),
            onPressed: () =>
                controller.setPixelsPerSecond(controller.pixelsPerSecond + 10),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
