import 'package:flutter/foundation.dart';

@immutable
class TimelinePlayerState {
  const TimelinePlayerState({
    required this.globalPosition,
    required this.clipIndex,
    required this.localPosition,
    required this.isPlaying,
    required this.totalDuration,
  });

  const TimelinePlayerState.initial()
    : globalPosition = Duration.zero,
      clipIndex = 0,
      localPosition = Duration.zero,
      isPlaying = false,
      totalDuration = Duration.zero;

  final Duration globalPosition;
  final int clipIndex;
  final Duration localPosition;
  final bool isPlaying;
  final Duration totalDuration;

  factory TimelinePlayerState.fromMap(Map<dynamic, dynamic> map) {
    return TimelinePlayerState(
      globalPosition: Duration(milliseconds: _readInt(map, 'globalPosition')),
      clipIndex: _readInt(map, 'clipIndex'),
      localPosition: Duration(milliseconds: _readInt(map, 'localPosition')),
      isPlaying: map['isPlaying'] == true,
      totalDuration: Duration(milliseconds: _readInt(map, 'totalDuration')),
    );
  }

  TimelinePlayerState copyWith({
    Duration? globalPosition,
    int? clipIndex,
    Duration? localPosition,
    bool? isPlaying,
    Duration? totalDuration,
  }) {
    return TimelinePlayerState(
      globalPosition: globalPosition ?? this.globalPosition,
      clipIndex: clipIndex ?? this.clipIndex,
      localPosition: localPosition ?? this.localPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      totalDuration: totalDuration ?? this.totalDuration,
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
    return other is TimelinePlayerState &&
        other.globalPosition == globalPosition &&
        other.clipIndex == clipIndex &&
        other.localPosition == localPosition &&
        other.isPlaying == isPlaying &&
        other.totalDuration == totalDuration;
  }

  @override
  int get hashCode {
    return Object.hash(
      globalPosition,
      clipIndex,
      localPosition,
      isPlaying,
      totalDuration,
    );
  }
}
