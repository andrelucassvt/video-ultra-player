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

  /// Uses [TimelineCompositionConfig.customWidth] ×
  /// [TimelineCompositionConfig.customHeight] as the output canvas.
  custom,
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
  ///
  /// With [OutputAspectRatio.custom], [customWidth] and [customHeight] are
  /// required, even and within [minCustomDimension]..[maxCustomDimension];
  /// other aspect ratios ignore them. [frameRate], when set, must be within
  /// 1..[maxFrameRate].
  factory TimelineCompositionConfig({
    OutputAspectRatio aspectRatio = OutputAspectRatio.original,
    int baseWidth = 1080,
    TimelineHdrMode hdrMode = TimelineHdrMode.keepHdr,
    bool preserveSourceQuality = false,
    bool enablePreview = true,
    int? customWidth,
    int? customHeight,
    int? frameRate,
  }) {
    if (baseWidth <= 0) {
      throw ArgumentError.value(baseWidth, 'baseWidth', 'Must be positive.');
    }
    final isCustom = aspectRatio == OutputAspectRatio.custom;
    if (isCustom) {
      _checkCustomDimension(customWidth, 'customWidth');
      _checkCustomDimension(customHeight, 'customHeight');
    }
    if (frameRate != null && (frameRate < 1 || frameRate > maxFrameRate)) {
      throw ArgumentError.value(
        frameRate,
        'frameRate',
        'Must be between 1 and $maxFrameRate.',
      );
    }
    return TimelineCompositionConfig._(
      aspectRatio: aspectRatio,
      baseWidth: baseWidth,
      hdrMode: hdrMode,
      preserveSourceQuality: preserveSourceQuality,
      enablePreview: enablePreview,
      customWidth: isCustom ? customWidth : null,
      customHeight: isCustom ? customHeight : null,
      frameRate: frameRate,
    );
  }

  const TimelineCompositionConfig._({
    required this.aspectRatio,
    required this.baseWidth,
    required this.hdrMode,
    required this.preserveSourceQuality,
    required this.enablePreview,
    required this.customWidth,
    required this.customHeight,
    required this.frameRate,
  });

  /// Smallest accepted [customWidth] / [customHeight].
  static const int minCustomDimension = 16;

  /// Largest accepted [customWidth] / [customHeight].
  static const int maxCustomDimension = 4096;

  /// Largest accepted [frameRate].
  static const int maxFrameRate = 60;

  static void _checkCustomDimension(int? value, String name) {
    if (value == null ||
        value.isOdd ||
        value < minCustomDimension ||
        value > maxCustomDimension) {
      throw ArgumentError.value(
        value,
        name,
        'Must be even and between $minCustomDimension and '
        '$maxCustomDimension.',
      );
    }
  }

  /// The output aspect ratio used by the native compositor.
  final OutputAspectRatio aspectRatio;

  /// Pixel count of the longer side of the canvas for
  /// [OutputAspectRatio.ratio16x9], [OutputAspectRatio.ratio9x16] and
  /// [OutputAspectRatio.ratio1x1]; the other side is derived from
  /// [aspectRatio]. Ignored by [OutputAspectRatio.original] and
  /// [OutputAspectRatio.custom].
  final int baseWidth;

  /// HDR handling requested from the native composition pipeline.
  final TimelineHdrMode hdrMode;

  /// Requests source frame rate and bitrate during re-encoding when supported.
  ///
  /// Burning overlays always requires a new encode, so this is a best-fidelity
  /// policy rather than a promise of byte-identical output.
  final bool preserveSourceQuality;

  /// Whether `load` should create a preview surface/texture and start a
  /// player.
  ///
  /// Headless sessions (`false`) skip texture, surface and player creation on
  /// Android — used when only export or audio extraction of the current
  /// timeline is needed — and `load` returns a synthetic negative id. iOS
  /// accepts the flag but ignores it in this version.
  final bool enablePreview;

  /// Canvas width with [OutputAspectRatio.custom]; `null` otherwise.
  final int? customWidth;

  /// Canvas height with [OutputAspectRatio.custom]; `null` otherwise.
  final int? customHeight;

  /// Target frame rate of the exported MP4, applied **only on export** — the
  /// preview keeps its own rate.
  ///
  /// It is a ceiling: Android only drops frames, so a 30 fps source exported
  /// at 60 stays at 30, while iOS writes a constant rate by repeating frames.
  /// Both look the same. When set it wins over [preserveSourceQuality] for
  /// the frame rate (bitrate is unaffected). `null` keeps each platform's
  /// default.
  final int? frameRate;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'aspectRatio': aspectRatio.name,
      'baseWidth': baseWidth,
      'hdrMode': hdrMode.name,
      'preserveSourceQuality': preserveSourceQuality,
      'enablePreview': enablePreview,
      if (customWidth != null) 'customWidth': customWidth,
      if (customHeight != null) 'customHeight': customHeight,
      if (frameRate != null) 'frameRate': frameRate,
    };
  }

  /// Fields left `null` keep their current value, so [copyWith] cannot clear
  /// [customWidth], [customHeight] or [frameRate]; build a new config instead.
  /// Switching away from [OutputAspectRatio.custom] drops the custom size, so
  /// switching back needs [customWidth] and [customHeight] again.
  TimelineCompositionConfig copyWith({
    OutputAspectRatio? aspectRatio,
    int? baseWidth,
    TimelineHdrMode? hdrMode,
    bool? preserveSourceQuality,
    bool? enablePreview,
    int? customWidth,
    int? customHeight,
    int? frameRate,
  }) {
    return TimelineCompositionConfig(
      aspectRatio: aspectRatio ?? this.aspectRatio,
      baseWidth: baseWidth ?? this.baseWidth,
      hdrMode: hdrMode ?? this.hdrMode,
      preserveSourceQuality:
          preserveSourceQuality ?? this.preserveSourceQuality,
      enablePreview: enablePreview ?? this.enablePreview,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
      frameRate: frameRate ?? this.frameRate,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineCompositionConfig &&
        other.aspectRatio == aspectRatio &&
        other.baseWidth == baseWidth &&
        other.hdrMode == hdrMode &&
        other.preserveSourceQuality == preserveSourceQuality &&
        other.enablePreview == enablePreview &&
        other.customWidth == customWidth &&
        other.customHeight == customHeight &&
        other.frameRate == frameRate;
  }

  @override
  int get hashCode => Object.hash(
    aspectRatio,
    baseWidth,
    hdrMode,
    preserveSourceQuality,
    enablePreview,
    customWidth,
    customHeight,
    frameRate,
  );
}
