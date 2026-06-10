import 'package:flutter/widgets.dart';
import 'package:video_ultra_player/src/models/clip_transition.dart';

/// Whether a [TimelineClip] contains a video or a still image.
enum MediaType {
  /// A video file (e.g. MP4, MOV).
  video,

  /// A still image used as a clip (e.g. JPEG, PNG).
  image,
}

/// An immutable description of a single clip within a timeline.
///
/// Pass a list of [TimelineClip]s to [NativeTimelinePlayer.load] or
/// [NativeTimelinePlayer.exportTimeline] to build a composition.
///
/// ## Trim
///
/// [trimStart] and [trimEnd] define a window inside the source file:
/// - [trimStart] is the offset from the beginning of the source (default 0).
/// - [trimEnd] is the absolute end point in the source. When set, it takes
///   precedence over [duration] for video clips.
/// - For [MediaType.image] clips, trim fields are ignored; use [duration].
///
/// ## Transition
///
/// [transitionToNext] describes the effect applied at the boundary between
/// this clip and the next one. `null` means a hard cut.
@immutable
class TimelineClip {
  /// Creates a [TimelineClip].
  ///
  /// [path] must be an absolute file-system path or an asset path resolved
  /// by the caller. [scale] must be greater than zero.
  ///
  /// When both [trimStart] and [trimEnd] are non-null, [trimEnd] must be
  /// greater than [trimStart].
  const TimelineClip({
    required this.path,
    required this.type,
    this.duration,
    this.alignment = Alignment.center,
    this.scale = 1.0,
    this.trimStart,
    this.trimEnd,
    this.transitionToNext,
  }) : assert(scale > 0, 'scale must be greater than zero');

  /// Absolute path to the media file.
  final String path;

  /// Whether this clip is a [MediaType.video] or [MediaType.image].
  final MediaType type;

  /// How long to display this clip. Required for [MediaType.image] clips;
  /// optional for video (omit to use the full video duration).
  ///
  /// For video clips, [trimEnd] takes precedence over [duration] when both
  /// are set.
  final Duration? duration;

  /// Pan-and-crop anchor within the clip frame. Defaults to [Alignment.center].
  final Alignment alignment;

  /// Uniform scale factor applied to the clip before compositing. Must be > 0.
  final double scale;

  /// Offset from the beginning of the source to start playback.
  ///
  /// `null` means start from the beginning of the source.
  /// Ignored for [MediaType.image] clips.
  final Duration? trimStart;

  /// Absolute end point in the source file.
  ///
  /// `null` means play to the end of the source (or use [duration] if set).
  /// When set, takes precedence over [duration] for [MediaType.video] clips.
  /// Ignored for [MediaType.image] clips.
  final Duration? trimEnd;

  /// The transition applied at the boundary between this clip and the next.
  ///
  /// `null` means a hard cut (no transition).
  final ClipTransition? transitionToNext;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': path,
      'type': type.name,
      'durationMs': duration?.inMilliseconds,
      'alignment': <String, double>{'x': alignment.x, 'y': alignment.y},
      'scale': scale,
      if (trimStart != null) 'trimStartMs': trimStart!.inMilliseconds,
      if (trimEnd != null) 'trimEndMs': trimEnd!.inMilliseconds,
      if (transitionToNext != null) 'transitionToNext': transitionToNext!.toJson(),
    };
  }

  TimelineClip copyWith({
    String? path,
    MediaType? type,
    Duration? duration,
    Alignment? alignment,
    double? scale,
    Duration? trimStart,
    Duration? trimEnd,
    ClipTransition? transitionToNext,
  }) {
    return TimelineClip(
      path: path ?? this.path,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      alignment: alignment ?? this.alignment,
      scale: scale ?? this.scale,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      transitionToNext: transitionToNext ?? this.transitionToNext,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineClip &&
        other.path == path &&
        other.type == type &&
        other.duration == duration &&
        other.alignment == alignment &&
        other.scale == scale &&
        other.trimStart == trimStart &&
        other.trimEnd == trimEnd &&
        other.transitionToNext == transitionToNext;
  }

  @override
  int get hashCode {
    return Object.hash(
      path,
      type,
      duration,
      alignment,
      scale,
      trimStart,
      trimEnd,
      transitionToNext,
    );
  }
}
