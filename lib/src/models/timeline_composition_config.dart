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

/// Strategy used by the native compositor when the input video is HDR.
enum TimelineHdrMode {
  /// Keeps the source dynamic range whenever the platform encoder supports it.
  keepHdr,

  /// Converts HDR inputs to SDR through the platform video decoder.
  ///
  /// On Android this avoids the OpenGL fallback that requires
  /// `GL_EXT_YUV_target`, while SDR inputs are left unchanged.
  toneMapToSdrUsingMediaCodec,
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
    TimelineHdrMode hdrMode = TimelineHdrMode.keepHdr,
    bool preserveSourceQuality = false,
  }) {
    if (baseWidth <= 0) {
      throw ArgumentError.value(baseWidth, 'baseWidth', 'Must be positive.');
    }
    return TimelineCompositionConfig._(
      aspectRatio: aspectRatio,
      baseWidth: baseWidth,
      hdrMode: hdrMode,
      preserveSourceQuality: preserveSourceQuality,
    );
  }

  const TimelineCompositionConfig._({
    required this.aspectRatio,
    required this.baseWidth,
    required this.hdrMode,
    required this.preserveSourceQuality,
  });

  /// The output aspect ratio used by the native compositor.
  final OutputAspectRatio aspectRatio;

  /// Horizontal pixel count of the output canvas. Height is derived from
  /// [aspectRatio].
  final int baseWidth;

  /// HDR handling requested from the native composition pipeline.
  final TimelineHdrMode hdrMode;

  /// Requests source frame rate and bitrate during re-encoding when supported.
  ///
  /// Burning overlays always requires a new encode, so this is a best-fidelity
  /// policy rather than a promise of byte-identical output.
  final bool preserveSourceQuality;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'aspectRatio': aspectRatio.name,
      'baseWidth': baseWidth,
      'hdrMode': hdrMode.name,
      'preserveSourceQuality': preserveSourceQuality,
    };
  }

  TimelineCompositionConfig copyWith({
    OutputAspectRatio? aspectRatio,
    int? baseWidth,
    TimelineHdrMode? hdrMode,
    bool? preserveSourceQuality,
  }) {
    return TimelineCompositionConfig(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      baseWidth: baseWidth ?? this.baseWidth,
      hdrMode: hdrMode ?? this.hdrMode,
      preserveSourceQuality:
          preserveSourceQuality ?? this.preserveSourceQuality,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineCompositionConfig &&
        other.aspectRatio == aspectRatio &&
        other.baseWidth == baseWidth &&
        other.hdrMode == hdrMode &&
        other.preserveSourceQuality == preserveSourceQuality;
  }

  @override
  int get hashCode =>
      Object.hash(aspectRatio, baseWidth, hdrMode, preserveSourceQuality);
}
