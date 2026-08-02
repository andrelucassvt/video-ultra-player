import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_ultra_player/src/models/timeline_composition_config.dart';
import 'package:video_ultra_player/src/models/timeline_export_progress.dart';
import 'package:video_ultra_player/src/models/timeline_player_state.dart';
import 'package:video_ultra_player/video_ultra_player_platform_interface.dart';

/// The default [VideoUltraPlayerPlatform] implementation that communicates
/// with native code via a Flutter [MethodChannel] and [EventChannel].
class MethodChannelVideoUltraPlayer extends VideoUltraPlayerPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'video_ultra_player/timeline_player',
  );

  @visibleForTesting
  final eventChannel = const EventChannel(
    'video_ultra_player/timeline_player/events',
  );

  @visibleForTesting
  final exportEventChannel = const EventChannel(
    'video_ultra_player/timeline_player/export',
  );

  @override
  Future<int> load(
    List<Map<String, dynamic>> clips, {
    Map<String, dynamic>? config,
  }) async {
    final textureId = await methodChannel.invokeMethod<int>(
      'load',
      <String, Object?>{
        'clips': clips,
        'config': config ?? TimelineCompositionConfig().toJson(),
      },
    );
    if (textureId == null) {
      throw StateError('Native timeline load did not return a texture id.');
    }
    return textureId;
  }

  @override
  Future<String> exportTimeline(
    List<Map<String, dynamic>> clips, {
    String? outputPath,
    Map<String, dynamic>? config,
  }) async {
    final exportedPath = await methodChannel
        .invokeMethod<String>('exportTimeline', <String, Object?>{
          'clips': clips,
          'outputPath': outputPath,
          'config': config ?? TimelineCompositionConfig().toJson(),
        });
    if (exportedPath == null) {
      throw StateError('Native timeline export did not return an output path.');
    }
    return exportedPath;
  }

  @override
  Future<String> exportCurrentTimeline(
    int textureId, {
    String? outputPath,
  }) async {
    final exportedPath = await methodChannel.invokeMethod<String>(
      'exportCurrentTimeline',
      <String, Object?>{'textureId': textureId, 'outputPath': outputPath},
    );
    if (exportedPath == null) {
      throw StateError(
        'Native exportCurrentTimeline did not return an output path.',
      );
    }
    return exportedPath;
  }

  @override
  Future<void> play(int textureId) {
    return methodChannel.invokeMethod<void>('play', _textureArgs(textureId));
  }

  @override
  Future<void> pause(int textureId) {
    return methodChannel.invokeMethod<void>('pause', _textureArgs(textureId));
  }

  @override
  Future<void> seekTo(int textureId, Duration position) {
    return methodChannel.invokeMethod<void>('seekTo', <String, Object?>{
      'textureId': textureId,
      'positionMs': position.inMilliseconds,
    });
  }

  @override
  Future<void> seekToClip(int textureId, int clipIndex) {
    return methodChannel.invokeMethod<void>('seekToClip', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
    });
  }

  @override
  Future<void> setVolume(int textureId, double volume) {
    return methodChannel.invokeMethod<void>('setVolume', <String, Object?>{
      'textureId': textureId,
      'volume': volume,
    });
  }

  @override
  Future<void> setClipAlignment(
    int textureId,
    int clipIndex,
    double x,
    double y,
  ) {
    return methodChannel.invokeMethod<void>(
      'setClipAlignment',
      <String, Object?>{
        'textureId': textureId,
        'clipIndex': clipIndex,
        'x': x,
        'y': y,
      },
    );
  }

  @override
  Future<void> dispose(int textureId) {
    return methodChannel.invokeMethod<void>('dispose', _textureArgs(textureId));
  }

  @override
  Stream<TimelinePlayerState> stateStream(int textureId) {
    return eventChannel
        .receiveBroadcastStream(_textureArgs(textureId))
        .map(
          (event) =>
              TimelinePlayerState.fromMap(event as Map<dynamic, dynamic>),
        );
  }

  @override
  Stream<TimelineExportProgress> exportProgress() {
    return exportEventChannel.receiveBroadcastStream().map(
      (event) => TimelineExportProgress.fromMap(event as Map<dynamic, dynamic>),
    );
  }

  // ── Editing operations ──────────────────────────────────────────────────

  @override
  Future<void> trimClip(
    int textureId,
    int clipIndex, {
    int? trimStartMs,
    int? trimEndMs,
  }) {
    return methodChannel.invokeMethod<void>('trimClip', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
      'trimStartMs': trimStartMs,
      'trimEndMs': trimEndMs,
    });
  }

  @override
  Future<void> splitClip(int textureId, int clipIndex, int atLocalPositionMs) {
    return methodChannel.invokeMethod<void>('splitClip', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
      'atLocalPositionMs': atLocalPositionMs,
    });
  }

  @override
  Future<void> insertClip(
    int textureId,
    int atIndex,
    Map<String, dynamic> clip,
  ) {
    return methodChannel.invokeMethod<void>('insertClip', <String, Object?>{
      'textureId': textureId,
      'atIndex': atIndex,
      'clip': clip,
    });
  }

  @override
  Future<void> removeClip(int textureId, int clipIndex) {
    return methodChannel.invokeMethod<void>('removeClip', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
    });
  }

  @override
  Future<void> moveClip(int textureId, int fromIndex, int toIndex) {
    return methodChannel.invokeMethod<void>('moveClip', <String, Object?>{
      'textureId': textureId,
      'fromIndex': fromIndex,
      'toIndex': toIndex,
    });
  }

  @override
  Future<void> replaceClip(
    int textureId,
    int clipIndex,
    Map<String, dynamic> clip,
  ) {
    return methodChannel.invokeMethod<void>('replaceClip', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
      'clip': clip,
    });
  }

  @override
  Future<void> setClipSpeed(int textureId, int clipIndex, double speed) {
    return methodChannel.invokeMethod<void>('setClipSpeed', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
      'speed': speed,
    });
  }

  @override
  Future<void> undo(int textureId) {
    return methodChannel.invokeMethod<void>('undo', _textureArgs(textureId));
  }

  @override
  Future<void> redo(int textureId) {
    return methodChannel.invokeMethod<void>('redo', _textureArgs(textureId));
  }

  // ── Audio track ──────────────────────────────────────────────────────────

  @override
  Future<void> setAudioTrack(int textureId, Map<String, dynamic> track) {
    return methodChannel.invokeMethod<void>('setAudioTrack', <String, Object?>{
      'textureId': textureId,
      'track': track,
    });
  }

  @override
  Future<void> removeAudioTrack(int textureId) {
    return methodChannel.invokeMethod<void>(
      'removeAudioTrack',
      <String, Object?>{'textureId': textureId},
    );
  }

  // ── Text overlays ────────────────────────────────────────────────────────

  @override
  Future<void> addTextOverlay(
    int textureId,
    Map<String, dynamic> overlay,
  ) {
    return methodChannel.invokeMethod<void>('addTextOverlay', <String, Object?>{
      'textureId': textureId,
      'overlay': overlay,
    });
  }

  @override
  Future<void> updateTextOverlay(
    int textureId,
    Map<String, dynamic> overlay,
  ) {
    return methodChannel.invokeMethod<void>(
      'updateTextOverlay',
      <String, Object?>{
        'textureId': textureId,
        'overlay': overlay,
      },
    );
  }

  @override
  Future<void> removeTextOverlay(int textureId, String overlayId) {
    return methodChannel.invokeMethod<void>(
      'removeTextOverlay',
      <String, Object?>{
        'textureId': textureId,
        'overlayId': overlayId,
      },
    );
  }

  // ── Thumbnail generation ────────────────────────────────────────────────

  @override
  Future<List<String>> generateThumbnails(
    String videoPath,
    List<int> timestampsMs, {
    int width = 120,
  }) async {
    final result = await methodChannel.invokeMethod<List<dynamic>>(
      'generateThumbnails',
      <String, Object?>{
        'videoPath': videoPath,
        'timestampsMs': timestampsMs,
        'width': width,
      },
    );
    return result?.cast<String>() ?? [];
  }

  Map<String, Object?> _textureArgs(int textureId) {
    return <String, Object?>{'textureId': textureId};
  }
}
