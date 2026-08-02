import 'package:flutter/foundation.dart';

/// An immutable descriptor for an external audio track overlaid on the timeline.
///
/// [path] is the absolute file-system path to the audio file.
/// [offset] controls where in the timeline the audio starts playing.
/// [volume] is the amplitude multiplier in `[0.0, 1.0]`.
/// [trimStart] and [trimEnd] define a sub-range within the source audio file
/// (end timestamp, not duration — mirrors [TimelineClip] trim semantics).
/// [fadeIn] and [fadeOut] set the ramp durations at the beginning and end.
@immutable
class AudioTrack {
  /// Creates an [AudioTrack].
  ///
  /// [volume] must be in the range `[0.0, 1.0]`.
  const AudioTrack({
    required this.path,
    this.offset = Duration.zero,
    this.volume = 1.0,
    this.trimStart,
    this.trimEnd,
    this.fadeIn,
    this.fadeOut,
  }) : assert(volume >= 0.0 && volume <= 1.0);

  /// Absolute path to the audio file.
  final String path;

  /// Position in the timeline where the audio track starts. Default is the
  /// very beginning of the timeline.
  final Duration offset;

  /// Amplitude multiplier in `[0.0, 1.0]`. Default is full volume (`1.0`).
  final double volume;

  /// Start offset within the source audio file.
  ///
  /// `null` means start from the beginning of the source.
  final Duration? trimStart;

  /// End timestamp within the source audio file.
  ///
  /// `null` means play to the end of the source (after [trimStart]).
  /// This is an absolute end point, not a duration.
  final Duration? trimEnd;

  /// Duration of the fade-in ramp at the start of the audio track.
  final Duration? fadeIn;

  /// Duration of the fade-out ramp at the end of the audio track.
  final Duration? fadeOut;

  /// Serialises this [AudioTrack] to a JSON-compatible map for the method
  /// channel. Optional fields are omitted when `null`.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'offsetMs': offset.inMilliseconds,
    'volume': volume,
    if (trimStart != null) 'trimStartMs': trimStart!.inMilliseconds,
    if (trimEnd != null) 'trimEndMs': trimEnd!.inMilliseconds,
    if (fadeIn != null) 'fadeInMs': fadeIn!.inMilliseconds,
    if (fadeOut != null) 'fadeOutMs': fadeOut!.inMilliseconds,
  };

  /// Returns a copy with the given fields replaced.
  AudioTrack copyWith({
    String? path,
    Duration? offset,
    double? volume,
    Duration? trimStart,
    Duration? trimEnd,
    Duration? fadeIn,
    Duration? fadeOut,
  }) => AudioTrack(
    path: path ?? this.path,
    offset: offset ?? this.offset,
    volume: volume ?? this.volume,
    trimStart: trimStart ?? this.trimStart,
    trimEnd: trimEnd ?? this.trimEnd,
    fadeIn: fadeIn ?? this.fadeIn,
    fadeOut: fadeOut ?? this.fadeOut,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrack &&
          path == other.path &&
          offset == other.offset &&
          volume == other.volume &&
          trimStart == other.trimStart &&
          trimEnd == other.trimEnd &&
          fadeIn == other.fadeIn &&
          fadeOut == other.fadeOut;

  @override
  int get hashCode =>
      Object.hash(path, offset, volume, trimStart, trimEnd, fadeIn, fadeOut);
}
