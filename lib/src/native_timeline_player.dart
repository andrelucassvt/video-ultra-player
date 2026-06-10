import 'package:video_ultra_player/src/models/timeline_composition_config.dart';
import 'package:video_ultra_player/src/models/timeline_export_progress.dart';
import 'package:video_ultra_player/src/models/timeline_clip.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

/// Controls a native timeline player that composes and plays a sequence of
/// [TimelineClip]s in a gapless, frame-accurate manner.
///
/// Call [load] to initialise the native composition and obtain a texture ID
/// suitable for rendering in a Flutter [Texture] widget. Then use [play],
/// [pause], [seekTo], and [seekToClip] to control playback. Listen to
/// [stateStream] for position and playback-state updates.
///
/// Always call [dispose] when the player is no longer needed to release the
/// underlying native texture and compositor resources.
///
/// ```dart
/// final player = NativeTimelinePlayer();
/// final textureId = await player.load(clips);
/// await player.play();
/// // …
/// await player.dispose();
/// ```
class NativeTimelinePlayer {
  /// Creates a [NativeTimelinePlayer].
  ///
  /// An optional [platform] implementation can be supplied for testing;
  /// production code should leave it as `null` to use the default channel.
  NativeTimelinePlayer({VideoUltraPlayerPlatform? platform})
    : _platform = platform ?? VideoUltraPlayerPlatform.instance;

  final VideoUltraPlayerPlatform _platform;
  int? _textureId;
  Stream<TimelinePlayerState>? _stateStream;
  Stream<TimelineExportProgress>? _exportProgressStream;
  bool _exporting = false;

  /// The Flutter texture ID registered by the native compositor after [load].
  ///
  /// Returns `null` when [isLoaded] is `false`.
  int? get textureId => _textureId;

  /// Whether [load] has completed and native resources are ready.
  bool get isLoaded => _textureId != null;

  /// A broadcast stream of [TimelinePlayerState] updates emitted by the
  /// native layer, including position and playback-state changes.
  ///
  /// Throws a [StateError] if [load] has not been called first.
  Stream<TimelinePlayerState> get stateStream {
    final textureId = _requireTextureId();
    return _stateStream ??= _platform
        .stateStream(textureId)
        .asBroadcastStream();
  }

  /// A broadcast stream of [TimelineExportProgress] events emitted during an
  /// active [exportTimeline] call.
  ///
  /// Throws a [StateError] if [exportTimeline] is not currently in progress.
  Stream<TimelineExportProgress> get exportProgress {
    if (!_exporting) {
      throw StateError(
        'NativeTimelinePlayer.exportTimeline must be in progress before this call.',
      );
    }
    return _exportProgressStream ??= _platform
        .exportProgress()
        .asBroadcastStream();
  }

  /// Loads [clips] into the native compositor and returns the Flutter texture ID.
  ///
  /// Pass an optional [config] to control output resolution and aspect ratio.
  /// Throws [ArgumentError] if [clips] is empty.
  Future<int> load(
    List<TimelineClip> clips, {
    TimelineCompositionConfig? config,
  }) async {
    if (clips.isEmpty) {
      throw ArgumentError.value(
        clips,
        'clips',
        'Must contain at least one clip.',
      );
    }

    final textureId = await _platform.load(
      clips.map((clip) => clip.toJson()).toList(growable: false),
      config: (config ?? TimelineCompositionConfig()).toJson(),
    );
    _textureId = textureId;
    _stateStream = null;
    return textureId;
  }

  /// Exports [clips] to a video file and returns the output file path.
  ///
  /// An optional [outputPath] overrides the default platform temp location.
  /// Progress events are available via [exportProgress] while this future is
  /// pending. Only one export can run at a time; a concurrent call throws
  /// [StateError].
  Future<String> exportTimeline(
    List<TimelineClip> clips, {
    String? outputPath,
    TimelineCompositionConfig? config,
  }) async {
    if (clips.isEmpty) {
      throw ArgumentError.value(
        clips,
        'clips',
        'Must contain at least one clip.',
      );
    }

    if (_exporting) {
      throw StateError('Only one timeline export can run at a time.');
    }

    _exporting = true;
    _exportProgressStream = null;
    try {
      return await _platform.exportTimeline(
        clips.map((clip) => clip.toJson()).toList(growable: false),
        outputPath: outputPath,
        config: (config ?? TimelineCompositionConfig()).toJson(),
      );
    } finally {
      _exporting = false;
    }
  }

  /// Starts or resumes playback of the loaded timeline.
  Future<void> play() {
    return _platform.play(_requireTextureId());
  }

  /// Pauses playback at the current position.
  Future<void> pause() {
    return _platform.pause(_requireTextureId());
  }

  /// Seeks to [position] relative to the start of the full timeline.
  Future<void> seekTo(Duration position) {
    return _platform.seekTo(_requireTextureId(), position);
  }

  /// Seeks to the beginning of the clip at [clipIndex] in the loaded timeline.
  Future<void> seekToClip(int clipIndex) {
    return _platform.seekToClip(_requireTextureId(), clipIndex);
  }

  /// Sets the playback [volume] in the range `[0.0, 1.0]`.
  ///
  /// Throws [RangeError] for values outside that range.
  Future<void> setVolume(double volume) {
    if (volume < 0 || volume > 1) {
      throw RangeError.range(volume, 0, 1, 'volume');
    }
    return _platform.setVolume(_requireTextureId(), volume);
  }

  /// Adjusts the pan-and-crop alignment for the clip at [clipIndex].
  ///
  /// [x] and [y] map to the same coordinate space as [Alignment]:
  /// `(-1, -1)` is top-left, `(0, 0)` is center, `(1, 1)` is bottom-right.
  Future<void> setClipAlignment(int clipIndex, double x, double y) {
    return _platform.setClipAlignment(_requireTextureId(), clipIndex, x, y);
  }

  /// Releases the native compositor and Flutter texture resources.
  ///
  /// Safe to call even when [isLoaded] is `false`. After disposal, [load] must
  /// be called again before any other method.
  Future<void> dispose() async {
    final textureId = _textureId;
    if (textureId == null) {
      return;
    }
    _textureId = null;
    _stateStream = null;
    await _platform.dispose(textureId);
  }

  int _requireTextureId() {
    final textureId = _textureId;
    if (textureId == null) {
      throw StateError(
        'NativeTimelinePlayer.load must complete before this call.',
      );
    }
    return textureId;
  }
}
