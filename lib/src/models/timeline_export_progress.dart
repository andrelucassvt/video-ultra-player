import 'package:flutter/foundation.dart';

/// The lifecycle phase of a [NativeTimelinePlayer.exportTimeline] operation.
enum TimelineExportState {
  /// No export is running.
  idle,

  /// Export is in progress — [TimelineExportProgress.progress] is updating.
  exporting,

  /// Export finished successfully.
  completed,

  /// Export terminated with an error.
  failed,
}

/// A snapshot of export progress emitted on [NativeTimelinePlayer.exportProgress].
@immutable
class TimelineExportProgress {
  /// Creates a [TimelineExportProgress] with an explicit [progress] and [state].
  const TimelineExportProgress({required this.progress, required this.state});

  /// Convenience constructor for the initial idle state.
  const TimelineExportProgress.idle()
    : progress = 0,
      state = TimelineExportState.idle;

  /// Normalised completion ratio in the range `[0.0, 1.0]`.
  final double progress;

  /// Current phase of the export operation.
  final TimelineExportState state;

  factory TimelineExportProgress.fromMap(Map<dynamic, dynamic> map) {
    final rawProgress = map['progress'];
    final progress = rawProgress is num ? rawProgress.toDouble() : 0.0;
    final rawState = map['state'];

    return TimelineExportProgress(
      progress: progress.clamp(0.0, 1.0).toDouble(),
      state: TimelineExportState.values.firstWhere(
        (state) => state.name == rawState,
        orElse: () => TimelineExportState.idle,
      ),
    );
  }

  TimelineExportProgress copyWith({
    double? progress,
    TimelineExportState? state,
  }) {
    return TimelineExportProgress(
      progress: progress ?? this.progress,
      state: state ?? this.state,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineExportProgress &&
        other.progress == progress &&
        other.state == state;
  }

  @override
  int get hashCode => Object.hash(progress, state);
}
