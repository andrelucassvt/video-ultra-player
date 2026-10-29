import 'package:flutter/foundation.dart';

/// An immutable snapshot of [NativeTimelinePlayer] playback state.
///
/// Emitted on [NativeTimelinePlayer.stateStream] whenever the native layer
/// reports a position update or a play/pause transition.
@immutable
class TimelinePlayerState {
  /// Creates a fully-specified [TimelinePlayerState].
  const TimelinePlayerState({
    required this.globalPosition,
    required this.clipIndex,
    required this.localPosition,
    required this.isPlaying,
    required this.totalDuration,
    this.clipDurations = const [],
    this.canUndo = false,
    this.canRedo = false,
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  /// A zero-position, paused state suitable as an initial value before [load].
  const TimelinePlayerState.initial()
    : globalPosition = Duration.zero,
      clipIndex = 0,
      localPosition = Duration.zero,
      isPlaying = false,
      totalDuration = Duration.zero,
      clipDurations = const [],
      canUndo = false,
      canRedo = false,
      frameWidth = 0,
      frameHeight = 0;

  /// Elapsed playback time measured from the very start of the timeline.
  final Duration globalPosition;

  /// Zero-based index of the clip currently playing.
  final int clipIndex;

  /// Elapsed playback time within the current clip.
  final Duration localPosition;

  /// Whether the player is currently playing (`true`) or paused (`false`).
  final bool isPlaying;

  /// Combined duration of all clips in the loaded timeline.
  final Duration totalDuration;

  /// Resolved duration of each clip in the current timeline, in order.
  ///
  /// Updated after every mutation (split, insert, remove, etc.). Empty when
  /// the native layer has not yet reported clip boundaries.
  final List<Duration> clipDurations;

  /// Whether the native edit history currently has an undo snapshot.
  final bool canUndo;

  /// Whether the native edit history currently has a redo snapshot.
  final bool canRedo;

  /// Pixel width of the frame the preview texture is showing right now; `0`
  /// until the first frame is drawn.
  ///
  /// It trails [NativeTimelinePlayer.setCompositionConfig]: until the native
  /// side draws a frame at the new size, the texture still holds the previous
  /// one. Lay the texture out with [frameAspectRatio] to keep that frame
  /// undistorted during the switch.
  final int frameWidth;

  /// Pixel height of the frame the preview texture is showing; see
  /// [frameWidth].
  final int frameHeight;

  /// [frameWidth] / [frameHeight], or `null` while no frame was drawn.
  double? get frameAspectRatio =>
      frameWidth > 0 && frameHeight > 0 ? frameWidth / frameHeight : null;

  factory TimelinePlayerState.fromMap(Map<dynamic, dynamic> map) {
    final rawClipDurations = map['clipDurationsMs'];
    final clipDurations = <Duration>[];
    if (rawClipDurations is List) {
      for (final item in rawClipDurations) {
        if (item is num) {
          clipDurations.add(Duration(milliseconds: item.round()));
        }
      }
    }

    return TimelinePlayerState(
      globalPosition: Duration(milliseconds: _readInt(map, 'globalPosition')),
      clipIndex: _readInt(map, 'clipIndex'),
      localPosition: Duration(milliseconds: _readInt(map, 'localPosition')),
      isPlaying: map['isPlaying'] == true,
      totalDuration: Duration(milliseconds: _readInt(map, 'totalDuration')),
      clipDurations: clipDurations,
      canUndo: map['canUndo'] == true,
      canRedo: map['canRedo'] == true,
      frameWidth: _readInt(map, 'frameWidth'),
      frameHeight: _readInt(map, 'frameHeight'),
    );
  }

  TimelinePlayerState copyWith({
    Duration? globalPosition,
    int? clipIndex,
    Duration? localPosition,
    bool? isPlaying,
    Duration? totalDuration,
    List<Duration>? clipDurations,
    bool? canUndo,
    bool? canRedo,
    int? frameWidth,
    int? frameHeight,
  }) {
    return TimelinePlayerState(
      globalPosition: globalPosition ?? this.globalPosition,
      clipIndex: clipIndex ?? this.clipIndex,
      localPosition: localPosition ?? this.localPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      totalDuration: totalDuration ?? this.totalDuration,
      clipDurations: clipDurations ?? this.clipDurations,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
    );
  }

  static int _readInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return 0;
  }

  @override
  bool operator ==(Object other) {
    if (other is! TimelinePlayerState) return false;
    if (other.globalPosition != globalPosition) return false;
    if (other.clipIndex != clipIndex) return false;
    if (other.localPosition != localPosition) return false;
    if (other.isPlaying != isPlaying) return false;
    if (other.totalDuration != totalDuration) return false;
    if (other.canUndo != canUndo) return false;
    if (other.canRedo != canRedo) return false;
    if (other.frameWidth != frameWidth) return false;
    if (other.frameHeight != frameHeight) return false;
    if (other.clipDurations.length != clipDurations.length) return false;
    for (var i = 0; i < clipDurations.length; i++) {
      if (other.clipDurations[i] != clipDurations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    return Object.hash(
      globalPosition,
      clipIndex,
      localPosition,
      isPlaying,
      totalDuration,
      Object.hashAll(clipDurations),
      canUndo,
      canRedo,
      frameWidth,
      frameHeight,
    );
  }
}
