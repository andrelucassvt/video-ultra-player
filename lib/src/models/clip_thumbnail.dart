/// A thumbnail frame extracted from a video clip at a specific point in time.
///
/// Instances are produced by [NativeTimelinePlayer.generateThumbnails] and
/// contain the file-system path to the cached JPEG image and the source
/// timestamp from which the frame was extracted.
class ClipThumbnail {
  /// Creates a [ClipThumbnail].
  const ClipThumbnail({required this.path, required this.time});

  /// Absolute file-system path to the cached JPEG thumbnail image.
  final String path;

  /// The source timestamp from which this frame was extracted.
  final Duration time;

  /// Deserialises a [ClipThumbnail] from a map returned by the native layer.
  ///
  /// The map must contain:
  /// - `'path'` (`String`) — absolute path to the cached image file.
  /// - `'timeMs'` (`num`) — the source timestamp in milliseconds.
  factory ClipThumbnail.fromMap(Map<dynamic, dynamic> map) {
    return ClipThumbnail(
      path: map['path'] as String,
      time: Duration(milliseconds: (map['timeMs'] as num).toInt()),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipThumbnail && other.path == path && other.time == time;
  }

  @override
  int get hashCode => Object.hash(path, time);

  @override
  String toString() => 'ClipThumbnail(path: $path, time: $time)';
}
