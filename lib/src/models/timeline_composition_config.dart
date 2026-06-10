import 'package:flutter/foundation.dart';

/// The output aspect ratio applied during native composition and export.
enum OutputAspectRatio {
  /// 16:9 landscape (e.g. 1920 × 1080).
  ratio16x9,

  /// 9:16 portrait (e.g. 1080 × 1920).
  ratio9x16,

  /// 1:1 square (e.g. 1080 × 1080).
  ratio1x1,

  /// Preserves the aspect ratio of the first clip in the timeline.
  original,
}

/// Configures the output resolution and aspect ratio of a timeline composition.
///
/// Pass an instance to [NativeTimelinePlayer.load] or
/// [NativeTimelinePlayer.exportTimeline] to control how clips are composed.
/// Defaults to [OutputAspectRatio.original] at 1080 px wide.
@immutable
class TimelineCompositionConfig {
  /// Creates a [TimelineCompositionConfig].
  ///
  /// [baseWidth] must be a positive integer (defaults to 1080).
  factory TimelineCompositionConfig({
    OutputAspectRatio aspectRatio = OutputAspectRatio.original,
    int baseWidth = 1080,
  }) {
    if (baseWidth <= 0) {
      throw ArgumentError.value(baseWidth, 'baseWidth', 'Must be positive.');
    }
    return TimelineCompositionConfig._(
      aspectRatio: aspectRatio,
      baseWidth: baseWidth,
    );
  }

  const TimelineCompositionConfig._({
    required this.aspectRatio,
    required this.baseWidth,
  });

  /// The output aspect ratio used by the native compositor.
  final OutputAspectRatio aspectRatio;

  /// Horizontal pixel count of the output canvas. Height is derived from
  /// [aspectRatio].
  final int baseWidth;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'aspectRatio': aspectRatio.name,
      'baseWidth': baseWidth,
    };
  }

  TimelineCompositionConfig copyWith({
    OutputAspectRatio? aspectRatio,
    int? baseWidth,
  }) {
    return TimelineCompositionConfig(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      baseWidth: baseWidth ?? this.baseWidth,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineCompositionConfig &&
        other.aspectRatio == aspectRatio &&
        other.baseWidth == baseWidth;
  }

  @override
  int get hashCode => Object.hash(aspectRatio, baseWidth);
}
