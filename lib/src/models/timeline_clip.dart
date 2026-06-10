import 'package:flutter/widgets.dart';

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
@immutable
class TimelineClip {
  /// Creates a [TimelineClip].
  ///
  /// [path] must be an absolute file-system path or an asset path resolved
  /// by the caller.  [scale] must be greater than zero.
  const TimelineClip({
    required this.path,
    required this.type,
    this.duration,
    this.alignment = Alignment.center,
    this.scale = 1.0,
  }) : assert(scale > 0, 'scale must be greater than zero');

  /// Absolute path to the media file.
  final String path;

  /// Whether this clip is a [MediaType.video] or [MediaType.image].
  final MediaType type;

  /// How long to display this clip. Required for [MediaType.image] clips;
  /// optional for video (omit to use the full video duration).
  final Duration? duration;

  /// Pan-and-crop anchor within the clip frame. Defaults to [Alignment.center].
  final Alignment alignment;

  /// Uniform scale factor applied to the clip before compositing. Must be > 0.
  final double scale;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': path,
      'type': type.name,
      'durationMs': duration?.inMilliseconds,
      'alignment': <String, double>{'x': alignment.x, 'y': alignment.y},
      'scale': scale,
    };
  }

  TimelineClip copyWith({
    String? path,
    MediaType? type,
    Duration? duration,
    Alignment? alignment,
    double? scale,
  }) {
    return TimelineClip(
      path: path ?? this.path,
      type: type ?? this.type,
      duration: duration ?? this.duration,
      alignment: alignment ?? this.alignment,
      scale: scale ?? this.scale,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineClip &&
        other.path == path &&
        other.type == type &&
        other.duration == duration &&
        other.alignment == alignment &&
        other.scale == scale;
  }

  @override
  int get hashCode {
    return Object.hash(path, type, duration, alignment, scale);
  }
}
