import 'package:flutter/foundation.dart';

enum TimelineExportState { idle, exporting, completed, failed }

@immutable
class TimelineExportProgress {
  const TimelineExportProgress({required this.progress, required this.state});

  const TimelineExportProgress.idle()
    : progress = 0,
      state = TimelineExportState.idle;

  final double progress;
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
