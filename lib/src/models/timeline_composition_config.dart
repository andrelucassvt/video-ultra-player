import 'package:flutter/foundation.dart';

enum OutputAspectRatio { ratio16x9, ratio9x16, ratio1x1, original }

@immutable
class TimelineCompositionConfig {
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

  final OutputAspectRatio aspectRatio;
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
