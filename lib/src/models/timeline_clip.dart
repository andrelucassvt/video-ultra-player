import 'package:flutter/widgets.dart';

enum MediaType { video, image }

@immutable
class TimelineClip {
  const TimelineClip({
    required this.path,
    required this.type,
    this.duration,
    this.alignment = Alignment.center,
    this.scale = 1.0,
  }) : assert(scale > 0, 'scale must be greater than zero');

  final String path;
  final MediaType type;
  final Duration? duration;
  final Alignment alignment;
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
