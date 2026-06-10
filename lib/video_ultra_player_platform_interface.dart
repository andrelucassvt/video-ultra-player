import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_ultra_player/src/models/timeline_export_progress.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_method_channel.dart';

/// The platform interface contract for [NativeTimelinePlayer].
///
/// Platform implementations must extend this class and register themselves as
/// [VideoUltraPlayerPlatform.instance] during plugin registration.
abstract class VideoUltraPlayerPlatform extends PlatformInterface {
  VideoUltraPlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoUltraPlayerPlatform _instance = MethodChannelVideoUltraPlayer();

  static VideoUltraPlayerPlatform get instance => _instance;

  static set instance(VideoUltraPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int> load(
    List<Map<String, dynamic>> clips, {
    Map<String, dynamic>? config,
  }) {
    throw UnimplementedError('load() has not been implemented.');
  }

  Future<String> exportTimeline(
    List<Map<String, dynamic>> clips, {
    String? outputPath,
    Map<String, dynamic>? config,
  }) {
    throw UnimplementedError('exportTimeline() has not been implemented.');
  }

  /// Exports the currently loaded (and edited) timeline without requiring
  /// a separate clip list. Preview and export share the same native state.
  Future<String> exportCurrentTimeline(
    int textureId, {
    String? outputPath,
  }) {
    throw UnimplementedError(
      'exportCurrentTimeline() has not been implemented.',
    );
  }

  Future<void> play(int textureId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  Future<void> pause(int textureId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  Future<void> seekTo(int textureId, Duration position) {
    throw UnimplementedError('seekTo() has not been implemented.');
  }

  Future<void> seekToClip(int textureId, int clipIndex) {
    throw UnimplementedError('seekToClip() has not been implemented.');
  }

  Future<void> setVolume(int textureId, double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  Future<void> setClipAlignment(
    int textureId,
    int clipIndex,
    double x,
    double y,
  ) {
    throw UnimplementedError('setClipAlignment() has not been implemented.');
  }

  Future<void> dispose(int textureId) {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  Stream<TimelinePlayerState> stateStream(int textureId) {
    throw UnimplementedError('stateStream() has not been implemented.');
  }

  Stream<TimelineExportProgress> exportProgress() {
    throw UnimplementedError('exportProgress() has not been implemented.');
  }

  // ── Editing operations ──────────────────────────────────────────────────

  /// Adjusts the trim in/out points of the clip at [clipIndex].
  ///
  /// Pass `null` for [trimStartMs] or [trimEndMs] to leave the current value
  /// unchanged.
  Future<void> trimClip(
    int textureId,
    int clipIndex, {
    int? trimStartMs,
    int? trimEndMs,
  }) {
    throw UnimplementedError('trimClip() has not been implemented.');
  }

  /// Splits the clip at [clipIndex] at [atLocalPositionMs] milliseconds from
  /// its trim-start, producing two clips in its place.
  Future<void> splitClip(
    int textureId,
    int clipIndex,
    int atLocalPositionMs,
  ) {
    throw UnimplementedError('splitClip() has not been implemented.');
  }

  /// Inserts [clip] at position [atIndex] in the timeline.
  Future<void> insertClip(
    int textureId,
    int atIndex,
    Map<String, dynamic> clip,
  ) {
    throw UnimplementedError('insertClip() has not been implemented.');
  }

  /// Removes the clip at [clipIndex] from the timeline.
  Future<void> removeClip(int textureId, int clipIndex) {
    throw UnimplementedError('removeClip() has not been implemented.');
  }

  /// Moves the clip at [fromIndex] to [toIndex].
  Future<void> moveClip(int textureId, int fromIndex, int toIndex) {
    throw UnimplementedError('moveClip() has not been implemented.');
  }

  /// Replaces the clip at [clipIndex] with [clip].
  Future<void> replaceClip(
    int textureId,
    int clipIndex,
    Map<String, dynamic> clip,
  ) {
    throw UnimplementedError('replaceClip() has not been implemented.');
  }
}
