import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/audio_track_row.dart';
import 'package:video_ultra_player_example/editor/widgets/clip_strip.dart';
import 'package:video_ultra_player_example/editor/widgets/text_track_row.dart';
import 'package:video_ultra_player_example/editor/widgets/timeline_playhead.dart';
import 'package:video_ultra_player_example/editor/widgets/timeline_ruler.dart';

const double _rulerTop = 0;
const double _clipTrackTop = 30;
const double _clipTrackHeight = 58;
const double _textTrackTop = 92;
const double _textTrackHeight = 30;
const double _audioTrackTop = 126;
const double _audioTrackHeight = 34;
const double _tracksHeight = 160;
const double _laneHeaderWidth = 40;

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
      height: _tracksHeight + 18,
      decoration: const BoxDecoration(
        color: editorSurface,
        border: Border(top: BorderSide(color: editorLine)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LaneHeaderColumn(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.max(
                  constraints.maxWidth,
                  timelineDuration.inMilliseconds /
                          Duration.millisecondsPerSecond *
                          widget.controller.pixelsPerSecond +
                      28,
                );
                final playheadX = _positionToPixels(
                  position,
                ).clamp(0.0, contentWidth);

                return SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    height: _tracksHeight,
                    child: Stack(
                      children: [
                        Positioned(
                          top: _rulerTop,
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
                          top: _clipTrackTop,
                          left: 0,
                          height: _clipTrackHeight,
                          width: contentWidth,
                          child: ClipStrip(
                            controller: widget.controller,
                            state: widget.state,
                            width: contentWidth,
                          ),
                        ),
                        Positioned(
                          top: _textTrackTop,
                          left: 0,
                          height: _textTrackHeight,
                          width: contentWidth,
                          child: TextTrackRow(
                            controller: widget.controller,
                            state: widget.state,
                            width: contentWidth,
                          ),
                        ),
                        Positioned(
                          top: _audioTrackTop,
                          left: 0,
                          height: _audioTrackHeight,
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
                            height: _tracksHeight,
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

class _LaneHeaderColumn extends StatelessWidget {
  const _LaneHeaderColumn();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _laneHeaderWidth,
      height: _tracksHeight,
      child: const Stack(
        children: [
          Positioned(
            top: _clipTrackTop,
            left: 0,
            right: 0,
            height: _clipTrackHeight,
            child: Center(
              child: Icon(
                Icons.movie_outlined,
                size: 20,
                color: editorTextMuted,
              ),
            ),
          ),
          Positioned(
            top: _textTrackTop,
            left: 0,
            right: 0,
            height: _textTrackHeight,
            child: Center(
              child: Icon(
                Icons.title,
                size: 20,
                color: editorTextMuted,
              ),
            ),
          ),
          Positioned(
            top: _audioTrackTop,
            left: 0,
            right: 0,
            height: _audioTrackHeight,
            child: Center(
              child: Icon(
                Icons.music_note_outlined,
                size: 20,
                color: editorTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
