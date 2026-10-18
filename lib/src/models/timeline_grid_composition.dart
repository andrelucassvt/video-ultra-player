import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A video placed inside one cell of a [TimelineGridComposition].
///
/// [rect] is normalized to the output canvas: `(0, 0)` is the top-left corner
/// and `(1, 1)` the bottom-right one. The video is scaled to cover the cell
/// and cropped around the center.
@immutable
class TimelineGridCell {
  /// Creates a [TimelineGridCell].
  const TimelineGridCell({required this.path, required this.rect});

  /// Absolute path to the source video file.
  final String path;

  /// Normalized cell bounds inside the output canvas.
  final Rect rect;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'path': path,
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineGridCell &&
        other.path == path &&
        other.rect == rect;
  }

  @override
  int get hashCode => Object.hash(path, rect);
}

/// Describes a split-screen video rendered by [NativeTimelinePlayer.renderGrid].
///
/// Every [videoCells] entry plays at the same time inside its own cell. The
/// output lasts as long as the longest video (capped by [maxDuration]);
/// shorter videos loop until the end. [overlayImagePath] is a PNG with the
/// exact output size drawn on top of every frame — transparent pixels reveal
/// the videos below, so cell shapes, borders, background and still images are
/// all defined by the caller.
@immutable
class TimelineGridComposition {
  /// Creates a [TimelineGridComposition].
  ///
  /// [width] and [height] must be positive and even (video encoders reject odd
  /// sizes). [videoCells] must not be empty, and every cell must lie inside the
  /// normalized `[0, 1]` canvas. [audioCellIndex], when set, must point at one
  /// of [videoCells]; the remaining cells are muted.
  factory TimelineGridComposition({
    required int width,
    required int height,
    required List<TimelineGridCell> videoCells,
    String? overlayImagePath,
    int? audioCellIndex,
    Duration? maxDuration,
  }) {
    if (width <= 0 || width.isOdd) {
      throw ArgumentError.value(width, 'width', 'Must be positive and even.');
    }
    if (height <= 0 || height.isOdd) {
      throw ArgumentError.value(height, 'height', 'Must be positive and even.');
    }
    if (videoCells.isEmpty) {
      throw ArgumentError.value(
        videoCells,
        'videoCells',
        'Must contain at least one cell.',
      );
    }
    for (final cell in videoCells) {
      final rect = cell.rect;
      if (rect.width <= 0 ||
          rect.height <= 0 ||
          rect.left < 0 ||
          rect.top < 0 ||
          rect.right > 1.0001 ||
          rect.bottom > 1.0001) {
        throw ArgumentError.value(
          rect,
          'videoCells',
          'Every cell must lie inside the normalized [0, 1] canvas.',
        );
      }
    }
    if (audioCellIndex != null &&
        (audioCellIndex < 0 || audioCellIndex >= videoCells.length)) {
      throw RangeError.index(audioCellIndex, videoCells, 'audioCellIndex');
    }
    if (maxDuration != null && maxDuration <= Duration.zero) {
      throw ArgumentError.value(
        maxDuration,
        'maxDuration',
        'Must be positive.',
      );
    }
    return TimelineGridComposition._(
      width: width,
      height: height,
      videoCells: List<TimelineGridCell>.unmodifiable(videoCells),
      overlayImagePath: overlayImagePath,
      audioCellIndex: audioCellIndex,
      maxDuration: maxDuration,
    );
  }

  const TimelineGridComposition._({
    required this.width,
    required this.height,
    required this.videoCells,
    required this.overlayImagePath,
    required this.audioCellIndex,
    required this.maxDuration,
  });

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// Videos played simultaneously, one per cell.
  final List<TimelineGridCell> videoCells;

  /// PNG drawn over every frame, with the same size as the output.
  final String? overlayImagePath;

  /// Index in [videoCells] whose audio is kept. `null` renders a silent video.
  final int? audioCellIndex;

  /// Upper bound for the output duration. `null` keeps the longest video.
  final Duration? maxDuration;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'width': width,
      'height': height,
      'cells': videoCells.map((cell) => cell.toJson()).toList(growable: false),
      'overlayImagePath': overlayImagePath,
      'audioCellIndex': audioCellIndex,
      'maxDurationMs': maxDuration?.inMilliseconds,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineGridComposition &&
        other.width == width &&
        other.height == height &&
        listEquals(other.videoCells, videoCells) &&
        other.overlayImagePath == overlayImagePath &&
        other.audioCellIndex == audioCellIndex &&
        other.maxDuration == maxDuration;
  }

  @override
  int get hashCode => Object.hash(
    width,
    height,
    Object.hashAll(videoCells),
    overlayImagePath,
    audioCellIndex,
    maxDuration,
  );
}
