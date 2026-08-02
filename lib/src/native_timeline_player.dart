import 'package:video_ultra_player/src/models/audio_track.dart';
import 'package:video_ultra_player/src/models/timeline_clip.dart';
import 'package:video_ultra_player/src/models/timeline_composition_config.dart';
import 'package:video_ultra_player/src/models/timeline_export_progress.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/src/models/timeline_text_overlay.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

/// Controls a native timeline player that composes and plays a sequence of
/// [TimelineClip]s in a gapless, frame-accurate manner.
///
/// Call [load] to initialise the native composition and obtain a texture ID
/// suitable for rendering in a Flutter [Texture] widget. Then use [play],
/// [pause], [seekTo], and [seekToClip] to control playback. Listen to
/// [stateStream] for position and playback-state updates.
///
/// ## Editing
///
/// After [load], the timeline can be mutated without a full dispose/reload:
/// [trimClip], [splitClip], [insertClip], [removeClip], [moveClip], and
/// [replaceClip] all preserve the active texture ID and seek position. Use
/// [exportCurrentTimeline] to export the edited result — this ensures the
/// exported MP4 matches exactly what the preview shows.
///
/// Always call [dispose] when the player is no longer needed to release the
/// underlying native texture and compositor resources.
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
  /// active [exportTimeline] or [exportCurrentTimeline] call.
  ///
  /// Throws a [StateError] if neither export is currently in progress.
  Stream<TimelineExportProgress> get exportProgress {
    if (!_exporting) {
      throw StateError(
        'An export must be in progress before accessing exportProgress.',
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

  /// Exports the currently loaded, edited timeline and returns the output path.
  ///
  /// Unlike [exportTimeline], this method uses the native compositor's current
  /// state so the exported MP4 matches exactly what the preview shows after
  /// any editing operations.
  ///
  /// Requires [load] to have completed. Throws [StateError] if another export
  /// is already running.
  Future<String> exportCurrentTimeline({String? outputPath}) async {
    if (_exporting) {
      throw StateError('Only one timeline export can run at a time.');
    }

    _exporting = true;
    _exportProgressStream = null;
    try {
      return await _platform.exportCurrentTimeline(
        _requireTextureId(),
        outputPath: outputPath,
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

  // ── Editing operations ──────────────────────────────────────────────────

  /// Adjusts the trim in/out of the clip at [clipIndex].
  ///
  /// Pass `null` for [trimStart] or [trimEnd] to leave the current value
  /// unchanged. Ignored for image clips.
  Future<void> trimClip(
    int clipIndex, {
    Duration? trimStart,
    Duration? trimEnd,
  }) {
    if (clipIndex < 0) {
      throw ArgumentError.value(clipIndex, 'clipIndex', 'Must be >= 0.');
    }
    return _platform.trimClip(
      _requireTextureId(),
      clipIndex,
      trimStartMs: trimStart?.inMilliseconds,
      trimEndMs: trimEnd?.inMilliseconds,
    );
  }

  /// Splits the clip at [clipIndex] at [atLocalPosition] from its trim-start,
  /// replacing it with two clips.
  ///
  /// [atLocalPosition] must be > zero.
  Future<void> splitClip(int clipIndex, Duration atLocalPosition) {
    if (clipIndex < 0) {
      throw ArgumentError.value(clipIndex, 'clipIndex', 'Must be >= 0.');
    }
    if (atLocalPosition <= Duration.zero) {
      throw ArgumentError.value(
        atLocalPosition,
        'atLocalPosition',
        'Must be > zero.',
      );
    }
    return _platform.splitClip(
      _requireTextureId(),
      clipIndex,
      atLocalPosition.inMilliseconds,
    );
  }

  /// Inserts [clip] at position [atIndex] in the timeline.
  Future<void> insertClip(int atIndex, TimelineClip clip) {
    if (atIndex < 0) {
      throw ArgumentError.value(atIndex, 'atIndex', 'Must be >= 0.');
    }
    return _platform.insertClip(_requireTextureId(), atIndex, clip.toJson());
  }

  /// Removes the clip at [clipIndex] from the timeline.
  Future<void> removeClip(int clipIndex) {
    if (clipIndex < 0) {
      throw ArgumentError.value(clipIndex, 'clipIndex', 'Must be >= 0.');
    }
    return _platform.removeClip(_requireTextureId(), clipIndex);
  }

  /// Moves the clip at [fromIndex] to [toIndex]. No-op when they are equal.
  Future<void> moveClip(int fromIndex, int toIndex) {
    if (fromIndex < 0) {
      throw ArgumentError.value(fromIndex, 'fromIndex', 'Must be >= 0.');
    }
    if (toIndex < 0) {
      throw ArgumentError.value(toIndex, 'toIndex', 'Must be >= 0.');
    }
    if (fromIndex == toIndex) return Future<void>.value();
    return _platform.moveClip(_requireTextureId(), fromIndex, toIndex);
  }

  /// Replaces the clip at [clipIndex] with [clip].
  Future<void> replaceClip(int clipIndex, TimelineClip clip) {
    if (clipIndex < 0) {
      throw ArgumentError.value(clipIndex, 'clipIndex', 'Must be >= 0.');
    }
    return _platform.replaceClip(
      _requireTextureId(),
      clipIndex,
      clip.toJson(),
    );
  }

  /// Sets the playback speed of the clip at [clipIndex] to [speed].
  ///
  /// [speed] must be in the range `[0.5, 2.0]`. Throws [ArgumentError] for
  /// negative [clipIndex] and [RangeError] for speed outside the valid range.
  Future<void> setClipSpeed(int clipIndex, double speed) {
    if (clipIndex < 0) {
      throw ArgumentError.value(clipIndex, 'clipIndex', 'Must be >= 0.');
    }
    if (speed < 0.5 || speed > 2.0) {
      throw RangeError.value(speed, 'speed', 'speed must be in [0.5, 2.0].');
    }
    return _platform.setClipSpeed(_requireTextureId(), clipIndex, speed);
  }

  /// Restores the previous edit snapshot in the native compositor.
  ///
  /// Requires [load] to have completed. If the native undo stack is empty, the
  /// native layer treats this as a safe no-op.
  Future<void> undo() {
    return _platform.undo(_requireTextureId());
  }

  /// Reapplies the next edit snapshot after [undo].
  ///
  /// Requires [load] to have completed. If the native redo stack is empty, the
  /// native layer treats this as a safe no-op.
  Future<void> redo() {
    return _platform.redo(_requireTextureId());
  }

  // ── Audio track ──────────────────────────────────────────────────────────

  /// Overlays an external [track] on the loaded timeline.
  ///
  /// The [track] starts at [AudioTrack.offset] within the timeline and its
  /// audio content is mixed on top of the clip audio at [AudioTrack.volume].
  ///
  /// Requires [load] to have completed. Throws [StateError] otherwise.
  Future<void> setAudioTrack(AudioTrack track) {
    _requireTextureId();
    return _platform.setAudioTrack(textureId!, track.toJson());
  }

  /// Removes any external audio track previously set via [setAudioTrack].
  ///
  /// Requires [load] to have completed. Throws [StateError] otherwise.
  Future<void> removeAudioTrack() {
    _requireTextureId();
    return _platform.removeAudioTrack(textureId!);
  }

  // ── Text overlays ────────────────────────────────────────────────────────

  /// Adds a text [overlay] to the loaded timeline.
  ///
  /// The overlay is burned into the composed video and appears in both the
  /// preview and the exported MP4 during its `start`/`end` window.
  ///
  /// Requires [load] to have completed. Throws [StateError] otherwise.
  Future<void> addTextOverlay(TimelineTextOverlay overlay) {
    _requireTextureId();
    return _platform.addTextOverlay(textureId!, overlay.toJson());
  }

  /// Updates the text overlay whose [TimelineTextOverlay.id] matches
  /// [overlay]'s id.
  ///
  /// Requires [load] to have completed. Throws [StateError] otherwise.
  Future<void> updateTextOverlay(TimelineTextOverlay overlay) {
    _requireTextureId();
    return _platform.updateTextOverlay(textureId!, overlay.toJson());
  }

  /// Removes the text overlay identified by [overlayId].
  ///
  /// Requires [load] to have completed. Throws [StateError] otherwise.
  Future<void> removeTextOverlay(String overlayId) {
    _requireTextureId();
    return _platform.removeTextOverlay(textureId!, overlayId);
  }

  // ── Thumbnail generation ────────────────────────────────────────────────

  /// Extracts thumbnail frames from [videoPath] at each timestamp in
  /// [timestamps] and returns the absolute file-system paths of the cached
  /// JPEG images.
  ///
  /// This is a **standalone utility** — it does not require [load] to have
  /// been called first. It can be used independently of any active player.
  ///
  /// [width] controls the pixel width of each thumbnail (height is scaled
  /// proportionally). Defaults to 120 px.
  ///
  /// Results are cached by `(videoPath, timestamp, width)` on the native
  /// side — a second identical call is served from cache without re-extraction.
  Future<List<String>> generateThumbnails(
    String videoPath,
    List<Duration> timestamps, {
    int width = 120,
  }) {
    final timestampsMs =
        timestamps.map((d) => d.inMilliseconds).toList(growable: false);
    return _platform.generateThumbnails(videoPath, timestampsMs, width: width);
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
