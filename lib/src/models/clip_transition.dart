import 'package:flutter/foundation.dart';

/// The type of transition applied at the boundary to the next clip.
enum TransitionType {
  /// No transition — a hard cut.
  none,

  /// A linear cross-dissolve between the outgoing and incoming clip.
  crossfade,
}

/// Describes the transition applied at the boundary from one [TimelineClip]
/// to the next.
///
/// Attach to [TimelineClip.transitionToNext]. `null` means a hard cut (same as
/// [TransitionType.none]).
@immutable
class ClipTransition {
  /// Creates a [ClipTransition].
  const ClipTransition({required this.type, required this.duration});

  /// The visual/audio effect applied during the transition.
  final TransitionType type;

  /// How long the transition lasts.
  final Duration duration;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    'durationMs': duration.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is ClipTransition && other.type == type && other.duration == duration;

  @override
  int get hashCode => Object.hash(type, duration);
}
